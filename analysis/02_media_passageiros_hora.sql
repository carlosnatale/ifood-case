-- analysis/02_media_passageiros_hora.sql

SELECT hora_pickup AS hora_do_dia,
       ROUND(AVG(passenger_count), 2) AS media_passageiros,
       COUNT(*) AS total_corridas
FROM ifood_case.silver.yellow_trips
WHERE ano_mes = '2023-05'
GROUP BY hora_pickup ORDER BY hora_pickup;

-- Pico de volume: 18h (237.971 corridas) | Maior media: 02h (1.46) | Menor: 06h (1.26)
