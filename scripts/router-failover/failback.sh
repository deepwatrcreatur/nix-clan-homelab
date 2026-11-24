#!/usr/bin/env bash
# elitedesk lets go, leases come back, router takes over again. If router
# cannot take over, elitedesk is promoted again so the network keeps a
# gateway.
set -u -o pipefail
# shellcheck source=scripts/router-failover/lib.sh
. "$(dirname "$0")/lib.sh"
# shellcheck source=/dev/null
. "$STATE"

log "== fail back"
[ "$(e1 hostname 2>/dev/null)" = elitedesk ] || { log "STOP: elitedesk is not on $GATEWAY"; exit 1; }
[ "$(r2 'systemctl is-active kea-dhcp4-server; true')" = inactive ] || { log "STOP: router not reachable as standby or its Kea runs"; exit 1; }
# WHY: rehearsal 2's fail back hit a boot-time standby activation still
# holding the lock; wait for router to be idle before letting go.
wait_idle r2 180 || { log "STOP: router still busy after 180 s; nothing changed"; exit 1; }
r2 "test -x $ROUTER_TOP/bin/switch-to-configuration" || { log "STOP: router lacks $ROUTER_TOP"; exit 1; }

log "elitedesk -> standby"
if ! elitedesk_to_standby fb-elitedesk || forced fb-elitedesk; then
  log "elitedesk gate failed; re-promoting elitedesk"
  promote_elitedesk rescue-promote && { log "RESCUE: elitedesk is primary again"; exit 2; }
  abort_all "elitedesk neither standby nor primary"
fi
lease_handback || true

log "router -> primary"
if ! router_to_primary fb-router || forced fb-router; then
  log "router did not take over; re-promoting elitedesk"
  promote_elitedesk rescue-promote && { log "RESCUE: elitedesk is primary again; investigate router"; exit 2; }
  log "RESCUE FAILED: use the consoles (docs/router-failover.md#abort)"; exit 3
fi
elitedesk 'sudo systemctl stop technitium-zone-ha-owner; true' >>"$LOG" 2>&1
log "fail back done: router is primary"
