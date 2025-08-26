# COBOL + FastAPI Debug Task

Your task:
1. Fix `main.cob` so it works correctly.
2. Fix `Dockerfile` so the app runs end-to-end.

Rules:
- **Do NOT modify** `app.py` or `index.html`.
- You can change anything in `main.cob` and `Dockerfile`.
- Input/output files (`input.txt`, `output.txt`, `accounts.txt`) are provided.

How to test:
```bash
docker build -t cobol-app .
docker run --rm -p 8000:8000 cobol-app
