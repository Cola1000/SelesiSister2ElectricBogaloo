#!/bin/bash
# network_manager.sh - Script to manage Bitcoin network nodes

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PIDS_FILE="$SCRIPT_DIR/node_pids.txt"

# Default configuration
DEFAULT_PORTS=(8001 8002 8003)
DEFAULT_DIFFICULTY=4

usage() {
    echo "Usage: $0 {start|stop|status|test|setup}"
    echo ""
    echo "Commands:"
    echo "  start    - Start all nodes"
    echo "  stop     - Stop all nodes"
    echo "  status   - Check nodes status"
    echo "  test     - Run network tests"
    echo "  setup    - Setup network (register peers)"
    echo ""
    echo "Environment Variables:"
    echo "  PORTS      - Space-separated ports (default: 8001 8002 8003)"
    echo "  DIFFICULTY - Mining difficulty (default: 4)"
    exit 1
}

log() {
    echo -e "${BLUE}[$(date +'%H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}✓${NC} $1"
}

error() {
    echo -e "${RED}✗${NC} $1"
}

warn() {
    echo -e "${YELLOW}!${NC} $1"
}

# Parse ports from environment or use defaults
IFS=' ' read -ra PORTS <<< "${PORTS:-${DEFAULT_PORTS[*]}}"
DIFFICULTY=${DIFFICULTY:-$DEFAULT_DIFFICULTY}

start_nodes() {
    log "Starting Bitcoin network with ${#PORTS[@]} nodes..."
    log "Ports: ${PORTS[*]}"
    log "Difficulty: $DIFFICULTY"
    
    # Clean up any existing PID file
    > "$PIDS_FILE"
    
    for port in "${PORTS[@]}"; do
        node_id="node-$port"
        log "Starting $node_id on port $port"
        
        # Start node in background
        python3 "$SCRIPT_DIR/node.py" \
            --port "$port" \
            --difficulty "$DIFFICULTY" \
            --node-id "$node_id" > "logs/$node_id.log" 2>&1 &
        
        pid=$!
        echo "$pid:$port:$node_id" >> "$PIDS_FILE"
        
        # Wait a bit for node to start
        sleep 2
        
        # Check if node is running
        if kill -0 "$pid" 2>/dev/null; then
            success "$node_id started (PID: $pid)"
        else
            error "Failed to start $node_id"
            return 1
        fi
    done
    
    log "All nodes started. Waiting 5 seconds before setup..."
    sleep 5
    
    # Auto setup peers
    setup_peers
}

stop_nodes() {
    log "Stopping all nodes..."
    
    if [[ ! -f "$PIDS_FILE" ]]; then
        warn "No PID file found. Nodes may not be running."
        return 0
    fi
    
    while IFS=':' read -r pid port node_id || [[ -n "$pid" ]]; do
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            log "Stopping $node_id (PID: $pid)"
            kill "$pid"
            
            # Wait for graceful shutdown
            for i in {1..10}; do
                if ! kill -0 "$pid" 2>/dev/null; then
                    success "$node_id stopped"
                    break
                fi
                sleep 1
                if [[ $i -eq 10 ]]; then
                    warn "Force killing $node_id"
                    kill -9 "$pid" 2>/dev/null || true
                fi
            done
        else
            warn "$node_id (PID: $pid) not running"
        fi
    done < "$PIDS_FILE"
    
    rm -f "$PIDS_FILE"
    success "All nodes stopped"
}

check_status() {
    log "Checking node status..."
    
    if [[ ! -f "$PIDS_FILE" ]]; then
        warn "No PID file found. Use '$0 start' to start nodes."
        return 0
    fi
    
    local running=0
    local total=0
    
    while IFS=':' read -r pid port node_id || [[ -n "$pid" ]]; do
        total=$((total + 1))
        
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            # Check HTTP endpoint
            if curl -s -f "http://localhost:$port/health" > /dev/null 2>&1; then
                success "$node_id (PID: $pid, Port: $port) - Running"
                running=$((running + 1))
            else
                error "$node_id (PID: $pid, Port: $port) - Process running but HTTP not responding"
            fi
        else
            error "$node_id (PID: $pid, Port: $port) - Not running"
        fi
    done < "$PIDS_FILE"
    
    log "Status: $running/$total nodes running"
    
    if [[ $running -eq $total ]] && [[ $total -gt 0 ]]; then
        return 0
    else
        return 1
    fi
}

setup_peers() {
    log "Setting up peer connections..."
    
    # Build peer list for each node
    for i in "${!PORTS[@]}"; do
        current_port="${PORTS[$i]}"
        node_id="node-$current_port"
        
        # Create peer list (all other nodes)
        peers=()
        for j in "${!PORTS[@]}"; do
            if [[ $i -ne $j ]]; then
                peers+=("http://localhost:${PORTS[$j]}")
            fi
        done
        
        if [[ ${#peers[@]} -gt 0 ]]; then
            peer_json=$(printf '"%s",' "${peers[@]}")
            peer_json="[${peer_json%,}]"
            
            log "Registering peers for $node_id: ${peers[*]}"
            
            response=$(curl -s -X POST "http://localhost:$current_port/nodes/register" \
                -H "Content-Type: application/json" \
                -d "{\"peers\": $peer_json}" 2>/dev/null || echo "ERROR")
            
            if [[ "$response" != "ERROR" ]]; then
                success "Peers registered for $node_id"
            else
                error "Failed to register peers for $node_id"
            fi
        fi
    done
    
    success "Peer setup completed"
}

run_tests() {
    log "Running network tests..."
    
    if ! check_status > /dev/null; then
        error "Not all nodes are running. Start nodes first with '$0 start'"
        return 1
    fi
    
    local test_port="${PORTS[0]}"
    local miner_port="${PORTS[1]}"
    
    log "Test 1: Adding transactions"
    
    # Add some test transactions
    transactions=(
        '{"sender": "Alice", "recipient": "Bob", "amount": 10.5}'
        '{"sender": "Bob", "recipient": "Charlie", "amount": 5.0}'
        '{"sender": "Charlie", "recipient": "Alice", "amount": 2.5}'
    )
    
    for tx in "${transactions[@]}"; do
        response=$(curl -s -X POST "http://localhost:$test_port/transaction" \
            -H "Content-Type: application/json" \
            -d "$tx" 2>/dev/null || echo "ERROR")
        
        if [[ "$response" != "ERROR" ]]; then
            success "Transaction added: $tx"
        else
            error "Failed to add transaction: $tx"
            return 1
        fi
    done
    
    log "Test 2: Mining block"
    
    response=$(curl -s "http://localhost:$miner_port/mine?miner=Miner1&reward=12.5" 2>/dev/null || echo "ERROR")
    
    if [[ "$response" != "ERROR" ]] && echo "$response" | grep -q "block mined successfully"; then
        success "Block mined successfully"
    else
        error "Failed to mine block"
        return 1
    fi
    
    log "Test 3: Checking chain synchronization (waiting 10 seconds)"
    sleep 10
    
    # Check if all nodes have the same chain length
    chain_lengths=()
    for port in "${PORTS[@]}"; do
        length=$(curl -s "http://localhost:$port/chain" 2>/dev/null | \
                python3 -c "import sys, json; print(json.load(sys.stdin)['length'])" 2>/dev/null || echo "0")
        chain_lengths+=("$length")
        log "Node $port chain length: $length"
    done
    
    # Check if all chain lengths are the same and > 1
    first_length="${chain_lengths[0]}"
    all_same=true
    
    for length in "${chain_lengths[@]}"; do
        if [[ "$length" != "$first_length" ]] || [[ "$length" -le 1 ]]; then
            all_same=false
            break
        fi
    done
    
    if [[ "$all_same" == true ]]; then
        success "All nodes synchronized (chain length: $first_length)"
    else
        error "Nodes not synchronized: ${chain_lengths[*]}"
        return 1
    fi
    
    log "Test 4: Checking node health"
    
    for port in "${PORTS[@]}"; do
        health=$(curl -s "http://localhost:$port/health" 2>/dev/null || echo "ERROR")
        if [[ "$health" != "ERROR" ]] && echo "$health" | grep -q '"status": "ok"'; then
            success "Node $port is healthy"
        else
            error "Node $port health check failed"
            return 1
        fi
    done
    
    success "All tests passed!"
    
    log "Network Summary:"
    echo "  • Nodes: ${#PORTS[@]}"
    echo "  • Chain length: $first_length blocks"
    echo "  • All nodes synchronized and healthy"
}

# Create logs directory
mkdir -p "$SCRIPT_DIR/logs"

# Main script logic
case "${1:-}" in
    start)
        start_nodes
        ;;
    stop)
        stop_nodes
        ;;
    status)
        check_status
        ;;
    setup)
        setup_peers
        ;;
    test)
        run_tests
        ;;
    *)
        usage
        ;;
esac