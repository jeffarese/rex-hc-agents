# rex-hc-agents

Your [herdr-core](https://github.com/herdrdev/herdr-core) (`hc`) agents as tabs
in [Rex](https://www.superlogical.com)'s sidebar, with their live status.

<p align="center">
  <img src="docs/media/demo.gif" width="960" alt="A Rex window with a shell in a session called shop. Three hc run commands start Claude Code agents named fix-auth, retries and docs. A herdr-core session appears in the sidebar with a tab for each, all marked as working. The retries tab changes to show the question it is waiting on, and fix-auth is marked done. A click on retries shows the agent asking to run a command. It is answered, the agent finishes, and the fix-auth and docs tabs are opened in turn.">
</p>
<p align="center"><sub>
  28 seconds, unedited (<a href="docs/media/demo.mp4">MP4</a>). Rex, herdr-core and the plugin are real. The
  agents are a script standing in for Claude Code, and the project is made up.
  <a href="docs/demo">How it was recorded.</a>
</sub></p>

herdr-core keeps agents running in the background, on this machine or another
one, whether or not a terminal is showing them. To see one in Rex you would
run `hc attach` by hand, per agent. This plugin does that for you: every agent
`hc` runs gets a tab of its own in a `herdr-core` session, opened when the
agent starts and closed when it ends. Each tab passes the agent's status on to
Rex, so the sidebar and the Activity view (⌘.) show which agents are working,
which are waiting on you, and which have finished.

This is an unofficial plugin. It is not affiliated with Rex or Herdr.

## Requirements

- [Rex](https://www.superlogical.com), with its `rex` command
- [herdr-core](https://github.com/herdrdev/herdr-core) (`hc`); tested with 0.1.19

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/jeffarese/rex-hc-agents/main/install.sh | sh
```

The script does four things:

- **Fetches the plugin:** it clones this repository into `~/.local/share/rex-hc-agents`. Run
  the same line again to update.
- **Links it:** `hc-agents/` is linked into `~/.config/rex/`.
- **Loads it:** this line is added to your `init.lua`:

  ```lua
  require("hc-agents").setup{}
  ```

- **Starts it:** Rex's config is checked and reloaded.

From a clone of your own, `./install.sh` links that clone instead, and `./install.sh --remove`
takes the link and the line out again.

## Using it

| To | Do |
| --- | --- |
| Find an agent | Rex's sidebar, the Activity view (⌘.), or any Rex picker |
| Type into an agent | Just type, when the agent has no pane in the Herdr app |
| Close an agent's tab | Close it, or press `ctrl+\` in it. The agent keeps running. |
| Get closed tabs back | **herdr-core: Reopen Closed Agent Tabs** in the command palette |

A tab you closed stays closed, also across restarts, until you reopen it.

## Settings

All settings are optional. These are the defaults, apart from `agents`, which
is empty:

```lua
require("hc-agents").setup{
  session = "herdr-core", -- the session that holds the tabs
  include = "agents",     -- which terminals get a tab (see below)
  attach = "auto",        -- how a tab attaches (see below)
  machines = "all",       -- "local": only this machine's terminals (see below)
  agents = { "mybot" },   -- more program names to treat as agents
  interval = 2,           -- seconds between checks
  autostart = true,       -- start the manager when Rex loads its config
}
```

`include` decides which herdr-core terminals get a tab:

| Value | Terminals |
| --- | --- |
| `"agents"` | Coding agents herdr-core knows (Claude Code, Codex, OpenCode, Pi, Gemini, Amp and others), plus anything that has reported a status |
| `"named"` | Also every terminal started with a name (`hc run --name`) |
| `"programs"` | Also scripts, shells and other programs: everything except the Herdr app's own pane shells |
| `"all"` | Every terminal |

`attach` decides what a tab may do to its agent:

| Value | Behavior |
| --- | --- |
| `"auto"` | Control an agent that has no pane in the Herdr app, and watch one that has |
| `"control"` | Always control: you can type, and the agent is resized to the tab |
| `"watch"` | Never type or resize (`hc attach --observe`) |

`machines` decides whose terminals get a tab. herdr-core lists the terminals of every machine
you added with `hc machine add`, and with `"all"` each of them gets a tab here. If those
machines run Rex too, install the plugin on each with `machines = "local"`: every machine then
shows its own agents, under its own host in Rex's sidebar.

`hc` and `rex` are found in `~/.local/bin` or on `PATH`. Pass `hc = "/path"` or
`rex = "/path"` to use others. Changing a setting and reloading Rex's config
replaces the running manager within a few seconds.

## How it works

- **The manager:** when Rex loads its config, the plugin starts `manager.lua`
  in the background, with no tab of its own. It asks `hc ls` every 2 seconds
  and opens a tab for each new agent. The `herdr-core` session is created when
  the first agent appears, and removed when its last tab is gone.
- **Tab names:** an agent started with a name (`hc run --name`, herdr-pool
  lanes) is labeled with that name. An unnamed coding agent keeps the title it
  sets, such as Claude Code's task summary. Anything else is labeled after its
  program and, on another machine, the machine (`zsh · mini`).
- **Status:** each tab runs `hc attach`, and herdr-core passes the agent's own
  [OSC 7501 status reports](https://www.superlogical.com/rex/docs/build/program-status)
  through. Rex shows the state the agent reported, not a guess.
- **Watched agents:** an agent the Herdr app shows in a pane is only watched
  by default, so a Rex tab never resizes a pane you are using there.
- **One manager:** only one runs at a time, however often Rex loads its
  config. If it dies, it is started again within a few seconds.
- **State:** a heartbeat, the list of closed tabs and the manager's log live
  in `~/.local/state/rex-hc-agents/`.

## Known limits

- **Narrow tabs:** a tab narrower than a watched agent's terminal shows the
  agent's screen cut off, because watching never resizes it.
- **`rex config check` starts the manager too:** the check runs the plugin.
  That is safe to repeat, since a second manager with the same settings exits
  at once.

## Development

```sh
rex do tests/common_test.lua
```

The tests cover the logic in `hc-agents/common.lua`: which terminals get a tab
and when the manager opens one. Rex runs Lua 5.1, so they run under `rex do`.

One Rex Lua quirk shapes the code. When a protected call catches an error,
closures stop sharing the plain locals they captured: each gets its own frozen
copy, while table fields stay shared. Rex's timers catch errors this way, so
the manager keeps its state in a table. To reproduce it:

```sh
rex do -e 'local n=0; local function f() n=n+1 end; f(); pcall(error, "x"); f(); return n'
```

This returns 1 instead of 2.

## License

[MIT](LICENSE)
