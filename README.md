# iFood Case – Data Architect

Solução de ponta a ponta para ingestão, disponibilização, qualidade de dados, governança e análise das corridas de **yellow taxi de Nova York (NYC TLC)**, referentes a **janeiro a maio de 2023**.

Arquitetura **Medallion** (Bronze / Silver / Gold) em **Delta Lake**, com ingestão em **PySpark**, camada de consumo e análise em **SQL**, qualidade de dados documentada com profiling e quality log, e classificação de sensibilidade dos campos alinhada à **LGPD**. Executado na **Databricks Free Edition**.

---

## Arquitetura

```
Fonte TLC (Parquet público, jan-mai/2023)
        |
        v
[ Landing Zone ]  /Volumes/ifood_case/bronze/landing/    <- arquivos originais intactos
        |  PySpark (cast explícito por arquivo)
        v
[ Bronze ]  ifood_case.bronze.yellow_tripdata_raw         <- 16.186.386 linhas, Delta
        |  SQL (profiling antes da limpeza)
        v
[ Silver ]  ifood_case.silver.yellow_trips                <- 15.337.137 linhas, Delta, PARTITIONED BY (ano_mes)
        |  SQL (quality gate + quality log)
        v
[ Gold ]    ifood_case.gold.receita_mensal                <- agregação mensal
            ifood_case.gold.passageiros_por_hora          <- média por hora do dia
            ifood_case.gold.field_classification          <- catálogo de sensibilidade LGPD
        |
        v
[ Usuário final ]  consultas SQL diretas nas tabelas Gold
```

| Camada | Responsabilidade | Linguagem |
|--------|-----------------|-----------|
| Landing | Cópia fiel dos Parquets originais | |
| Bronze | Raw em Delta + metadados de linhagem (`_ingestao_ts`), schema reconciliado | PySpark |
| Silver | Dados limpos, tipados, colunas obrigatórias garantidas, particionada | SQL |
| Gold | Tabelas de consumo, métricas e catálogo de classificação | SQL |

---

## Estrutura do repositório

```
ifood-case/
├─ src/
│  ├─ 00_setup.sql                       # Catálogo, schemas e Volume
│  ├─ 01_ingestion.py                    # PySpark: download + landing + Bronze
│  ├─ 02_silver.sql                      # Limpeza, qualidade, quality log
│  └─ 03_gold.sql                        # Tabelas de consumo + time travel
├─ analysis/
│  ├─ 01_media_total_amount.sql          # Pergunta 1 (duas interpretações)
│  └─ 02_media_passageiros_hora.sql      # Pergunta 2
├─ governance/
│  ├─ 00b_profiling.sql                  # Profiling da Bronze (qualidade da fonte)
│  └─ 04_data_classification.sql         # Catálogo de sensibilidade LGPD
├─ notebooks/
│  ├─ 00_setup.ipynb
│  ├─ 01_ingestion.ipynb
│  ├─ 02_silver.ipynb
│  ├─ 03_gold.ipynb
│  ├─ 00b_profiling.sql.ipynb
│  ├─ 04_data_classification.ipynb
│  ├─ analysis.ipynb
│  └─ visual_analysis.ipynb              # Análise visual com gráficos (matplotlib)
├─ README.md
└─ requirements.txt
```

> Os arquivos em `src/`, `analysis/` e `governance/` são a fonte canônica (código limpo e versionável).
> A pasta `notebooks/` contém os mesmos passos exportados do Databricks **com os outputs de execução visíveis**.

---

## Como executar

> A **Community Edition foi descontinuada** em 01/01/2026. Use a **Databricks Free Edition** (gratuita, sem cartão de crédito, serverless): https://www.databricks.com/learn/free-edition

Execute na ordem abaixo. Cada notebook corresponde a um arquivo em `src/` ou `governance/`.

### Passo 1 – Setup (`src/00_setup.sql`)

Cria o catálogo Unity Catalog, os 3 schemas e o Volume da landing zone.

```sql
CREATE CATALOG IF NOT EXISTS ifood_case;
CREATE SCHEMA IF NOT EXISTS ifood_case.bronze;
CREATE SCHEMA IF NOT EXISTS ifood_case.silver;
CREATE SCHEMA IF NOT EXISTS ifood_case.gold;
CREATE VOLUME IF NOT EXISTS ifood_case.bronze.landing;
```

### Passo 2 – Ingestão PySpark (`src/01_ingestion.py`)

Faz o download dos 5 Parquets para o Volume e materializa a **Bronze** em Delta.

```
Origem: https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_2023-{MM}.parquet
Destino: /Volumes/ifood_case/bronze/landing/
Tabela:  ifood_case.bronze.yellow_tripdata_raw
```

> **Decisão técnica – conflito de schema:** `passenger_count` e `congestion_surcharge` aparecem como INT em alguns meses e DOUBLE em outros. A opção `enableVectorizedReader=false` não está disponível no runtime serverless da Free Edition. Solução: ler cada arquivo individualmente com `.cast()` explícito e unir com `unionByName`.

| Arquivo | Linhas |
|---------|--------|
| yellow_tripdata_2023-01.parquet | 3.066.766 |
| yellow_tripdata_2023-02.parquet | 2.913.955 |
| yellow_tripdata_2023-03.parquet | 3.403.766 |
| yellow_tripdata_2023-04.parquet | 3.288.250 |
| yellow_tripdata_2023-05.parquet | 3.513.649 |
| **Bronze total** | **16.186.386** |

### Passo 3 – Profiling da Bronze (`governance/00b_profiling.sql`)

Análise exploratória dos dados brutos **antes** da limpeza. Documenta a qualidade da fonte e justifica cada regra aplicada na Silver.

| Métrica | Valor |
|---------|-------|
| Total de linhas | 16.186.386 |
| Vendors distintos | 3 |
| Nulos em passenger_count | 428.665 |
| Passageiro = 0 | 273.481 |
| total_amount negativo (estornos) | 141.407 |
| Timestamps invertidos | 6.181 |
| Registros fora do período | 104 |
| Valor mínimo (total_amount) | -982,95 USD |
| Valor máximo (total_amount) | 6.304,90 USD |
| Data mais antiga encontrada | 2001-01-01 |
| Data mais recente encontrada | 2023-09-05 |

### Passo 4 – Silver (`src/02_silver.sql`)

Aplica as regras de qualidade (justificadas pelo profiling) e garante as **5 colunas obrigatórias**: `VendorID`, `passenger_count`, `total_amount`, `tpep_pickup_datetime`, `tpep_dropoff_datetime`.

| Regra | Registros removidos | Justificativa |
|-------|-------------------|---------------|
| `passenger_count IS NOT NULL` | 428.665 | Nulos identificados no profiling |
| `passenger_count > 0` | 273.481 | Corridas sem passageiro — inválidas |
| `total_amount >= 0` | 141.407 | Estornos e erros de medidor |
| `dropoff > pickup` | 6.181 | Timestamps invertidos |
| Janela jan–mai/2023 | 104 | Datas vazadas (2001 a set/2023) |
| **Total removido** | **849.249 (5,24%)** | |

Resultado por mês:

| ano_mes | corridas | ticket_medio (USD) |
|---------|----------|--------------------|
| 2023-01 | 2.917.665 | 27,46 |
| 2023-02 | 2.764.200 | 27,37 |
| 2023-03 | 3.226.999 | 28,28 |
| 2023-04 | 3.109.876 | 28,78 |
| 2023-05 | 3.319.397 | 29,45 |
| **Total Silver** | **15.337.137 (94,76%)** | |

Quality gate (todos zerados confirma a limpeza):

| viola_valor_negativo | viola_passageiros | viola_tempo |
|---------------------|-------------------|-------------|
| 0 | 0 | 0 |

O `02_silver.sql` também persiste o resultado de cada execução na tabela `ifood_case.bronze.quality_log` para auditoria contínua.

### Passo 5 – Gold (`src/03_gold.sql`)

Materializa as tabelas de consumo em Delta e demonstra o time travel para auditoria:

- `ifood_case.gold.receita_mensal` — receita total e ticket médio por mês
- `ifood_case.gold.passageiros_por_hora` — média de passageiros por hora do dia, por mês

```sql
SELECT * FROM ifood_case.gold.receita_mensal ORDER BY ano_mes;
SELECT * FROM ifood_case.gold.passageiros_por_hora WHERE ano_mes = '2023-05' ORDER BY hora_pickup;
DESCRIBE HISTORY ifood_case.silver.yellow_trips;  -- auditoria de versões Delta
```

### Passo 6 – Classificação de dados (`governance/04_data_classification.sql`)

Cria o catálogo de sensibilidade dos campos alinhado à LGPD:

| Campo | Tipo | Sensibilidade | LGPD |
|-------|------|--------------|------|
| total_amount | FINANCIAL | **RESTRICTED** | DADO_FINANCEIRO |
| vendor_id | IDENTIFIER | INTERNAL | DADO_CADASTRAL |
| tpep_pickup_datetime | OPERATIONAL | INTERNAL | — |
| tpep_dropoff_datetime | OPERATIONAL | INTERNAL | — |
| passenger_count | OPERATIONAL | INTERNAL | — |
| hora_pickup | DERIVED | PUBLIC | — |
| ano_mes | DERIVED | PUBLIC | — |

### Passo 7 – Análises (`analysis/`)

Scripts com as respostas às perguntas do case.

### Passo 8 – Visualização (`notebooks/visual_analysis.ipynb`)

Notebook Python com 5 seções e 10 gráficos em cores iFood (matplotlib): profiling, funil de qualidade, classificação de sensibilidade, análises das perguntas 1 e 2.

---

## Resultados das análises

### Pergunta 1 – Média de `total_amount` por mês

**Interpretação A — média do valor por corrida:**

| ano_mes | media_total_amount_por_corrida (USD) |
|---------|--------------------------------------|
| 2023-01 | 27,46 |
| 2023-02 | 27,37 |
| 2023-03 | 28,28 |
| 2023-04 | 28,78 |
| 2023-05 | 29,45 |

Tendência de alta de **+7,2%** de jan a mai, consistente com o aumento sazonal de demanda na primavera.

**Interpretação B — média da receita mensal da frota:**

| media_receita_mensal (USD) |
|---------------------------|
| 86.858.506,85 |

### Pergunta 2 – Média de `passenger_count` por hora do dia (maio/2023)

| hora_do_dia | media_passageiros | total_corridas |
|-------------|-------------------|----------------|
| 0 | 1,43 | 88.547 |
| 1 | 1,44 | 57.501 |
| 2 | 1,46 | 37.001 |
| 3 | 1,45 | 24.073 |
| 4 | 1,40 | 15.726 |
| 5 | 1,28 | 18.186 |
| 6 | 1,26 | 45.431 |
| 7 | 1,28 | 91.710 |
| 8 | 1,30 | 125.390 |
| 9 | 1,31 | 140.792 |
| 10 | 1,35 | 153.473 |
| 11 | 1,36 | 167.229 |
| 12 | 1,38 | 180.326 |
| 13 | 1,39 | 184.462 |
| 14 | 1,39 | 200.572 |
| 15 | 1,40 | 204.870 |
| 16 | 1,40 | 204.992 |
| 17 | 1,39 | 223.959 |
| 18 | 1,38 | 237.971 |
| 19 | 1,39 | 213.682 |
| 20 | 1,40 | 189.914 |
| 21 | 1,42 | 194.116 |
| 22 | 1,43 | 179.479 |
| 23 | 1,42 | 139.995 |

**Principais observações:**

- **Maior média** entre 00h–03h (1,43–1,46): grupos saindo da vida noturna.
- **Menor média** entre 05h–07h (1,26–1,28): deslocamentos individuais de trabalho.
- **Pico de volume** às 18h (237.971 corridas) com média baixa (1,38): saída do trabalho, viagens individuais.
- Banda estreita (1,26 a 1,46) o dia todo: yellow taxi de NY é majoritariamente um **modal individual**.

---

## Qualidade de dados e governança

### Profiling

O script `governance/00b_profiling.sql` analisa a Bronze antes de qualquer limpeza, documentando problemas por tipo com contagem e percentual. Cada regra da Silver tem evidência quantitativa no profiling — nenhum filtro é arbitrário.

### Quality gate e quality log

O `src/02_silver.sql` executa um quality gate após a limpeza (resultado: 0 violações) e persiste o resultado na tabela `ifood_case.bronze.quality_log` a cada execução, criando um histórico de qualidade auditável.

### Classificação de sensibilidade (LGPD)

O script `governance/04_data_classification.sql` cria o catálogo `ifood_case.gold.field_classification`, classificando cada campo da Silver por tipo (FINANCIAL, IDENTIFIER, OPERATIONAL, DERIVED), nível de sensibilidade (RESTRICTED, INTERNAL, PUBLIC) e categoria LGPD. `total_amount` é o único campo RESTRICTED/DADO_FINANCEIRO — seu acesso deve ser controlado e auditado.

### Linhagem e time travel

- A coluna `_ingestao_ts` na Bronze registra quando cada batch foi ingerido, permitindo rastrear a origem de qualquer registro.
- O Delta Lake mantém o histórico completo de versões da tabela Silver (`DESCRIBE HISTORY`), permitindo restaurar estados anteriores em caso de incidente de dados.

---

## Decisões técnicas

| Decisão | Justificativa |
|---------|--------------|
| Arquitetura Medallion | Separação de responsabilidades, rastreabilidade e reprocessamento sem tocar na fonte |
| Delta Lake | ACID, time travel, schema enforcement e evolution nativos |
| PySpark na ingestão | Requisito explícito do case; cast explícito resolve o conflito INT/DOUBLE sem config de cluster |
| SQL no consumo | Linguagem universal para o usuário final; legível e manutenível |
| Particionamento por `ano_mes` | Acelera queries analíticas e prepara para ingestão incremental futura |
| `_ingestao_ts` na Bronze | Linhagem de dados para auditoria de quando cada batch foi processado |
| Profiling antes da limpeza | Cada regra da Silver tem evidência quantitativa — sem filtro arbitrário |
| `quality_log` persistido | Histórico auditável de qualidade — governança contínua, não pontual |
| Classificação LGPD | Separa campos por sensibilidade, definindo políticas de acesso por nível |
| Duas interpretações da Pergunta 1 | Enunciado ambíguo; responder as duas demonstra rigor analítico |

---

## Dependências

```
pyspark==3.5.1
delta-spark==3.2.0
matplotlib==3.9.0
pandas==2.2.2
numpy==1.26.4
nbformat==5.10.4
```

> Na Databricks Free Edition, PySpark, Delta, matplotlib, pandas e numpy já vêm pré-instalados. O `requirements.txt` é para referência e execução local opcional.
