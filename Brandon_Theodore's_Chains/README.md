# Mini Bitcoin Network

CHAINSS~~ FREAKY~~!!!

> [Video demo](https://drive.google.com/file/d/1Q4ZzUZC0OyTdJdK8pmwEzwcjlSQMnRdt/view?usp=sharing)

## Features
- Block: index, timestamp, transactions, previous_hash, nonce, difficulty, merkle_root, hash (SHA-256)
- Transaction mempool; optional coinbase on mining
- Proof-of-Work with configurable difficulty
- HTTP peer registration and block broadcast
- Longest-chain rule with conflict resolution

## Quick Start
```bash
cd PATH/TO/THIS/DIRECTORY
chmod +x nmgr.sh
./nmgr.sh start     # start nodes, auto-setup peers
./nmgr.sh test      # add tx, mine, verify sync
./nmgr.sh stop      # stop nodes
```
Notes: `nmgr.sh` auto-creates `.venv` and installs `requirements.txt`. Logs: `logs/node-PORT.log`. Configure with env: `PORTS_STR` and `DIFFICULTY`.

## Manual Run
```bash
python3 -m venv .venv && . .venv/bin/activate
pip install -r requirements.txt
python node.py --port 8001 --node-id node1 --difficulty 4
python node.py --port 8002 --node-id node2 --difficulty 4
python node.py --port 8003 --node-id node3 --difficulty 4
# register peers
curl -s -X POST http://localhost:8001/nodes/register -H 'Content-Type: application/json' -d '{"peers":["http://localhost:8002","http://localhost:8003"]}'
curl -s -X POST http://localhost:8002/nodes/register -H 'Content-Type: application/json' -d '{"peers":["http://localhost:8001","http://localhost:8003"]}'
curl -s -X POST http://localhost:8003/nodes/register -H 'Content-Type: application/json' -d '{"peers":["http://localhost:8001","http://localhost:8002"]}'
```

## API
- `GET /health` — node status
- `POST /nodes/register` — body: `{"peers":["http://host:port", ...]}`
- `GET /peers` — list peers
- `POST /transaction` — body: `{"sender":"A","recipient":"B","amount":1.0}` (201 Created)
- `GET /transactions/pool` — current mempool
- `GET /mine?miner=NAME&reward=12.5&difficulty=4` — mine and broadcast
- `POST /block` — receive a mined block from peer
- `GET /chain` — full chain
- `GET /resolve` — adopt the longest valid chain

## Notes
- PoW target: leading zeros per `difficulty`
- After mining, included transactions are removed from mempool
- No signatures/UTXO/balances; educational only

## License
MIT
