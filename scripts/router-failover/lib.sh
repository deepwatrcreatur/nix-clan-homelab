# shellcheck shell=bash disable=SC2034  # constants are used by the scripts that source this
# Shared helpers for the manual router failover rehearsal.
# Procedure and reasoning: docs/router-failover.md.
#
# INVARIANT: every step that can leave the network without a gateway has an
# automatic way back. A failed gate runs the abort path instead of stopping;
# rehearsals 2 and 3 stopped on a failed gate and left both routers down.

set -u -o pipefail

SSH_USER=${FAILOVER_SSH_USER:-deepwatrcreatur}
SSH_OPTS=(-o ConnectTimeout=5 -o ServerAliveInterval=2 -o ServerAliveCountMax=3 -o BatchMode=yes)

GATEWAY=10.10.10.1
ROUTER_STANDBY_IP=10.10.10.2
ELITEDESK_STANDBY_IP=10.10.10.4
ROUTER_WAN=enp6s17
ROUTER_LAN=enp6s16
ELITEDESK_WAN=enp1s0f1np1
ELITEDESK_LAN=enp1s0f0np0
ROUTER_WAN_MAC=02:76:c6:01:2a:b0
MARKER=/var/lib/router-failover/demoted
KEA_DIR=/var/lib/private/kea

# Testing the abort paths: FAILOVER_FORCE_FAIL=<step> makes that gate fail
# after its action ran (steps: demote, promote, fb-elitedesk, fb-router).
FORCE_FAIL=${FAILOVER_FORCE_FAIL:-}

RUN_DIR=${FAILOVER_DIR:-}
if [ -z "$RUN_DIR" ]; then
  echo "set FAILOVER_DIR to the rehearsal directory (preflight.sh prints it)" >&2
  exit 64
fi
LOG="$RUN_DIR/rehearsal.log"
STATE="$RUN_DIR/state.env"

ts() { date '+%T.%3N'; }
log() { echo "$(ts) $*" | tee -a "$LOG"; }

_ssh() { local alias=$1 addr=$2; shift 2; ssh "${SSH_OPTS[@]}" -o HostKeyAlias="$alias" "$SSH_USER@$addr" "$@"; }
r1() { _ssh router "$GATEWAY" "$@"; }
r2() { _ssh router "$ROUTER_STANDBY_IP" "$@"; }
e1() { _ssh elitedesk "$GATEWAY" "$@"; }
e4() { _ssh elitedesk "$ELITEDESK_STANDBY_IP" "$@"; }
# WHY: a role switch moves the host's address; ask whichever one answers.
# GOTCHA: both helpers must check the hostname, since 10.10.10.1 can be
# either host.
router() { r2 "$@" 2>/dev/null || { [ "$(r1 hostname 2>/dev/null)" = router ] && r1 "$@"; }; }
elitedesk() { e4 "$@" 2>/dev/null || { [ "$(e1 hostname 2>/dev/null)" = elitedesk ] && e1 "$@"; }; }

unit_status() { # host-fn unit -> "SubState=.. Result=.. ExecMainStatus=.."
  "$1" "systemctl show -p SubState,Result,ExecMainStatus $2" 2>/dev/null \
    | sort | tr '\n' ' ' | sed 's/ $//'
}

# wait_unit host-fn unit timeout-seconds: 0 success, 1 failed, 2 timed out.
# SubState=running means activation is still going; only exited counts.
wait_unit() {
  local fn=$1 unit=$2 timeout=$3 out="" waited=0
  while [ "$waited" -lt "$timeout" ]; do
    sleep 2; waited=$((waited + 2))
    out=$(unit_status "$fn" "$unit") || true
    log "  $unit: ${out:-<no answer>}"
    case "$out" in
      "ExecMainStatus=0 Result=success SubState=exited") return 0 ;;
      *SubState=running*|*SubState=start*|"") ;;
      *) return 1 ;;
    esac
  done
  return 2
}

# Start a detached switch-to-configuration on a host; retries while another
# activation holds the lock (rehearsal 2: the boot-time standby activation
# was still running and fb-router failed with "Could not acquire lock").
run_switch() { # host-fn unit-base toplevel timeout
  local fn=$1 base=$2 top=$3 timeout=$4 try unit rc
  for try in 1 2 3; do
    unit="$base-$try"
    wait_idle "$fn" 120 || log "  WARN: $unit: host still busy, trying anyway"
    log "start $unit: $top test"
    "$fn" "sudo systemd-run --unit=$unit --remain-after-exit $top/bin/switch-to-configuration test" >>"$LOG" 2>&1 || true
    wait_unit "$fn" "$unit" "$timeout"; rc=$?
    [ "$rc" = 0 ] && return 0
    if "$fn" "journalctl -u $unit --no-pager" 2>/dev/null | grep -q 'Could not acquire lock'; then
      log "  $unit: lock held by another activation; retrying"
      continue
    fi
    "$fn" "journalctl -u $unit --no-pager | tail -15" >>"$LOG" 2>&1 || true
    return "$rc"
  done
  return 1
}

wait_idle() { # host-fn timeout: no switch-to-configuration running, no jobs
  local fn=$1 timeout=$2 waited=0 out
  while [ "$waited" -lt "$timeout" ]; do
    # shellcheck disable=SC2016 # expands on the remote host
    out=$("$fn" 'echo "$(pgrep -fc "bin/[s]witch-to-configuration") $(systemctl list-jobs --no-legend | wc -l)"' 2>/dev/null) || out=""
    [ "$out" = "0 0" ] && return 0
    sleep 3; waited=$((waited + 3))
  done
  return 1
}

forced() { [ "$FORCE_FAIL" = "$1" ] && log "  FAILOVER_FORCE_FAIL=$1: treating gate as failed"; }

# Copy Kea's lease files host to host without ever leaving the target with
# a partial set: extract into a temporary directory, check it, then swap.
copy_leases() { # from-fn to-fn
  "$1" "sudo sh -c 'cd $KEA_DIR && tar -cf - dhcp4.leases*'" \
    | "$2" "sudo sh -c 'set -e; install -d -m 0700 $KEA_DIR; t=\$(mktemp -d $KEA_DIR/.incoming.XXXXXX); trap \"rm -rf \$t\" EXIT; tar -C \$t -xf -; test -s \$t/dhcp4.leases; rm -f $KEA_DIR/dhcp4.leases*; mv \$t/dhcp4.leases* $KEA_DIR/'"
}

# --- lease handback (elitedesk -> router), only while router's Kea is off.
# Each side is reduced to the latest record per address; for router only
# unexpired leases count. Every router lease must be on elitedesk too.
# Returns 0 only when router's files now hold elitedesk's leases (or router's
# Kea is already serving, so a copy would replace newer renewals).
lease_handback() {
  # shellcheck disable=SC2016 # awk program
  local latest='{ if ($1 != "address" && $5 >= until[$1]) { until[$1] = $5; mac[$1] = $2 } }
    END { for (a in until) if (!active || until[a] > systime()) print a "," mac[a] }'
  if [ "$(router 'systemctl is-active kea-dhcp4-server; true')" != inactive ]; then
    log "lease handback skipped: router's Kea is serving"
    return 0
  fi
  router "sudo sh -c 'cat $KEA_DIR/dhcp4.leases*'" | gawk -F, -v active=1 "$latest" | sort >"$RUN_DIR/r.leases" \
    || { log "lease handback failed: router read"; return 1; }
  elitedesk "sudo sh -c 'cat $KEA_DIR/dhcp4.leases*'" | gawk -F, -v active=0 "$latest" | sort >"$RUN_DIR/e.leases" \
    || { log "lease handback failed: elitedesk read"; return 1; }
  log "leases: router $(wc -l <"$RUN_DIR/r.leases") active, elitedesk $(wc -l <"$RUN_DIR/e.leases")"
  if [ ! -s "$RUN_DIR/e.leases" ] || [ -n "$(comm -23 "$RUN_DIR/r.leases" "$RUN_DIR/e.leases")" ]; then
    log "lease handback failed: elitedesk lacks some of router's leases (router's files kept)"
    return 1
  fi
  log "elitedesk issued or renewed $(comm -13 "$RUN_DIR/r.leases" "$RUN_DIR/e.leases" | wc -l)"
  copy_leases elitedesk router || { log "lease handback failed: copy (router's files kept)"; return 1; }
}

# --- building blocks of every abort -----------------------------------------

# 10.10.10.1 can be either host; only talk to router there.
r1_router() { [ "$(r1 hostname 2>/dev/null)" = router ] && r1 "$@"; }

elitedesk_released() { # WAN down and no gateway address: safe for router to take over
  local g; g=$(elitedesk "ip -br link show $ELITEDESK_WAN | awk '{print \$2}'; ip -br addr | grep -c '$GATEWAY/'; true" | tr '\n' ' ')
  [ "$g" = "DOWN 0 " ]
}

router_released() { # router holds neither the WAN nor the gateway address
  local g; g=$(router "ip -br link show $ROUTER_WAN | awk '{print \$2}'; ip -br addr | grep -c '$GATEWAY/'; true" | tr '\n' ' ')
  log "  router released? $g"
  [ "$g" = "DOWN 0 " ]
}

elitedesk_to_standby() { # unit-base
  # shellcheck disable=SC2153 # set in state.env
  run_switch elitedesk "$1" "$ELITEDESK_TOP" 90 || return 1
  elitedesk "sudo ip link set $ELITEDESK_WAN down; sudo ip link set $ELITEDESK_WAN address \"\$(ethtool -P $ELITEDESK_WAN | awk '{print \$3}')\"" >>"$LOG" 2>&1
  local g; g=$(elitedesk "ip -br link show $ELITEDESK_WAN | awk '{print \$2}'; ip -br addr | grep -c '$GATEWAY/'; systemctl is-active kea-dhcp4-server; cat /run/router-ha/role; echo; true" | tr '\n' ' ')
  log "  elitedesk: $g"
  [ "$g" = "DOWN 0 inactive backup " ]
}

# Success means router holds the gateway, the baseline WAN lease and Kea.
router_to_primary() { # unit-base
  # shellcheck disable=SC2153 # set in state.env
  run_switch router "$1" "$ROUTER_TOP" 120 || return 1
  # WHY: after the WAN MAC moves back the ISP gateway answers only once the
  # link has gone down and up (rehearsal 1).
  r1_router "sudo ip link set $ROUTER_WAN down && sleep 2 && sudo ip link set $ROUTER_WAN up && sudo networkctl reconfigure $ROUTER_WAN; sudo arping -U -c 3 -I $ROUTER_LAN $GATEWAY >/dev/null; true" >>"$LOG" 2>&1 \
    || { log "  router does not hold $GATEWAY"; return 1; }
  local wan=""
  for _ in $(seq 1 30); do
    # shellcheck disable=SC2153 # set in state.env
    r1_router "ip -br addr show $ROUTER_WAN" | grep -qF "$BASE_WAN_IP" && { wan=1; break; }
    sleep 2
  done
  [ -n "$wan" ] || { log "  router has no WAN lease ($BASE_WAN_IP) after 60 s"; return 1; }
  log "  router WAN back: $BASE_WAN_IP"
  r1_router "test ! -e $MARKER && systemctl is-active --quiet kea-dhcp4-server" || { log "  router: marker present or Kea down"; return 1; }
}

# Router could not (or must not) hold the gateway: fence it, then promote
# elitedesk. INVARIANT: never promote elitedesk while router may still hold
# the WAN or 10.10.10.1 (two gateways, one modem lease).
fence_router_and_promote_elitedesk() { # reason
  log "RESCUE: $*"
  # shellcheck disable=SC2153 # set in state.env
  run_switch router rescue-fence "$ROUTER_TOP/specialisation/standby" 90 || log "  WARN: fence switch did not finish cleanly"
  if ! router_released; then
    log "RESCUE FAILED: router may still hold the WAN or $GATEWAY; elitedesk NOT promoted. Use router's console (docs/router-failover.md#abort)"
    exit 3
  fi
  if promote_elitedesk rescue-promote; then
    e1 "sudo arping -U -c 3 -I $ELITEDESK_LAN $GATEWAY >/dev/null; true"
    log "RESCUE done: elitedesk is primary; investigate router"
    exit 2
  fi
  log "RESCUE FAILED: elitedesk did not promote. Use the consoles (docs/router-failover.md#abort)"
  exit 3
}

# GOTCHA: elitedesk hands its zones back only when another primary answers
# SOA, so this must run after router holds 10.10.10.1; run before, it kept
# its Primary copies and added 24 s to the outage (rehearsal 4).
demote_elitedesk_zones() {
  elitedesk "sudo systemctl stop technitium-zone-ha-owner; sudo systemctl reset-failed technitium-zone-ha-owner; sudo systemctl start technitium-zone-ha-reconcile; true" >>"$LOG" 2>&1
  # shellcheck disable=SC2016 # expands on elitedesk
  if elitedesk 'journalctl --no-pager _SYSTEMD_INVOCATION_ID="$(systemctl show -p InvocationID --value technitium-zone-ha-reconcile)"' 2>/dev/null | grep -q 'keeping the Primary copy'; then
    log "  WARN: elitedesk kept Primary zone copies; rerun: sudo systemctl start technitium-zone-ha-reconcile"
  else
    log "  elitedesk zones back to Secondary"
  fi
}

# Full abort: elitedesk lets go, leases come back, router takes over.
abort_all() {
  log "ABORT: $*"
  elitedesk_to_standby ab-elitedesk || log "  WARN: elitedesk did not return cleanly to standby"
  if ! elitedesk_released; then
    log "ABORT STOPPED: elitedesk still holds the WAN or $GATEWAY; router not promoted. Use elitedesk's console (docs/router-failover.md#abort)"
    exit 3
  fi
  # WHY: an abort happens during the cutover, when elitedesk served for
  # seconds at most; a failed handback is logged but must not keep the
  # network without a gateway.
  lease_handback || log "  WARN: router serves its own snapshot; check for duplicate leases"
  if router_to_primary ab-router; then
    demote_elitedesk_zones
    log "ABORT done: router is primary"
    exit 1
  fi
  fence_router_and_promote_elitedesk "router did not come back as primary"
}

promote_elitedesk() { # unit-base
  run_switch elitedesk "$1" "$ELITEDESK_TOP/specialisation/primary" 90
}
