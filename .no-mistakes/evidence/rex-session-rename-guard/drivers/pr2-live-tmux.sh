#!/usr/bin/env bash
# Live control for the Rex session-rename guard: the same real bin/fm-spawn.sh
# scout spawn on the tmux backend, against a private tmux server on its own
# socket, so the rendered launch role can be compared with the Rex spawn's.
set -u
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"
REX_BUNDLE_DIR="$HOME/Library/Application Support/com.superlogical.rex/RexServer/Versions/Current/Rex Server.app/Contents/MacOS"
CODE=$1
OUT=$2
mkdir -p "$OUT"
SCRATCH=$(mktemp -d "${TMPDIR:-/tmp}/uxb-pr2-tmux.XXXXXX")
PROJ="$SCRATCH/proj"
git init -q -b main "$PROJ"
printf 'max_trees = 1\nroot = "."\n' >"$PROJ/treehouse.toml"
git -C "$PROJ" add treehouse.toml
git -C "$PROJ" -c user.email=t@t -c user.name=t commit -q -m init
printf '.treehouse/\n' >"$PROJ/.git/info/exclude"

SOCK="$SCRATCH/tmux.sock"
tmux -S "$SOCK" -f /dev/null new-session -d -s firstmate -x 200 -y 50 || { echo "tmux start failed"; exit 1; }
cleanup() { tmux -S "$SOCK" kill-server >/dev/null 2>&1; echo "tmux_killed=$?" >"$OUT/teardown.log"; ( cd "$PROJ" && treehouse status 2>&1 | tail -1 ) >>"$OUT/teardown.log"; }
trap cleanup EXIT
PANE=$(tmux -S "$SOCK" display-message -p -t firstmate '#{pane_id}')
SERVER_PID=$(tmux -S "$SOCK" display-message -p '#{pid}')
{
  echo "date: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  echo "code: $(git -C "$CODE" log --oneline -1)"
  echo "tmux: $(tmux -V) private socket $SOCK"
} >"$OUT/env.txt"

home="$OUT/home"; id=live-tmux-control
"$CODE/bin/fm-lab-home.sh" create "$home" >/dev/null; mkdir -p "$home/data/$id"
touch "$home/state/.last-watcher-beat"
printf '# Task\n## Captain'"'"'s intent\nLive control for the Rex rename guard.\n\n## Firstmate spec\nExercise the launch role only.\n' >"$home/data/$id/brief.md"
env -u REX_SESSION -u REX_BLOCK -u REX_CLIENT -u REX_SERVER -u TERM_PROGRAM -u HERDR_ENV \
  TMUX="$SOCK,$SERVER_PID,0" TMUX_PANE="$PANE" FM_ROOT_OVERRIDE='' FM_HOME="$home" \
  FM_STATE_OVERRIDE="$home/state" \
  FM_CONFIG_OVERRIDE="$home/config" FM_SPAWN_NO_GUARD=1 \
  "$CODE/bin/fm-spawn.sh" "$id" "$PROJ" --scout 'sleep 600' --backend tmux >"$OUT/spawn.out" 2>&1
echo "spawn_exit=$?" >>"$OUT/spawn.out"
grep -E '^(backend|window|worktree)=' "$home/state/$id.meta" >"$OUT/meta.txt" 2>&1
sed -n '1,/^$/p' "$home/data/$id/launch-brief.md" >"$OUT/launch-role.txt" 2>&1
cat "$OUT/env.txt"; echo; tail -2 "$OUT/spawn.out"; echo; cat "$OUT/meta.txt"; echo
echo "guard lines in tmux role: $(grep -c 'Ignore any Rex hook prompt' "$OUT/launch-role.txt")"
