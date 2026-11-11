-- rex do tests/common_test.lua
--
-- Checks the pure parts of hc-agents/common.lua. Rex runs Lua 5.1, so the
-- tests run under `rex do` rather than a separate Lua install.

local here = (debug.getinfo(1, "S").source:gsub("^@", "")):match("^(.*/)") or "./"
local common = dofile(here .. "../hc-agents/common.lua")

-- Counters live in a table: Rex's Lua stops sharing a plain local with
-- closures after pcall catches an error, and one check below does that.
local run = { failures = {}, count = 0 }

local function eq(a, b) return rex.json.encode(a) == rex.json.encode(b) end

local function check(name, got, want)
  run.count = run.count + 1
  if not eq(got, want) then
    run.failures[#run.failures + 1] = name .. "\n    got:  " .. rex.json.encode(got)
      .. "\n    want: " .. rex.json.encode(want)
  end
end

local cfg = common.config({ hc = "/bin/hc", rex = "/bin/rex", state_dir = "/tmp/x" })

-- config
check("config defaults", { cfg.session, cfg.include, cfg.interval, cfg.autostart },
  { "herdr-core", "agents", 2, true })
check("config keeps given binaries", { cfg.hc, cfg.rex }, { "/bin/hc", "/bin/rex" })
check("config survives json", common.config(rex.json.decode(rex.json.encode(cfg))).session, "herdr-core")
check("config rejects a bad include", (pcall(common.config, { include = "some" })), false)
check("config attach defaults to auto", cfg.attach, "auto")
check("config keeps a given attach", common.config({ attach = "watch" }).attach, "watch")
check("config rejects a bad attach", (pcall(common.config, { attach = "peek" })), false)
check("config autostart can be turned off", common.config({ autostart = false }).autostart, false)

-- is_agent
check("known agent", common.is_agent({ agent = "claude-code" }, cfg), true)
check("plain shell", common.is_agent({ agent = "zsh" }, cfg), false)
check("reported a status", common.is_agent({ agent = "env", status = "working" }, cfg), true)
check("named script stays out by default", common.is_agent({ agent = "env", name = "watchdog" }, cfg), false)
check("named script with include=named",
  common.is_agent({ agent = "env", name = "watchdog" }, common.config({ include = "named" })), true)
check("extra agent names", common.is_agent({ agent = "mybot" }, common.config({ agents = { "mybot" } })), true)
check("script with include=programs",
  common.is_agent({ agent = "run-watch.sh" }, common.config({ include = "programs" })), true)
check("a shell started with hc run shows with include=programs",
  common.is_agent({ agent = "zsh" }, common.config({ include = "programs" })), true)
check("a Herdr pane's shell stays out with include=programs",
  common.is_agent({ agent = "zsh", where = "~ / 1" }, common.config({ include = "programs" })), false)
check("a shell started from a Herdr pane shows with include=programs",
  common.is_agent({ agent = "zsh", where = "~ / 1", parent = "t1" }, common.config({ include = "programs" })), true)
check("named shell with include=programs",
  common.is_agent({ agent = "zsh", name = "build" }, common.config({ include = "programs" })), true)
check("script stays out by default",
  common.is_agent({ agent = "run-watch.sh" }, common.config({})), false)
check("include=all", common.is_agent({ agent = "zsh" }, common.config({ include = "all" })), true)

-- labels
check("label is the name", common.tab_label({ address = "t1", name = "r9-feel" }, cfg), "r9-feel")
check("unnamed agents keep Rex's title", common.tab_label({ address = "t1", agent = "claude" }, cfg), nil)
check("a status makes an agent", common.tab_label({ address = "t1", agent = "mybot", status = "idle" }, cfg), nil)
check("a shell is labeled after its program", common.tab_label({ address = "t1", agent = "zsh" }, cfg), "zsh")
check("and its machine", common.tab_label({ address = "mini/t6", agent = "zsh" }, cfg), "zsh · mini")

check("title is the program", common.title({ address = "t3", agent = "zsh" }), "zsh")
check("title names another machine", common.title({ address = "mini/t6", agent = "zsh" }), "zsh · mini")
check("title prefers the name", common.title({ address = "mini/t6", agent = "zsh", name = "build" }), "build · mini")
check("title falls back to the address", common.title({ address = "t3" }), "t3")

-- scan_view
local view = {
  windows = {
    { window_id = "w1", layers = { { blocks = { { block_id = "b1", label = "shell" } } } } },
    { window_id = "w2", label = "r9-feel", layers = { { blocks = { { block_id = "b2", label = "hc:mini/t6" } } } } },
  },
}
check("scan finds agent tabs only", common.scan_view(view), { ["mini/t6"] = true })

-- plan
local function addresses(list)
  local out = {}
  for _, t in ipairs(list) do out[#out + 1] = t.address end
  return out
end

local data = {
  terminals = {
    { address = "t1", agent = "zsh", state = "live" },
    { address = "t2", agent = "claude", state = "live" },
    { address = "t3", agent = "codex", state = "live", status = "working" },
    { address = "mini/t6", agent = "claude", state = "live", name = "r9-feel" },
    { address = "t8", agent = "claude", state = "finished", exit_code = 0 },
  },
}
local p = common.plan(data, { ["mini/t6"] = true }, { t3 = true, t9 = true }, cfg)
check("plan opens tabs for new live agents only", addresses(p.create), { "t2" })
check("plan leaves a closed tab closed", p.known.t3, true)
check("plan knows every live agent", p.known, { t2 = true, t3 = true, ["mini/t6"] = true })
check("plan forgets an agent that left the list", p.known.t9, nil)
check("closed tabs are the known agents without a tab",
  common.closed(p.known, { ["mini/t6"] = true, t2 = true }), { "t3" })
check("emptying known reopens closed tabs",
  addresses(common.plan(data, { ["mini/t6"] = true }, {}, cfg).create), { "t2", "t3" })

-- machines
local here_only = common.config({ machines = "local", include = "all" })
check("machines defaults to all", cfg.machines, "all")
check("config rejects a bad machines", (pcall(common.config, { machines = "mine" })), false)
check('machines = "local" leaves another machine\'s terminals out',
  { common.is_agent({ address = "mini/t6", agent = "claude" }, here_only), common.is_agent({ address = "t6", agent = "claude" }, here_only) },
  { false, true })
check('machines = "local" plans no tab for another machine',
  addresses(common.plan(data, {}, {}, common.config({ machines = "local" })).create), { "t2", "t3" })

if #run.failures > 0 then
  print(#run.failures .. " of " .. run.count .. " checks failed:\n  " .. table.concat(run.failures, "\n  "))
  rex.stop(1)
end
print("all " .. run.count .. " checks passed")
