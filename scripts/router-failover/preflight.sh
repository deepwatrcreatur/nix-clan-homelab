#!/usr/bin/env bash
# Check that both hosts are in their normal roles on their current
# configuration, idle, and record the baseline. Prints FAILOVER_DIR.
# Usage: scripts/router-failover/preflight.sh   (docs/router-failover.md)
set -u -o pipefail
FAILOVER_DIR=${FAILOVER_DIR:-$HOME/failover-$(date +%F-%H%M)}
mkdir -p "$FAILOVER_DIR"
export FAILOVER_DIR
# shellcheck source=scripts/router-failover/lib.sh
. "$(dirname "$0")/lib.sh"

fail() { log "PREFLIGHT FAILED: $*"; exit 1; }

# WHY: role switches use these exact toplevels. Booting an older generation
# from the boot menu leaves /run/current-system behind the profile, and its
# specialisations are older too (rehearsal 3).
ROUTER_TOP=$(r1 'readlink -f /run/current-system') || fail "router not reachable on $GATEWAY"
[ "$(r1 hostname)" = router ] || fail "$GATEWAY is not router"
[ "$(r1 'readlink -f /nix/var/nix/profiles/system')" = "$ROUTER_TOP" ] || fail "router is not running its current generation"
ELITEDESK_TOP=$(e4 'readlink -f /run/current-system') || fail "elitedesk not reachable on $ELITEDESK_STANDBY_IP"
# GOTCHA: elitedesk's profile is a deploy-rs wrapper that references the system.
e4 "nix-store -q --references \$(readlink -f /nix/var/nix/profiles/system) | grep -qxF $ELITEDESK_TOP" \
  || fail "elitedesk is not running its current generation"

r1 "test -x $ROUTER_TOP/specialisation/standby/bin/switch-to-configuration" || fail "router has no standby specialisation"
e4 "test -x $ELITEDESK_TOP/specialisation/primary/bin/switch-to-configuration" || fail "elitedesk has no primary specialisation"
r1 "test ! -e $MARKER" || fail "router has a demoted marker"
[ "$(r1 'systemctl is-active kea-dhcp4-server; true')" = active ] || fail "router Kea not active"
[ "$(e4 "ip -br link show $ELITEDESK_WAN | awk '{print \$2}'; ip -br addr | grep -c '$GATEWAY/'; systemctl is-active kea-dhcp4-server; cat /run/router-ha/role; echo; true" | tr '\n' ' ')" = "DOWN 0 inactive backup " ] \
  || fail "elitedesk is not a clean standby"
wait_idle r1 30 || fail "router has an activation or jobs running"
wait_idle e4 30 || fail "elitedesk has an activation or jobs running"
[ -z "$(r1 'systemctl --failed --no-legend')" ] || log "WARN: router has failed units: $(r1 'systemctl --failed --no-legend' | tr '\n' ' ')"

BASE_WAN_IP=$(r1 "ip -4 -br addr show $ROUTER_WAN | awk '{print \$3}' | cut -d/ -f1")
[ -n "$BASE_WAN_IP" ] || fail "router has no WAN IPv4"
BASE_PREFIX=$(r1 "journalctl -b -u systemd-networkd | grep -o 'delegated prefix [0-9a-f:]*/[0-9]*' | tail -1 | cut -d' ' -f3")
BASE_LEASES=$(r1 "sudo sh -c 'cat $KEA_DIR/dhcp4.leases* | wc -l'")
cat >"$STATE" <<STATE
ROUTER_TOP=$ROUTER_TOP
ELITEDESK_TOP=$ELITEDESK_TOP
BASE_WAN_IP=$BASE_WAN_IP
BASE_PREFIX=$BASE_PREFIX
BASE_LEASES=$BASE_LEASES
STATE
log "preflight ok: WAN $BASE_WAN_IP, prefix ${BASE_PREFIX:-?}, $BASE_LEASES lease lines"
echo "export FAILOVER_DIR=$FAILOVER_DIR"
