-- =============================================================
-- governance/04_data_classification.sql  |  iFood Case
-- -------------------------------------------------------------
-- Catalogo de classificacao de sensibilidade dos campos.
-- Implementa a camada de Data Classification alinhada a LGPD,
-- separando campos por nivel de acesso e categoria regulatoria.
-- =============================================================

CREATE TABLE IF NOT EXISTS ifood_case.gold.field_classification (
    tabela        STRING,
    campo         STRING,
    tipo          STRING,    -- IDENTIFIER | FINANCIAL | OPERATIONAL | DERIVED
    sensibilidade STRING,    -- PUBLIC | INTERNAL | RESTRICTED
    lgpd_categoria STRING,   -- DADO_CADASTRAL | DADO_FINANCEIRO | NULL
    descricao     STRING
);

-- Limpa e reinsere para idempotencia
DELETE FROM ifood_case.gold.field_classification WHERE tabela = 'yellow_trips';

INSERT INTO ifood_case.gold.field_classification VALUES
('yellow_trips', 'vendor_id',             'IDENTIFIER',  'INTERNAL',   'DADO_CADASTRAL',  'ID do provedor TPEP - identifica a empresa de tecnologia'),
('yellow_trips', 'tpep_pickup_datetime',  'OPERATIONAL', 'INTERNAL',   NULL,              'Hora do embarque - dado de localizacao temporal'),
('yellow_trips', 'tpep_dropoff_datetime', 'OPERATIONAL', 'INTERNAL',   NULL,              'Hora do desembarque'),
('yellow_trips', 'passenger_count',       'OPERATIONAL', 'INTERNAL',   NULL,              'Quantidade de passageiros por corrida'),
('yellow_trips', 'total_amount',          'FINANCIAL',   'RESTRICTED', 'DADO_FINANCEIRO', 'Valor total cobrado - dado financeiro sensivel (LGPD Art. 5)'),
('yellow_trips', 'hora_pickup',           'DERIVED',     'PUBLIC',     NULL,              'Hora do embarque derivada para analise - sem identificacao'),
('yellow_trips', 'ano_mes',               'DERIVED',     'PUBLIC',     NULL,              'Particao mensal derivada para analise - sem identificacao');

-- Consulta final: classificacao ordenada por nivel de sensibilidade
SELECT * FROM ifood_case.gold.field_classification
ORDER BY
    CASE sensibilidade WHEN 'RESTRICTED' THEN 1 WHEN 'INTERNAL' THEN 2 ELSE 3 END,
    tipo;

-- =============================================================
-- RESULTADO REAL OBTIDO:
-- tabela       | campo                | tipo        | sensibilidade | lgpd_categoria  | descricao
-- yellow_trips | total_amount         | FINANCIAL   | RESTRICTED    | DADO_FINANCEIRO | Valor total cobrado...
-- yellow_trips | vendor_id            | IDENTIFIER  | INTERNAL      | DADO_CADASTRAL  | ID do provedor TPEP...
-- yellow_trips | tpep_pickup_datetime | OPERATIONAL | INTERNAL      | null            | Hora do embarque...
-- yellow_trips | passenger_count      | OPERATIONAL | INTERNAL      | null            | Quantidade de passageiros...
-- yellow_trips | tpep_dropoff_datetime| OPERATIONAL | INTERNAL      | null            | Hora do desembarque
-- yellow_trips | ano_mes              | DERIVED     | PUBLIC        | null            | Particao mensal...
-- yellow_trips | hora_pickup          | DERIVED     | PUBLIC        | null            | Hora do embarque derivada...
--
-- IMPLICACOES DE GOVERNANCA:
--   RESTRICTED (total_amount): acesso controlado, nao expor em Gold
--     sem necessidade de negocio; auditoria de acesso obrigatoria.
--   INTERNAL (vendor_id, datetimes): acesso para times de dados e
--     operacoes; nao compartilhar externamente sem anonimizacao.
--   PUBLIC (derived): colunas derivadas sem identificacao direta;
--     podem ser usadas em dashboards publicos.
-- =============================================================
