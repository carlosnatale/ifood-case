# iFood Case – Data Architect

Solução de ponta a ponta para ingestão, disponibilização e análise dos dados de corridas de **yellow taxi de Nova York (NYC TLC)**, referentes a **janeiro a maio de 2023**.

Arquitetura **Medallion** (Bronze / Silver / Gold) em **Delta Lake**, com ingestão em **PySpark** e camada de consumo e análise em **SQL**, executada na **Databricks Free Edition**.

---

## Arquitetura

```
Fonte TLC (Parquet público, jan-mai/2023)
        |
        v
[ Landing Zone ]  /Volumes/ifood_case/bronze/landing/   <- arquivos originais intactos
        |  PySpark (cast explícito por arquivo)
        v
[ Bronze ]  ifood_case.bronze.yellow_tripdata_raw        <- 16.186.386 linhas, Delta
        |  SQL
        v
[ Silver ]  ifood_case.silver.yellow_trips               <- 15.337.137 linhas, Delta, PARTITIONED BY (ano_mes)
        |  SQL
        v
[ Gold ]    ifood_case.gold.receita_mensal               <- agregação mensal
            ifood_case.gold.passageiros_por_hora         <- média por hora do dia
        |
        v
[ Usuário final ]  consultas SQL diretas nas tabelas Gold
```

| Camada | Responsabilidade | Linguagem |
|--------|-----------------|-----------|
| Landing | Cópia fiel dos Parquets originais | |
| Bronze | Raw em Delta + metadados de linhagem (_ingestao_ts), schema reconciliado | PySpark |
| Silver | Dados limpos, tipados, colunas obrigatórias garantidas, particionada | SQL |
| Gold | Tabelas de consumo e métricas prontas para o usuário final | SQL |

---

## Estrutura do repositório

```
ifood-case/
├─ src/
│  ├─ 00_setup.sql              # Catálogo, schemas e Volume
│  ├─ 01_ingestion.py           # PySpark: download + landing + Bronze
│  ├─ 02_silver.sql             # Limpeza, tipagem e colunas obrigatórias
│  └─ 03_gold.sql               # Tabelas de consumo
├─ analysis/
│  ├─ 01_media_total_amount.sql # Pergunta 1 (duas interpretações)
│  └─ 02_media_passageiros_hora.sql  # Pergunta 2
├─ README.md
└─ requirements.txt
```

---

## Como executar

> A **Community Edition foi descontinuada** em 01/01/2026. Use a **Databricks Free Edition** (gratuita, sem cartão de crédito, serverless):
> https://www.databricks.com/learn/free-edition

Execute os notebooks na ordem abaixo. Cada um corresponde a um arquivo em `src/`.

### Passo 1 – Setup (`00_setup`)
Cria o catálogo Unity Catalog, os 3 schemas e o Volume da landing zone.

```sql
CREATE CATALOG IF NOT EXISTS ifood_case;
CREATE SCHEMA IF NOT EXISTS ifood_case.bronze;
CREATE SCHEMA IF NOT EXISTS ifood_case.silver;
CREATE SCHEMA IF NOT EXISTS ifood_case.gold;
CREATE VOLUME IF NOT EXISTS ifood_case.bronze.landing;
```

### Passo 2 – Ingestão PySpark (`01_ingestion`)
Faz o download dos 5 Parquets direto para o Volume e materializa a **Bronze** em Delta.

```
Origem: https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_2023-{MM}.parquet
Destino: /Volumes/ifood_case/bronze/landing/
Tabela:  ifood_case.bronze.yellow_tripdata_raw
```

> **Decisão técnica – conflito de schema:** os Parquets do TLC têm tipos divergentes entre meses (`passenger_count` e `congestion_surcharge` aparecem como INT em alguns arquivos e DOUBLE em outros). A opção `enableVectorizedReader=false` não está disponível no runtime serverless da Free Edition. A solução adotada foi ler cada arquivo individualmente com `.cast()` explícito em todas as colunas e depois uni-los com `unionByName`. Isso elimina o conflito sem depender de configuração de cluster.

Resultado após execução:

| Arquivo | Linhas |
|---------|--------|
| yellow_tripdata_2023-01.parquet | 3.066.766 |
| yellow_tripdata_2023-02.parquet | 2.913.955 |
| yellow_tripdata_2023-03.parquet | 3.403.766 |
| yellow_tripdata_2023-04.parquet | 3.288.250 |
| yellow_tripdata_2023-05.parquet | 3.513.649 |
| **Bronze total** | **16.186.386** |

### Passo 3 – Silver (`02_silver`)
Aplica regras de qualidade e garante as **5 colunas obrigatórias** do case:
`VendorID`, `passenger_count`, `total_amount`, `tpep_pickup_datetime`, `tpep_dropoff_datetime`.

Regras aplicadas:

| Regra | Justificativa |
|-------|--------------|
| `tpep_pickup_datetime` entre 2023-01-01 e 2023-05-31 | Remove datas vazadas de outros anos/meses presentes nos arquivos mensais |
| `total_amount >= 0` | Registros negativos são estornos ou erros de medidor que distorcem médias |
| `passenger_count > 0` | Corridas com 0 passageiros são inválidas para análise de demanda |
| `tpep_dropoff_datetime > tpep_pickup_datetime` | Remove registros com timestamps invertidos |

Resultado – sanidade por mês:

| ano_mes | corridas | ticket_medio (USD) |
|---------|----------|--------------------|
| 2023-01 | 2.917.665 | 27.46 |
| 2023-02 | 2.764.200 | 27.37 |
| 2023-03 | 3.226.999 | 28.28 |
| 2023-04 | 3.109.876 | 28.78 |
| 2023-05 | 3.319.397 | 29.45 |
| **Total Silver** | **15.337.137** | |

Quality gate (todos os indicadores zerados confirma a limpeza):

| viola_valor_negativo | viola_passageiros | viola_tempo |
|---------------------|-------------------|-------------|
| 0 | 0 | 0 |

### Passo 4 – Gold (`03_gold`)
Materializa duas tabelas de consumo em Delta:

- `ifood_case.gold.receita_mensal` – receita total e ticket médio por mês
- `ifood_case.gold.passageiros_por_hora` – média de passageiros por hora do dia, por mês

Consulta para o usuário final:

```sql
SELECT * FROM ifood_case.gold.receita_mensal ORDER BY ano_mes;
SELECT * FROM ifood_case.gold.passageiros_por_hora WHERE ano_mes = '2023-05' ORDER BY hora_pickup;
```

### Passo 5 – Análises (`analysis`)
Scripts em `analysis/` com as respostas às perguntas do case.

---

## Resultados das análises

### Pergunta 1 – Média de `total_amount` por mês (todos os yellow taxis)

O enunciado admite duas leituras. Ambas foram respondidas.

**Interpretação A (principal) – média do valor por corrida, mês a mês:**

| ano_mes | media_total_amount_por_corrida (USD) |
|---------|--------------------------------------|
| 2023-01 | 27.46 |
| 2023-02 | 27.37 |
| 2023-03 | 28.28 |
| 2023-04 | 28.78 |
| 2023-05 | 29.45 |

Tendência de alta ao longo do período (+7,2% de jan a mai), consistente com o aumento sazonal de demanda na primavera em Nova York.

**Interpretação B (complemento) – média da receita mensal da frota no período:**

| media_receita_mensal (USD) |
|---------------------------|
| 86.858.506,85 |

A frota de yellow taxi faturou, em média, aproximadamente **USD 86,8 milhões por mês** entre janeiro e maio de 2023.

---

### Pergunta 2 – Média de `passenger_count` por hora do dia em maio/2023

Critério adotado: hora do embarque (`tpep_pickup_datetime`), que representa o momento em que o passageiro "pegou o táxi".

| hora_do_dia | media_passageiros | total_corridas |
|-------------|-------------------|----------------|
| 0 | 1.43 | 88.547 |
| 1 | 1.44 | 57.501 |
| 2 | 1.46 | 37.001 |
| 3 | 1.45 | 24.073 |
| 4 | 1.40 | 15.726 |
| 5 | 1.28 | 18.186 |
| 6 | 1.26 | 45.431 |
| 7 | 1.28 | 91.710 |
| 8 | 1.30 | 125.390 |
| 9 | 1.31 | 140.792 |
| 10 | 1.35 | 153.473 |
| 11 | 1.36 | 167.229 |
| 12 | 1.38 | 180.326 |
| 13 | 1.39 | 184.462 |
| 14 | 1.39 | 200.572 |
| 15 | 1.40 | 204.870 |
| 16 | 1.40 | 204.992 |
| 17 | 1.39 | 223.959 |
| 18 | 1.38 | 237.971 |
| 19 | 1.39 | 213.682 |
| 20 | 1.40 | 189.914 |
| 21 | 1.42 | 194.116 |
| 22 | 1.43 | 179.479 |
| 23 | 1.42 | 139.995 |

**Principais observações:**

- A **menor média de passageiros** ocorre às **05h–07h** (1.26–1.28), horário dominado por viagens individuais (trabalhadores em turno, deslocamentos ao aeroporto).
- A **maior média** ocorre entre **00h–03h** (1.43–1.46), provável reflexo de grupos saindo de bares e restaurantes à noite.
- O **pico de volume de corridas** é às **18h** (237.971 corridas), coincidindo com o horário de saída do trabalho, mas com média de passageiros relativamente baixa (1.38), o que indica viagens predominantemente individuais.
- A média permanece em uma banda estreita (**1.26 a 1.46**) ao longo de todo o dia, sugerindo que o yellow taxi em Nova York é majoritariamente um modal individual.

---

## Decisões técnicas

| Decisão | Justificativa |
|---------|--------------|
| Arquitetura Medallion | Separação de responsabilidades, rastreabilidade e reprocessamento sem tocar na fonte |
| Delta Lake | ACID, time travel, schema enforcement e evolution nativos |
| PySpark na ingestão | Requisito explícito do case; cast explícito por arquivo resolve o conflito de tipos sem config de cluster |
| SQL no consumo | Linguagem universal para o usuário final; mais legível e manutenível para análises |
| Particionamento por `ano_mes` na Silver | Acelera todas as queries analíticas, que são quase sempre filtradas por mês |
| Colunas `_ingestao_ts` na Bronze | Rastreabilidade de linhagem: permite auditoria de quando cada batch foi ingerido |
| Duas interpretações da Pergunta 1 | O enunciado é ambíguo; apresentar as duas demonstra rigor analítico |

---

## Dependências

```
pyspark==3.5.1
delta-spark==3.2.0
```

> Na Databricks Free Edition, PySpark e Delta já vêm pré-instalados. O `requirements.txt` é para referência e execução local opcional.

