# Web_Crawler_Eleicao_2026

> Atividade prática de **Engenharia de Software** — Manifesto Ágil e Extreme Programming (XP)
> **UNIFACIMP WYDEN** · Curso: Sistemas de Informação · Professor: Thalles Canela
> **Aluno:** Ilderlan de Jesus Melo · **Matrícula:** 202502506783

## Objetivo

Evoluir o script `buscador.sh` (Shell Script) que consulta os resultados do TSE, aplicando práticas de XP:
retornar **todos os municípios do Maranhão**, separar **1º e 2º turno** e **indicar os eleitos**,
corrigindo falhas e melhorando legibilidade e mensagens de erro, sem mudar o propósito do script.
(No enunciado o arquivo aparece como `tse-top-candidates.sh`; no repositório-base ele se chama `buscador.sh`.)

## Pré-requisitos

- `bash` 4.4 ou superior (no macOS, instale com `brew install bash`)
- `curl` e `jq`
- Acesso à internet (API de resultados do TSE)

## Como executar

```bash
chmod +x buscador.sh
./buscador.sh -h                      # ajuda
./buscador.sh                         # todos os municípios do MA, 1º turno, todos os cargos
```

| Opção | Descrição | Padrão |
|-------|-----------|--------|
| `-u UF` | sigla da UF | `ma` |
| `-m MUNICÍPIO` | `todos` ou código TSE de 5 dígitos (ex.: `07242`) | `todos` |
| `-t TURNO` | `1`, `2` ou `ambos` | `1` |
| `-c "CARGOS"` | `1` Presidente · `3` Governador · `5` Senador · `6` Dep. Federal · `7` Dep. Estadual | `"6 7 5 3 1"` |
| `-n LIMITE` | máximo de candidatos por cargo | `20` |
| `-e` | mostra somente os eleitos | desligado |
| `-h` | ajuda | |

Variáveis de ambiente continuam valendo como padrão (`TSE_RESULTS_BASE_URL`, `_YEAR`, `_UF`, `_MUNICIPALITY`,
`_ROUND`, `_LIMIT`, `_ONLY_ELECTED`, `_COLOR`, `_FEDERAL_ELECTION`, `_STATE_ELECTION`,
`_FEDERAL_ELECTION_2T`, `_STATE_ELECTION_2T`). As opções de linha de comando têm prioridade.

### Exemplos

```bash
./buscador.sh -m 07242 -c 3              # Governador em um município
./buscador.sh -t ambos -c "1 3" -e       # só eleitos de Presidente/Governador, 1º e 2º turno
./buscador.sh -t 2 -c 1                  # 2º turno de Presidente em todos os municípios do MA
./buscador.sh -c 5 -n 5 > senadores.txt  # 5 mais votados a Senador por município, salvo em arquivo
```

Exemplo de saída (eleitos em maiúsculas, em verde/negrito no terminal ou com `*` quando sem cor):

```
==== SÃO LUÍS (07242) [1/1] ====

Governador (cargo 3) - 1º TURNO
+-----------------+--------+-------+------------+
| NOME            | NÚMERO | VOTOS | SITUAÇÃO   |
+-----------------+--------+-------+------------+
| EDUARDO BRAIDE  |     55 |   900 | ELEITO     | *
| ORLEANS BRANDÃO |     15 |   600 | Não eleito |
+-----------------+--------+-------+------------+
```

> **Sobre "ELEITO":** a coluna SITUAÇÃO mostra o status que o TSE informa para a eleição como um todo
> (por exemplo, o governador eleito do Maranhão aparece como `ELEITO` em todos os municípios, mesmo
> naqueles em que outro candidato teve mais votos). Não indica o mais votado em cada município;
> para isso, basta olhar a coluna VOTOS, que já vem ordenada do maior para o menor.

> Consultar os 217 municípios com 5 cargos faz ~1.000 requisições por turno e leva alguns minutos.
> Use `-c` e `-m` para consultas mais rápidas.

## Melhorias e correções realizadas

| Commit | O que mudou |
|--------|-------------|
| `refactor` | Funções (`validate_config`, `fetch_json`, `show_cargo`, `main`); falha de um cargo não aborta os outros; erro mostra HTTP e URL; lista vazia tratada; checagem de versão do bash |
| `fix` | Alinhamento das tabelas com acentos (`pad_left`/`pad_right` por caractere) |
| `feat` | Opções `-u -m -n -c -h` com validação |
| `feat` | Todos os municípios do MA, lidos da lista oficial do TSE (`config/mun-e…-cm.json`) |
| `feat` | 1º e 2º turno separados (`-t`); 2º turno só para Presidente/Governador; 404 vira resumo "sem dados" |
| `feat` | Coluna SITUAÇÃO com o status do TSE, destaque dos eleitos e filtro `-e` |
| `fix` | Remove o `\r` das saídas do `jq` no Windows (tabela embaralhada) e fixa `.sh` com LF via `.gitattributes` |

Diagnóstico completo (feito antes de alterar o código): ver `git log` e o primeiro commit deste README.

## Como o XP foi aplicado

- **Pequenas mudanças:** uma melhoria por commit, sem reescrever o projeto.
- **Feedback curto:** o script foi executado após cada alteração; o comportamento foi corrigido antes de seguir.
- **Refatoração contínua:** a primeira etapa só reorganizou o código, sem mudar o comportamento.
- **Integração frequente:** commits pequenos e descritivos, branch `melhoria-xp` integrada na `main`.
- **Simplicidade:** apenas `bash`, `curl` e `jq`; nenhuma dependência nova.
- **Software funcionando:** a `main` final continua executável.

## Divisão do pair programming

A atividade foi feita **individualmente** (sem dupla). Para manter a prática, os papéis foram alternados em ciclos
curtos pelo mesmo aluno: no papel de **Driver** implementei a mudança; no papel de **Navigator** revisei o diff,
questionei o resultado e executei o script antes de commitar.

## Evidências de validação

Cenários executados (cole abaixo a saída real de cada um):

| Cenário | Comando | Resultado esperado |
|---------|---------|--------------------|
| Ajuda | `./buscador.sh -h` | exibe o uso |
| Um município | `./buscador.sh -m 07242 -c 3` | tabela de Governador com SITUAÇÃO |
| Todos os municípios | `./buscador.sh -c 3 -n 3` | um bloco por município do MA, `[i/217]` |
| 1º turno | `./buscador.sh -m 07242 -t 1 -c 1` | título "1º TURNO" |
| 2º turno | `./buscador.sh -m 07242 -t 2 -c "1 3"` | tabela do 2º turno ou resumo "sem dados" |
| Eleitos | `./buscador.sh -m 07242 -c 5 -e` | só candidatos eleitos |
| Parâmetro inválido | `./buscador.sh -c 9` | `Erro: cargo não suportado` |
| Município inexistente | `./buscador.sh -m 99999 -c 3` | aviso com HTTP 404 e URL |
| Dependência ausente | executar sem `jq` | `Erro: jq não encontrado` |

```text
$ bash -c ./buscador.sh -h | head -6
Uso: ./buscador.sh [opções]

Consulta no TSE os candidatos mais votados por cargo.

Opções:
  -u UF         sigla da UF (padrão: ma)

$ ./buscador.sh -m 07242 -c 3

==== DAVINÓPOLIS (07242) [1/1] ====

Governador (cargo 3) - 1º TURNO
+-----------------+--------+-------+------------+
| NOME            | NÚMERO | VOTOS | SITUAÇÃO   |
+-----------------+--------+-------+------------+
| ORLEANS BRANDÃO |     15 |  4085 | Não eleito |
| EDUARDO BRAIDE  |     55 |  3992 | ELEITO     | *
| FELIPE CAMARÃO  |     13 |  1087 | Não eleito |
| ROBERTO ROCHA   |     28 |   156 | Não eleito |
| ANDRÉ LUIS      |     14 |    39 | Não eleito |
| SAULO ARCANGELI |     16 |     5 | Não eleito |
| REGINALDO LIMA  |     21 |     4 | Não eleito |
| DIMAS CASSIMIRO |     29 |     1 | Não eleito |
+-----------------+--------+-------+------------+

$ ./buscador.sh -m 07242 -t 1 -c 1 -n 5

==== DAVINÓPOLIS (07242) [1/1] ====

Presidente (cargo 1) - 1º TURNO
+-----------------------+--------+-------+------------+
| NOME                  | NÚMERO | VOTOS | SITUAÇÃO   |
+-----------------------+--------+-------+------------+
| LULA                  |     13 |  5232 | 2º turno   |
| FLAVIO BOLSONARO      |     22 |  3840 | 2º turno   |
| ESCRITOR AUGUSTO CURY |     70 |   238 | Não eleito |
| RENAN SANTOS          |     14 |   194 | Não eleito |
| RONALDO CAIADO        |     55 |   132 | Não eleito |
+-----------------------+--------+-------+------------+

$ ./buscador.sh -m 07242 -t 2 -c 1 3 -n 5

==== DAVINÓPOLIS (07242) [1/1] ====

Presidente (cargo 1) - 2º TURNO
+------------------+--------+-------+------------+
| NOME             | NÚMERO | VOTOS | SITUAÇÃO   |
+------------------+--------+-------+------------+
| LULA             |     13 |  5829 | ELEITO     | *
| FLAVIO BOLSONARO |     22 |  3885 | Não eleito |
+------------------+--------+-------+------------+

Sem dados disponíveis (normal quando o cargo não teve 2º turno ou a apuração não terminou):
  cargo 3, 2º turno: 1 consulta(s)

$ ./buscador.sh -m 07242 -c 5 -e

==== DAVINÓPOLIS (07242) [1/1] ====

Senador (cargo 5) - 1º TURNO
+----------------+--------+-------+----------+
| NOME           | NÚMERO | VOTOS | SITUAÇÃO |
+----------------+--------+-------+----------+
| LAHESIO BONFIM |    300 |  3956 | ELEITO   | *
| FUFUCA         |    111 |  1834 | ELEITO   | *
+----------------+--------+-------+----------+

$ ./buscador.sh -c 9
Erro: cargo não suportado: 9 (use 1, 3, 5, 6 ou 7)

$ ./buscador.sh -m 99999 -c 3

==== 99999 (99999) [1/1] ====
Aviso: falha ao consultar o cargo 3 (1º turno) no município 99999 (HTTP 404): https://resultados.tse.jus.br/oficial/ele2026/6259/dados/ma/ma99999-c0003-e006259-u.json
Erro: 1 consulta(s) com falha; veja os avisos acima

$ bash -c ./buscador.sh -c 3 -n 3 | head -25

==== AFONSO CUNHA (07013) [1/217] ====

Governador (cargo 3) - 1º TURNO
+-----------------+--------+-------+------------+
| NOME            | NÚMERO | VOTOS | SITUAÇÃO   |
+-----------------+--------+-------+------------+
| EDUARDO BRAIDE  |     55 |  3756 | ELEITO     | *
| ORLEANS BRANDÃO |     15 |  1421 | Não eleito |
| FELIPE CAMARÃO  |     13 |   561 | Não eleito |
+-----------------+--------+-------+------------+

==== ALCÂNTARA (07030) [2/217] ====

Governador (cargo 3) - 1º TURNO
+-----------------+--------+-------+------------+
| NOME            | NÚMERO | VOTOS | SITUAÇÃO   |
+-----------------+--------+-------+------------+
| EDUARDO BRAIDE  |     55 |  8533 | ELEITO     | *
| ORLEANS BRANDÃO |     15 |  2979 | Não eleito |
| FELIPE CAMARÃO  |     13 |  1938 | Não eleito |
+-----------------+--------+-------+------------+

==== ALDEIAS ALTAS (07056) [3/217] ====


```

## Referências

Manifesto Ágil: agilemanifesto.org · XP: agilealliance.org/glossary/xp · GitHub Docs: docs.github.com
