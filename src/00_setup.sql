-- =============================================================
-- src/00_setup.sql  |  iFood Case - Data Architect
-- -------------------------------------------------------------
-- Cria o catalogo, schemas e Volume da landing zone.
-- Rodar UMA vez antes de qualquer outra etapa.
-- =============================================================

CREATE CATALOG IF NOT EXISTS ifood_case;

CREATE SCHEMA IF NOT EXISTS ifood_case.bronze;
CREATE SCHEMA IF NOT EXISTS ifood_case.silver;
CREATE SCHEMA IF NOT EXISTS ifood_case.gold;

CREATE VOLUME IF NOT EXISTS ifood_case.bronze.landing;

-- Caminho fisico da landing zone:
--   /Volumes/ifood_case/bronze/landing/
