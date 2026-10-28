#!/usr/bin/env bash
# buscador.sh - Consulta os resultados do TSE (candidatos por cargo) via API pública.
# Configuração por variáveis de ambiente TSE_RESULTS_* (veja o README.md).
set -Eeuo pipefail

# Requisitos de versão: nameref (4.3), array vazio com set -u (4.4)
if (( BASH_VERSINFO[0] < 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] < 4) )); then
  printf 'Erro: este script requer bash 4.4 ou superior (atual: %s)\n' "$BASH_VERSION" >&2
  exit 1
fi

readonly DEFAULT_BASE_URL="https://resultados.tse.jus.br/oficial"
readonly -a CARGOS=(6 7 5 3 1)
readonly NAME_HEADER="NOME" NUMBER_HEADER="NÚMERO" VOTES_HEADER="VOTOS"

BASE_URL="${TSE_RESULTS_BASE_URL:-$DEFAULT_BASE_URL}"
YEAR="${TSE_RESULTS_YEAR:-2026}"
UF="${TSE_RESULTS_UF:-ma}"
MUNICIPIO="${TSE_RESULTS_MUNICIPALITY:-07242}"
LIMIT="${TSE_RESULTS_LIMIT:-20}"
FEDERAL_ELECTION="${TSE_RESULTS_FEDERAL_ELECTION:-6257}"
STATE_ELECTION="${TSE_RESULTS_STATE_ELECTION:-6259}"
COLOR_MODE="${TSE_RESULTS_COLOR:-auto}"

FETCH_HTTP_CODE=""
tmp_dir=""
use_color=false

die()  { printf 'Erro: %s\n' "$*" >&2; exit 1; }
warn() { printf 'Aviso: %s\n' "$*" >&2; }

validate_config() {
  command -v curl >/dev/null || die "curl não encontrado (instale com seu gerenciador de pacotes)"
  command -v jq   >/dev/null || die "jq não encontrado (instale com seu gerenciador de pacotes)"
  [[ "$UF" =~ ^[[:alpha:]]{2}$ ]]        || die "TSE_RESULTS_UF deve conter duas letras"
  [[ "$MUNICIPIO" =~ ^[0-9]{5}$ ]]       || die "TSE_RESULTS_MUNICIPALITY deve conter cinco dígitos"
  [[ "$YEAR" =~ ^[0-9]{4}$ ]]            || die "TSE_RESULTS_YEAR deve conter quatro dígitos"
  [[ "$LIMIT" =~ ^[1-9][0-9]*$ ]]        || die "TSE_RESULTS_LIMIT deve ser um inteiro positivo"
  [[ "$FEDERAL_ELECTION" =~ ^[0-9]+$ && "$STATE_ELECTION" =~ ^[0-9]+$ ]] \
    || die "códigos de eleição devem ser numéricos"
  [[ "$COLOR_MODE" =~ ^(auto|always|never)$ ]] || die "TSE_RESULTS_COLOR deve ser auto, always ou never"
  UF="${UF,,}"
  BASE_URL="${BASE_URL%/}"
}

setup_color() {
  if [[ "$COLOR_MODE" == always ]] \
     || { [[ "$COLOR_MODE" == auto && -t 1 && "${TERM:-dumb}" != dumb ]] && [[ ! -v NO_COLOR ]]; }; then
    use_color=true
  fi
}

print_rule() {
  local name_width="$1" number_width="$2" votes_width="$3"
  printf '+-%*s-+-%*s-+-%*s-+\n' "$name_width" '' "$number_width" '' "$votes_width" '' | tr ' ' '-'
}

print_table() {
  local -n table_rows="$1"
  local name_width=${#NAME_HEADER} number_width=${#NUMBER_HEADER} votes_width=${#VOTES_HEADER}
  local row name number votes
  for row in "${table_rows[@]}"; do
    IFS=$'\t' read -r name number votes <<<"$row"
    (( ${#name} > name_width )) && name_width=${#name}
    (( ${#number} > number_width )) && number_width=${#number}
    (( ${#votes} > votes_width )) && votes_width=${#votes}
  done
  print_rule "$name_width" "$number_width" "$votes_width"
  printf '| %-*s | %*s | %*s |\n' "$name_width" "$NAME_HEADER" "$number_width" "$NUMBER_HEADER" "$votes_width" "$VOTES_HEADER"
  print_rule "$name_width" "$number_width" "$votes_width"
  for row in "${table_rows[@]}"; do
    IFS=$'\t' read -r name number votes <<<"$row"
    if $use_color; then
      printf '| \033[36m%-*s\033[0m | %*s | \033[32m%*s\033[0m |\n' "$name_width" "$name" "$number_width" "$number" "$votes_width" "$votes"
    else
      printf '| %-*s | %*s | %*s |\n' "$name_width" "$name" "$number_width" "$number" "$votes_width" "$votes"
    fi
  done
  print_rule "$name_width" "$number_width" "$votes_width"
}

# Retorna o código da eleição do cargo; status 1 se o cargo não for suportado.
election_for_cargo() {
  case "$1" in
    1)         printf '%s' "$FEDERAL_ELECTION" ;;
    3|5|6|7)   printf '%s' "$STATE_ELECTION" ;;
    *)         return 1 ;;
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

# show_cargo CARGO -> imprime a tabela do cargo; status 1 em caso de falha (já avisada).
show_cargo() {
  local cargo="$1" election file rows_file url cargo_name cargo_padded election_padded
  local -a rows=()

  election="$(election_for_cargo "$cargo")" || { warn "cargo não suportado: $cargo"; return 1; }
  file="$tmp_dir/cargo-$cargo.json"
  rows_file="$tmp_dir/cargo-$cargo.tsv"
  printf -v cargo_padded '%04d' "$cargo"
  printf -v election_padded '%06d' "$election"
  url="$BASE_URL/ele$YEAR/$election/dados/$UF/${UF}${MUNICIPIO}-c${cargo_padded}-e${election_padded}-u.json"

  fetch_json "$url" "$file" \
    || { warn "falha ao consultar o cargo $cargo (HTTP $FETCH_HTTP_CODE): $url"; return 1; }
  jq -e '.carg | type == "array"' "$file" >/dev/null 2>&1 \
    || { warn "resposta inválida para o cargo $cargo (JSON sem a lista 'carg')"; return 1; }

  cargo_name="$(jq -r --arg cargo "$cargo" '.carg[] | select(.cd == $cargo) | .nmn' "$file" | head -n 1)"
  [[ -n "$cargo_name" ]] || { warn "cargo $cargo ausente na resposta"; return 1; }

  printf '\n%s (cargo %s)\n' "$cargo_name" "$cargo"

  jq -r --arg cargo "$cargo" --argjson limit "$LIMIT" '
    [
      .carg[] | select(.cd == $cargo)
      | .. | objects | .cand? // empty | .[]
      | select((.nmu // "") != "" and (.n // "") != "")
      | { nome: (.nmu | gsub("[[:cntrl:]]"; " ")), numero: .n, votos: ((.vap // "0") | tonumber) }
    ]
    | unique_by(.numero)
    | sort_by([-.votos, (.nome | ascii_downcase), .numero])
    | .[:$limit][]
    | [.nome, .numero, (.votos | tostring)] | @tsv
  ' "$file" >"$rows_file" || { warn "não foi possível ler os candidatos do cargo $cargo"; return 1; }

  mapfile -t rows <"$rows_file"
  if (( ${#rows[@]} == 0 )); then
    printf '  (nenhum candidato com votos na resposta do TSE)\n'
    return 0
  fi
  print_table rows
}

main() {
  validate_config
  setup_color
  tmp_dir="$(mktemp -d)"
  trap 'rm -rf "$tmp_dir"' EXIT

  local cargo failures=0
  for cargo in "${CARGOS[@]}"; do
    show_cargo "$cargo" || failures=$((failures + 1))
  done
  (( failures == 0 )) || die "$failures cargo(s) com falha; veja os avisos acima"
}

main "$@"
