#!/usr/bin/env bash
# Live evidence for the Rex session-rename guard: a real bin/fm-spawn.sh scout
# spawn with --backend rex on a private Rex lab server, launching a harmless raw
# command, into a scratch project whose in-project treehouse pool has one slot.
# Records the rendered launch-brief.md role contract and Rex's own session-start
# hook text from the worker's tab.
set -u
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"
REX_BUNDLE_DIR="$HOME/Library/Application Support/com.superlogical.rex/RexServer/Versions/Current/Rex Server.app/Contents/MacOS"
export REX_BIN_DIR="${REX_BIN_DIR:-$REX_BUNDLE_DIR}"
CODE=$1   # firstmate checkout under test
OUT=$2    # evidence directory
H=/Users/roderik/code/firstmate-rex/bin/fm-rex-lab.sh
mkdir -p "$OUT"
SCRATCH=$(mktemp -d "${TMPDIR:-/tmp}/uxb-pr2-live.XXXXXX")
PROJ="$SCRATCH/proj"
git init -q -b main "$PROJ"
printf 'max_trees = 1\nroot = "."\n' >"$PROJ/treehouse.toml"
git -C "$PROJ" add treehouse.toml
git -C "$PROJ" -c user.email=t@t -c user.name=t commit -q -m init
printf '.treehouse/\n' >"$PROJ/.git/info/exclude"

LAB=$("$H" name uxb-pr2-live)
cleanup() {
  "$H" teardown "$LAB" >"$OUT/teardown.log" 2>&1; echo "teardown_exit=$?" >>"$OUT/teardown.log"
  ( cd "$PROJ" && treehouse status 2>&1 | tail -1 ) >>"$OUT/teardown.log"
}
trap cleanup EXIT
"$H" provision "$LAB" >"$OUT/provision.log" 2>&1 || { echo "provision failed"; cat "$OUT/provision.log"; exit 1; }

REAL_REX_DIR=${REX_BIN_DIR:-$REX_BUNDLE_DIR}
[ -x "$REAL_REX_DIR/rex" ] || { echo "no real rex binary"; exit 1; }
SHIM="$OUT/shim"
mkdir -p "$SHIM"
cat >"$SHIM/rex" <<EOF
#!/usr/bin/env bash
args=()
for a in "\$@"; do case "\$a" in --autostart|--autostart=*) ;; *) args+=("\$a") ;; esac; done
exec env REX_BIN_DIR="$REAL_REX_DIR" PATH="$PATH" "$H" run "$LAB" "\${args[@]}"
EOF
chmod +x "$SHIM/rex"

{
  echo "date: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  echo "code: $(git -C "$CODE" log --oneline -1)"
  echo "rex: $("$H" run "$LAB" version | head -1)"
  echo "treehouse: $(treehouse --version)"
  echo "lab server: $("$H" server "$LAB")"
} >"$OUT/env.txt"

home="$OUT/home"; id=live-rex-rename
"$CODE/bin/fm-lab-home.sh" create "$home" >/dev/null; mkdir -p "$home/data/$id"
touch "$home/state/.last-watcher-beat"
printf '# Task\n## Captain'"'"'s intent\nLive evidence for the Rex rename guard.\n\n## Firstmate spec\nExercise the launch role only.\n' >"$home/data/$id/brief.md"
env -u REX_SESSION -u REX_BLOCK -u REX_CLIENT -u REX_SERVER -u TMUX -u HERDR_ENV \
  PATH="$SHIM:$PATH" REX_BIN_DIR="$SHIM" FM_ROOT_OVERRIDE='' FM_HOME="$home" \
  FM_STATE_OVERRIDE="$home/state" \
  FM_CONFIG_OVERRIDE="$home/config" FM_SPAWN_NO_GUARD=1 \
  "$CODE/bin/fm-spawn.sh" "$id" "$PROJ" --scout 'sleep 600' --backend rex >"$OUT/spawn.out" 2>&1
echo "spawn_exit=$?" >>"$OUT/spawn.out"
grep -E '^(backend|window|rex_server|rex_session_id|rex_block_id|worktree)=' "$home/state/$id.meta" >"$OUT/meta.txt" 2>&1
sed -n '1,/^$/p' "$home/data/$id/launch-brief.md" >"$OUT/launch-role.txt" 2>&1

# Rex's own session-start hook text, read from inside the worker's tab.
sid=$(sed -n 's/^rex_session_id=//p' "$home/state/$id.meta"); bid=$(sed -n 's/^rex_block_id=//p' "$home/state/$id.meta")
if [ -n "$sid" ] && [ -n "$bid" ]; then
  "$H" run "$LAB" send -s "$sid" -b "$bid" -- $'\003' >/dev/null 2>&1
  sleep 1
  "$H" run "$LAB" send -s "$sid" -b "$bid" -- "\"\$REX_BIN_DIR/rex\" -S \"\$REX_SERVER\" --autostart=false __internal session-start --agent claude | grep -A1 'rex session rename'; echo HOOK_EXIT=\$?" >/dev/null 2>&1
  "$H" run "$LAB" send -s "$sid" -b "$bid" -- $'\r' >/dev/null 2>&1
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    sleep 1
    "$H" run "$LAB" capture -s "$sid" -b "$bid" --unwrap --trim >"$OUT/worker-tab.txt" 2>&1
    grep -q 'HOOK_EXIT=' "$OUT/worker-tab.txt" && break
  done
  "$H" run "$LAB" list --json >"$OUT/lab-sessions.json" 2>&1 || true
fi
( cd "$PROJ" && treehouse status 2>&1 | tail -1 ) >"$OUT/pool-during.txt"
cat "$OUT/env.txt"; echo; tail -3 "$OUT/spawn.out"; echo; cat "$OUT/meta.txt"; echo; cat "$OUT/launch-role.txt"; echo; tail -8 "$OUT/worker-tab.txt" 2>/dev/null
