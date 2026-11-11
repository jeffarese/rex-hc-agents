-- rex do manager.lua --args '<config json>'
--
-- Runs in the background, without a tab of its own. Every few seconds it asks
-- herdr-core for its live terminals and opens a tab in the agents session for
-- each new agent. A tab runs agent-tab.sh, which attaches to the agent with
-- `hc attach`; that passes the agent's status on to Rex, so the sidebar shows
-- it. The tab closes when the agent ends or you detach (ctrl+\), and a tab
-- you closed stays closed.

local dir = (debug.getinfo(1, "S").source:gsub("^@", "")):match("^(.*/)") or "./"
local common = dofile(dir .. "common.lua")
local cfg = common.config(rex.args)

local HEARTBEAT = cfg.state_dir .. "/manager.heartbeat"
local REOPEN = cfg.state_dir .. "/reopen"
local CLOSED = cfg.state_dir .. "/closed"
local TAB_SCRIPT = dir .. "agent-tab.sh"
-- This run's mark in the heartbeat: its settings and a token of its own.
local SETTINGS = rex.json.encode(cfg)
-- The token must differ between two managers that start in the same second, so
-- it comes from the system, not from Lua's unseeded math.random.
local function token()
  local f = io.open("/dev/urandom", "rb")
  local bytes = f and f:read(8)
  if f then f:close() end
  if not bytes or #bytes < 8 then return tostring(os.time()) .. "-" .. tostring(os.clock()) end
  return (bytes:gsub(".", function(c) return string.format("%02x", c:byte()) end))
end
local ME = SETTINGS .. "\n" .. token()

rex.exec({ "mkdir", "-p", cfg.state_dir })

-- The heartbeat holds "<beat>\n<settings>\n<token>", rewritten on every
-- check. One manager runs at a time: a start that sees another manager with
-- its own settings still beating leaves, and a running manager leaves when
-- another one took the heartbeat over (a config reload with new settings).
local function heartbeat()
  local text = common.read_file(HEARTBEAT) or ""
  local beat, owner = text:match("^(%d+)\n(.*)$")
  return beat, owner
end

local function beat(n)
  common.write_file(HEARTBEAT, n .. "\n" .. ME)
end

-- A manager that was killed leaves a heartbeat that looks recent, so watch
-- whether it moves instead of how old it is.
local seen, owner = heartbeat()
if seen and owner and owner:sub(1, #SETTINGS + 1) == SETTINGS .. "\n" then
  rex.sleep(cfg.interval + 1.5)
  if heartbeat() ~= seen then return "already running" end
end

-- State lives in a table: Rex's Lua stops sharing a plain local with the
-- closures that use it once a protected call, such as the one around each
-- timer tick, catches an error. A table's fields stay shared.
local state = {
  known = {},      -- addresses that already got a tab
  closed = "",     -- the closed tabs as last written to the file
  beats = 0,       -- checks so far; the heartbeat's first line
  attached = nil,  -- the session id this script is attached to
  hc_failed = false, -- the last `hc ls` failed, and that was logged
}

local function log(message)
  rex.log("error", "hc-agents: " .. tostring(message))
end

local function tab(t)
  return {
    window_label = common.tab_label(t, cfg),
    layout = {
      block = {
        flavor = common.SHELL_FLAVOR,
        label = common.TAB_PREFIX .. t.address,
        options = {
          command = {
            "/usr/bin/env", "HC_BIN=" .. cfg.hc, "HC_ATTACH=" .. cfg.attach,
            "/bin/sh", TAB_SCRIPT, t.address, common.title(t),
          },
        },
      },
    },
  }
end

-- The agents session's id, or nil when it doesn't exist (yet, or any more).
local function find_session()
  local list, err = rex.call("session.list")
  if not list then return nil, err end
  for _, s in ipairs(list.sessions or {}) do
    if s.label == cfg.session then return s.session_id end
  end
  return nil
end

local function tick()
  local _, holder = heartbeat()
  if holder and holder ~= ME then os.exit(0) end
  state.beats = state.beats + 1
  beat(state.beats)

  if common.read_file(REOPEN) then
    os.remove(REOPEN)
    state.known = {}
  end
  local tabs, opened = {}, {}

  local res, err = rex.exec({ cfg.hc, "ls", "--json" }, { timeout = 10 })
  if not res or not res.ok then
    -- herdr-core isn't running, or isn't installed. Say so once, not every check.
    if not state.hc_failed then log("can't list herdr-core's terminals with " .. cfg.hc .. ": " .. tostring(err or (res and res.stderr) or "")) end
    state.hc_failed = true
    return
  end
  state.hc_failed = false
  local data = rex.json.decode(res.stdout)
  if type(data) ~= "table" then return end

  local sid, list_err = find_session()
  if list_err then return log(list_err) end
  local view
  if sid then
    -- A script reads a session's view only once it is attached to it.
    if state.attached ~= sid then
      local attached, attach_err = rex.call("session.attach", { session_id = sid })
      if not attached then return log(attach_err) end
      state.attached = sid
      view = attached.view
    end
    view = view or rex.call("session.view", { session_id = sid })
    if not view then
      state.attached = nil
      return
    end
    tabs = common.scan_view(view)
  end

  local p = common.plan(data, tabs, state.known, cfg)

  -- When its last agent ends, the session is left without a tab, and an app that is attached
  -- keeps it in the sidebar. Nothing is in it, so it goes; the next agent makes it again.
  if sid and #p.create == 0 and #(view.windows or {}) == 0 then
    local _, destroy_err = rex.call("session.destroy", { session_id = sid })
    if destroy_err then log("can't remove the empty session: " .. tostring(destroy_err)) end
    state.attached = nil
    sid = nil
  end

  for _, t in ipairs(p.create) do
    local spec = tab(t)
    local ok, new_err
    if sid then
      spec.session_id = sid
      spec.focus = false
      ok, new_err = rex.call("session.new_window", spec)
    else
      ok, new_err = rex.call("session.create", { label = cfg.session, initial_windows = { spec } })
      sid = ok and ok.session_id
      -- The next tab of this check, and giving the tabs up, need the session attached.
      if sid and rex.call("session.attach", { session_id = sid }) then state.attached = sid end
    end
    if ok then
      opened[t.address] = true
    else
      log("can't open a tab for " .. t.address .. ": " .. tostring(new_err))
      p.known[t.address] = nil -- try again on the next check
    end
  end
  state.known = p.known

  -- Whoever opens a tab owns its terminal's size, and an app that shows the tab later only
  -- offers to take it over ("Sized by another client"). The manager shows nothing, so it
  -- gives its tabs up: the first app to show one sizes it.
  if sid and next(opened) then
    local _, disown_err = rex.call("session.disown_block", { session_id = sid })
    if disown_err then log("can't give up the new tabs: " .. tostring(disown_err)) end
  end

  -- Remember the tabs the user closed, so they stay closed after a restart.
  for address in pairs(opened) do tabs[address] = true end
  local closed = table.concat(common.closed(p.known, tabs), "\n")
  if closed ~= state.closed then
    common.write_file(CLOSED, closed)
    state.closed = closed
  end
end

-- The file as it is, so an entry that no longer applies is written out of it.
state.closed = common.read_file(CLOSED) or ""
for address in state.closed:gmatch("[^\n]+") do
  state.known[address] = true
end

-- Two managers that start together both get here. The one that wrote last
-- keeps the heartbeat; the other sees that and leaves before it opens a tab.
beat(0)
rex.sleep(0.5)
tick()
rex.every(cfg.interval, tick)
