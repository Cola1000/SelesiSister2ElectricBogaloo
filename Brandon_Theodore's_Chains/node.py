
from __future__ import annotations
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from typing import List, Dict, Any, Optional, Set
import hashlib, json, time, os
import httpx

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
    if not transactions:
        return "0"*64
    layer = [sha256_hex(json.dumps(tx, sort_keys=True).encode()) for tx in transactions]
    while len(layer) > 1:
        nxt = []
        for i in range(0, len(layer), 2):
            l = layer[i]
            r = layer[i] if i+1 == len(layer) else layer[i+1]
            nxt.append(sha256_hex((l+r).encode()))
        layer = nxt
    return layer[0]

def hash_block_header(index:int,timestamp:float,previous_hash:str,merkle_root:str,nonce:int,difficulty:int)->str:
    header = {"index":index,"timestamp":round(timestamp,6),"previous_hash":previous_hash,"merkle_root":merkle_root,"nonce":nonce,"difficulty":difficulty}
    return sha256_hex(json.dumps(header, sort_keys=True, separators=(",",":")).encode())

def valid_pow(difficulty:int, h:str)->bool:
    return h.startswith("0"*difficulty)

def make_genesis_block(difficulty:int):
    ts = 1720000000.0
    merkle = "0"*64
    nonce = 0
    h = hash_block_header(0, ts, "0"*64, merkle, nonce, difficulty)
    while not valid_pow(difficulty, h):
        nonce += 1
        h = hash_block_header(0, ts, "0"*64, merkle, nonce, difficulty)
    return Block(index=0,timestamp=ts,transactions=[],previous_hash="0"*64,nonce=nonce,difficulty=difficulty,merkle_root=merkle,hash=h)

def valid_block(prev:Block,new:Block)->bool:
    if new.index != prev.index + 1: return False
    if new.previous_hash != prev.hash: return False
    if new.merkle_root != merkle_root_from_transactions(new.transactions): return False
    if new.hash != hash_block_header(new.index,new.timestamp,new.previous_hash,new.merkle_root,new.nonce,new.difficulty): return False
    if not valid_pow(new.difficulty,new.hash): return False
    return True

def valid_chain(chain: List[Block])->bool:
    if not chain: return False
    for i in range(1,len(chain)):
        if not valid_block(chain[i-1], chain[i]):
            return False
    return True

DEFAULT_DIFFICULTY = int(os.environ.get("DIFFICULTY","4"))
class NodeState:
    def __init__(self,difficulty:int=DEFAULT_DIFFICULTY):
        self.chain: List[Block] = [make_genesis_block(difficulty)]
        self.mempool: List[Dict[str,Any]] = []
        self.peers: Set[str] = set()
    @property
    def last_block(self)->Block:
        return self.chain[-1]

state = NodeState()
app = FastAPI(title="Mini Bitcoin Node",version="1.0.0")

@app.get("/health")
def health(): return {"status":"ok","height":state.last_block.index,"difficulty":state.last_block.difficulty}

class RegisterPeersReq(BaseModel): peers: List[str]
@app.post("/nodes/register")
def register_nodes(req: RegisterPeersReq):
    for p in req.peers: state.peers.add(p.rstrip("/"))
    return {"message":"peers registered","total":len(state.peers),"peers":sorted(state.peers)}

@app.get("/peers")
def get_peers(): return {"peers":sorted(state.peers)}

@app.get("/transactions/pool")
def tx_pool(): return {"count":len(state.mempool),"transactions":state.mempool}

@app.post("/transaction", status_code=201)
def new_transaction(tx: Transaction):
    state.mempool.append(tx.dict())
    return {"message":"transaction queued","pool_size":len(state.mempool)}

@app.get("/chain")
def full_chain(): return {"length":len(state.chain),"chain":[b.dict() for b in state.chain]}

@app.get("/mine")
def mine(miner: Optional[str]=None, reward: float=0.0, difficulty: Optional[int]=None):
    if not state.mempool and reward <= 0: raise HTTPException(400,"Mempool empty; add transactions or set reward with miner")
    txs = list(state.mempool)
    if miner and reward>0: txs.insert(0, {"sender":"COINBASE","recipient":miner,"amount":float(reward)})
    idx = state.last_block.index + 1
    ts = time.time()
    prev_h = state.last_block.hash
    merkle = merkle_root_from_transactions(txs)
    nonce = 0
    diff = int(difficulty) if difficulty is not None else state.last_block.difficulty
    while True:
        h = hash_block_header(idx, ts, prev_h, merkle, nonce, diff)
        if valid_pow(diff, h): break
        nonce += 1
    new_block = Block(index=idx,timestamp=ts,transactions=txs,previous_hash=prev_h,nonce=nonce,difficulty=diff,merkle_root=merkle,hash=h)
    state.chain.append(new_block)
    state.mempool.clear()
    import httpx
    for peer in list(state.peers):
        try:
            with httpx.Client(timeout=5.0) as client: client.post(f"{peer}/block", json=new_block.dict())
        except Exception: pass
    return {"message":"mined","block":new_block.dict(),"broadcasted_to":len(state.peers)}

class BlockReq(Block): pass
@app.post("/block")
def receive_block(b: BlockReq):
    incoming = Block(**b.dict()); last = state.last_block
    if incoming.previous_hash == last.hash and incoming.index == last.index + 1:
        if valid_block(last, incoming):
            state.chain.append(incoming)
            included = {json.dumps(tx, sort_keys=True) for tx in incoming.transactions}
            state.mempool = [tx for tx in state.mempool if json.dumps(tx, sort_keys=True) not in included]
            return {"message":"accepted"}
        else: raise HTTPException(400,"invalid block")
    else:
        replaced = resolve_conflicts()
        if replaced: return {"message":"replaced-by-longest"}
        raise HTTPException(409,"conflict unresolved; rejected")

@app.get("/resolve")
def resolve():
    replaced = resolve_conflicts()
    return {"replaced":replaced,"length":len(state.chain)}

def resolve_conflicts()->bool:
    new_chain=None; max_length=len(state.chain)
    for peer in list(state.peers):
        try:
            with httpx.Client(timeout=5.0) as client:
                r = client.get(f"{peer}/chain")
                if r.status_code!=200: continue
                data=r.json(); length=int(data["length"]); candidate=[Block(**b) for b in data["chain"]]
                if length>max_length and valid_chain(candidate):
                    max_length=length; new_chain=candidate
        except Exception: pass
    if new_chain:
        state.chain=new_chain
        included=set()
        for b in state.chain:
            for tx in b.transactions: included.add(json.dumps(tx, sort_keys=True))
        state.mempool=[tx for tx in state.mempool if json.dumps(tx, sort_keys=True) not in included]
        return True
    return False
