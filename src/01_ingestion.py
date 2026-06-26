# =============================================================
# 01_ingestion.py  |  iFood Case - Data Architect
# -------------------------------------------------------------
# Etapa de INGESTAO (PySpark).
#   Fonte TLC (Parquet) -> Landing Zone (Volume) -> Bronze (Delta)
#
# Atende ao requisito do case: "Deve utilizar PySpark em alguma etapa".
# Ambiente: Databricks Free Edition (serverless).
# Linguagem do notebook: Python.
# =============================================================

import os
import glob
import urllib.request
from functools import reduce
from pyspark.sql import functions as F

# -------------------------------------------------------------
# Celula 1 - Parametros
# -------------------------------------------------------------
LANDING = "/Volumes/ifood_case/bronze/landing"
BASE_URL = "https://d37ci6vzurychx.cloudfront.net/trip-data"
MESES = ["2023-01", "2023-02", "2023-03", "2023-04", "2023-05"]
TABELA_BRONZE = "ifood_case.bronze.yellow_tripdata_raw"

# -------------------------------------------------------------
# Celula 2 - Download para a landing zone (idempotente)
#   O 'skip' evita baixar de novo arquivos que ja existem.
#   Plano B: se a rede bloquear, faca upload manual pela UI
#   (Catalog > Volume landing > Upload to volume) e pule esta celula.
# -------------------------------------------------------------
os.makedirs(LANDING, exist_ok=True)

for mes in MESES:
    arquivo = f"yellow_tripdata_{mes}.parquet"
    destino = f"{LANDING}/{arquivo}"
    if os.path.exists(destino):
        print(f"[skip] {arquivo} ja existe")
        continue
    url = f"{BASE_URL}/{arquivo}"
    print(f"[download] {url}")
    urllib.request.urlretrieve(url, destino)
    print(f"[ok] {destino}")

print("Arquivos na landing:", os.listdir(LANDING))

# Saida real obtida:
#   [skip] yellow_tripdata_2023-01.parquet ja existe
#   [skip] yellow_tripdata_2023-02.parquet ja existe
#   [skip] yellow_tripdata_2023-03.parquet ja existe
#   [skip] yellow_tripdata_2023-04.parquet ja existe
#   [skip] yellow_tripdata_2023-05.parquet ja existe
#   Arquivos na landing: ['yellow_tripdata_2023-01.parquet', ... , '2023-05.parquet']

# -------------------------------------------------------------
# Celula 3 - Leitura com CAST EXPLICITO por arquivo + union
# -------------------------------------------------------------
# ARMADILHA REAL DO DATASET:
#   Os Parquets do TLC tem tipos divergentes entre meses.
#   passenger_count (e congestion_surcharge) vem como INT em
#   alguns arquivos e DOUBLE em outros.
#
#   - Impor um schema na leitura NAO resolve: o leitor vetorizado
#     do Spark recusa o cast INT32 -> DOUBLE e lanca
#     SchemaColumnConvertNotSupportedException.
#   - A config spark.sql.parquet.enableVectorizedReader = false
#     NAO esta disponivel no runtime serverless da Free Edition
#     (erro CONFIG_NOT_AVAILABLE.WITHOUT_SUGGESTION).
#
# SOLUCAO (robusta, sem depender de config de cluster):
#   ler cada arquivo individualmente, aplicar .cast() explicito
#   em todas as colunas e unir tudo com unionByName.
# -------------------------------------------------------------
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

# Metadados de linhagem (boa pratica de governanca):
#   registra QUANDO cada lote foi ingerido.
df_bronze = df_raw.withColumn("_ingestao_ts", F.current_timestamp())

# Gravacao da Bronze em Delta
(
    df_bronze.write
    .format("delta")
    .mode("overwrite")
    .option("overwriteSchema", "true")
    .saveAsTable(TABELA_BRONZE)
)

total = spark.table(TABELA_BRONZE).count()
print(f"\nBronze gravada em {TABELA_BRONZE}: {total} linhas")

# -------------------------------------------------------------
# Resultado real obtido (contagem por arquivo e total da Bronze):
#   [lido] yellow_tripdata_2023-01.parquet: 3066766 linhas
#   [lido] yellow_tripdata_2023-02.parquet: 2913955 linhas
#   [lido] yellow_tripdata_2023-03.parquet: 3403766 linhas
#   [lido] yellow_tripdata_2023-04.parquet: 3288250 linhas
#   [lido] yellow_tripdata_2023-05.parquet: 3513649 linhas
#
#   Bronze gravada: 16186386 linhas
# -------------------------------------------------------------
