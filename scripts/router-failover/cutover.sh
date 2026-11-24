#!/usr/bin/env bash
# Hand the leases over, demote router, promote elitedesk. Any failed gate
# runs the abort automatically. Run preflight.sh first.
set -u -o pipefail
# shellcheck source=scripts/router-failover/lib.sh
. "$(dirname "$0")/lib.sh"
# shellcheck source=/dev/null
. "$STATE"

back_to_router() { # router demoted (or half-demoted), elitedesk untouched
  log "ABORT: $*"
  if router_to_primary ab-router; then demote_elitedesk_zones; log "ABORT done: router is primary"; exit 1; fi
  fence_router_and_promote_elitedesk "router did not come back as primary"
}

log "== cutover"
log "stop router Kea and copy leases"
r1 'sudo systemctl stop kea-dhcp4-server' || { r1 'sudo systemctl start kea-dhcp4-server'; log "STOP: could not stop Kea"; exit 1; }
copy_leases r1_router e4 \
  || { r1 'sudo systemctl start kea-dhcp4-server'; log "STOP: lease copy failed; router Kea restarted"; exit 1; }
log "  copied $(e4 "sudo sh -c 'cat $KEA_DIR/dhcp4.leases* | wc -l'") lease lines (baseline $BASE_LEASES)"

# INVARIANT: router's WAN must be down before elitedesk's comes up (one lease).
log "demote router"
r1 "sudo systemctl stop fo-demote; sudo systemctl reset-failed fo-demote; true" >/dev/null 2>&1
r1 "sudo systemd-run --unit=fo-demote --remain-after-exit $ROUTER_TOP/specialisation/standby/bin/switch-to-configuration test" >>"$LOG" 2>&1 || true
wait_unit router fo-demote 90 || back_to_router "fo-demote did not finish with status 0"
# WHY: the workstation may still cache 10.10.10.2 as unreachable from
# earlier; poll instead of reading once (rehearsal 4: a single read 3 s after
# the switch got no answer and aborted a good demote).
g=""
# WHY: a wall-clock limit; each unanswered SSH attempt can itself take 5 s.
deadline=$((SECONDS + 30))
while [ "$SECONDS" -lt "$deadline" ]; do
  g=$(r2 "ip -br link show $ROUTER_WAN | awk '{print \$2}'; ip -br addr | grep -c '$GATEWAY/'; test -e $MARKER && echo marker; true" 2>/dev/null | tr '\n' ' ')
  [ "$g" = "DOWN 0 marker " ] && break
  sleep 2
done
log "  router: ${g:-<no answer on $ROUTER_STANDBY_IP>}"
{ [ "$g" = "DOWN 0 marker " ] && ! forced demote; } || back_to_router "demote gate: ${g:-no answer}"

log "promote elitedesk"
promote_elitedesk fo-promote || abort_all "fo-promote failed"
g=""
# WHY: a wall-clock limit; each unanswered SSH attempt can itself take 5 s.
deadline=$((SECONDS + 30))
while [ "$SECONDS" -lt "$deadline" ]; do
  g=$(e1 "ip -br addr show $ELITEDESK_LAN | grep -c '$GATEWAY/'; ip -br link show $ELITEDESK_WAN | awk '{print \$2, \$3}'; cat /run/router-ha/role; echo; systemctl is-active kea-dhcp4-server; true" 2>/dev/null | tr '\n' ' ')
  [ "$g" = "1 UP $ROUTER_WAN_MAC master active " ] && break
  sleep 2
done
log "  elitedesk: ${g:-<no answer on $GATEWAY>}"
{ [ "$g" = "1 UP $ROUTER_WAN_MAC master active " ] && ! forced promote; } || abort_all "promote gate: $g"
e1 "sudo arping -U -c 3 -I $ELITEDESK_LAN $GATEWAY >/dev/null; true"
deadline=$((SECONDS + 30))
while [ "$SECONDS" -lt "$deadline" ]; do
  e1 "ip -br addr show $ELITEDESK_WAN" | grep -qF "$BASE_WAN_IP" && { log "  elitedesk WAN: $BASE_WAN_IP"; break; }
  sleep 2
done
e1 "ip -br addr show $ELITEDESK_WAN" | grep -qF "$BASE_WAN_IP" || abort_all "elitedesk got no WAN lease ($BASE_WAN_IP) in 30 s"
log "cutover done: elitedesk is primary. Observe (docs step 4), then failback.sh."
