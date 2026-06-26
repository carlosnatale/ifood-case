-- =============================================================
-- 00_setup.sql  |  iFood Case - Data Architect
-- -------------------------------------------------------------
-- Cria o catalogo, os schemas da arquitetura Medallion e o
-- Volume da landing zone.
--
-- Ambiente: Databricks Free Edition (serverless, Unity Catalog).
-- Executar UMA vez, antes de qualquer outra etapa.
-- Linguagem do notebook: SQL.
-- =============================================================

-- Celula 1: catalogo raiz do projeto
CREATE CATALOG IF NOT EXISTS ifood_case;

-- Celula 2: schemas da arquitetura Medallion
--   bronze -> dado bruto (raw)
--   silver -> dado limpo e tipado
--   gold   -> dado pronto para consumo
CREATE SCHEMA IF NOT EXISTS ifood_case.bronze;
CREATE SCHEMA IF NOT EXISTS ifood_case.silver;
CREATE SCHEMA IF NOT EXISTS ifood_case.gold;

-- Celula 3: Volume para a landing zone (arquivos Parquet originais do TLC)
CREATE VOLUME IF NOT EXISTS ifood_case.bronze.landing;

-- -------------------------------------------------------------
-- Resultado esperado:
--   Caminho fisico da landing zone disponivel em:
--     /Volumes/ifood_case/bronze/landing/
--   As 3 celulas retornam tabela vazia (comandos DDL), sem erro.
-- -------------------------------------------------------------
