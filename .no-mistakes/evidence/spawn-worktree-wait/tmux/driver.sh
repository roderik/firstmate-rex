#!/usr/bin/env bash
set -u
CODE=$1; PROJ=$2; OUT=$3
for spec in "override-3:3" "default:-unset-" "blank:" "zero:0" "zero-padded:00" "non-numeric:soon"; do
  name=${spec%%:*}; value=${spec#*:}
  home=$(cd "$(mktemp -d "${TMPDIR:-/tmp}/fm-lab.XXXXXX")" && pwd -P); mkdir -p "$OUT/$name"
  "$CODE/bin/fm-lab-home.sh" create "$home" >/dev/null 2>&1
  mkdir -p "$home/tmux"; touch "$home/state/.last-watcher-beat" 2>/dev/null
  id="live-wait-$name"; mkdir -p "$home/data/$id" "$home/projects" "$home/state" "$home/config"
  printf '# Task\n## Captain'"'"'s intent\nwait test\n\n## Firstmate spec\nspawn wait only\n' >"$home/data/$id/brief.md"
  printf 'codex\n' >"$home/config/crew-harness"
  export TMUX_TMPDIR="$home/tmux"
  tmux -L fm-lab new-session -d -s fm -c /tmp
  start=$(date +%s)
  if [ "$value" = -unset- ]; then unset FM_SPAWN_WORKTREE_WAIT_SECS; else export FM_SPAWN_WORKTREE_WAIT_SECS=$value; fi
  TMUX=$(tmux -L fm-lab display -p '#{socket_path},1,0') env -u NO_MISTAKES_GATE -u FM_GATE_REFUSE_BYPASS -u FM_ROOT_OVERRIDE -u FM_STATE_OVERRIDE -u FM_DATA_OVERRIDE -u FM_CONFIG_OVERRIDE -u FM_PROJECTS_OVERRIDE -u HERDR_ENV \
    FM_HOME="$home" FM_SPAWN_NO_GUARD=1 "$CODE/bin/fm-spawn.sh" "$id" "$PROJ" --backend tmux --mode no-mistakes --yolo off >"$OUT/$name/spawn.out" 2>&1
  rc=$?; end=$(date +%s)
  printf 'case=%s value=[%s] exit=%s elapsed=%ss meta_published=%s\n  %s\n' "$name" "$value" "$rc" "$((end-start))" "$([ -e "$home/state/$id.meta" ] && echo yes || echo no)" "$(grep -m1 'did not enter' "$OUT/$name/spawn.out" || tail -3 "$OUT/$name/spawn.out")" >"$OUT/$name/result.txt"
  tmux -L fm-lab kill-server 2>/dev/null; rm -rf "$home"
done
cat "$OUT"/*/result.txt
