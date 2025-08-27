#!/usr/bin/env python3
from __future__ import annotations
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from typing import List, Dict, Any, Optional, Set
import hashlib, json, time, os
import httpx
import uvicorn
import argparse
import asyncio

class Transaction(BaseModel):
    sender: str
    recipient: str
    amount: float

class Block(BaseModel):
    index: int
    timestamp: float
    transactions: List[Dict[str, Any]]
    previous_hash: str
    nonce: int
    difficulty: int
    merkle_root: str
    hash: str

def sha256_hex(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()

def merkle_root_from_transactions(transactions: List[Dict[str, Any]]) -> str:
    """Calculate Merkle Root from transactions"""
    if not transactions:
        return "0"*64
    
    # Hash each transaction
    layer = [sha256_hex(json.dumps(tx, sort_keys=True).encode()) for tx in transactions]
    
    # Build merkle tree
    while len(layer) > 1:
        nxt = []
        for i in range(0, len(layer), 2):
            l = layer[i]
            r = layer[i] if i+1 == len(layer) else layer[i+1]  # duplicate last if odd
            nxt.append(sha256_hex((l+r).encode()))
        layer = nxt
    
    return layer[0]

def hash_block_header(index: int, timestamp: float, previous_hash: str, 
                     merkle_root: str, nonce: int, difficulty: int) -> str:
    """Hash the block header for mining"""
    header = {
        "index": index,
        "timestamp": round(timestamp, 6),
        "previous_hash": previous_hash,
        "merkle_root": merkle_root,
        "nonce": nonce,
        "difficulty": difficulty
    }
    return sha256_hex(json.dumps(header, sort_keys=True, separators=(",", ":")).encode())

def valid_pow(difficulty: int, h: str) -> bool:
    """Check if hash satisfies proof-of-work difficulty"""
    return h.startswith("0" * difficulty)

def make_genesis_block(difficulty: int) -> Block:
    """Create the genesis block"""
    ts = 1720000000.0
    merkle = "0" * 64
    nonce = 0
    
    # Mine genesis block
    h = hash_block_header(0, ts, "0"*64, merkle, nonce, difficulty)
    while not valid_pow(difficulty, h):
        nonce += 1
        h = hash_block_header(0, ts, "0"*64, merkle, nonce, difficulty)
    
    return Block(
        index=0,
        timestamp=ts,
        transactions=[],
        previous_hash="0"*64,
        nonce=nonce,
        difficulty=difficulty,
        merkle_root=merkle,
        hash=h
    )

def valid_block(prev: Block, new: Block) -> bool:
    """Validate a new block against the previous block"""
    if new.index != prev.index + 1:
        return False
    if new.previous_hash != prev.hash:
        return False
    if new.merkle_root != merkle_root_from_transactions(new.transactions):
        return False
    if new.hash != hash_block_header(new.index, new.timestamp, new.previous_hash, 
                                   new.merkle_root, new.nonce, new.difficulty):
        return False
    if not valid_pow(new.difficulty, new.hash):
        return False
    return True

def valid_chain(chain: List[Block]) -> bool:
    """Validate entire blockchain"""
    if not chain:
        return False
    
    for i in range(1, len(chain)):
        if not valid_block(chain[i-1], chain[i]):
            return False
    return True

# Configuration
DEFAULT_DIFFICULTY = int(os.environ.get("DIFFICULTY", "4"))
DEFAULT_PORT = int(os.environ.get("PORT", "8000"))
NODE_ID = os.environ.get("NODE_ID", f"node-{DEFAULT_PORT}")

class NodeState:
    def __init__(self, difficulty: int = DEFAULT_DIFFICULTY):
        self.chain: List[Block] = [make_genesis_block(difficulty)]
        self.mempool: List[Dict[str, Any]] = []
        self.peers: Set[str] = set()
        self.node_id = NODE_ID
    
    @property
    def last_block(self) -> Block:
        return self.chain[-1]

# Global state
_mempool_keys: Set[str] = set()
state = NodeState()

# FastAPI app
app = FastAPI(
    title="Mini Bitcoin Node",
    version="1.0.0",
    description=f"Bitcoin Node {NODE_ID}"
)

@app.get("/health")
def health():
    """Health check endpoint"""
    return {
        "status": "ok",
        "node_id": state.node_id,
        "height": state.last_block.index,
        "difficulty": state.last_block.difficulty,
        "peers": len(state.peers),
        "mempool_size": len(state.mempool)
    }

class RegisterPeersReq(BaseModel):
    peers: List[str]

@app.post("/nodes/register")
def register_nodes(req: RegisterPeersReq):
    """Register peer nodes"""
    for p in req.peers:
        state.peers.add(p.rstrip("/"))
    return {
        "message": "peers registered",
        "total": len(state.peers),
        "peers": sorted(state.peers)
    }

@app.get("/peers")
def get_peers():
    """Get list of peer nodes"""
    return {"peers": sorted(state.peers)}

@app.get("/transactions/pool")
def tx_pool():
    """Get transaction pool"""
    return {
        "count": len(state.mempool),
        "transactions": state.mempool
    }

@app.post("/transaction", status_code=201)
@app.post("/transaction", status_code=201)
def new_transaction(tx: Transaction):
    if tx.amount <= 0:
        raise HTTPException(400, "Amount must be positive")
    if tx.sender == tx.recipient:
        raise HTTPException(400, "Sender and recipient cannot be the same")

    key = json.dumps(tx.dict(), sort_keys=True)
    if key not in _mempool_keys:
        _mempool_keys.add(key)
        state.mempool.append(tx.dict())

        for peer in list(state.peers):
            try:
                with httpx.Client(timeout=3.0) as client:
                    client.post(f"{peer}/transaction", json=tx.dict())
            except Exception:
                pass

    return {"message": "transaction queued", "pool_size": len(state.mempool)}

@app.get("/chain")
def full_chain(summary: bool=False):
    if summary:
        return {"length": len(state.chain),
                "last": state.chain[-1].dict() if state.chain else None}
    return {"length": len(state.chain),
            "chain": [b.dict() for b in state.chain]}

@app.get("/mine")
def mine(miner: Optional[str] = None, reward: float = 0.0, difficulty: Optional[int] = None):
    """Mine a new block"""
    if not state.mempool and reward <= 0:
        raise HTTPException(400, "Mempool empty; add transactions or set reward with miner")
    
    # Prepare transactions
    txs = list(state.mempool)
    if miner and reward > 0:
        # Add coinbase transaction
        txs.insert(0, {
            "sender": "COINBASE",
            "recipient": miner,
            "amount": float(reward)
        })
    
    # Block parameters
    idx = state.last_block.index + 1
    ts = time.time()
    prev_h = state.last_block.hash
    merkle = merkle_root_from_transactions(txs)
    nonce = 0
    diff = int(difficulty) if difficulty is not None else state.last_block.difficulty
    
    print(f"Mining block {idx} with difficulty {diff}...")
    start_time = time.time()
    
    # Proof of Work
    while True:
        h = hash_block_header(idx, ts, prev_h, merkle, nonce, diff)
        if valid_pow(diff, h):
            break
        nonce += 1
        
        # Progress indicator
        if nonce % 10000 == 0:
            print(f"Nonce: {nonce}")
    
    mining_time = time.time() - start_time
    print(f"Block mined! Nonce: {nonce}, Time: {mining_time:.2f}s")
    
    # Create new block
    new_block = Block(
        index=idx,
        timestamp=ts,
        transactions=txs,
        previous_hash=prev_h,
        nonce=nonce,
        difficulty=diff,
        merkle_root=merkle,
        hash=h
    )
    
    # Add to chain
    state.chain.append(new_block)
    state.mempool.clear()
    
    # Broadcast to peers
    broadcasted = 0
    for peer in list(state.peers):
        try:
            with httpx.Client(timeout=5.0) as client:
                response = client.post(f"{peer}/block", json=new_block.dict())
                if response.status_code == 200:
                    broadcasted += 1
        except Exception as e:
            print(f"Failed to broadcast to {peer}: {e}")
    
    return {
        "message": "block mined successfully",
        "block": new_block.dict(),
        "mining_time": mining_time,
        "broadcasted_to": broadcasted
    }

class BlockReq(Block):
    pass

@app.post("/block")
def receive_block(b: BlockReq):
    """Receive and validate new block from peer"""
    incoming = Block(**b.dict())
    last = state.last_block
    
    print(f"Received block {incoming.index} from peer")
    
    # Check if this block extends our chain
    if incoming.previous_hash == last.hash and incoming.index == last.index + 1:
        if valid_block(last, incoming):
            # Valid extension
            state.chain.append(incoming)
            
            # Remove included transactions from mempool
            included = {json.dumps(tx, sort_keys=True) for tx in incoming.transactions}
            state.mempool = [tx for tx in state.mempool 
                           if json.dumps(tx, sort_keys=True) not in included]
            
            print(f"Block {incoming.index} accepted")
            return {"message": "block accepted"}
        else:
            raise HTTPException(400, "invalid block")
    else:
        # Chain conflict - try to resolve
        print("Chain conflict detected, resolving...")
        replaced = resolve_conflicts()
        if replaced:
            return {"message": "chain replaced by longer valid chain"}
        raise HTTPException(409, "chain conflict unresolved; block rejected")

@app.get("/resolve")
def resolve():
    """Manually trigger chain conflict resolution"""
    replaced = resolve_conflicts()
    return {
        "message": "conflict resolution completed",
        "replaced": replaced,
        "length": len(state.chain)
    }

def resolve_conflicts() -> bool:
    """Resolve chain conflicts using longest chain rule"""
    new_chain = None
    max_length = len(state.chain)
    
    print(f"Resolving conflicts... Current chain length: {max_length}")
    
    for peer in list(state.peers):
        try:
            with httpx.Client(timeout=10.0) as client:
                r = client.get(f"{peer}/chain")
                if r.status_code != 200:
                    continue
                
                data = r.json()
                length = int(data["length"])
                candidate = [Block(**b) for b in data["chain"]]
                
                print(f"Peer {peer} chain length: {length}")
                
                if length > max_length and valid_chain(candidate):
                    max_length = length
                    new_chain = candidate
                    print(f"Found longer valid chain from {peer}")
                    
        except Exception as e:
            print(f"Failed to get chain from {peer}: {e}")
    
    if new_chain:
        print(f"Replacing chain with length {len(new_chain)}")
        state.chain = new_chain
        
        # Update mempool - remove transactions that are now in blocks
        included = set()
        for b in state.chain:
            for tx in b.transactions:
                included.add(json.dumps(tx, sort_keys=True))
        
        state.mempool = [tx for tx in state.mempool 
                        if json.dumps(tx, sort_keys=True) not in included]
        
        return True
    
    return False

@app.get("/")
def root():
    """Root endpoint with node info"""
    return {
        "message": f"Mini Bitcoin Node {state.node_id}",
        "endpoints": {
            "health": "GET /health",
            "chain": "GET /chain", 
            "mine": "GET /mine?miner=<address>&reward=<amount>",
            "transaction": "POST /transaction",
            "peers": "GET /peers",
            "register": "POST /nodes/register"
        }
    }

def main():
    """Main function to run the node"""
    parser = argparse.ArgumentParser(description="Mini Bitcoin Node")
    parser.add_argument("--port", type=int, default=DEFAULT_PORT, help="Port to run on")
    parser.add_argument("--difficulty", type=int, default=DEFAULT_DIFFICULTY, help="Mining difficulty")
    parser.add_argument("--node-id", type=str, help="Node identifier")
    
    args = parser.parse_args()
    
    # Set environment variables
    os.environ["PORT"] = str(args.port)
    os.environ["DIFFICULTY"] = str(args.difficulty)
    if args.node_id:
        os.environ["NODE_ID"] = args.node_id
    
    # Update global state
    global state
    state.node_id = os.environ.get("NODE_ID", f"node-{args.port}")
    
    print(f"Starting Bitcoin Node {state.node_id} on port {args.port}")
    print(f"Difficulty: {args.difficulty}")
    
    uvicorn.run(app, host="0.0.0.0", port=args.port, log_level="info")

if __name__ == "__main__":
    main()