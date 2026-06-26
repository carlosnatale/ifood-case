-- =============================================================
-- 02_silver.sql  |  iFood Case - Data Architect
-- -------------------------------------------------------------
-- Camada SILVER: dados limpos, tipados e com as colunas
-- obrigatorias garantidas. Particionada por ano_mes.
--
-- Garante as 5 colunas exigidas pelo case na camada de consumo:
--   VendorID, passenger_count, total_amount,
--   tpep_pickup_datetime, tpep_dropoff_datetime
--
-- Linguagem do notebook: SQL.
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
    -- Colunas derivadas para acelerar as analises
    DATE_FORMAT(tpep_pickup_datetime, 'yyyy-MM') AS ano_mes,      -- particao
    HOUR(tpep_pickup_datetime)                   AS hora_pickup    -- hora do embarque
FROM ifood_case.bronze.yellow_tripdata_raw
WHERE
    -- 1) Janela real do case (remove datas vazadas de outros meses
    --    presentes nos arquivos mensais do TLC)
    tpep_pickup_datetime >= '2023-01-01'
    AND tpep_pickup_datetime <  '2023-06-01'
    -- 2) Regras de qualidade de negocio
    AND total_amount    IS NOT NULL
    AND total_amount    >= 0     -- remove estornos / erros de medidor (valores negativos)
    AND passenger_count IS NOT NULL
    AND passenger_count >  0     -- remove corridas sem passageiro (invalidas p/ analise)
    AND tpep_dropoff_datetime > tpep_pickup_datetime;  -- remove timestamps invertidos

-- -------------------------------------------------------------
-- Celula 2 - Sanidade: distribuicao por mes
-- -------------------------------------------------------------
SELECT ano_mes,
       COUNT(*)                    AS corridas,
       ROUND(AVG(total_amount), 2) AS ticket_medio
FROM ifood_case.silver.yellow_trips
GROUP BY ano_mes
ORDER BY ano_mes;

-- Resultado real obtido:
--   ano_mes | corridas | ticket_medio
--   2023-01 | 2917665  | 27.46
--   2023-02 | 2764200  | 27.37
--   2023-03 | 3226999  | 28.28
--   2023-04 | 3109876  | 28.78
--   2023-05 | 3319397  | 29.45
--   ---------------------------------
--   Total Silver: 15.337.137 linhas
--   (Bronze 16.186.386 -> Silver 15.337.137: ~849 mil linhas
--    removidas pela limpeza, ~5,2% do volume bruto)

-- -------------------------------------------------------------
-- Celula 3 - Quality gate: confirma que a limpeza funcionou
--            (nenhuma linha pode violar as regras de negocio)
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

-- Resultado real obtido (todos zerados = limpeza OK):
--   viola_valor_negativo | viola_passageiros | viola_tempo
--   0                    | 0                 | 0
