#!/usr/bin/env bash
# Make a promoted elitedesk the permanent primary: after cutover.sh, switch it
# from the `primary` specialisation (test-activated, gone on reboot) to the
# inventory-primary generation <toplevel> and make that the boot default.
# Procedure: docs/router-failover.md#permanent-primary.
#
# INVARIANT: the gateway never goes unowned. Router stays fenced (marker) the
# whole time; if the new generation fails a gate, elitedesk goes back to the
# promoted specialisation it was running, which cutover.sh already proved.
set -u -o pipefail
here=$(dirname "$(readlink -f "$0")")
# shellcheck source=lib.sh
. "$here/lib.sh"
# shellcheck disable=SC1090 # written by preflight.sh
. "$STATE"

NEW_TOP=${1:?usage: make-permanent.sh /nix/store/...-nixos-system-elitedesk-...}
ELITEDESK_MGMT=192.168.100.98
ZONES="deepwatercreature.com 10.10.in-addr.arpa"
TOKEN_FILE=/var/lib/technitium-dns-server/nix-router-api-token
SAVE=/var/lib/router-failover/permanent

zone_types() { # -> "10.10.in-addr.arpa=Primary deepwatercreature.com=Primary "
  e1 "sudo sh -c 'curl -fsS -G --data-urlencode token=\$(tr -d \"\\r\\n\" <$TOKEN_FILE) http://127.0.0.1:5380/api/zones/list'" \
    | grep -o '"name":"[^"]*","type":"[^"]*"' | sed 's/"name":"\([^"]*\)","type":"\([^"]*\)"/\1=\2/' \
    | grep -E "^(${ZONES// /|})=" | sort | tr '\n' ' '
}
want_zones="10.10.in-addr.arpa=Primary deepwatercreature.com=Primary "

back_to_promoted() {
  log "ROLLBACK: $*"
  e1 "sudo nix-env -p /nix/var/nix/profiles/system --set $ELITEDESK_TOP && sudo $ELITEDESK_TOP/bin/switch-to-configuration boot" >>"$LOG" 2>&1 \
    || log "  WARN: boot default not restored; check elitedesk's profile"
  if run_switch elitedesk pm-rollback "$ELITEDESK_TOP/specialisation/primary" 120; then
    log "ROLLBACK done: elitedesk runs the promoted specialisation again (router stays fenced)"
  else
    log "ROLLBACK FAILED: use elitedesk's console; abort with docs/router-failover.md#abort"
  fi
  exit 1
}

log "make-permanent: $NEW_TOP"

# --- gates: the cutover finished and nothing has changed since ---------------
[ "$(e1 hostname 2>/dev/null)" = elitedesk ] || { log "elitedesk does not hold $GATEWAY; run cutover.sh first"; exit 64; }
g=$(e1 "cat /run/router-ha/role; echo; systemctl is-active kea-dhcp4-server; true" | tr '\n' ' ')
[ "$g" = "master active " ] || { log "elitedesk is not the promoted primary ($g)"; exit 64; }
router "test -e $MARKER" || { log "router has no $MARKER; it could come back as a gateway"; exit 64; }
router_released || { log "router still holds the WAN or $GATEWAY"; exit 64; }
z=$(zone_types)
[ "$z" = "$want_zones" ] || { log "elitedesk's zones are not Primary ($z)"; exit 64; }
wait_idle elitedesk 120 || { log "elitedesk is busy"; exit 64; }

# --- prepare without touching services ------------------------------------
log "copy the new generation to elitedesk"
nix copy --no-check-sigs --to "ssh-ng://$SSH_USER@$ELITEDESK_MGMT?remote-program=/run/wrappers/bin/sudo%20nix-daemon" "$NEW_TOP" >>"$LOG" 2>&1 \
  || { log "copy failed; nothing changed"; exit 64; }
log "save zone exports and router's Pangolin state on elitedesk ($SAVE)"
e1 "sudo install -d -m 0700 $SAVE" || exit 64
for zone in $ZONES; do
  e1 "sudo sh -c 'curl -fsS -G --data-urlencode token=\$(tr -d \"\\r\\n\" <$TOKEN_FILE) --data-urlencode zone=$zone http://127.0.0.1:5380/api/zones/export > $SAVE/$zone.zone && test -s $SAVE/$zone.zone'" \
    || { log "zone export of $zone failed; nothing changed"; exit 64; }
done
# WHY: Pangolin's database holds the sites and resources, and gerbil's key is
# the WireGuard identity the remote newt clients trust.
router "sudo tar -C /var/lib/pangolin/config -cf - db key" | e1 "sudo sh -c 'cat > $SAVE/pangolin.tar && test -s $SAVE/pangolin.tar'" \
  || { log "Pangolin state copy failed; nothing changed"; exit 64; }

# GOTCHA: the full generation drops technitium-zone-ha-owner, and stopping it
# runs its demote hook. With the role file at master the hook refuses; stop
# it here, where a refusal is visible, rather than inside the switch.
e1 "sudo systemctl stop technitium-zone-ha-owner; sudo systemctl reset-failed technitium-zone-ha-owner; true" >>"$LOG" 2>&1
z=$(zone_types)
[ "$z" = "$want_zones" ] || back_to_promoted "zones changed when the HA owner stopped ($z); exports in $SAVE"

# --- switch ------------------------------------------------------------------
log "set the boot default and switch"
e1 "sudo nix-env -p /nix/var/nix/profiles/system --set $NEW_TOP" >>"$LOG" 2>&1 || back_to_promoted "profile update failed"
unit=pm-switch
e1 "sudo systemctl stop $unit; sudo systemctl reset-failed $unit; true" >/dev/null 2>&1
e1 "sudo systemd-run --unit=$unit --remain-after-exit $NEW_TOP/bin/switch-to-configuration switch" >>"$LOG" 2>&1 || true
wait_unit elitedesk "$unit" 300; rc=$?
if [ "$rc" != 0 ]; then
  e1 "journalctl -u $unit --no-pager | tail -20" >>"$LOG" 2>&1 || true
  # WHY: exit 4 only means a unit failed to start; the gates below decide.
  log "  WARN: switch finished with $(unit_status elitedesk $unit); checking gates"
fi

# --- gates -------------------------------------------------------------------
ok=1
[ "$(e1 hostname 2>/dev/null)" = elitedesk ] || { log "  gate: elitedesk does not answer on $GATEWAY"; ok=; }
[ -n "$ok" ] && for _ in $(seq 1 30); do
  e1 "ip -br addr show $ELITEDESK_WAN" | grep -qF "$BASE_WAN_IP" && break
  sleep 2
done
e1 "ip -br addr show $ELITEDESK_WAN" | grep -qF "$BASE_WAN_IP" || { log "  gate: WAN lease $BASE_WAN_IP missing"; ok=; }
# GOTCHA: is-active with several units succeeds if any one is active.
for u in kea-dhcp4-server technitium-dns-server caddy; do
  e1 "systemctl is-active --quiet $u" || { log "  gate: $u is not active"; ok=; }
done
z=$(zone_types); [ "$z" = "$want_zones" ] || { log "  gate: zones are $z"; ok=; }
forced permanent && ok=
[ -n "$ok" ] || back_to_promoted "a gate failed after the switch"
e1 "sudo arping -U -c 3 -I $ELITEDESK_LAN $GATEWAY >/dev/null; true"

# --- Pangolin state ------------------------------------------------------------
log "restore Pangolin state from router"
e1 "sudo sh -c 'set -e; systemctl stop gerbil pangolin; install -d -o pangolin -g fossorial -m 0770 /var/lib/pangolin/config; tar -C /var/lib/pangolin/config -xf $SAVE/pangolin.tar; chown -R pangolin:fossorial /var/lib/pangolin/config/db; chown gerbil:fossorial /var/lib/pangolin/config/key; systemctl start pangolin gerbil'" >>"$LOG" 2>&1 \
  || log "  WARN: Pangolin state restore failed; tunnels need attention (tar in $SAVE)"

failed=$(e1 "systemctl list-units --failed --plain --no-legend | awk '{print \$1}' | tr '\n' ' '")
[ -z "$failed" ] || log "  WARN: failed units on elitedesk: $failed"
log "DONE: elitedesk is the permanent primary; router stays fenced by $MARKER"
