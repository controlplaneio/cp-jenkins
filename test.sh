#!/usr/bin/env bash
#
# Jenkins configuration test runner
#
# Andrew Martin, 2017-12-29 15:38:15
# sublimino@gmail.com
#
## Usage: %SCRIPT_NAME% [options] filename
##
## Options:
##   -d, --description [string]  Description
##   -t, --type [bash]           Template type to create
##   --debug                     More debug
##
##   -h --help                   Display this message
##

# exit on error or pipe failure
set -eo pipefail
# error on unset variable
set -o nounset
# error on clobber
set -o noclobber

# user defaults
DEBUG=0

# resolved directory and self
declare -r DIR=$(cd "$(dirname "$0")" && pwd)
declare -r THIS_SCRIPT="${DIR}/$(basename "$0")"

# required defaults
declare -a ARGUMENTS
EXPECTED_NUM_ARGUMENTS=0
ARGUMENTS=()
CONTAINER_ID=''
PORT="8080"

READY_LOG_TEXT="Jenkins provided DSL script setup complete"
FAILED_LOG_TEXT="Failed to run script file"

export CONTAINER_TAG=latest

main() {
  handle_arguments "$@"

  trap cleanup EXIT

  build_jenkins

  info "Starting Jenkins..."

  start_jenkins

  wait_until_initialised

  sleep 3

  info "Running tests..."

  run_tests

  success "Test complete"
}

build_jenkins() {
  make build
}

start_jenkins() {
  make test-run
  info "Waiting for cid file..."
  until [[ -f /tmp/jenkins-test.cid ]]; do
    sleep 0.2
  done
  CONTAINER_ID=$(cat /tmp/jenkins-test.cid)
}

cleanup() {
  docker ps -qf "id=${CONTAINER_ID}" \
    | xargs --no-run-if-empty docker kill
}

wait_until_initialised() {
  local IS_FAILED=0
  local START_TIME="${SECONDS}"
  while read LINE; do
    if echo "${LINE}" | grep --color=always -E "${READY_LOG_TEXT}"; then
      success "Jenkins is ready"
      break
    elif echo "${LINE}" | grep --color=always -E "${FAILED_LOG_TEXT}"; then
      warning "Failed to start Jenkins, failing"
      IS_FAILED=$((IS_FAILED + 1))
    else
      echo -e "${LINE}" | grep --color=always -E '^|INFO: !!!.*' || true
    fi

    if [[ "${IS_FAILED}" -gt 30 ]]; then
      error "Failed"
      break
    elif [[ "${IS_FAILED}" -gt 0 ]]; then
      IS_FAILED=$((IS_FAILED + 1))
    fi

    if [[ $(( SECONDS - START_TIME )) -gt 200 ]]; then
      error "Timeout reached, test took over 200s"
    fi
  done < <(docker logs -f "${CONTAINER_ID}" 2>&1)

  if [[ "${IS_FAILED}" == 0 ]]; then
    return 0
  else
    return 1
  fi
}

# TODO: bats suite
run_tests() {
  local HTTP_STATUS_CODE
  local HOST
  local COUNT=0

  HOST=$(docker inspect -f "{{.NetworkSettings.IPAddress}}" jenkins-test)

  while HTTP_STATUS_CODE=$(curl -o /dev/null \
    --silent \
    --head \
    --write-out '%{http_code}\n' \
    ${HOST}:${PORT} || true); do

      [[ $(( COUNT++ )) -gt 10 ]] && break
      [[ "${HTTP_STATUS_CODE}" = 403 ]] && break

      printf '.'
      sleep 1
  done

  if [[ "${HTTP_STATUS_CODE}" != 403 ]]; then
    error "Expected 403 from UI. Got ${HTTP_STATUS_CODE}"
  fi

  success "Pass"
}

handle_arguments() {
  [[ $# = 0 && "${EXPECTED_NUM_ARGUMENTS}" -gt 0 ]] && usage

  parse_arguments "$@"
  validate_arguments "$@"
}

parse_arguments() {
  while [ $# -gt 0 ]; do
    case $1 in
      -h | --help) usage ;;
      --debug)
        DEBUG=1
        set -xe
        ;;
      -d | --description)
        shift
        not_empty_or_usage "${1:-}"
        DESCRIPTION="${1}"
        ;;
      -t | --type)
        shift
        not_empty_or_usage "${1:-}"
        case $1 in
          bash) FILETYPE=bash ;;
          *) usage "Template type '${1}' not recognised" ;;
        esac
        ;;
      --)
        shift
        break
        ;;
      -*) usage "${1}: unknown option" ;;
      *) ARGUMENTS+=("$1") ;;
    esac
    shift
  done
}

validate_arguments() {
  [[ "${EXPECTED_NUM_ARGUMENTS}" -gt 0 && -z "${FILETYPE:-}" ]] && usage "Filetype required"

  check_number_of_expected_arguments

  [[ "${#ARGUMENTS[@]}" -gt 0 ]] && FILENAME="${ARGUMENTS[0]}" || true
}

# helper functions

usage() {
  [ "$*" ] && echo "${THIS_SCRIPT}: ${COLOUR_RED}$*${COLOUR_RESET}" && echo
  sed -n '/^##/,/^$/s/^## \{0,1\}//p' "${THIS_SCRIPT}" | sed "s/%SCRIPT_NAME%/$(basename "${THIS_SCRIPT}")/g"
  exit 2
} 2>/dev/null

success() {
  [ "${*:-}" ] && RESPONSE="$*" || RESPONSE="Unknown Success"
  printf "%s\n" "$(log_message_prefix)${COLOUR_GREEN}${RESPONSE}${COLOUR_RESET}"
} 1>&2

info() {
  [ "${*:-}" ] && INFO="$*" || INFO="Unknown Info"
  printf "%s\n" "$(log_message_prefix)${COLOUR_WHITE}${INFO}${COLOUR_RESET}"
} 1>&2

warning() {
  [ "${*:-}" ] && ERROR="$*" || ERROR="Unknown Warning"
  printf "%s\n" "$(log_message_prefix)${COLOUR_RED}${ERROR}${COLOUR_RESET}"
} 1>&2

error() {
  [ "${*:-}" ] && ERROR="$*" || ERROR="Unknown Error"
  printf "%s\n" "$(log_message_prefix)${COLOUR_RED}${ERROR}${COLOUR_RESET}"
  exit 3
} 1>&2

error_env_var() {
  error "${1} environment variable required"
}

log_message_prefix() {
  local TIMESTAMP="[$(date +'%Y-%m-%dT%H:%M:%S%z')]"
  local THIS_SCRIPT_SHORT=${THIS_SCRIPT/$DIR/.}
  tput bold 2>/dev/null
  echo -n "${TIMESTAMP} ${THIS_SCRIPT_SHORT}: "
}

is_empty() {
  [[ -z ${1-} ]] && return 0 || return 1
}

not_empty_or_usage() {
  is_empty "${1-}" && usage "Non-empty value required" || return 0
}

check_number_of_expected_arguments() {
  [[ "${EXPECTED_NUM_ARGUMENTS}" != "${#ARGUMENTS[@]}" ]] && {
    ARGUMENTS_STRING="argument"
    [[ "${EXPECTED_NUM_ARGUMENTS}" -gt 1 ]] && ARGUMENTS_STRING="${ARGUMENTS_STRING}"s
    usage "${EXPECTED_NUM_ARGUMENTS} ${ARGUMENTS_STRING} expected, ${#ARGUMENTS[@]} found"
  }
  return 0
}

hr() {
  printf '=%.0s' $(seq $(tput cols))
  echo
}

wait_safe() {
  local PIDS="${1}"
  for JOB in ${PIDS}; do
    wait "${JOB}"
  done
}

export CLICOLOR=1
export TERM="xterm-color"
export COLOUR_BLACK=$(tput setaf 0 :-"" 2>/dev/null)
export COLOUR_RED=$(tput setaf 1 :-"" 2>/dev/null)
export COLOUR_GREEN=$(tput setaf 2 :-"" 2>/dev/null)
export COLOUR_YELLOW=$(tput setaf 3 :-"" 2>/dev/null)
export COLOUR_BLUE=$(tput setaf 4 :-"" 2>/dev/null)
export COLOUR_MAGENTA=$(tput setaf 5 :-"" 2>/dev/null)
export COLOUR_CYAN=$(tput setaf 6 :-"" 2>/dev/null)
export COLOUR_WHITE=$(tput setaf 7 :-"" 2>/dev/null)
export COLOUR_RESET=$(tput sgr0 :-"" 2>/dev/null)

main "$@"
