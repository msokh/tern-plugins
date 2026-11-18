#!/bin/sh
# usage: launch.sh OUTPUT_FILE STDIN_FILE|- PROGRAM [ARGS...]
# Runs PROGRAM (with STDIN_FILE on stdin unless it is `-`), then saves what the pane shows to
# OUTPUT_FILE before the session can end, and exits with the program's status.
output=$1
input=$2
shift 2
if [ "$input" = - ]; then
	"$@"
else
	"$@" < "$input"
fi
status=$?
"${TERN_EXE:-tern}" capture "$TERN_PANE" --scrollback 2>/dev/null | tail -n 2000 > "$output"
exit "$status"
