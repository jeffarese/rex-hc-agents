-- hc-agents: herdr-core agents in Rex's sidebar.
--
-- In ~/.config/rex/init.lua:
--
--   require("hc-agents").setup{}
--
-- When Rex loads its config, this starts manager.lua in the background. It
-- gives each herdr-core agent a tab of its own in a session named
-- "herdr-core". Each tab is attached to its agent and passes the agent's
-- status on to Rex, so the sidebar and its Activity view (cmd+.) show which
-- agents are working, waiting on you, or done.
--
-- Settings, all optional:
--   session   = "herdr-core"  the session that holds the agent tabs
--   include   = "agents"      "agents": coding agents and anything that reports
--                             a status; "named": also every named terminal;
--                             "programs": also scripts, shells and other programs,
--                             everything but the Herdr app's own pane shells;
--                             "all": every herdr-core terminal
--   attach    = "auto"        how a tab attaches: "control" types into the agent
--                             and resizes it to the tab; "watch" does neither;
--                             "auto" controls agents without a Herdr app pane
--   machines  = "all"         "local": only this machine's terminals, for when
--                             every machine runs Rex with this plugin
--   agents    = {}            more program names to treat as agents
--   interval  = 2             seconds between checks of herdr-core
--   autostart = true          start the manager when Rex loads its config
--   hc, rex                   paths to the binaries (found in ~/.local/bin or PATH)

local dir = (debug.getinfo(1, "S").source:gsub("^@", "")):match("^(.*/)") or "./"
local common = dofile(dir .. "common.lua")

local M = {}

function M.setup(opts)
  local cfg = common.config(opts)

  rex.action{
    name = "hc_agents_reopen",
    title = "herdr-core: Reopen Closed Agent Tabs",
    description = "Give every herdr-core agent whose tab you closed or detached its tab back.",
    category = "herdr-core",
    keywords = "hc herdr agents claude codex sidebar closed detached restore tabs",
    run = function()
      rex.exec({ "mkdir", "-p", cfg.state_dir })
      return common.write_file(cfg.state_dir .. "/reopen", "")
    end,
  }

  -- Rex may still be starting when it loads this file, so retry for a few
  -- seconds, and start the manager again if it dies. --autostart=false keeps a retry from starting a second server.
  -- `rex config check` also loads this file; a second manager leaves at once.
  if cfg.autostart then
    local script = [[
mkdir -p "$4"
fails=0
while [ $fails -lt 20 ]; do
  started=$(date +%s)
  if "$1" --autostart=false do "$2" --args "$3" >"$4/manager.log" 2>&1; then exit 0; fi
  # A manager that ran for a while and then died (killed, or Rex restarted)
  # gets its tries back; one that can't start at all gives up after 20.
  if [ $(( $(date +%s) - started )) -gt 30 ]; then fails=0; else fails=$((fails + 1)); fi
  sleep 1
done
exit 1
]]
    rex.exec.start({ "/bin/sh", "-c", script, "sh", cfg.rex, dir .. "manager.lua", rex.json.encode(cfg), cfg.state_dir },
      { detach = true, stdout = false, stderr = false })
  end

  return cfg
end

return M
