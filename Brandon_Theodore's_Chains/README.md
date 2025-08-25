# IT'S NOT DONE YET

# Cara cepat menjalankan (ringkas)

1. Buat venv & install deps:

```bash
python -m venv .venv && source .venv/bin/activate   # Windows: .venv\Scripts\activate
pip install -r requirements.txt
```

2. Jalankan 3 node (di terminal terpisah):

```bash
uvicorn node:app --port 5001 --reload
uvicorn node:app --port 5002 --reload
uvicorn node:app --port 5003 --reload
```

3. Registrasikan peer di masing-masing node:

```bash
curl -X POST localhost:5001/nodes/register -H "Content-Type: application/json" -d '{"peers":["http://localhost:5002","http://localhost:5003"]}'
curl -X POST localhost:5002/nodes/register -H "Content-Type: application/json" -d '{"peers":["http://localhost:5001","http://localhost:5003"]}'
curl -X POST localhost:5003/nodes/register -H "Content-Type: application/json" -d '{"peers":["http://localhost:5001","http://localhost:5002"]}'
```

4. Tambah transaksi & mining:

```bash
# tambahkan transaksi ke 5001
curl -X POST localhost:5001/transaction -H "Content-Type: application/json" -d '{"sender":"Alice","recipient":"Bob","amount":10.5}'
curl -X POST localhost:5001/transaction -H "Content-Type: application/json" -d '{"sender":"Charlie","recipient":"Diana","amount":3.2}'

# mine (dengan coinbase reward opsional 12.5 ke "Node1")
curl "localhost:5001/mine?miner=Node1&reward=12.5"
```

5. Cek sinkronisasi & konsensus:

```bash
curl localhost:5002/chain | jq
curl localhost:5003/chain | jq
# paksa resolve bila perlu
curl localhost:5002/resolve
```

# Fitur yang sudah ada

* **Block structure**: `index, timestamp, transactions, previous_hash, nonce, difficulty, merkle_root, hash`
* **Hashing**: SHA-256 atas header JSON terurut.
* **Mempool**: `POST /transaction` → antrean transaksi.
* **Mining (PoW)**: `GET /mine` — hash harus berawalan `0 * difficulty`.

  * Default difficulty = 4 (bisa override per-block via `?difficulty=5`).
* **Merkle Root**: dihitung dari daftar transaksi (duplikasi node terakhir kalau ganjil).
* **Networking**:

  * `POST /block` untuk menerima blok baru dari peer.
  * Node yang berhasil mining akan broadcast ke semua peers (best-effort).
* **Chain Synchronization**:

  * Validasi `previous_hash`, hash, PoW.
  * Jika konflik/tertinggal → `GET /resolve` ambil `/chain` dari peers dan terapkan **Longest Chain Rule**.
* **In-memory** (tanpa DB).
* Endpoint tambahan: `/health`, `/peers`, `/nodes/register`, `/transactions/pool`, `/chain`, `/resolve`.

# Requirement Gathering (Markdown)

Ada di file: `requirements.md` (ikut di ZIP). Isinya:

* Tujuan, lingkup, stakeholder
* Spesifikasi fungsional & non-fungsional
* Definisi PoW, struktur blok, dan Merkle root
* Spesifikasi endpoint & kriteria validasi
* Skenario uji (acceptance)
* Batasan & asumsi
* **Credits/References** (Nakamoto, 2008)