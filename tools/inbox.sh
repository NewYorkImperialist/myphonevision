#!/usr/bin/env bash
# Teammate messages: open GitHub issues you're assigned to, mentioned in or wrote, that someone
# else touched since the last check. Run by the Claude Code hooks in .claude/settings.json.
#   tools/inbox.sh all    every open issue involving you (session start)
#   tools/inbox.sh 120    only new activity, at most one GitHub call per 120 s (each prompt)
set -u
stamp="$(git rev-parse --git-dir)/inbox-last-check"
now=$(date +%s)
last=$(cat "$stamp" 2>/dev/null || echo 0)
if [ "${1:-all}" != all ]; then
  [ $((now - last)) -lt "$1" ] && exit 0
  since=$last
else
  since=0
fi
me=$(gh api user -q .login 2>/dev/null) || exit 0
out=$(gh issue list --search "involves:@me" --state open \
  --json number,title,author,updatedAt,comments \
  --jq ".[] | select((.updatedAt | fromdateiso8601) > $since)
        | select($since == 0 or ((.comments[-1].author.login // .author.login) != \"$me\"))
        | \"#\(.number) \(.title)  (last: \(.comments[-1].author.login // .author.login))\"" 2>/dev/null) || exit 0
echo "$now" > "$stamp"
[ -n "$out" ] && printf 'Teammate messages (GitHub issues; read with gh issue view N --comments):\n%s\n' "$out"
exit 0
