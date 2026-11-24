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
  fence_router_and_promote_elitedesk "elitedesk did not return cleanly to standby"
fi
# INVARIANT: router's Kea starts with its primary role, so it may only start
# once its files hold elitedesk's leases; otherwise it could re-issue them.
lease_handback || fence_router_and_promote_elitedesk "lease handback failed"

log "router -> primary"
if ! router_to_primary fb-router || forced fb-router; then
  fence_router_and_promote_elitedesk "router did not take over"
fi
demote_elitedesk_zones
log "fail back done: router is primary"
