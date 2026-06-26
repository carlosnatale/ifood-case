-- =============================================================
-- src/03_gold.sql  |  iFood Case - Data Architect
-- -------------------------------------------------------------
-- Camada Gold: tabelas de consumo para os usuarios finais.
-- =============================================================

CREATE OR REPLACE TABLE ifood_case.gold.receita_mensal
USING DELTA AS
SELECT
    ano_mes,
    COUNT(*)                    AS total_corridas,
    ROUND(SUM(total_amount), 2) AS receita_total,
    ROUND(AVG(total_amount), 2) AS ticket_medio_corrida
FROM ifood_case.silver.yellow_trips
GROUP BY ano_mes;

CREATE OR REPLACE TABLE ifood_case.gold.passageiros_por_hora
USING DELTA AS
SELECT
    ano_mes,
    hora_pickup,
    COUNT(*)                       AS total_corridas,
    ROUND(AVG(passenger_count), 2) AS media_passageiros
FROM ifood_case.silver.yellow_trips
GROUP BY ano_mes, hora_pickup;

-- Disponibilizacao para o usuario final
SELECT * FROM ifood_case.gold.receita_mensal ORDER BY ano_mes;
SELECT * FROM ifood_case.gold.passageiros_por_hora
WHERE ano_mes = '2023-05' ORDER BY hora_pickup;

-- Delta time travel: auditoria de versoes
DESCRIBE HISTORY ifood_case.silver.yellow_trips;
