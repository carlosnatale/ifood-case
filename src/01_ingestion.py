# =============================================================
# src/01_ingestion.py  |  iFood Case - Data Architect
# -------------------------------------------------------------
# Etapa PySpark: download -> landing zone -> Bronze (Delta).
# =============================================================

import os
import glob
import urllib.request
from functools import reduce
from pyspark.sql import functions as F

LANDING     = "/Volumes/ifood_case/bronze/landing"
BASE_URL    = "https://d37ci6vzurychx.cloudfront.net/trip-data"
MESES       = ["2023-01", "2023-02", "2023-03", "2023-04", "2023-05"]
TABELA_BRONZE = "ifood_case.bronze.yellow_tripdata_raw"

# --- Download idempotente ---
os.makedirs(LANDING, exist_ok=True)
for mes in MESES:
    arquivo = f"yellow_tripdata_{mes}.parquet"
    destino = f"{LANDING}/{arquivo}"
    if os.path.exists(destino):
        print(f"[skip] {arquivo} ja existe"); continue
    urllib.request.urlretrieve(f"{BASE_URL}/{arquivo}", destino)
    print(f"[ok] {destino}")
print("Landing:", os.listdir(LANDING))

# --- Cast explicito por arquivo (resolve conflito INT/DOUBLE entre meses) ---
# Armadilha: passenger_count e congestion_surcharge variam entre INT e DOUBLE.
# enableVectorizedReader=false nao disponivel no serverless da Free Edition.
# Solucao: ler arquivo a arquivo, .cast() explicito, union.
dfs = []
for path in sorted(glob.glob(f"{LANDING}/yellow_tripdata_2023-*.parquet")):
    d = spark.read.parquet(path).select(
        F.col("VendorID").cast("long").alias("VendorID"),
        F.col("tpep_pickup_datetime").cast("timestamp"),
        F.col("tpep_dropoff_datetime").cast("timestamp"),
        F.col("passenger_count").cast("double"),
        F.col("trip_distance").cast("double"),
        F.col("RatecodeID").cast("double"),
        F.col("store_and_fwd_flag").cast("string"),
        F.col("PULocationID").cast("long"),
        F.col("DOLocationID").cast("long"),
        F.col("payment_type").cast("long"),
        F.col("fare_amount").cast("double"),
        F.col("extra").cast("double"),
        F.col("mta_tax").cast("double"),
        F.col("tip_amount").cast("double"),
        F.col("tolls_amount").cast("double"),
        F.col("improvement_surcharge").cast("double"),
        F.col("total_amount").cast("double"),
        F.col("congestion_surcharge").cast("double"),
        F.col("airport_fee").cast("double"),
    )
    dfs.append(d)
    print(f"[lido] {path.split('/')[-1]}: {d.count()} linhas")

df_raw = reduce(lambda a, b: a.unionByName(b), dfs)

# Metadados de linhagem
df_bronze = df_raw.withColumn("_ingestao_ts", F.current_timestamp())

(df_bronze.write.format("delta").mode("overwrite")
    .option("overwriteSchema", "true").saveAsTable(TABELA_BRONZE))

print(f"\nBronze gravada: {spark.table(TABELA_BRONZE).count()} linhas")

# Resultado real:
#   [lido] 2023-01: 3066766 | 2023-02: 2913955 | 2023-03: 3403766
#   [lido] 2023-04: 3288250 | 2023-05: 3513649
#   Bronze gravada: 16186386 linhas
