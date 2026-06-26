-- =============================================================
-- src/02_silver.sql  |  iFood Case - Data Architect
-- -------------------------------------------------------------
-- Camada SILVER: dados limpos, tipados e com as colunas
-- obrigatorias garantidas. Particionada por ano_mes.
--
-- Justificativa de cada regra baseada no profiling (00b):
--   - passenger_count nulos : 428.665 registros -> IS NOT NULL
--   - passageiro = 0        : 273.481 registros -> > 0
--   - total_amount negativo : 141.407 registros -> >= 0 (estornos)
--   - timestamp invertido   :   6.181 registros -> dropoff > pickup
--   - fora do periodo       :     104 registros -> janela temporal
-- =============================================================

-- -------------------------------------------------------------
-- Celula 1 - Criacao da tabela Silver
-- -------------------------------------------------------------
CREATE OR REPLACE TABLE ifood_case.silver.yellow_trips
USING DELTA
PARTITIONED BY (ano_mes)
AS
SELECT
    CAST(VendorID AS INT)                        AS vendor_id,
    tpep_pickup_datetime,
    tpep_dropoff_datetime,
    CAST(passenger_count AS INT)                 AS passenger_count,
    CAST(total_amount AS DECIMAL(10,2))          AS total_amount,
    DATE_FORMAT(tpep_pickup_datetime, 'yyyy-MM') AS ano_mes,
    HOUR(tpep_pickup_datetime)                   AS hora_pickup
FROM ifood_case.bronze.yellow_tripdata_raw
WHERE
    tpep_pickup_datetime >= '2023-01-01'
    AND tpep_pickup_datetime <  '2023-06-01'     -- 104 registros fora do periodo removidos
    AND total_amount    IS NOT NULL
    AND total_amount    >= 0                      -- 141.407 estornos/erros removidos
    AND passenger_count IS NOT NULL               -- 428.665 nulos removidos
    AND passenger_count >  0                      -- 273.481 corridas sem passageiro removidas
    AND tpep_dropoff_datetime > tpep_pickup_datetime; -- 6.181 timestamps invertidos removidos

-- -------------------------------------------------------------
-- Celula 2 - Sanidade: distribuicao por mes
-- -------------------------------------------------------------
SELECT ano_mes,
       COUNT(*)                    AS corridas,
       ROUND(AVG(total_amount), 2) AS ticket_medio
FROM ifood_case.silver.yellow_trips
GROUP BY ano_mes
ORDER BY ano_mes;

-- Resultado real:
--   2023-01 | 2917665 | 27.46
--   2023-02 | 2764200 | 27.37
--   2023-03 | 3226999 | 28.28
--   2023-04 | 3109876 | 28.78
--   2023-05 | 3319397 | 29.45
--   Total   : 15.337.137 (94,76% aproveitamento sobre Bronze)

-- -------------------------------------------------------------
-- Celula 3 - Quality gate
-- -------------------------------------------------------------
SELECT
    SUM(CASE WHEN total_amount < 0 THEN 1 ELSE 0 END)
        AS viola_valor_negativo,
    SUM(CASE WHEN passenger_count <= 0 THEN 1 ELSE 0 END)
        AS viola_passageiros,
    SUM(CASE WHEN tpep_dropoff_datetime <= tpep_pickup_datetime
             THEN 1 ELSE 0 END)
        AS viola_tempo
FROM ifood_case.silver.yellow_trips;

-- Resultado real: 0 | 0 | 0 (todas as regras satisfeitas)

-- -------------------------------------------------------------
-- Celula 4 - Quality log (historico de qualidade por execucao)
-- -------------------------------------------------------------
CREATE TABLE IF NOT EXISTS ifood_case.bronze.quality_log (
    run_ts             TIMESTAMP,
    camada             STRING,
    total_bronze       LONG,
    total_silver       LONG,
    pct_aproveitamento DOUBLE,
    removidos_nulo_pax LONG,
    removidos_pax_zero LONG,
    removidos_valor_neg LONG,
    removidos_ts_inv   LONG,
    removidos_periodo  LONG
);

INSERT INTO ifood_case.bronze.quality_log
WITH
  b AS (SELECT COUNT(*) AS n FROM ifood_case.bronze.yellow_tripdata_raw),
  s AS (SELECT COUNT(*) AS n FROM ifood_case.silver.yellow_trips),
  v AS (
    SELECT
        SUM(CASE WHEN passenger_count IS NULL THEN 1 ELSE 0 END) AS nulo_pax,
        SUM(CASE WHEN passenger_count <= 0   THEN 1 ELSE 0 END)  AS pax_zero,
        SUM(CASE WHEN total_amount    <  0   THEN 1 ELSE 0 END)  AS val_neg,
        SUM(CASE WHEN tpep_dropoff_datetime
                 <= tpep_pickup_datetime     THEN 1 ELSE 0 END)  AS ts_inv,
        SUM(CASE WHEN tpep_pickup_datetime < '2023-01-01'
                  OR tpep_pickup_datetime >= '2023-06-01'
                                             THEN 1 ELSE 0 END)  AS periodo
    FROM ifood_case.bronze.yellow_tripdata_raw
  )
SELECT
    CURRENT_TIMESTAMP(),
    'silver',
    b.n,
    s.n,
    ROUND(s.n * 100.0 / b.n, 2),
    v.nulo_pax,
    v.pax_zero,
    v.val_neg,
    v.ts_inv,
    v.periodo
FROM b, s, v;

-- Consulta o historico
SELECT * FROM ifood_case.bronze.quality_log ORDER BY run_ts DESC;

-- Resultado real da primeira execucao:
--   run_ts             | camada | total_bronze | total_silver | pct_aproveitamento | ...
--   2025-xx-xx xx:xx   | silver | 16186386     | 15337137     | 94.76              | ...
