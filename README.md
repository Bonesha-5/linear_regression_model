# Rwanda Live Hen Price Prediction

## Mission and problem
My mission is to help Rwandan youth and smallholder farmers succeed in poultry farming through guidance on farm setup, flock care, vet access and profit tracking.
Farmers often sell hens without knowing what price to expect in different markets and months, which hurts their profits.
This project predicts the market price of a live hen in a given Rwandan market and month, so farmers can decide where and when to sell.

## Dataset
**WFP Food Prices for Rwanda** - real monthly retail prices collected by the UN World Food Programme in markets across all 5 provinces of Rwanda.
I used the live hen prices (2012-2015) as the target and joined the same market's prices for eggs, maize, soybeans, dry beans and beef as features, together with location (province, district, latitude, longitude) and time (year, month). The final modelling table has 1,639 rows and 11 features (2 categorical, 9 numeric).

Source: [Humanitarian Data Exchange - WFP Food Prices for Rwanda](https://data.humdata.org/dataset/wfp-food-prices-for-rwanda)

## API (Swagger UI)
Public endpoint for testing: **https://hen-price-api.onrender.com/docs**

- `POST /predict` - returns the predicted hen price (RWF) for the 11 inputs
- `POST /retrain` - upload a CSV with the same columns as the training data to retrain the model

Note: the API runs on Render's free plan and may take up to a minute to wake up on the first request.

## Video demo
YouTube: **To be added**

## How to run the mobile app
1. Install [Flutter](https://docs.flutter.dev/get-started/install) and set up an Android emulator (Android Studio -> Device Manager) or connect an Android phone with USB debugging on.
2. Clone this repository:
   ```bash
   git clone https://github.com/Bonesha-5/linear_regression_model.git
   ```
3. Go into the Flutter app folder:
   ```bash
   cd linear_regression_model/summative/FlutterApp
   ```
4. Install the dependencies:
   ```bash
   flutter pub get
   ```
5. Start the emulator, then check it is detected:
   ```bash
   flutter devices
   ```
6. Run the app on the emulator (use the device ID shown by `flutter devices`):
   ```bash
   flutter run -d emulator-5554 or flutter run -d 32151JEHN10602 #depends on method you use like debugging or another emulator
   ```
7. In the app, choose a province and district (latitude and longitude fill in automatically), enter the year, month and local prices, then tap **Predict**.

## Model results
Four scikit-learn models were trained and compared on the same test set (mean squared error, lower is better):

| Model | Train MSE | Test MSE |
|---|---|---|
| **Random Forest (best, saved)** | 13,971 | **108,982** |
| Decision Tree | 0 | 171,765 |
| Linear Regression (closed form) | 195,577 | 186,904 |
| Linear Regression (SGD, gradient descent) | 200,416 | 197,283 |

Random Forest has the lowest test MSE (typical error about +or- 330 RWF on an average price of ~3,900 RWF), so it is the model served by the API.

## Limitations
The WFP data only records hen prices for 2012–2015. Prices have risen a lot since then, so the model underpredicts current prices. The `/retrain` endpoint lets the model learn from newer market data without redeploying.

## Repository structure
```
linear_regression_model/
├── README.md
├── .gitignore                       # excludes .venv, caches and the retrain sample CSV
└── summative/
    ├── pyproject.toml
    ├── uv.lock
    ├── linear_regression/
    │   ├── multivariate.ipynb       # data preparation, 4 models, loss curve, saved model
    │   └── wfp_food_prices_rwa.csv  # raw WFP dataset (source linked above)
    ├── API/
    │   ├── prediction.py            # FastAPI: /predict, /retrain, CORS
    │   ├── requirements.txt
    │   └── best_model.pkl           # Random Forest + preprocessing + training data
    └── FlutterApp/                  # one-page Flutter mobile app
```
