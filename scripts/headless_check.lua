-- Headless checks for the fixes this fork carries on top of upstream.
--
-- Run from the repository root:
--   nvim --headless -u NONE --cmd 'set rtp+=.' \
--     -c 'luafile scripts/headless_check.lua' -c 'qa!'
--
-- No dependencies: only the plugin modules and the Neovim API.

local failures = 0

local function check(name, condition, detail)
    if condition then
        io.write("ok   " .. name .. "\n")
    else
        failures = failures + 1
        io.write("FAIL " .. name .. (detail and ("  -- " .. tostring(detail)) or "") .. "\n")
    end
end

local function newBuffer()
    local Buffer = require("vim-be-good.buffer")
    local bufnr = vim.api.nvim_create_buf(false, true)
    local window = { buffer = nil }
    local buffer = Buffer:new(bufnr, window)
    window.buffer = buffer
    return bufnr, window, buffer
end

-- relative: the cursor must never start on the line it has to delete.
do
    local Relative = require("vim-be-good.games.relative")
    local round = Relative:new("easy", {})
    local onTarget = 0
    for _ = 1, 2000 do
        local lines, cursorIdx = round:render()
        local line = lines[cursorIdx]
        if not line or line:find("DELETE_ME", 1, true) then
            onTarget = onTarget + 1
        end
    end
    check("relative: cursor never on DELETE_ME", onTarget == 0, onTarget .. " of 2000")
end

-- whackamole: only letters can flip case, so only letters may be the target.
do
    local Whack = require("vim-be-good.games.whackamole")
    local round = Whack:new("easy", { buffer = {} })
    local instant = 0
    for _ = 1, 2000 do
        local lines = round:render()
        if lines[1] == round.__winLine then
            instant = instant + 1
        end
    end
    check("whackamole: no round wins without a move", instant == 0, instant .. " of 2000")
end

-- ci{: the lines table is 1-based, and the round stays winnable.
do
    local Ci = require("vim-be-good.games.ci")
    local bufnr, window = newBuffer()
    local round = Ci:new("easy", window)
    local broken, minIdx, maxIdx = 0, math.huge, -math.huge
    local wins = 0
    for _ = 1, 2000 do
        round:getConfig()
        local lines = round:render()
        for idx in pairs(lines) do
            minIdx = math.min(minIdx, idx)
            maxIdx = math.max(maxIdx, idx)
        end
        if not pcall(vim.api.nvim_buf_set_lines, bufnr, 0, -1, false, lines) then
            broken = broken + 1
        end

        -- The user's ci{ leaves only the rewritten line behind.
        local solved = round.config.ifStatement
            and string.format("if (%s) {bar}", round.config.randomWord)
            or "[bar]"
        window.buffer.getGameLines = function() return { solved } end
        if round:checkForWin() then
            wins = wins + 1
        end
    end
    check("ci{: every render is accepted by nvim_buf_set_lines", broken == 0, broken .. " of 2000")
    check("ci{: lines stay inside 1..20", minIdx >= 1 and maxIdx <= 20,
        string.format("indexes %s..%s", minIdx, maxIdx))
    check("ci{: every round can be won", wins == 2000, wins .. " of 2000")
end

-- buffer: a shorter render must not leave lines behind, or the menu ignores picks.
do
    local bufnr, _, buffer = newBuffer()
    buffer:setInstructions({})
    local long = {}
    for idx = 1, 36 do long[idx] = "line " .. idx end
    buffer:render(long)
    local menu = {}
    for idx = 1, 34 do menu[idx] = "menu " .. idx end
    buffer:render(menu)

    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    check("buffer: shorter render ends with the new last line", lines[#lines] == "menu 34", lines[#lines])

    local before = #buffer:getGameLines()
    vim.api.nvim_buf_set_lines(bufnr, #buffer.instructions + 1, #buffer.instructions + 2, false, {})
    check("buffer: game lines shrink after a deletion", #buffer:getGameLines() == before - 1,
        string.format("%d -> %d", before, #buffer:getGameLines()))
end

-- end screen: deleting the last line has to be detected.
do
    local GameRunner = require("vim-be-good.game-runner")
    local function fakeRunner(userLines, onFinished)
        return setmetatable({
            currentRound = 10,
            config = { roundCount = 10 },
            results = { timings = { 1.5 }, successes = 1, games = { "words", "relative" } },
            window = {
                buffer = {
                    getGameLines = function() return userLines end,
                    debugLine = function() end,
                    render = function() end,
                },
            },
            onFinished = onFinished or function() end,
        }, { __index = GameRunner })
    end

    local expected = fakeRunner({}):renderEndGame()
    local deletedLast = {}
    for idx = 1, #expected - 1 do deletedLast[idx] = expected[idx] end

    local state
    fakeRunner(deletedLast, function(_, nextState) state = nextState end):checkForNext()
    check("end screen: deleting the last line quits", state == "quit", state)

    local summary = fakeRunner({})
    summary.results.games = { "words", "relative", "words" }
    check("end screen: summary names every game",
        table.concat(summary:renderEndGame(), "\n"):find("words, relative", 1, true) ~= nil)
end

-- on_lines: listeners receive the event arguments unchanged.
do
    local bufnr, _, buffer = newBuffer()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "one" })
    local got
    buffer:onChange(function(...) got = { n = select("#", ...), ... } end)
    vim.api.nvim_buf_set_lines(bufnr, 0, 1, false, { "changed" })
    vim.wait(500, function() return got ~= nil end)
    check("buffer: on_lines arguments forwarded",
        got ~= nil and got[1] == "lines" and got[2] == bufnr, got and got[1])
end

-- window: a headless run has no UI, so the size must come from vim.o.
do
    local WindowHandler = require("vim-be-good.window")
    local ok, window = pcall(WindowHandler.new, WindowHandler)
    check("window: size available without a UI", ok and window.config.width > 0)
end

io.write(failures == 0 and "ALL PASS\n" or ("FAILURES: " .. failures .. "\n"))
if failures > 0 then
    vim.cmd("cq")
end
