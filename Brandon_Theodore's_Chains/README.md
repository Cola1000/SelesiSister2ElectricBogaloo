# IT'S NOT DONE YET
# Mini Bitcoin Network

Implementasi Bitcoin Network sederhana yang dapat dijalankan secara lokal dengan multiple nodes dan mendukung sinkronisasi antar-node.

## 🚀 Fitur

### ✅ Sudah Diimplementasi
- **Block Structure & Hashing**: Block dengan index, timestamp, transactions, previous_hash, hash menggunakan SHA-256
- **Mining**: Proof-of-Work dengan difficulty yang dapat diatur
- **Merkle Root**: Perhitungan merkle root dari transaksi-transaksi dalam block
- **Transaction Pool**: Pool transaksi yang belum masuk ke block
- **Networking**: REST API untuk komunikasi antar-node
- **Chain Synchronization**: Sinkronisasi menggunakan Longest Chain Rule
- **Peer Discovery**: Registrasi dan manajemen peer nodes
- **Conflict Resolution**: Penyelesaian konflik chain otomatis

### 🏗️ Struktur Block
```json
{
  "index": 1,
  "timestamp": 1720000000.0,
  "transactions": [
    {"sender": "Alice", "recipient": "Bob", "amount": 10.5}
  ],
  "previous_hash": "000abc123...",
  "nonce": 12345,
  "difficulty": 4,
  "merkle_root": "def456...",
  "hash": "0000789..."
}
```

## 📦 Requirements

Pastikan Anda memiliki Python 3.7+ dan install dependencies:

```bash
pip install -r requirements.txt
```

Requirements:
- fastapi==0.111.0
- uvicorn==0.30.1
- httpx==0.27.0
- pydantic==2.8.2

## 🎮 Quick Start

### 1. Menjalankan Network (Otomatis)

Gunakan script bash untuk menjalankan 3 nodes sekaligus:

```bash
# Buat script executable
chmod +x network_manager.sh

# Start semua nodes
./network_manager.sh start

# Cek status
./network_manager.sh status

# Run tests
./network_manager.sh test

# Stop semua nodes
./network_manager.sh stop
```

### 2. Menjalankan Node Manual

Anda juga bisa menjalankan node secara manual:

```bash
# Node 1 (Port 8001)
python node.py --port 8001 --node-id node1 --difficulty 4

# Node 2 (Port 8002) 
python node.py --port 8002 --node-id node2 --difficulty 4

# Node 3 (Port 8003)
python node.py --port 8003 --node-id node3 --difficulty 4
```

### 3. Setup Peer Connections

Setelah nodes berjalan, register peers untuk setiap node:

```bash
# Register peers untuk Node 1
curl -X POST http://localhost:8001/nodes/register \
  -H "Content-Type: application/json" \
  -d '{"peers": ["http://localhost:8002", "http://localhost:8003"]}'

# Register peers untuk Node 2
curl -X POST http://localhost:8002/nodes/register \
  -H "Content-Type: application/json" \
  -d '{"peers": ["http://localhost:8001", "http://localhost:8003"]}'

# Register peers untuk Node 3
curl -X POST http://localhost:8003/nodes/register \
  -H "Content-Type: application/json" \
  -d '{"peers": ["http://localhost:8001", "http://localhost:8002"]}'
```

### 4. Testing dengan Interactive Tester

```bash
# Interactive mode
python network_tester.py

# Automated tests
python network_tester.py --auto

# Custom ports
python network_tester.py --ports 8001 8002 8003 8004
```

## 🔧 API Endpoints

### Node Health
```bash
GET /health
# Response: {"status": "ok", "node_id": "node1", "height": 5, "difficulty": 4}
```

### Transactions
```bash
# Add transaction
POST /transaction
Content-Type: application/json
{
  "sender": "Alice",
  "recipient": "Bob", 
  "amount": 10.5
}

# View transaction pool
GET /transactions/pool
```

### Mining
```bash
# Mine new block
GET /mine?miner=MinerName&reward=12.5&difficulty=4

# Mine without reward (only process mempool)
GET /mine
```

### Blockchain
```bash
# Get full chain
GET /chain

# Resolve conflicts
GET /resolve
```

### Peer Management
```bash
# Register peers
POST /nodes/register
Content-Type: application/json
{
  "peers": ["http://localhost:8002", "http://localhost:8003"]
}

# Get peers
GET /peers
```

## 🧪 Testing Scenarios

### Scenario 1: Basic Transaction Flow
1. Start 3 nodes
2. Add beberapa transaksi
3. Mine block di satu node
4. Verifikasi block tersebar ke semua node

### Scenario 2: Chain Synchronization
1. Stop satu node
2. Mine beberapa block di node lain
3. Start kembali node yang di-stop
4. Verifikasi node catch-up dengan chain terpanjang

### Scenario 3: Concurrent Mining
1. Add banyak transaksi
2. Mine secara bersamaan di multiple nodes
3. Verifikasi hanya satu chain yang menang (longest chain rule)

### Scenario 4: Conflict Resolution
1. Isolate satu node dari network
2. Mine different blocks di isolated node vs network
3. Reconnect node
4. Verifikasi longest chain rule diterapkan

## 🔄 Cara Kerja Sinkronisasi

### Ketika Node Menerima Block Baru:
1. **Valid Extension**: Block extends current chain → langsung diterima
2. **Chain Conflict**: Block tidak extend current chain → resolve conflicts
3. **Longest Chain Rule**: Query semua peers, ambil chain terpanjang yang valid
4. **Mempool Update**: Hapus transaksi yang sudah masuk block dari mempool

### Proof of Work:
- Difficulty menentukan jumlah leading zeros di hash
- Node mencoba berbagai nonce sampai hash memenuhi syarat  
- Mining time tergantung difficulty dan processing power

### Merkle Root:
- Hash semua transaksi dalam block
- Build binary tree dengan hash pairs
- Root adalah single hash representing all transactions

## 📊 Monitoring

### Check Node Status:
```bash
curl http://localhost:8001/health
```

### View Blockchain:
```bash
curl http://localhost:8001/chain | jq '.'
```

### Check Transaction Pool:
```bash
curl http://localhost:8001/transactions/pool | jq '.'
```

### Monitor Logs:
```bash
tail -f logs/node-8001.log
tail -f logs/node-8002.log  
tail -f logs/node-8003.log
```

## 🎛️ Configuration

### Environment Variables:
- `PORT`: Port number (default: 8000)
- `DIFFICULTY`: Mining difficulty (default: 4)
- `NODE_ID`: Node identifier (default: node-{port})

### Script Variables:
- `PORTS`: Space-separated ports untuk network_manager.sh
- `DIFFICULTY`: Global mining difficulty

### Contoh Custom Configuration:
```bash
# Start dengan difficulty tinggi
DIFFICULTY=6 ./network_manager.sh start

# Start dengan ports custom
PORTS="9001 9002 9003 9004" ./network_manager.sh start
```

## 🐛 Troubleshooting

### Node Tidak Start:
- Cek port sudah digunakan: `lsof -i :8001`
- Cek logs: `tail -f logs/node-8001.log`
- Kill process: `pkill -f "node.py"`

### Nodes Tidak Sinkron:
- Manual resolve: `curl http://localhost:8001/resolve`
- Restart semua nodes: `./network_manager.sh stop && ./network_manager.sh start`
- Cek peer connections: `curl http://localhost:8001/peers`

### Mining Terlalu Lambat:
- Turunkan difficulty: `DIFFICULTY=2 ./network_manager.sh start`
- atau gunakan parameter: `GET /mine?difficulty=2`

### Mempool Penuh:
- Mine block: `GET /mine?miner=cleanup`
- Clear dengan restart: `./network_manager.sh stop && ./network_manager.sh start`

## 🔒 Security Notes

⚠️ **Ini adalah implementasi untuk pembelajaran - JANGAN gunakan di production!**

Missing security features:
- Digital signatures untuk transaksi
- Address validation
- Balance checking  
- Network encryption
- DoS protection
- Input sanitization

## 🧩 Extension Ideas

- [ ] Digital signatures dengan elliptic curve cryptography
- [ ] UTXO model instead of account balance
- [ ] Persistent storage (database)
- [ ] WebSocket untuk real-time updates
- [ ] REST API documentation dengan Swagger
- [ ] Docker containerization
- [ ] Adjustable difficulty berdasarkan block time
- [ ] Transaction fees
- [ ] Multi-signature transactions

## 📚 Understanding the Code

### Key Components:

1. **Block**: Data structure containing transactions and metadata
2. **Transaction**: Simple transfer between sender and recipient
3. **Mining**: Proof-of-Work algorithm finding valid nonce
4. **Chain**: List of validated blocks
5. **Mempool**: Pending transactions waiting to be mined
6. **Peers**: Other nodes in the network
7. **Sync**: Longest chain rule implementation

### Important Functions:

- `hash_block_header()`: Creates block hash for mining
- `valid_pow()`: Validates proof-of-work
- `merkle_root_from_transactions()`: Calculates merkle root
- `valid_block()`: Validates block structure and PoW
- `resolve_conflicts()`: Implements longest chain rule

## 🤝 Contributing

Contributions welcome! Areas for improvement:
- Security enhancements
- Performance optimizations  
- Better error handling
- More test scenarios
- Documentation improvements

## 📄 License

MIT License - lihat file LICENSE untuk detail lengkap.

---

**Happy Mining! ⛏️💎**