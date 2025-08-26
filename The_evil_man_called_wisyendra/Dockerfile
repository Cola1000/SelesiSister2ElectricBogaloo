FROM python:3.11-slim

# System deps: GnuCOBOL compiler and runtime
RUN apt-get update && apt-get install -y --no-install-recommends \
    gnucobol gcc \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Python deps
COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

# App sources
COPY app.py index.html main.cob accounts.txt ./

# Compile COBOL
RUN cobc -x -free -o main main.cob

# Expose FastAPI port
EXPOSE 8000

# Runtime
CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8000"]
