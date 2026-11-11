#!/bin/sh
# Install hc-agents: link it into Rex's config folder, load it from init.lua,
# and reload Rex's config so the manager starts.
#
#   ./install.sh            install, or update the link
#   ./install.sh --remove   unlink it and drop the require line
#
# Without a clone, the script makes one in ~/.local/share/rex-hc-agents (or updates it):
#
#   curl -fsSL https://raw.githubusercontent.com/jeffarese/rex-hc-agents/main/install.sh | sh
set -eu

here=$(cd "$(dirname "$0")" 2>/dev/null && pwd || pwd)
# Run from a pipe, or from a copy of this file alone: clone the rest, where it can stay.
if [ ! -f "$here/hc-agents/init.lua" ]; then
  repo=${REX_HC_AGENTS_REPO:-https://github.com/jeffarese/rex-hc-agents.git}
  here=${XDG_DATA_HOME:-$HOME/.local/share}/rex-hc-agents
  if [ -d "$here/.git" ]; then
    git -C "$here" pull --quiet --ff-only
  else
    mkdir -p "$(dirname "$here")"
    git clone --quiet "$repo" "$here"
  fi
fi
conf_dir=${XDG_CONFIG_HOME:-$HOME/.config}/rex
init=${REX_CONFIG:-$conf_dir/init.lua}
link=$(dirname "$init")/hc-agents
line='require("hc-agents").setup{}'

if [ "${1:-}" = "--remove" ]; then
  if [ -L "$link" ]; then rm "$link"; fi
  if [ -f "$init" ]; then
    tmp=$(mktemp)
    grep -v -e 'require("hc-agents")' -e '^-- herdr-core agents in Rex' "$init" > "$tmp" || true
    cat "$tmp" > "$init"
    rm -f "$tmp"
  fi
  rex config reload
  echo "Removed hc-agents. Close the herdr-core session yourself if you no longer want it."
  exit 0
fi

mkdir -p "$(dirname "$init")"
if [ -e "$link" ] && [ ! -L "$link" ]; then
  echo "$link exists and isn't a link; move it away first." >&2
  exit 1
fi
ln -sfn "$here/hc-agents" "$link"

if ! grep -q 'require("hc-agents")' "$init" 2>/dev/null; then
  printf '\n-- herdr-core agents in Rex: a tab for each agent in the "herdr-core" session.\n%s\n' "$line" >> "$init"
fi

rex config check
rex config reload
echo "Installed. Each herdr-core agent now gets a tab in Rex's herdr-core session."
