# Web_Crawler_Eleicao_2026

> Atividade prática de **Engenharia de Software** — Manifesto Ágil e Extreme Programming (XP)
> **UNIFACIMP WYDEN** · Curso: Sistemas de Informação · Professor: Thalles Canela
> **Aluno:** Ilderlan de Jesus Melo · **Matrícula:** 202502506783

## Diagnóstico (antes de alterar o código)

Script analisado: `buscador.sh` (no enunciado aparece como `tse-top-candidates.sh`).
Executei e li o código antes de modificar qualquer linha.

### Pontos que precisam de correção

1. **Município fixo** (`07242`): só existe resultado para uma cidade.
2. **Sem opção de turno**: só consulta o arquivo do 1º turno; não há como pedir o 2º.
3. **Eleitos não aparecem**: o filtro `jq` descarta os campos de situação do candidato.
4. **Um erro derruba tudo**: `die` encerra o script na primeira falha (ex.: um cargo com HTTP 404), sem mostrar o código HTTP.
5. **Tabela desalinhada com acentos**: `printf` do bash preenche por bytes; `NÚMERO`, `SÃO LUÍS`, `CAMARÃO` quebram as colunas.
6. **Lista vazia quebra**: array vazio com `set -u` dá `unbound variable` em bash < 4.4, e não há aviso de "nenhum candidato".
7. **Requisito de bash não verificado**: usa `local -n` (≥ 4.3) sem checar a versão.
8. **`die` dentro de `$(...)`** (`election_for_cargo`) só encerra o subshell.
9. **Sem `--help` nem argumentos**: configuração apenas por variáveis de ambiente.

### Melhorias planejadas (uma por vez, com commit pequeno)

| # | Mudança | Tipo |
|---|---------|------|
| 1 | Organizar em funções e melhorar mensagens de erro (itens 4, 6, 7, 8) | refactor |
| 2 | Corrigir alinhamento com acentos (item 5) | fix |
| 3 | Opções de linha de comando `-u -m -n -c -h` (item 9) | feat |
| 4 | Todos os municípios do Maranhão (item 1) | feat |
| 5 | 1º e 2º turno separados (item 2) | feat |
| 6 | Indicar eleitos (item 3) | feat |
| 7 | README final com uso, divisão do pair programming e validação | docs |
