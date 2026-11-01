#!/bin/sh
# usage: launch.sh PROMPT_FILE PROGRAM [ARGS...]
prompt=$1
shift
exec "$@" < "$prompt"
