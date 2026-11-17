"""
Hen Price Prediction API
Predicts the retail price (RWF) of a live hen in a Rwandan market,
using the Random Forest model trained in multivariate.ipynb.
"""
import io
import threading
from pathlib import Path
from typing import Literal

import joblib
import pandas as pd
from fastapi import FastAPI, File, HTTPException, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field
from sklearn.base import clone

# Load the saved model bundle once at startup (from the repository file)

MODEL_PATH = Path(__file__).parent / "best_model.pkl"
bundle = joblib.load(MODEL_PATH)
model_lock = threading.Lock()  # stops /predict from reading a half-updated model

FEATURES = bundle["cat_features"] + bundle["num_features"]
TARGET = bundle["target"]

Province = Literal[
    "Eastern Province", "Kigali City", "Northern Province",
    "Southern Province", "Western Province",
]
District = Literal[
    "Bugesera", "Burera", "Gakenke", "Gatsibo", "Gicumbi", "Gisagara", "Huye",
    "Kamonyi", "Karongi", "Kayonza", "Kicukiro", "Kirehe", "Musanze", "Ngoma",
    "Ngororero", "Nyabihu", "Nyagatare", "Nyamagabe", "Nyamasheke", "Nyarugenge",
    "Nyaruguru", "Rubavu", "Ruhango", "Rulindo", "Rusizi", "Rutsiro", "Rwamagana",
]

app = FastAPI(
    title="Rwanda Live Hen Price Prediction API",
    description="Predicts the market price (RWF) of a live hen in a Rwandan market and month, "
                "to help poultry farmers decide where and when to sell.",
    version="1.0.0",
)

# CORS configuration
# ALLOWED: only the browser origins we trust -> our own deployed API page on
#   Render (so the Swagger UI works) and the local Flutter web debug server
#   (fixed to port 8080) for testing in a browser.
# RESTRICTED: every other website. We do NOT use "*", so an unknown site
#   cannot call this API from a visitor's browser.
# Methods: only GET (docs, health check) and POST (/predict, /retrain) - the
#   only methods this API uses. Headers: only Content-Type and Accept, which
#   JSON and file-upload requests need. Credentials: False, because the API
#   uses no cookies or login sessions, so browsers should never send them.

app.add_middleware(
    CORSMiddleware,
    allow_origins=[
        "https://hen-price-api.onrender.com",
        "http://localhost:8080",
        "http://127.0.0.1:8080",
    ],
    allow_methods=["GET", "POST"],
    allow_headers=["Content-Type", "Accept"],
    allow_credentials=False,
)


class HenPriceInput(BaseModel):
    province: Province = Field(
        description="Province where the market is located")
    district: District = Field(
        description="District where the market is located")
    latitude: float = Field(
        ge=-2.9, le=-1.0, description="Market latitude (inside Rwanda)")
    longitude: float = Field(
        ge=28.8, le=30.9, description="Market longitude (inside Rwanda)")
    year: int = Field(ge=2012, le=2030, description="Year of sale")
    month: int = Field(ge=1, le=12, description="Month of sale (1-12)")
    egg_price: float = Field(
        ge=20, le=1000, description="Price of one egg in the same market (RWF)")
    maize_price: float = Field(
        ge=50, le=2000, description="Price of 1 kg maize (RWF)")
    soybean_price: float = Field(
        ge=100, le=3000, description="Price of 1 kg soybeans (RWF)")
    beans_price: float = Field(
        ge=100, le=2000, description="Price of 1 kg dry beans (RWF)")
    beef_price: float = Field(
        ge=500, le=10000, description="Price of 1 kg beef (RWF)")

    model_config = {
        "json_schema_extra": {
            "example": {
                "province": "Northern Province", "district": "Gicumbi",
                "latitude": -1.53, "longitude": 30.08, "year": 2014, "month": 2,
                "egg_price": 100, "maize_price": 208.75, "soybean_price": 443.75,
                "beans_price": 331, "beef_price": 1800,
            }
        }
    }


class PredictionOutput(BaseModel):
    predicted_hen_price_rwf: float
    model: str


@app.get("/")
def home():
    return {"message": "Hen price prediction API is running. Open /docs to test it."}


@app.post("/predict", response_model=PredictionOutput)
def predict(data: HenPriceInput):
    row = pd.DataFrame([data.model_dump()])[FEATURES]
    with model_lock:
        processed = bundle["preprocessor"].transform(row)
        price = float(bundle["model"].predict(processed)[0])
    return PredictionOutput(predicted_hen_price_rwf=round(price, 2), model="Random Forest")


@app.post("/retrain")
async def retrain(file: UploadFile = File(..., description="CSV with the same columns as the training data")):
    if not file.filename.lower().endswith(".csv"):
        raise HTTPException(
            status_code=400, detail="Please upload a .csv file.")

    try:
        new_data = pd.read_csv(io.BytesIO(await file.read()))
    except Exception:
        raise HTTPException(
            status_code=400, detail="Could not read the CSV file.")

    required = FEATURES + [TARGET]
    missing = [c for c in required if c not in new_data.columns]
    if missing:
        raise HTTPException(
            status_code=400, detail=f"CSV is missing columns: {missing}")

    new_data = new_data[required].copy()
    for col in bundle["num_features"] + [TARGET]:
        new_data[col] = pd.to_numeric(new_data[col], errors="coerce")
    new_data = new_data.dropna()
    if new_data.empty:
        raise HTTPException(
            status_code=400, detail="No valid rows found in the CSV.")

    # Random Forest is not SGD, so we refit on ORIGINAL data + NEW rows
    combined = pd.concat(
        [bundle["training_data"], new_data], ignore_index=True)
    X, y = combined[FEATURES], combined[TARGET]

    new_preprocessor = clone(bundle["preprocessor"])
    new_model = clone(bundle["model"])
    new_model.fit(new_preprocessor.fit_transform(X), y)

    # Swap in the new model: /predict uses it immediately, no redeploy needed
    with model_lock:
        bundle["preprocessor"] = new_preprocessor
        bundle["model"] = new_model
        bundle["training_data"] = combined
    # The updated model lives in memory which it is lost when the
    # service restarts or sleeps, and the original model is loaded again.

    return {
        "message": "Model retrained and now in use.",
        "new_rows_added": int(len(new_data)),
        "total_training_rows": int(len(combined)),
    }
