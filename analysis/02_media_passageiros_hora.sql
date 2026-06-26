-- =============================================================
-- analysis/02_media_passageiros_hora.sql  |  iFood Case
-- -------------------------------------------------------------
-- Pergunta 2: Qual a media de passageiros (passenger_count) por
-- cada hora do dia que pegaram taxi no mes de maio, considerando
-- todos os taxis da frota?
--
-- Criterio adotado: "hora em que pegaram o taxi" = hora do
-- embarque (tpep_pickup_datetime).
--
-- Linguagem do notebook: SQL.
-- =============================================================

SELECT
    hora_pickup                    AS hora_do_dia,    -- 0 a 23
    ROUND(AVG(passenger_count), 2) AS media_passageiros,
    COUNT(*)                       AS total_corridas
FROM ifood_case.silver.yellow_trips
WHERE ano_mes = '2023-05'
GROUP BY hora_pickup
ORDER BY hora_pickup;

-- -------------------------------------------------------------
-- Resultado real obtido (maio/2023):
--   hora_do_dia | media_passageiros | total_corridas
--    0 | 1.43 |  88547
--    1 | 1.44 |  57501
--    2 | 1.46 |  37001   <- maior media de passageiros (madrugada)
--    3 | 1.45 |  24073
--    4 | 1.40 |  15726
--    5 | 1.28 |  18186
--    6 | 1.26 |  45431   <- menor media (deslocamento individual de trabalho)
--    7 | 1.28 |  91710
--    8 | 1.30 | 125390
--    9 | 1.31 | 140792
--   10 | 1.35 | 153473
--   11 | 1.36 | 167229
--   12 | 1.38 | 180326
--   13 | 1.39 | 184462
--   14 | 1.39 | 200572
--   15 | 1.40 | 204870
--   16 | 1.40 | 204992
--   17 | 1.39 | 223959
--   18 | 1.38 | 237971   <- pico de VOLUME de corridas (saida do trabalho)
--   19 | 1.39 | 213682
--   20 | 1.40 | 189914
--   21 | 1.42 | 194116
--   22 | 1.43 | 179479
--   23 | 1.42 | 139995
--
-- Insights:
--   - Maior media de passageiros de madrugada (00h-03h, ~1.43-1.46):
--     grupos saindo da vida noturna.
--   - Menor media no inicio da manha (06h-07h, ~1.26-1.28):
--     viagens individuais de trabalho.
--   - Pico de demanda as 18h (237.971 corridas), mas media baixa
--     (1.38): saida do trabalho com viagens individuais.
--   - Banda estreita (1.26 a 1.46) o dia todo: o yellow taxi de NY
--     e majoritariamente um modal individual.
-- -------------------------------------------------------------
