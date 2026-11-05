#!/bin/sh
# Keeps private names, home paths and secrets out of this public repository.
# usage: check-public.sh index | message FILE | history
# The denylist (one literal per line) comes from $TERN_PLUGINS_DENYLIST (CI secret) or
# $TERN_PLUGINS_DENYLIST_FILE (default ~/.config/tern-plugins/denylist). Matches are reported
# by file only so the listed names never reach a log.
set -eu

mode=${1:-index}
cd "$(git rev-parse --show-toplevel)"

# Why: the repository owner's login is public in every install URL, so a shared list naming it
# would flag the README.
owner=$(git remote get-url origin | sed -E 's#^.*[:/]([^/]+)/[^/]+$#\1#')
raw=$(mktemp)
list=$(mktemp)
trap 'rm -f "$raw" "$list"' EXIT
if [ -n "${TERN_PLUGINS_DENYLIST:-}" ]; then
	printf '%s\n' "$TERN_PLUGINS_DENYLIST" > "$raw"
else
	file=${TERN_PLUGINS_DENYLIST_FILE:-$HOME/.config/tern-plugins/denylist}
	[ -r "$file" ] && cat "$file" > "$raw"
fi
tr -d '\r' < "$raw" | grep -v -e '^[[:space:]]*$' -e "^${owner}\$" -i > "$list" || true
if [ ! -s "$list" ]; then
	echo "check-public: no denylist; set TERN_PLUGINS_DENYLIST or TERN_PLUGINS_DENYLIST_FILE" >&2
	exit 2
fi

home_paths='/Users/[A-Za-z0-9._-]+|/home/[a-z_][a-z0-9_-]*/'
failed=0
fail() {
	echo "check-public: $1" >&2
	failed=1
}

case $mode in
index)
	for f in $(git grep --cached -l -I -i -F -f "$list" -- . || true); do
		fail "$f contains a denylisted name"
	done
	for f in $(git grep --cached -l -I -E "$home_paths" -- . ':!scripts/check-public.sh' || true); do
		fail "$f contains an absolute home path"
	done
	gitleaks git --pre-commit --staged --no-banner --redact . >&2 || fail "gitleaks found a secret in staged changes"
	;;
message)
	msg=$2
	grep -q -i -F -f "$list" "$msg" && fail "commit message contains a denylisted name"
	grep -q -E "$home_paths" "$msg" && fail "commit message contains an absolute home path"
	;;
history)
	for rev in $(git rev-list --all); do
		if git grep -q -I -i -F -f "$list" "$rev" -- . ||
			git log -1 --format=%B "$rev" | grep -q -i -F -f "$list"; then
			fail "commit $rev contains a denylisted name"
		fi
		if git grep -q -I -E "$home_paths" "$rev" -- . ':!scripts/check-public.sh'; then
			fail "commit $rev contains an absolute home path"
		fi
	done
	gitleaks git --no-banner --redact . >&2 || fail "gitleaks found a secret in history"
	;;
*)
	echo "usage: check-public.sh index | message FILE | history" >&2
	exit 2
	;;
esac

exit $failed
