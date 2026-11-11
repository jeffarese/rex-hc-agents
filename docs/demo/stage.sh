#!/bin/sh
# Builds the demo's stage on this Mac, all of it synthetic, and prints the
# folder it lives in. `stage.sh --down <folder>` stops it and deletes it.
#
#   w=$(sh docs/demo/stage.sh)
#   (. "$w/env.sh" && rex ls)
#   sh docs/demo/stage.sh --down "$w"
#
# The stage is a herdr-core core and a Rex server of their own, with their
# own home folder, config and state. The Rex server loads this repository's
# plugin. `claude` there is bin/claude, a script. Nothing of yours is read or
# touched, and your own sessions and agents don't show.
set -eu
kit=$(cd "$(dirname "$0")" && pwd)
repo_root=$(cd "$kit/../.." && pwd)
hc_bin=$(command -v herdr-core 2>/dev/null || echo "$HOME/.local/bin/herdr-core")
rex_bin=$(command -v rex 2>/dev/null || echo "$HOME/.local/bin/rex")

if [ "${1:-}" = --down ]; then
  w=${2:?usage: stage.sh --down <folder>}
  [ -f "$w/env.sh" ] || { echo "not a demo folder: $w" >&2; exit 2; }
  # shellcheck disable=SC1091
  . "$w/env.sh"
  # The Rex app that record.sh started, then the Rex server.
  for f in "$w/app.pid" "$w/rex.pid"; do
    [ -f "$f" ] && kill "$(cat "$f")" 2>/dev/null || :
  done
  herdr-core server stop >/dev/null 2>&1 || :
  # A program still running from the folder ends by its PID.
  pids=$(ps -axo pid=,command= | awk -v w="$w/" 'index($0, w) {print $1}')
  [ -z "$pids" ] || kill $pids 2>/dev/null || :
  rm -rf "$w"
  exit 0
fi

[ -x "$hc_bin" ] || { echo "needs herdr-core" >&2; exit 2; }
[ -x "$rex_bin" ] || { echo "needs rex" >&2; exit 2; }

# Short on purpose: Unix socket paths have a ~104 byte limit on macOS.
w=$(mktemp -d /tmp/rhd.XXXXXX)
# The real path, so Rex shows the shop as ~/code/shop.
w=$(cd "$w" && pwd -P)
mkdir -p "$w/bin" "$w/s" "$w/c/rex" "$w/home/code/shop" "$w/rexstate" "$w/home/Library/Application Support/rex"
ln -s "$hc_bin" "$w/bin/herdr-core"
ln -s "$hc_bin" "$w/bin/hc"
ln -s "$rex_bin" "$w/bin/rex"
ln -s "$kit/bin/claude" "$w/bin/claude"
ln -s "$repo_root/hc-agents" "$w/c/rex/hc-agents"

cat > "$w/env.sh" <<ENV
# The demo stage's environment (stage.sh).
export DEMO_WORK='$w' HOME='$w/home' ZDOTDIR='$w/home' SHELL=/bin/zsh
export PATH='$w/bin:/usr/bin:/bin:/usr/sbin:/sbin'
export XDG_STATE_HOME='$w/s' XDG_CONFIG_HOME='$w/c'
export HC_SESSION=rhd REX_CONFIG='$w/c/rex/init.lua'
# Where a Rex app whose home is this folder looks for "This Mac".
export REX_SERVER='$w/home/Library/Application Support/rex/server.sock'
export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 DEMO_PACE='${DEMO_PACE:-1}'
unset HC_TERMINAL_ID HC_TERMINAL_SOCKET CLAUDE_CONFIG_DIR TERM_PROGRAM TERM_PROGRAM_VERSION
unset REX_SESSION REX_BLOCK REX_CLIENT REX_HOME
ENV
# shellcheck disable=SC1091
. "$w/env.sh"

# Rex starts a shell with the account's real home; the stage's shells go back to the stage's.
printf 'export HOME="%s"\n' "$HOME" > "$HOME/.zshenv"
printf 'PROMPT="%%F{cyan}%%~%%f %%F{magenta}❯%%f "\nunsetopt beep\n' > "$HOME/.zshrc"
cat > "$REX_CONFIG" <<LUA
require("hc-agents").setup{ hc = "$w/bin/hc", rex = "$w/bin/rex" }
LUA

# The core is named for a made-up machine: hc names a core after the host the
# first time it starts and keeps the name in core.json.
cd "$HOME"
herdr-core server start >/dev/null
herdr-core server stop >/dev/null
sed -i '' 's/"name": *"[^"]*"/"name": "laptop"/' "$XDG_STATE_HOME/herdr-core/rhd/core.json"
herdr-core server start >/dev/null

# The Rex server, with the stage's environment, so its terminals and the
# plugin's manager stay on the stage.
nohup rex server run --listen "$REX_SERVER" --state-dir "$w/rexstate" --config "$REX_CONFIG" \
  --restore=false >"$w/rex.log" 2>&1 &
echo $! > "$w/rex.pid"
i=0
until rex --autostart=false ls >/dev/null 2>&1; do
  i=$((i + 1)); [ $i -lt 50 ] || { echo "the Rex server didn't start: $w/rex.log" >&2; exit 1; }
  sleep 0.2
done
echo "$w"
