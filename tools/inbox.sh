#!/usr/bin/env bash
# Teammate messages: open GitHub issues you're assigned to, mentioned in or wrote.
# Run by the Claude Code hooks in .claude/settings.json.
#   tools/inbox.sh all    every open issue involving you (session start)
#   tools/inbox.sh 120    only unseen activity by someone else, at most one check per 120 s (each prompt)
set -u
mode=${1:-all}
dir=$(git rev-parse --git-dir) || exit 0
stamp="$dir/inbox-last-check" seen="$dir/inbox-seen" mefile="$dir/inbox-login"
now=$(date +%s)
if [ "$mode" != all ]; then
  last=$(cat "$stamp" 2>/dev/null || echo 0)
  [ $((now - last)) -lt "$mode" ] && exit 0
fi
echo "$now" > "$stamp"
fail() { [ "$mode" = all ] && echo "Teammate inbox disabled: $1"; exit 0; }
me=$(cat "$mefile" 2>/dev/null)
if [ -z "$me" ]; then
  me=$(gh api user -q .login 2>/dev/null) || fail "install gh and run gh auth login"
  echo "$me" > "$mefile"
fi
# key = number@updatedAt, so an issue shows again whenever it changes; no clock comparison,
# so issues that reach the search index late are still caught.
rows=$(gh issue list --search "involves:@me" --state open \
  --json number,title,author,updatedAt,comments \
  --jq '.[] | "\(.number)@\(.updatedAt)\t\(.comments[-1].author.login // .author.login)\t#\(.number) \(.title)"') \
  || fail "gh issue list failed"
touch "$seen"
if [ "$mode" = all ]; then
  out=$(printf '%s\n' "$rows" | awk -F'\t' 'NF { print $3 "  (last: " $2 ")" }')
else
  out=$(printf '%s\n' "$rows" | awk -F'\t' -v me="$me" 'NR==FNR { s[$0]; next } NF && !($1 in s) && $2 != me { print $3 "  (last: " $2 ")" }' "$seen" -)
fi
printf '%s\n' "$rows" | cut -f1 | grep . >> "$seen"
[ -n "$out" ] && printf 'Teammate messages (GitHub issues; read with gh issue view N --comments):\n%s\n' "$out"
exit 0
