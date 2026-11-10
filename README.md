# hc-agents for Rex

**Your [herdr-core](https://github.com/herdrdev/herdr-core) agents in Rex's
sidebar.** Every agent that `hc` runs, on this machine or another one, gets a
tab of its own in a `herdr-core` session. Each tab is attached to its agent
and passes its status on to Rex. The sidebar then marks which agents are
working, which are waiting on you, and which have finished, and so does the
Activity view (⌘.).

```
herdr-core
  r9-feel    ◐  ← working
  r9-art     ◆  ← waiting on you (permission, a question, a login)
  fix-auth   ✓  ← done, not looked at yet
```

## How it works

- **When Rex loads its config**, the plugin starts `manager.lua` in the
  background. It has no tab of its own.
- **The manager** asks `hc ls` every 2 seconds. Each new agent gets a tab in
  the `herdr-core` session, which is created when the first one appears. An
  agent started with a name (`hc run --name`, herdr-pool lanes) is labeled
  with that name. An unnamed coding agent keeps the title it sets, such as
  Claude Code's task summary. Anything else is labeled after its program and,
  for another machine, the machine (`zsh · mini`).
- **Each agent tab** runs `hc attach`. An agent with no pane in the Herdr app
  gets a real attach: you can type into it and it is resized to the tab. An
  agent the Herdr app shows in a pane is only watched (`--observe`), so the
  tab never resizes a pane you are using there. Either way herdr-core passes
  the agent's own OSC 7501 status reports through, so Rex shows the real
  state, not a guess.
- **A tab closes** when its agent ends or when you detach from it (ctrl+\\).
  A tab you closed or detached stays closed, also across restarts.
- **If the manager dies** it is started again within a few seconds. Only one
  runs at a time, however often Rex loads its config.

An agent is a terminal whose program herdr-core knows as a coding agent
(Claude Code, Codex, OpenCode, Pi, Gemini, Amp and others) or that has reported
a status. Scripts and shells stay out unless you set `include` (see Settings).

It needs `hc` (herdr-core), `rex` and zsh.

## Using it

| To | Do |
| --- | --- |
| Find an agent | Rex's sidebar, the Activity view (⌘.), or any Rex picker |
| Type into an agent | just type, when it has no Herdr app pane |
| Close an agent's tab | close it, or press ctrl+\\ in it; the agent keeps running |
| Get closed tabs back | **herdr-core: Reopen Closed Agent Tabs** in the command palette |

## Install

```sh
./install.sh
```

It links `hc-agents/` into `~/.config/rex/`, adds this line to `init.lua`, and
reloads Rex's config:

```lua
require("hc-agents").setup{}
```

`./install.sh --remove` takes it out again.

### Settings

```lua
require("hc-agents").setup{
  session = "herdr-core", -- the session that holds the tabs
  include = "agents",     -- "named" adds every named terminal; "programs" adds scripts, shells
                          -- and other programs (all but Herdr's pane shells); "all" adds everything
  attach = "auto",        -- "control": always type and resize; "watch": never
  agents = { "mybot" },   -- more program names to treat as agents
  interval = 2,           -- seconds between checks
  autostart = true,       -- start the manager when Rex loads its config
}
```

`hc` and `rex` are found in `~/.local/bin`, or on `PATH`. Pass `hc = "/path"`
or `rex = "/path"` to use others. The plugin keeps a heartbeat, the closed tabs and
the manager's log in `~/.local/state/rex-hc-agents/`. Changing a setting and
reloading Rex's config replaces the running manager within a few seconds.

## Tests

```sh
rex do tests/common_test.lua
```

The tests cover the logic in `hc-agents/common.lua`: which terminals get a
tab and when the manager opens one. Rex runs Lua 5.1, so they run under
`rex do`.

## Notes

- **Rex's Lua and pcall.** When a protected call catches an error, closures stop
  sharing the plain locals they captured. Each one gets its own frozen copy,
  while table fields stay shared. Rex's timers catch errors this way, so the
  manager keeps its state in a table. Reproduce it with
  `rex do -e 'local n=0; local function f() n=n+1 end; f(); pcall(error, "x"); f(); return n'`,
  which returns 1 instead of 2.
- **`rex config check` runs the plugin too**, including starting the manager.
  That is safe to repeat: a second manager with the same settings leaves at once.
- **A tab narrower than the agent's terminal** shows a watched agent's screen
  cut to the tab, because watching never resizes it. This applies to agents
  with a Herdr app pane, or to `attach = "watch"`.
