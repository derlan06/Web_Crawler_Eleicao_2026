#!/usr/bin/env bash
# buscador.sh - Consulta os resultados do TSE (candidatos por cargo) via API pública.
# Configuração por variáveis de ambiente TSE_RESULTS_* (veja o README.md).
set -Eeuo pipefail

# Requisitos de versão: nameref (4.3), array vazio com set -u (4.4)
if (( BASH_VERSINFO[0] < 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] < 4) )); then
  printf 'Erro: este script requer bash 4.4 ou superior (atual: %s)\n' "$BASH_VERSION" >&2
  exit 1
fi

# Contagem de caracteres (e não de bytes) exige locale UTF-8
[[ "${LC_ALL:-${LANG:-}}" == *[Uu][Tt][Ff]-8* ]] || export LC_ALL=C.UTF-8

readonly DEFAULT_BASE_URL="https://resultados.tse.jus.br/oficial"
readonly -a DEFAULT_CARGOS=(6 7 5 3 1)
CARGOS=("${DEFAULT_CARGOS[@]}")
readonly NAME_HEADER="NOME" NUMBER_HEADER="NÚMERO" VOTES_HEADER="VOTOS" STATUS_HEADER="SITUAÇÃO"

BASE_URL="${TSE_RESULTS_BASE_URL:-$DEFAULT_BASE_URL}"
YEAR="${TSE_RESULTS_YEAR:-2026}"
UF="${TSE_RESULTS_UF:-ma}"
MUNICIPIO="${TSE_RESULTS_MUNICIPALITY:-todos}"   # "todos" ou código TSE de 5 dígitos
LIMIT="${TSE_RESULTS_LIMIT:-20}"
FEDERAL_ELECTION="${TSE_RESULTS_FEDERAL_ELECTION:-6257}"
STATE_ELECTION="${TSE_RESULTS_STATE_ELECTION:-6259}"
# Códigos do 2º turno: por padrão, o código do 1º turno + 1 (padrão observado
# nas eleições gerais anteriores). Ajuste pelas variáveis se o TSE usar outros.
FEDERAL_ELECTION_2T="${TSE_RESULTS_FEDERAL_ELECTION_2T:-$((FEDERAL_ELECTION + 1))}"
STATE_ELECTION_2T="${TSE_RESULTS_STATE_ELECTION_2T:-$((STATE_ELECTION + 1))}"
ROUND="${TSE_RESULTS_ROUND:-1}"   # 1, 2 ou ambos
ONLY_ELECTED="${TSE_RESULTS_ONLY_ELECTED:-false}"   # true: mostra só os eleitos
COLOR_MODE="${TSE_RESULTS_COLOR:-auto}"

FETCH_HTTP_CODE=""
MUNI_CODES=()
MUNI_NAMES=()
TURNOS=()
declare -A NO_DATA=()   # cargo -> nº de consultas sem dados (2º turno)
tmp_dir=""
use_color=false

die()  { printf 'Erro: %s\n' "$*" >&2; exit 1; }
warn() { printf 'Aviso: %s\n' "$*" >&2; }

usage() {
  cat <<'EOT'
Uso: ./buscador.sh [opções]

Consulta no TSE os candidatos mais votados por cargo.

Opções:
  -u UF         sigla da UF (padrão: ma)
  -m MUNICÍPIO  "todos" (padrão) para todos os municípios da UF, ou o
                código TSE de um município (5 dígitos, ex.: 07242)
  -t TURNO      1 (padrão), 2 ou ambos. O 2º turno só existe para Presidente
                e Governador, e apenas onde a disputa não foi decidida no 1º
  -e            mostra somente os candidatos eleitos. "Eleito" é a situação
                informada pelo TSE para a eleição como um todo (estado/país),
                e não o candidato mais votado no município
  -n LIMITE     máximo de candidatos por cargo (padrão: 20)
  -c "CARGOS"   cargos separados por espaço: 1=Presidente 3=Governador
                5=Senador 6=Dep. Federal 7=Dep. Estadual (padrão: "6 7 5 3 1")
  -h            mostra esta ajuda

Variáveis de ambiente (TSE_RESULTS_*) continuam valendo como padrão;
as opções de linha de comando têm prioridade sobre elas.
EOT
}

parse_args() {
  local opt OPTIND=1
  while getopts ':u:m:t:n:c:eh' opt; do
    case "$opt" in
      u) UF="$OPTARG" ;;
      m) MUNICIPIO="$OPTARG" ;;
      t) ROUND="$OPTARG" ;;
      e) ONLY_ELECTED=true ;;
      n) LIMIT="$OPTARG" ;;
      c) read -r -a CARGOS <<<"$OPTARG" ;;
      h) usage; exit 0 ;;
      :)  die "a opção -$OPTARG exige um valor (veja -h)" ;;
      \?) die "opção inválida: -$OPTARG (veja -h)" ;;
    esac
  done
  (( OPTIND > $# )) || die "argumento inesperado: ${!OPTIND} (veja -h)"
}

validate_config() {
  command -v curl >/dev/null || die "curl não encontrado (instale com seu gerenciador de pacotes)"
  command -v jq   >/dev/null || die "jq não encontrado (instale com seu gerenciador de pacotes)"
  [[ "$UF" =~ ^[[:alpha:]]{2}$ ]]        || die "TSE_RESULTS_UF deve conter duas letras"
  MUNICIPIO="${MUNICIPIO,,}"
  [[ "$MUNICIPIO" == todos || "$MUNICIPIO" =~ ^[0-9]{5}$ ]] \
    || die "município deve ser 'todos' ou um código TSE de cinco dígitos (-m / TSE_RESULTS_MUNICIPALITY)"
  [[ "$YEAR" =~ ^[0-9]{4}$ ]]            || die "TSE_RESULTS_YEAR deve conter quatro dígitos"
  [[ "$LIMIT" =~ ^[1-9][0-9]*$ ]]        || die "TSE_RESULTS_LIMIT deve ser um inteiro positivo"
  [[ "$FEDERAL_ELECTION" =~ ^[0-9]+$ && "$STATE_ELECTION" =~ ^[0-9]+$ ]] \
    || die "códigos de eleição devem ser numéricos"
  [[ "$COLOR_MODE" =~ ^(auto|always|never)$ ]] || die "TSE_RESULTS_COLOR deve ser auto, always ou never"
  [[ "$FEDERAL_ELECTION_2T" =~ ^[0-9]+$ && "$STATE_ELECTION_2T" =~ ^[0-9]+$ ]] \
    || die "códigos de eleição do 2º turno devem ser numéricos"
  [[ "$ONLY_ELECTED" =~ ^(true|false)$ ]] || die "TSE_RESULTS_ONLY_ELECTED deve ser true ou false"
  ROUND="${ROUND,,}"
  case "$ROUND" in
    1) TURNOS=(1) ;;
    2) TURNOS=(2) ;;
    ambos|1,2|1-2) TURNOS=(1 2) ;;
    *) die "turno deve ser 1, 2 ou ambos (-t / TSE_RESULTS_ROUND)" ;;
  esac
  (( ${#CARGOS[@]} > 0 )) || die "informe ao menos um cargo (opção -c)"
  local cargo
  for cargo in "${CARGOS[@]}"; do
    election_for_cargo "$cargo" 1 >/dev/null || die "cargo não suportado: $cargo (use 1, 3, 5, 6 ou 7)"
  done
  UF="${UF,,}"
  BASE_URL="${BASE_URL%/}"
}

setup_color() {
  if [[ "$COLOR_MODE" == always ]] \
     || { [[ "$COLOR_MODE" == auto && -t 1 && "${TERM:-dumb}" != dumb ]] && [[ ! -v NO_COLOR ]]; }; then
    use_color=true
  fi
}

# pad_right/pad_left TEXTO LARGURA -> resultado em $REPLY.
# O printf do bash preenche por BYTES e desalinha acentos (NÚMERO, SÃO LUÍS);
# aqui o preenchimento é por caracteres.
pad_right() { local n=$(( $2 - ${#1} )); (( n < 0 )) && n=0; printf -v REPLY '%s%*s' "$1" "$n" ''; }
pad_left()  { local n=$(( $2 - ${#1} )); (( n < 0 )) && n=0; printf -v REPLY '%*s%s' "$n" '' "$1"; }

print_rule() {
  printf '+'
  local w
  for w in "$@"; do printf '%*s+' "$((w + 2))" '' | tr ' ' '-'; done
  printf '\n'
}

# is_elected SITUAÇÃO -> 0 se o TSE marcou o candidato como eleito
# ("Eleito", "Eleito por QP", "Eleito por média"; "Não eleito" não conta).
is_elected() { local v="${1,,}"; [[ "$v" == eleito* ]]; }

print_table() {
  local -n table_rows="$1"
  local name_width=${#NAME_HEADER} number_width=${#NUMBER_HEADER} votes_width=${#VOTES_HEADER} status_width=${#STATUS_HEADER}
  local row name number votes status c1 c2 c3 c4
  for row in "${table_rows[@]}"; do
    IFS=$'\t' read -r name number votes status <<<"$row"
    is_elected "$status" && status="${status^^}"
    (( ${#name} > name_width )) && name_width=${#name}
    (( ${#number} > number_width )) && number_width=${#number}
    (( ${#votes} > votes_width )) && votes_width=${#votes}
    (( ${#status} > status_width )) && status_width=${#status}
  done
  print_rule "$name_width" "$number_width" "$votes_width" "$status_width"
  pad_right "$NAME_HEADER" "$name_width";     c1="$REPLY"
  pad_left  "$NUMBER_HEADER" "$number_width"; c2="$REPLY"
  pad_left  "$VOTES_HEADER" "$votes_width";   c3="$REPLY"
  pad_right "$STATUS_HEADER" "$status_width"; c4="$REPLY"
  printf '| %s | %s | %s | %s |\n' "$c1" "$c2" "$c3" "$c4"
  print_rule "$name_width" "$number_width" "$votes_width" "$status_width"
  for row in "${table_rows[@]}"; do
    IFS=$'\t' read -r name number votes status <<<"$row"
    is_elected "$status" && status="${status^^}"
    pad_right "$name" "$name_width";     c1="$REPLY"
    pad_left  "$number" "$number_width"; c2="$REPLY"
    pad_left  "$votes" "$votes_width";   c3="$REPLY"
    pad_right "$status" "$status_width"; c4="$REPLY"
    if is_elected "$status"; then
      # eleitos: linha em negrito/verde (ou marcada com * quando sem cor)
      if $use_color; then
        printf '| \033[1;32m%s\033[0m | \033[1;32m%s\033[0m | \033[1;32m%s\033[0m | \033[1;32m%s\033[0m |\n' "$c1" "$c2" "$c3" "$c4"
      else
        printf '| %s | %s | %s | %s | *\n' "$c1" "$c2" "$c3" "$c4"
      fi
    elif $use_color; then
      printf '| \033[36m%s\033[0m | %s | \033[32m%s\033[0m | %s |\n' "$c1" "$c2" "$c3" "$c4"
    else
      printf '| %s | %s | %s | %s |\n' "$c1" "$c2" "$c3" "$c4"
    fi
  done
  print_rule "$name_width" "$number_width" "$votes_width" "$status_width"
}

# election_for_cargo CARGO TURNO -> código da eleição no stdout.
# Status 1: cargo não suportado; status 2: cargo sem 2º turno.
election_for_cargo() {
  local cargo="$1" turno="$2"
  case "$cargo:$turno" in
    1:1)         printf '%s' "$FEDERAL_ELECTION" ;;
    3:1|5:1|6:1|7:1) printf '%s' "$STATE_ELECTION" ;;
    1:2)         printf '%s' "$FEDERAL_ELECTION_2T" ;;
    3:2)         printf '%s' "$STATE_ELECTION_2T" ;;
    5:2|6:2|7:2) return 2 ;;
    *)           return 1 ;;
  esac
}

# fetch_json URL DESTINO -> 0 se HTTP 200; senão 1 e FETCH_HTTP_CODE com o motivo.
fetch_json() {
  local url="$1" dest="$2"
  FETCH_HTTP_CODE="$(curl --silent --show-error --location \
      --retry 3 --retry-all-errors --connect-timeout 10 --max-time 30 \
      --write-out '%{http_code}' --output "$dest" "$url")" || { FETCH_HTTP_CODE="erro-de-rede"; return 1; }
  [[ "$FETCH_HTTP_CODE" == 200 ]]
}

# (jq.exe no Windows termina as linhas com \r; por isso as saídas do jq passam por tr -d '\r')
# Carrega MUNI_CODES/MUNI_NAMES: todos os municípios da UF (lista oficial do TSE)
# ou apenas o município pedido em -m.
load_municipios() {
  local election_padded election file="$tmp_dir/municipios.json" url code name found=false
  # Arquivo EA12 do TSE: config/mun-e<eleição de 6 dígitos>-cm.json
  # (tenta a eleição estadual e, se não existir, a federal)
  for election in "$STATE_ELECTION" "$FEDERAL_ELECTION"; do
    printf -v election_padded '%06d' "$election"
    url="$BASE_URL/ele$YEAR/$election/config/mun-e${election_padded}-cm.json"
    if fetch_json "$url" "$file"; then found=true; break; fi
  done

  if ! $found; then
    [[ "$MUNICIPIO" == todos ]] \
      || { MUNI_CODES=("$MUNICIPIO"); MUNI_NAMES=("$MUNICIPIO"); return 0; }
    die "não foi possível obter a lista de municípios (HTTP $FETCH_HTTP_CODE): $url"
  fi

  while IFS=$'\t' read -r code name; do
    [[ "$MUNICIPIO" == todos || "$MUNICIPIO" == "$code" ]] || continue
    MUNI_CODES+=("$code"); MUNI_NAMES+=("$name")
  done < <(jq -r --arg uf "$UF" '
      (.abr // [])[]
      | select(((.cd // "") | ascii_downcase) == $uf)
      | (.mu // [])[]
      | [.cd, .nm] | @tsv
    ' "$file" | tr -d '\r')

  if (( ${#MUNI_CODES[@]} == 0 )); then
    if [[ "$MUNICIPIO" == todos ]]; then
      die "nenhum município encontrado para a UF '$UF' em $url"
    fi
    MUNI_CODES=("$MUNICIPIO"); MUNI_NAMES=("$MUNICIPIO")   # código fora da lista: tenta mesmo assim
  fi
}

# show_cargo MUNICÍPIO TURNO CARGO -> imprime a tabela do cargo.
# Status 1: falha (já avisada); 2: sem dados (esperado no 2º turno);
# 3: não se aplica (cargo sem 2º turno).
show_cargo() {
  local muni="$1" turno="$2" cargo="$3" election file rows_file url cargo_name cargo_padded election_padded
  local -a rows=()

  local rc=0
  election="$(election_for_cargo "$cargo" "$turno")" || rc=$?
  case "$rc" in
    0) ;;
    2) return 3 ;;   # cargo sem 2º turno: não se aplica, não é falha
    *) warn "cargo não suportado: $cargo"; return 1 ;;
  esac
  file="$tmp_dir/cargo-$cargo-t$turno.json"
  rows_file="$tmp_dir/cargo-$cargo-t$turno.tsv"
  printf -v cargo_padded '%04d' "$cargo"
  printf -v election_padded '%06d' "$election"
  url="$BASE_URL/ele$YEAR/$election/dados/$UF/${UF}${muni}-c${cargo_padded}-e${election_padded}-u.json"

  if ! fetch_json "$url" "$file"; then
    # 2º turno inexistente (cargo decidido no 1º turno) aparece como HTTP 404
    [[ "$turno" == 2 && "$FETCH_HTTP_CODE" == 404 ]] && return 2
    warn "falha ao consultar o cargo $cargo (${turno}º turno) no município $muni (HTTP $FETCH_HTTP_CODE): $url"
    return 1
  fi
  jq -e '.carg | type == "array"' "$file" >/dev/null 2>&1 \
    || { warn "resposta inválida para o cargo $cargo (JSON sem a lista 'carg')"; return 1; }

  cargo_name="$(jq -r --arg cargo "$cargo" '.carg[] | select(.cd == $cargo) | .nmn' "$file" | tr -d '\r' | head -n 1)"
  [[ -n "$cargo_name" ]] || { warn "cargo $cargo ausente na resposta"; return 1; }

  printf '\n%s (cargo %s) - %dº TURNO\n' "$cargo_name" "$cargo" "$turno"

  jq -r --arg cargo "$cargo" --argjson limit "$LIMIT" --argjson only_elected "$ONLY_ELECTED" '
    [
      .carg[] | select(.cd == $cargo)
      | .. | objects | .cand? // empty | .[]
      | select((.nmu // "") != "" and (.n // "") != "")
      | {
          nome: (.nmu | gsub("[[:cntrl:]]"; " ")),
          numero: .n,
          votos: ((.vap // "0") | tonumber),
          situacao: (if ((.st // "") != "") then .st
                     elif ((.e // "") == "s") then "Eleito"
                     else "-" end)
        }
    ]
    | unique_by(.numero)
    | sort_by([-.votos, (.nome | ascii_downcase), .numero])
    | (if $only_elected then map(select(.situacao | test("^eleito"; "i"))) else . end)
    | .[:$limit][]
    | [.nome, .numero, (.votos | tostring), .situacao] | @tsv
  ' "$file" | tr -d '\r' >"$rows_file" || { warn "não foi possível ler os candidatos do cargo $cargo"; return 1; }

  mapfile -t rows <"$rows_file"
  if (( ${#rows[@]} == 0 )); then
    printf '  (nenhum candidato para exibir: resposta vazia ou nenhum eleito marcado pelo TSE)\n'
    return 0
  fi
  print_table rows
}

# Resume (uma vez só) o que não tinha dados, em vez de repetir por município.
report_no_data() {
  local key
  (( ${#NO_DATA[@]} > 0 )) || return 0
  printf '\nSem dados disponíveis (normal quando o cargo não teve 2º turno ou a apuração não terminou):\n'
  for key in $(printf '%s\n' "${!NO_DATA[@]}" | sort); do
    printf '  cargo %s, %sº turno: %s consulta(s)\n' "${key%%:*}" "${key##*:}" "${NO_DATA[$key]}"
  done
}

main() {
  parse_args "$@"
  validate_config
  setup_color
  tmp_dir="$(mktemp -d)"
  trap 'rm -rf "$tmp_dir"' EXIT

  load_municipios

  local cargo turno rc i total=${#MUNI_CODES[@]} failures=0
  for (( i = 0; i < total; i++ )); do
    printf '\n==== %s (%s) [%d/%d] ====\n' "${MUNI_NAMES[i]}" "${MUNI_CODES[i]}" "$((i + 1))" "$total"
    for turno in "${TURNOS[@]}"; do
      for cargo in "${CARGOS[@]}"; do
        rc=0
        show_cargo "${MUNI_CODES[i]}" "$turno" "$cargo" || rc=$?
        case "$rc" in
          0|3) ;;
          2) NO_DATA[$cargo:$turno]=$(( ${NO_DATA[$cargo:$turno]:-0} + 1 )) ;;
          *) failures=$((failures + 1)) ;;
        esac
      done
    done
  done
  report_no_data
  (( failures == 0 )) || die "$failures consulta(s) com falha; veja os avisos acima"
}

main "$@"
