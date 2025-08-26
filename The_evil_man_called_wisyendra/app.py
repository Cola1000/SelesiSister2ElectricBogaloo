from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel, Field
import subprocess
from pathlib import Path

app = FastAPI()

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

COBOL_EXEC = "./main"
INPUT_FILE = Path("input.txt")
OUTPUT_FILE = Path("output.txt")

class BankingRequest(BaseModel):
    account: str = Field(..., pattern=r"^\d{6}$")
    action: str = Field(..., pattern=r"^(NEW|DEP|WDR|BAL)$")
    amount: float = 0.0

@app.get("/")
def read_root():
    return FileResponse(Path(__file__).parent / "index.html")

@app.post("/banking")
def banking_op(req: BankingRequest):
    amount_str = f"{req.amount:09.2f}"
    input_line = f"{req.account}{req.action}{amount_str}"

    INPUT_FILE.write_text(input_line)

    try:
        subprocess.run([COBOL_EXEC], check=True)
    except subprocess.CalledProcessError as e:
        return {"status": "error", "message": str(e)}

    if OUTPUT_FILE.exists():
        result = OUTPUT_FILE.read_text().strip()
    else:
        result = "No output file"

    return {
        "status": "success",
        "result": result
    }
