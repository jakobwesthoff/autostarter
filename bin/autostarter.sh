#!/bin/bash

####
# Copyright (c) 2011, Jakob Westhoff <jakob@westhoffswelt.de>
# 
# All rights reserved.
# 
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
# 
#  - Redistributions of source code must retain the above copyright notice, this
#    list of conditions and the following disclaimer.
#  - Redistributions in binary form must reproduce the above copyright notice,
#    this list of conditions and the following disclaimer in the documentation
#    and/or other materials provided with the distribution.
# 
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
# WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
# SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
# CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
# OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
# OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
####

##
# Enable a stricter bash script processing to minimize errors in the code.
##
set -o nounset
set -o errexit

##
# Display usage information for this script
#
# This function does not exit the script. If you want to exit after displaying
# usage information you need to call exit afterwards manually.
##
usage() {
    cat <<EOF
Usage: ${0} [option,...]

Options:
  --disable-notifications: 
    Don't use notify-send to display messages as desktop notifications

  --config <file>:
    Use a special configuration file (Default: ${HOME}/.autostarter)

EOF
}

##
# Print out an error to STDERR as well as using an indicator if enabled
#
# Errors are considered fatal. After an error has been logged the execution of
# the whole application is stopped.
#
# @param message
##
perror() {
    local message="$@"

    echo "[!] ${message}" >&2

    if [ $NO_NOTIFY -ne 0 ]; then
        notify-send --urgency=normal --icon=error "Autostarter" "${message}"
    fi
    exit 244
}

##
# Print some sort of log message and display it as notification if not disabled
#
# @param message
##
plog() {
    local message="$@"
    echo "[>] ${message}" >&42

    if [ $NO_NOTIFY -ne 0 ]; then
        notify-send --urgency=normal --icon=information "Autostarter" "${message}"
    fi
}

# Open the file descriptor with number 42 to point to stdout. This allows for
# logging from inside of functions with a return value.
exec 42>&1

##
# Cleanup everything for a clean exit
#
# This function will be automatically called upon different signals the script
# receives.
##
cleanup() {
    # Close fd 42 again (We want to leave a clean env don't we? ;)
    exec 42>&-
}

##
# Always cleanup the temporary mess we might have left behind
##
trap 'cleanup' TERM INT EXIT

##
# Wait until a new window appears
##
wait_for_new_window_id() {
    local initial="$(wmctrl -l)"

    while [ "$(wmctrl -l)" == "$initial" ]; do
        sleep .5
    done

    wmctrl -l|tail -n1|awk '{print $1}'
}

##
# Switch to a certain workspace
##
workspace() {
    local wsnumber="$1"
    local x="$(echo "scale=0; (${wsnumber}%${HORIZONTAL_WORKSPACES})*${RESOLUTION_WIDTH}"|bc)"
    local y="$(echo "scale=0; (${wsnumber}/${VERTICAL_WORKSPACES})*${RESOLUTION_HEIGHT}"|bc)"

    wmctrl -o $x,$y
}

##
# Wait for a new window to appear and position it then
##
position() {
    local id="${CURRENT_WINDOW_ID}"
    local x="$1"
    local y="$2"
    local w="$3"
    local h="$4"

    wmctrl -i -r "$id" -e "0,$x,$y,$w,$h"
    
    sleep .5
}

run() {
    local found=1
    local data=""
    local pid=""
    local counter=0

    nohup "$@" 2>/dev/null 1>/dev/null &
    pid=$!

    echo "Waiting for PID: $pid ($@)"
    
    while [ $found -ne 0 ]; do
        data="$(wmctrl -pl|awk '{print $1 "\tpid:" $3}')"
        if echo "${data}" | grep -q "pid:${pid}"; then
            found=0
        else
            let counter=counter+1
            if [ $counter -lt 10 ]; then
                sleep .5
            else
                break;
            fi
        fi
    done

    if [ $counter -lt 10 ]; then
        CURRENT_WINDOW_ID="$(echo "$data"|tail -n1|awk '{print $1}')"
    else
        CURRENT_WINDOW_ID="$(wmctrl -l|tail -n1|awk '{print $1}')"
    fi
}

##
# Default options used if not specified on the commandline or in the configfile
# otherwise
##
NO_NOTIFY="1"
CONFIG_FILE="${HOME}/.autostarter"
HORIZONTAL_WORKSPACES="1"
VERTICAL_WORKSPACES="1"

##
# Parse the commandline options and set the appropriate global variables
##
while [ $# -ne 0 ]; do
    case "$1" in
        "--help")
            usage
            exit 0
        ;;
        "-h")
            usage
            exit 0
        ;;
        "--disable-notifications")
            NO_NOTIFY="0"
        ;;
        "--config")
            shift
            CONFIG_FILE="$1"
        ;;
    esac
    shift
done

if [ ! -f "${CONFIG_FILE}" ]; then
    perror "The configfile ${CONFIG_FILE} is not readable."
fi

source "${CONFIG_FILE}"

# Determine current screen resolution
RESOLUTION_WIDTH="$(xrandr --current|grep current|sed -e 's@^.*\scurrent\s*\([0-9]\+\)\s*x\s*\([0-9]\+\).*$@\1@')"
RESOLUTION_HEIGHT="$(xrandr --current|grep current|sed -e 's@^.*\scurrent\s*\([0-9]\+\)\s*x\s*\([0-9]\+\).*$@\2@')"
RESOLUTION="${RESOLUTION_WIDTH}x${RESOLUTION_HEIGHT}"

if [ "$(type -t "${RESOLUTION}")" != "function" ]; then
    perror "Please define a section named '${RESOLUTION}()' inside your config file to configure autostart applications for this resolution."
fi

CURRENT_WINDOW_ID=""

${RESOLUTION}
