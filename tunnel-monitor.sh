#!/usr/bin/env bash

# Simple tunnel monitoring script
# Made by Jiab77
#
# It has been written initially for the 'localtonet' service
# but later on has been adapted for the 'loophole' service
# for performances reasons.
#
# Version 0.0.0

# Options
set -o xtrace

# Config
CLEAR_SCREEN=true
ENABLE_SVC_CHECK=true
ENABLE_SVC_KILL=true
KILL_CHECK_THRES=10
WAIT_DELAY_LOOP=30
WAIT_DELAY_PRECHECK=5
WAIT_DELAY_CHECK=5
CURL_TIMEOUT=5

# Credentials
SVC_USER="admin"
SVC_PASS="changeme"

# Provider
SVC_PROVIDER="loophole"  # For later use

# Internals
BIN_SVC="/opt/loophole/loophole"
BIN_SCREEN=$(command -v screen 2>/dev/null)
SCRIPT_DIR="$(dirname "$0")"
SCRIPT_FILE="$(basename "$0")"
SCRIPT_NAME="${SCRIPT_FILE/.sh/}"
CONFIG_FILE="${SCRIPT_DIR}/${SCRIPT_NAME}.conf"
MAP_TO_REMOTE_HOST=false
KILL_CHECK_COUNTER=0

# Functions
function die() {
  echo -e "\nError: $*\n" >&2
  exit 255
}
function print_usage() {
  echo -e "\nUsage: $SCRIPT_FILE [flags] [port] [name] [sub-domain] [domain]"
  echo -e "\nFlags:"
  echo -e "  -h | --help\t\tPrint this message and exit"
  echo -e "  -c | --config\t\tLoad config from given file"
  echo -e "  -t | --target\t\tCreate tunnel from remote host"
  echo
  exit
}
function create_tunnel() {
  if [[ $MAP_TO_REMOTE_HOST == true && -n $REMOTE_HOST ]]; then
    if [[ -n $SVC_USER && -n $SVC_PASS ]]; then
      screen -dmS $TUN_NAME $BIN_SVC http $SVC_PORT \
             $REMOTE_HOST \
             -u $SVC_USER \
             -p $SVC_PASS \
             --hostname $SVC_NAME \
             --disable-old-ciphers \
             --disable-proxy-error-page \
             --verbose
    else
      screen -dmS $TUN_NAME $BIN_SVC http $SVC_PORT \
             $REMOTE_HOST \
             --hostname $SVC_NAME \
             --disable-old-ciphers \
             --disable-proxy-error-page \
             --verbose
    fi
  else
    if [[ -n $SVC_USER && -n $SVC_PASS ]]; then
      screen -dmS $TUN_NAME $BIN_SVC http $SVC_PORT \
             -u $SVC_USER \
             -p $SVC_PASS \
             --hostname $SVC_NAME \
             --disable-old-ciphers \
             --disable-proxy-error-page \
             --verbose
    else
      screen -dmS $TUN_NAME $BIN_SVC http $SVC_PORT \
             --hostname $SVC_NAME \
             --disable-old-ciphers \
             --disable-proxy-error-page \
             --verbose
    fi
  fi
}
function check_tunnel() {
  screen -ls 2>/dev/null | grep -c $TUN_NAME
}
function check_svc_health() {
  curl -sSL --connect-timeout $CURL_TIMEOUT "$SVC_URL/health" &>/dev/null
  RET_CODE_CURL=$? ; echo -n $RET_CODE_CURL
}
function kill_tunnel() {
  killall -KILL $BIN_SVC 2>/dev/null
}
function run_monitor() {
  while :; do
    [[ $CLEAR_SCREEN == true ]] && clear
    echo -ne "\nChecking service tunnel state..."
    if [[ $(check_tunnel) -eq 0 ]]; then
      echo -e " down! Starting it...\n"
      create_tunnel
      echo -ne "Waiting for tunnel to be created..."
      sleep $WAIT_DELAY_CHECK
      if [[ $(check_tunnel) -eq 1 ]]; then
        echo " done."
      else
        echo " failed."
      fi
    else
      echo " up."
      if [[ $ENABLE_SVC_CHECK == true ]]; then
        echo -ne "\nChecking service health..."
        sleep $WAIT_DELAY_PRECHECK
        if [[ $(check_svc_health) -ne 0 ]]; then
          if [[ $ENABLE_SVC_KILL == true && $KILL_CHECK_COUNTER -ge $KILL_CHECK_THRES ]]; then
            echo -ne " broken! Killing existing tunnel... [Ctrl+C to stop]\n"
            kill_tunnel && KILL_CHECK_COUNTER=0
          else
            echo -ne " altered! Expect some issues with the tunnel... [Ctrl+C to stop]\n"
            ((KILL_CHECK_COUNTER++))
          fi
        else
          echo -ne " running.\n\nNothing else to do. [Ctrl+C to stop]\n"
          KILL_CHECK_COUNTER=0
        fi
      fi
    fi
    sleep $WAIT_DELAY_LOOP
  done
}

# Checks
[[ -z $BIN_SVC ]] && die "You must have 'BIN_SVC' variable defined to run this script."
[[ -z $BIN_SCREEN ]] && die "You must have 'screen' installed to run this script."
[[ ! -r $BIN_SVC ]] && die "You must have 'loophole' installed to run this script."
[[ ! -x $BIN_SVC ]] && die "The 'loophole' binary permissions are invalid, please fix them and try again."

# Flags
[[ $1 == "-h" || $1 == "--help" ]] && print_usage
[[ $1 == "-c" || $1 == "--config" ]] && shift && CONFIG_FILE="$1" && shift
if [[ $1 == "-t" || $1 == "--target" ]]; then
  MAP_TO_REMOTE_HOST=true
  shift
  REMOTE_HOST="$1"
  shift
fi

# Args
SVC_PORT=${1:-8080}
TUN_NAME="${2:-tunnel}"
SVC_NAME="${3:-$USER}"
SVC_DOMAIN="${4:-loophole.site}"

# Config
[[ -r "$CONFIG_FILE" ]] && source "$CONFIG_FILE"

# Init
SVC_URL="https://${SVC_NAME}.${SVC_DOMAIN}"

# Overrides
TUN_COUNT=$(screen -ls 2>/dev/null | grep -ci "$TUN_NAME")
[[ $TUN_COUNT -ge 0 ]] && TUN_NAME+="$((TUN_COUNT++))"

# Main
run_monitor
