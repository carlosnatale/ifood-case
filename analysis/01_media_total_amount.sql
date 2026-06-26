-- =============================================================
-- analysis/01_media_total_amount.sql  |  iFood Case
-- -------------------------------------------------------------
-- Pergunta 1: Qual a media de valor total (total_amount) recebido
-- em um mes, considerando todos os yellow taxis da frota?
--
-- O enunciado e ambiguo ("media de valor total recebido em um mes"
-- pode ser media por corrida OU receita media mensal), entao
-- respondemos as DUAS interpretacoes e explicitamos a premissa.
--
-- Linguagem do notebook: SQL.
-- =============================================================

-- -------------------------------------------------------------
-- Interpretacao A (resposta principal):
-- media do valor por corrida, mes a mes.
-- "Em media, quanto vale uma corrida em cada mes?"
-- -------------------------------------------------------------
SELECT
    ano_mes,
    ROUND(AVG(total_amount), 2) AS media_total_amount_por_corrida
FROM ifood_case.silver.yellow_trips
GROUP BY ano_mes
ORDER BY ano_mes;

-- Resultado real obtido:
--   ano_mes | media_total_amount_por_corrida (USD)
--   2023-01 | 27.46
--   2023-02 | 27.37
--   2023-03 | 28.28
--   2023-04 | 28.78
--   2023-05 | 29.45
--   Insight: alta de +7,2% no ticket medio de jan a mai,
--   consistente com a retomada sazonal de demanda na primavera.

-- -------------------------------------------------------------
-- Interpretacao B (complemento):
-- media da receita mensal entre os 5 meses.
-- "Em media, quanto a frota fatura por mes no periodo?"
-- -------------------------------------------------------------
WITH receita_por_mes AS (
    SELECT ano_mes, SUM(total_amount) AS receita_mes
    FROM ifood_case.silver.yellow_trips
    GROUP BY ano_mes
)
SELECT ROUND(AVG(receita_mes), 2) AS media_receita_mensal
FROM receita_por_mes;

-- Resultado real obtido:
--   media_receita_mensal (USD)
--   86858506.85
--   Insight: a frota de yellow taxi faturou, em media,
--   ~USD 86,8 milhoes por mes entre jan e mai/2023.
