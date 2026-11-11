-- Shared code for the hc-agents Rex plugin: its settings, which herdr-core
-- terminals get a tab, and which tabs are open.
--
-- init.lua and manager.lua load this file with dofile. Everything here except
-- the file helpers is pure, so tests/common_test.lua can check it with `rex do`.

local M = {}

M.TAB_PREFIX = "hc:"
M.SHELL_FLAVOR = "com.superlogical.terminal.shell"

-- Program names herdr-core reports in `agent` for coding agents. A terminal
-- that reported an OSC 7501 status counts as an agent too.
M.KNOWN_AGENTS = {
  ["aider"] = true, ["amp"] = true, ["claude"] = true, ["claude-code"] = true,
  ["codex"] = true, ["copilot"] = true, ["crush"] = true, ["cursor-agent"] = true,
  ["droid"] = true, ["gemini"] = true, ["goose"] = true, ["kimi"] = true,
  ["omo"] = true, ["opencode"] = true, ["pi"] = true, ["qwen"] = true,
}

local INCLUDE = { agents = true, named = true, programs = true, all = true }
local ATTACH = { auto = true, control = true, watch = true }
local MACHINES = { all = true, ["local"] = true }
-- Plain shells: with include = "programs", the Herdr app's own pane shells stay out.
local SHELLS = { sh = true, bash = true, zsh = true, fish = true, dash = true, ksh = true,
  tcsh = true, csh = true, nu = true, pwsh = true, powershell = true, cmd = true, xonsh = true, elvish = true }

local function file_exists(path)
  local f = io.open(path, "r")
  if f then f:close() end
  return f ~= nil
end

-- Settings from setup{...} or a script's --args, with defaults filled in.
-- The result is plain data, so it survives rex.json.encode and decode.
function M.config(opts)
  opts = opts or {}
  local home = os.getenv("HOME") or ""
  local function bin(name, given)
    if given and given ~= "" then return given end
    local local_bin = home .. "/.local/bin/" .. name
    if file_exists(local_bin) then return local_bin end
    return name
  end
  local include = opts.include or "agents"
  if not INCLUDE[include] then
    error('hc-agents: include must be "agents", "named", "programs" or "all", got ' .. tostring(include), 0)
  end
  local attach = opts.attach or "auto"
  if not ATTACH[attach] then
    error('hc-agents: attach must be "auto", "control" or "watch", got ' .. tostring(attach), 0)
  end
  local machines = opts.machines or "all"
  if not MACHINES[machines] then
    error('hc-agents: machines must be "all" or "local", got ' .. tostring(machines), 0)
  end
  local agents = {}
  for _, name in ipairs(opts.agents or {}) do agents[#agents + 1] = tostring(name) end
  return {
    session = opts.session or "herdr-core",
    include = include,
    attach = attach,
    machines = machines,
    agents = agents,
    interval = tonumber(opts.interval) or 2,
    autostart = opts.autostart ~= false,
    hc = bin("hc", opts.hc),
    rex = bin("rex", opts.rex),
    state_dir = opts.state_dir
      or ((os.getenv("XDG_STATE_HOME") or (home .. "/.local/state")) .. "/rex-hc-agents"),
  }
end

local function contains(list, value)
  for _, v in ipairs(list or {}) do
    if v == value then return true end
  end
  return false
end

-- Whether a terminal from `hc ls --json` gets a tab.
function M.is_agent(t, cfg)
  -- With machines = "local", another machine's terminals are left to the Rex there.
  if cfg.machines == "local" and M.machine(t.address) then return false end
  if cfg.include == "all" then return true end
  if M.is_coding_agent(t, cfg) then return true end
  local named = t.name ~= nil and t.name ~= ""
  if cfg.include == "named" then return named end
  if cfg.include == "programs" then
    -- A Herdr pane's shell has a place (`where`) and no parent. A shell started
    -- with `hc run` has no place, or a parent.
    local pane = t.where ~= nil and t.where ~= "" and (t.parent == nil or t.parent == "")
    return named or not (pane and SHELLS[((t.agent or ""):lower():gsub("%.exe$", ""))])
  end
  return false
end

-- Whether a terminal is a coding agent: it reported a status, or herdr-core
-- knows its program as one.
function M.is_coding_agent(t, cfg)
  if t.status ~= nil and t.status ~= "" then return true end
  return t.agent ~= nil and (M.KNOWN_AGENTS[t.agent] or contains(cfg.agents, t.agent)) or false
end

-- The tab's label in the sidebar: the name the terminal was started with. An
-- unnamed coding agent gets no label, so Rex shows the title the agent sets,
-- such as Claude Code's task summary. Anything else is labeled after its
-- program, since Rex would otherwise name the tab after hc itself.
function M.tab_label(t, cfg)
  if t.name and t.name ~= "" then return t.name end
  if M.is_coding_agent(t, cfg) then return nil end
  return M.title(t)
end

-- "mini/t6" -> "mini"; "t6" (this machine) -> nil.
function M.machine(address)
  return address:match("^(.+)/[^/]+$")
end

-- The title a tab starts with, until its program sets one: what runs, and
-- where when that is another machine. "zsh · mini", "run-watch.sh".
function M.title(t)
  local what = (t.name and t.name ~= "" and t.name) or (t.agent and t.agent ~= "" and t.agent) or t.address
  local machine = M.machine(t.address)
  return machine and (what .. " · " .. machine) or what
end

-- The agent tabs in a session.view result: address -> true.
function M.scan_view(view)
  local tabs = {}
  for _, w in ipairs(view.windows or {}) do
    for _, layer in ipairs(w.layers or {}) do
      for _, b in ipairs(layer.blocks or {}) do
        local label = b.label or ""
        if label:sub(1, #M.TAB_PREFIX) == M.TAB_PREFIX then
          tabs[label:sub(#M.TAB_PREFIX + 1)] = true
        end
      end
    end
  end
  return tabs
end

-- What the manager should do for one `hc ls --json` result.
--
-- tabs:  the agent tabs open now, from scan_view.
-- known: addresses that already got a tab. A known agent without a tab was
--        closed or detached by the user, so it stays closed.
--
-- Returns create (terminals that need a tab) and known (the next known set:
-- an address that left the list is forgotten, so it gets a tab if it returns).
function M.plan(data, tabs, known, cfg)
  local p = { create = {}, known = {} }
  for _, t in ipairs(data.terminals or {}) do
    if t.state == "live" and M.is_agent(t, cfg) then
      if not tabs[t.address] and not known[t.address] then
        p.create[#p.create + 1] = t
      end
      p.known[t.address] = true
    end
  end
  return p
end

-- The tabs the user closed: known agents without a tab. The manager keeps
-- them in a file, so they stay closed when it starts again.
function M.closed(known, tabs)
  local out = {}
  for address in pairs(known) do
    if not tabs[address] then out[#out + 1] = address end
  end
  table.sort(out)
  return out
end

function M.write_file(path, text)
  local f = io.open(path, "w")
  if not f then return false end
  f:write(text)
  f:close()
  return true
end

function M.read_file(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local text = f:read("*a")
  f:close()
  return text
end

return M
