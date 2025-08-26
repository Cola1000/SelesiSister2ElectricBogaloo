
# Banking (COBOL + FastAPI)

This is a tiny banking demo where a COBOL program reads `input.txt`, updates/reads `accounts.txt`, and writes to `output.txt`. A FastAPI app (`app.py`) provides a simple HTTP API and static HTML to interact with the COBOL binary.

## What I fixed

- **COBOL record lengths**: `IN-RECORD`, `ACC-RECORD-RAW`, and `TMP-RECORD` were `PIC X(15)` but actual lines are 18 chars (`6` for account + `3` for action + `9` for amount with dot). Now `PIC X(18)`.
- **Field slicing**: Offsets were wrong (e.g., `1:5`). Now use positions `1:6` (account), `7:3` (action), `10:9` (amount).
- **DEP/WDR math**: Reversed previously. Now `DEP` adds and `WDR` subtracts (with insufficient-funds guard).
- **Output writing**: Previously `OUT-RECORD` wasn't written to `output.txt`. Added `WRITE-OUTPUT` step.
- **Consistent update**: When balance changes, write the updated record to `temp.txt` and atomically `mv` to `accounts.txt`.
- **Rai → IDR conversion**: Added automatic conversion in COBOL output (default `1 RAI = 100,000,000 IDR`). You can adjust the constant inside `main.cob` (search for `RAI-TO-IDR`).

## Build & Run (Docker)

```bash
# from this directory
docker build -t banking:latest .
docker run -it --rm -p 8000:8000 banking:latest
```

Open the UI: `http://localhost:8000`

Example curl:
```bash
# Check balance
curl -X POST http://localhost:8000/banking \
  -H 'Content-Type: application/json' \
  -d '{"account":"123456","action":"BAL","amount":0}'
```

## Kubernetes

1. Push your image:
```bash
# tag & push (replace username)
docker tag banking:latest YOUR_DOCKERHUB_USERNAME/banking:latest
docker push YOUR_DOCKERHUB_USERNAME/banking:latest
```

2. Deploy:
```bash
kubectl apply -f k8s/deployment.yaml
kubectl apply -f k8s/service.yaml
# optional, if you have an Ingress controller
kubectl apply -f k8s/ingress.yaml
```

**Tip (Kubernetes & the hardcoded URL in `index.html`)**: the HTML calls `http://127.0.0.1:8000/banking`. To keep it working without editing HTML, use:

```bash
kubectl port-forward svc/banking-svc 8000:8000
# then open http://127.0.0.1:8000 in your browser
```

Access:
- Via NodePort: `http://<node-ip>:30080`
- Via Ingress (if configured): `http://banking.local/`

> Note: the `Deployment` mounts an `emptyDir` over `/app` to allow writes to `accounts.txt`. For persistence, replace `emptyDir` with a `PersistentVolumeClaim`.

## File formats

- `accounts.txt`: `AAAAAAXXX#########` (6-digit account, 3-letter action, 9-char amount with dot, e.g. `123456BAL001690.00`)
- `input.txt`: Same layout, e.g. `123456WDR000100.00`
- `output.txt`: A single line with message and **IDR conversion** appended, e.g.  
  `BALANCE: 001690.00 | ≈ IDR Rp 169000000000.00`

## Dev notes

- Do **not** modify `app.py` or `index.html` (per assignment). All fixes are inside `main.cob` and containerization manifests.
- The conversion rate is a constant in COBOL; adjust as needed.
```

