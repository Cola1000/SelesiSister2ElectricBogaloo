#!/usr/bin/env bash
set -Eeuo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
log()    { echo -e "[$(date +%H:%M:%S)] ${BLUE}$*${NC}"; }
ok()     { echo -e "[$(date +%H:%M:%S)] ${GREEN}$*${NC}"; }
warn()   { echo -e "[$(date +%H:%M:%S)] ${YELLOW}$*${NC}"; }
err()    { echo -e "[$(date +%H:%M:%S)] ${RED}$*${NC}" >&2; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PIDS_FILE="$SCRIPT_DIR/node_pids.txt"
LOG_DIR="$SCRIPT_DIR/logs"
mkdir -p "$LOG_DIR"

# Defaults (can be overridden via env)
PORTS_STR="${PORTS_STR:-"8001 8002 8003"}"
read -r -a PORTS <<< "$PORTS_STR"
DIFFICULTY="${DIFFICULTY:-4}"
VENV_DIR="${VENV_DIR:-$SCRIPT_DIR/.venv}"
PY="${PY:-$VENV_DIR/bin/python}"

usage() {
  cat <<USAGE
Usage: $0 {start|stop|status|setup|test}

Environment:
  PORTS_STR   Space-separated ports for nodes (default: "8001 8002 8003")
  DIFFICULTY  Mining difficulty (default: 4)
  VENV_DIR    Python venv dir (default: .venv under project)
  PY          Python binary (default: \$VENV_DIR/bin/python)
USAGE
}

ensure_venv() {
  if [[ ! -x "$PY" ]]; then
    log "Creating Python virtualenv at $VENV_DIR ..."
    python3 -m venv "$VENV_DIR"
    "$VENV_DIR/bin/pip" install --upgrade pip wheel
    log "Installing requirements..."
    "$VENV_DIR/bin/pip" install -r "$SCRIPT_DIR/requirements.txt"
  fi
}

start() {
  ensure_venv
  : > "$PIDS_FILE"
  log "Starting ${#PORTS[@]} nodes (difficulty=$DIFFICULTY)"
  for port in "${PORTS[@]}"; do
    node_id="node-$port"
    log "Starting $node_id on :$port"
    # Use nohup so processes survive this shell; redirect logs
    if nohup "$PY" "$SCRIPT_DIR/node.py"         --port "$port" --node-id "$node_id" --difficulty "$DIFFICULTY"         >"$LOG_DIR/$node_id.log" 2>&1 & then
      pid=$!
      echo "$pid" >> "$PIDS_FILE"
      # Wait briefly and verify pid still alive
      sleep 1
      if kill -0 "$pid" 2>/dev/null; then
        ok "$node_id started (PID $pid)"
      else
        err "Failed to start $node_id (see logs/$node_id.log)"
        exit 1
      fi
    else
      err "nohup failed for $node_id"
      exit 1
    fi
  done
  log "All nodes started; giving them 3s to warm up"
  sleep 3
  setup
}

stop() {
  if [[ ! -f "$PIDS_FILE" ]]; then
    warn "No $PIDS_FILE; nothing to stop"
    return 0
  fi
  while read -r pid; do
    [[ -n "${pid:-}" ]] || continue
    if kill -0 "$pid" 2>/dev/null; then
      log "Stopping PID $pid"
      kill "$pid" 2>/dev/null || true
      # Grace period then SIGKILL if needed
      for _ in {1..10}; do
        kill -0 "$pid" 2>/dev/null || { ok "Stopped $pid"; break; }
        sleep 0.2
      done
      kill -9 "$pid" 2>/dev/null || true
    fi
  done < "$PIDS_FILE"
  : > "$PIDS_FILE"
  ok "All nodes stopped"
}

status() {
  if [[ ! -f "$PIDS_FILE" ]]; then
    warn "No $PIDS_FILE; run start first"
    return 0
  fi
  i=0
  while read -r pid; do
    port="${PORTS[$i]:-?}"
    [[ -z "$port" ]] && break
    if kill -0 "$pid" 2>/dev/null; then
      ok "node-$port running (PID $pid)"
    else
      err "node-$port not running"
    fi
    i=$((i+1))
  done < "$PIDS_FILE"
}

setup() {
  log "Registering peers"
  for current in "${PORTS[@]}"; do
    peers=()
    for p in "${PORTS[@]}"; do
      [[ "$p" != "$current" ]] && peers+=("http://localhost:$p")
    done

    # Bangun JSON array secara aman tanpa dependensi eksternal
    json_peers=$(printf '%s\n' "${peers[@]}" | awk '{printf "\"%s\",",$0}' | sed 's/,$//')
    payload="{\"peers\":[${json_peers}]}"

    url="http://localhost:$current/nodes/register"
    log "POST $url payload=$payload"

    # Jangan pakai -f supaya kalau 422 kita tetap lihat body error-nya
    http_code=$(curl -s -o /tmp/reg.$current.out -w "%{http_code}" \
      -X POST "$url" -H 'Content-Type: application/json' -d "$payload")

    if [[ "$http_code" == "200" ]]; then
      ok "node-$current registered ${#peers[@]} peers"
    else
      err "Failed to register peers for node-$current (HTTP $http_code)"
      cat /tmp/reg.$current.out >&2
      exit 1
    fi
  done
}


test_net() {
  miner="${PORTS[-1]}"
  log "Submitting example transactions to first node :${PORTS[0]}"
  curl -fsS -X POST "http://localhost:${PORTS[0]}/transaction"     -H 'Content-Type: application/json'     -d '{"sender":"Alice","recipient":"Bob","amount":1.23}' >/dev/null
  curl -fsS -X POST "http://localhost:${PORTS[0]}/transaction"     -H 'Content-Type: application/json'     -d '{"sender":"Carol","recipient":"Dave","amount":0.5}' >/dev/null

  log "Mining a block on miner :$miner"
  curl -fsS "http://localhost:$miner/mine?miner=Miner1&reward=12.5" >/dev/null

  log "Checking chain lengths:"
  for p in "${PORTS[@]}"; do
    len=$(curl -fsS "http://localhost:$p/chain" | python - <<'PY'
import sys, json; print(len(json.load(sys.stdin)["chain"]))
PY
)
    echo "  node-$p length: $len"
  done

  log "Resolving conflicts on all nodes"
  for p in "${PORTS[@]}"; do
    curl -fsS "http://localhost:$p/resolve" >/dev/null || true
  done
  ok "Basic test complete."
}

cmd="${1:-}"
case "${cmd:-}" in
  start) start ;;
  stop)  stop ;;
  status) status ;;
  setup) setup ;;
  test)  test_net ;;
  *) usage; exit 1 ;;
esac