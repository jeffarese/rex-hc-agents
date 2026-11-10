#!/bin/zsh
# agent-tab.zsh ADDRESS [TITLE]
#
# The program in each agent's tab: `hc attach`, which shows the agent and
# passes its OSC 7501 status on to Rex, so the sidebar shows it working,
# waiting on you, or done. The tab closes when the agent ends or you detach
# (ctrl+\).
#
# TITLE names the tab until the agent's program sets a title of its own.
#
# HC_ATTACH picks how: "control" types into the agent and resizes it to the
# tab; "watch" (`--observe`) does neither; "auto" (the default) controls an
# agent that has no pane in the Herdr app and watches one that does, so the
# tab never resizes a pane you are looking at there.

addr=${1:?usage: agent-tab.zsh ADDRESS [TITLE]}
hc=${HC_BIN:-hc}
mode=${HC_ATTACH:-auto}

printf '\e]2;%s\a' "${2:-$addr}"

if [[ $mode == auto ]]; then
  # The Herdr app labels the terminals it holds in a pane with herdr.space.
  if [[ $("$hc" get "$addr" --json 2>/dev/null) == *'"herdr.space"'* ]]; then
    mode=watch
  else
    mode=control
  fi
fi

[[ $mode == watch ]] && exec "$hc" attach --observe "$addr"
exec "$hc" attach "$addr"
