
# Banking (COBOL + FastAPI)

## Build & Run (Docker)

```bash
# from this directory
docker build -t banking:latest .
docker run -it --rm -p 8000:8000 banking:latest
```

Open the UI: `http://localhost:8000`

Example curl:
```bash
# Cek saldo
curl -X POST http://localhost:8000/banking \
  -H 'Content-Type: application/json' \
  -d '{"account":"123456","action":"BAL","amount":0}'

# Setor 100.00
curl -X POST http://localhost:8000/banking \
  -H 'Content-Type: application/json' \
  -d '{"account":"123456","action":"DEP","amount":100.00}'

# Tarik 50.00
curl -X POST http://localhost:8000/banking \
  -H 'Content-Type: application/json' \
  -d '{"account":"123456","action":"WDR","amount":50.00}'

```

## Kubernetes

> Notes: This might not work :c

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

## BONUS:

### Conversion to IDR

### Interest

Adds Interest (Compound) to every account in `accounts.txt` **every 23 seconds**.
Disabled by default; only runs when you execute the COBOL binary with the `-apply-interest` flag.
This feature does **not** modify the FastAPI/Python layer.

* **Default rate:** `INTEREST-RATE = 0.10` (≈ **10% per 23 seconds**) — edit in `main.cob` then rebuild.
* **Atomic update:** writes to `temp.txt` then `mv temp.txt accounts.txt` to avoid partial writes.
* **Stop it:** `Ctrl+C` (interactive) or stop the container/pod.

**Run locally (dev):**

```bash
# compile once (if testing outside Docker)
cobc -x -free -o main main.cob

# start interest loop (runs forever; Ctrl+C to stop)
./main -apply-interest
```

**Run inside Docker (alongside the API):**

```bash
# start the API
docker run -d --name banking -p 8000:8000 banking:latest

# start interest loop in the same container
docker exec -it banking ./main -apply-interest
```

**Run in Kubernetes:**

```bash
# start interest loop in the running pod (interactive; Ctrl+C to stop)
kubectl exec -it deploy/banking-app -- ./main -apply-interest
```

**Quick test (single cycle) without changing code:**

```bash
# Docker: run ~1 cycle then exit
docker exec -it banking sh -lc 'timeout 25s ./main -apply-interest || true'

# Kubernetes: same idea
kubectl exec -it deploy/banking-app -- sh -lc 'timeout 25s ./main -apply-interest || true'
```

> Tip: backup before testing — e.g., `cp accounts.txt accounts.bak`.