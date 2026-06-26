-- analysis/01_media_total_amount.sql

-- Interpretacao A: media por corrida, mes a mes
SELECT ano_mes, ROUND(AVG(total_amount), 2) AS media_total_amount_por_corrida
FROM ifood_case.silver.yellow_trips GROUP BY ano_mes ORDER BY ano_mes;
-- 2023-01: 27.46 | 2023-02: 27.37 | 2023-03: 28.28 | 2023-04: 28.78 | 2023-05: 29.45

-- Interpretacao B: media da receita mensal no periodo
WITH r AS (SELECT ano_mes, SUM(total_amount) AS receita_mes
           FROM ifood_case.silver.yellow_trips GROUP BY ano_mes)
SELECT ROUND(AVG(receita_mes), 2) AS media_receita_mensal FROM r;
-- 86858506.85
