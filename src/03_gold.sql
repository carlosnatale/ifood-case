-- =============================================================
-- 03_gold.sql  |  iFood Case - Data Architect
-- -------------------------------------------------------------
-- Camada GOLD: tabelas de consumo para os usuarios finais.
-- Isola o usuario da complexidade das camadas anteriores.
--
-- Linguagem do notebook: SQL.
-- =============================================================

-- -------------------------------------------------------------
-- Celula 1 - Receita e ticket medio por mes (suporta a Pergunta 1)
-- -------------------------------------------------------------
CREATE OR REPLACE TABLE ifood_case.gold.receita_mensal
USING DELTA AS
SELECT
    ano_mes,
    COUNT(*)                    AS total_corridas,
    ROUND(SUM(total_amount), 2) AS receita_total,
    ROUND(AVG(total_amount), 2) AS ticket_medio_corrida
FROM ifood_case.silver.yellow_trips
GROUP BY ano_mes;

-- -------------------------------------------------------------
-- Celula 2 - Media de passageiros por hora do dia (suporta a Pergunta 2)
-- -------------------------------------------------------------
CREATE OR REPLACE TABLE ifood_case.gold.passageiros_por_hora
USING DELTA AS
SELECT
    ano_mes,
    hora_pickup,
    COUNT(*)                       AS total_corridas,
    ROUND(AVG(passenger_count), 2) AS media_passageiros
FROM ifood_case.silver.yellow_trips
GROUP BY ano_mes, hora_pickup;

-- -------------------------------------------------------------
-- Celula 3 - Disponibilizacao para o usuario final (consumo via SQL)
-- -------------------------------------------------------------
-- Receita por mes
SELECT * FROM ifood_case.gold.receita_mensal ORDER BY ano_mes;

-- Passageiros por hora (maio)
SELECT * FROM ifood_case.gold.passageiros_por_hora
WHERE ano_mes = '2023-05'
ORDER BY hora_pickup;

-- -------------------------------------------------------------
-- Resultado real obtido (gold.passageiros_por_hora, maio/2023):
--   ano_mes | hora_pickup | total_corridas | media_passageiros
--   2023-05 |  0 |  88547 | 1.43
--   2023-05 |  1 |  57501 | 1.44
--   2023-05 |  2 |  37001 | 1.46
--   2023-05 |  3 |  24073 | 1.45
--   2023-05 |  4 |  15726 | 1.40
--   2023-05 |  5 |  18186 | 1.28
--   2023-05 |  6 |  45431 | 1.26
--   2023-05 |  7 |  91710 | 1.28
--   2023-05 |  8 | 125390 | 1.30
--   2023-05 |  9 | 140792 | 1.31
--   2023-05 | 10 | 153473 | 1.35
--   2023-05 | 11 | 167229 | 1.36
--   2023-05 | 12 | 180326 | 1.38
--   2023-05 | 13 | 184462 | 1.39
--   2023-05 | 14 | 200572 | 1.39
--   2023-05 | 15 | 204870 | 1.40
--   2023-05 | 16 | 204992 | 1.40
--   2023-05 | 17 | 223959 | 1.39
--   2023-05 | 18 | 237971 | 1.38   <- pico de volume de corridas
--   2023-05 | 19 | 213682 | 1.39
--   2023-05 | 20 | 189914 | 1.40
--   2023-05 | 21 | 194116 | 1.42
--   2023-05 | 22 | 179479 | 1.43
--   2023-05 | 23 | 139995 | 1.42
-- -------------------------------------------------------------
