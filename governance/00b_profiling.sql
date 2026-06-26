-- =============================================================
-- governance/00b_profiling.sql  |  iFood Case - Data Architect
-- -------------------------------------------------------------
-- Analise exploratoria da Bronze ANTES da limpeza.
-- Documenta a qualidade da fonte e justifica cada regra da Silver.
-- Executar APOS 01_ingestion e ANTES de 02_silver.
-- =============================================================

SELECT
    COUNT(*)                                                              AS total_linhas,
    COUNT(DISTINCT VendorID)                                              AS vendors,

    -- Campos nulos
    SUM(CASE WHEN passenger_count IS NULL THEN 1 ELSE 0 END)             AS nulos_passenger,
    SUM(CASE WHEN total_amount   IS NULL THEN 1 ELSE 0 END)              AS nulos_total_amount,

    -- Violacoes de regra de negocio
    SUM(CASE WHEN passenger_count <= 0   THEN 1 ELSE 0 END)              AS passageiro_zero,
    SUM(CASE WHEN total_amount   <  0    THEN 1 ELSE 0 END)              AS valor_negativo,
    SUM(CASE WHEN tpep_dropoff_datetime
             <= tpep_pickup_datetime     THEN 1 ELSE 0 END)              AS timestamp_invertido,
    SUM(CASE WHEN tpep_pickup_datetime < '2023-01-01'
              OR tpep_pickup_datetime >= '2023-06-01' THEN 1 ELSE 0 END) AS fora_do_periodo,

    -- Estatisticas de total_amount
    MIN(total_amount)                                                     AS min_valor,
    MAX(total_amount)                                                     AS max_valor,
    ROUND(AVG(total_amount), 2)                                           AS media_valor,

    -- Amplitude temporal real da fonte
    MIN(tpep_pickup_datetime)                                             AS data_mais_antiga,
    MAX(tpep_pickup_datetime)                                             AS data_mais_recente

FROM ifood_case.bronze.yellow_tripdata_raw;

-- =============================================================
-- RESULTADO REAL OBTIDO:
-- -------------------------------------------------------------
-- total_linhas         : 16186386
-- vendors              : 3
-- nulos_passenger      : 428665   -> justifica: IS NOT NULL na Silver
-- nulos_total_amount   : 0
-- passageiro_zero      : 273481   -> justifica: > 0 na Silver
-- valor_negativo       : 141407   -> justifica: >= 0 na Silver (estornos)
-- timestamp_invertido  : 6181     -> justifica: dropoff > pickup na Silver
-- fora_do_periodo      : 104      -> justifica: filtro de janela temporal na Silver
-- min_valor            : -982.95  (estorno mais alto registrado)
-- max_valor            : 6304.90  (corrida mais cara)
-- media_valor          : 27.84
-- data_mais_antiga     : 2001-01-01 (dado vazado de outro periodo)
-- data_mais_recente    : 2023-09-05 (dado vazado de outro mes)
--
-- RESUMO DO IMPACTO DA LIMPEZA:
--   Bronze : 16.186.386 linhas
--   Silver : 15.337.137 linhas
--   Removidos: 849.249 linhas (5,24% do volume bruto)
-- =============================================================
