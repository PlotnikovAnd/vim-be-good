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

-- relative: the cursor must never start on the line it has to delete, and the
-- board must fit the window (#138).
do
    local WindowHandler = require("vim-be-good.window")
    local Relative = require("vim-be-good.games.relative")

    local onTarget, overflows, firstOverflow = 0, 0, nil
    local savedLines, savedColumns = vim.o.lines, vim.o.columns
    for _, lines in ipairs({ 12, 14, 20, 24, 30, 50 }) do
        vim.o.lines = lines
        vim.o.columns = 80
        local window = WindowHandler:new()
        local round = Relative:new("easy", window)

        for _ = 1, 500 do
            local board, cursorIdx = round:render()
            local line = board[cursorIdx]
            if not line or line:find("DELETE_ME", 1, true) then
                onTarget = onTarget + 1
            end
            if 1 + #round:getInstructions() + #board > window.config.height then
                overflows = overflows + 1
                firstOverflow = firstOverflow or lines
            end
        end
    end

    check("relative: cursor never on DELETE_ME", onTarget == 0, onTarget .. " of 3000")
    check("relative: board fits the window", overflows == 0,
        overflows .. " renders overflow, first on a " .. tostring(firstOverflow) .. "-line terminal")
    vim.o.lines, vim.o.columns = savedLines, savedColumns
end

-- relative: the target indent follows the difficulty and the two options.
do
    local Relative = require("vim-be-good.games.relative")
    local function indent(difficulty, options)
        vim.g.vim_be_good_delete_me_fixed_offset = nil
        vim.g.vim_be_good_delete_me_random_offset = nil
        for name, value in pairs(options or {}) do
            vim.g[name] = value
        end
        local round = Relative:new(difficulty, { config = { width = 80, height = 30 } })
        for _, line in ipairs(round:render()) do
            local pad = line:match("^( *)DELETE_ME$")
            if pad then
                return #pad
            end
        end
    end

    local noobOk, easyMax = true, 0
    for _ = 1, 200 do
        if indent("noob") ~= 0 then
            noobOk = false
        end
        easyMax = math.max(easyMax, indent("easy"))
    end
    check("relative: noob keeps the target at the start of the line", noobOk)
    check("relative: easy indents up to 10 columns", easyMax <= 10 and easyMax > 3, easyMax .. " columns")

    local fixedOk = true
    for _ = 1, 50 do
        if indent("nightmare", { vim_be_good_delete_me_fixed_offset = 7 }) ~= 7 then
            fixedOk = false
        end
    end
    check("relative: fixed offset is honoured", fixedOk)

    local capped, seen = true, false
    for _ = 1, 200 do
        local offset = indent("tpope", { vim_be_good_delete_me_random_offset = 3 })
        if offset < 0 or offset > 3 then
            capped = false
        end
        seen = seen or offset > 0
    end
    check("relative: random offset caps the difficulty default", capped and seen)

    local noobCapped = true
    for _ = 1, 200 do
        if indent("noob", { vim_be_good_delete_me_random_offset = 5 }) ~= 0 then
            noobCapped = false
        end
    end
    check("relative: random offset keeps noob at the start of the line", noobCapped)

    vim.g.vim_be_good_delete_me_fixed_offset = nil
    vim.g.vim_be_good_delete_me_random_offset = nil

    -- a narrow window must still show the whole target line
    local narrow = Relative:new("tpope", { config = { width = 20, height = 30 } })
    local widest, wraps = 0, false
    for _ = 1, 200 do
        for _, line in ipairs(narrow:render()) do
            widest = math.max(widest, #line)
            if #line > 20 then
                wraps = true
            end
        end
    end
    check("relative: indent fits a 20 column window", not wraps and widest == 19, widest .. " columns")
end

-- relative: a fractional window height must not break the cursor range.
do
    local WindowHandler = require("vim-be-good.window")
    local Relative = require("vim-be-good.games.relative")
    local window = WindowHandler:new(5.5, 6)
    local round = Relative:new("easy", window)

    local bad = 0
    for _ = 1, 500 do
        local board, cursorIdx = round:render()
        if cursorIdx > #board or cursorIdx < 1 then
            bad = bad + 1
        end
    end
    check("relative: fractional window height keeps the cursor in range", bad == 0, bad .. " of 500")
end

-- whackamole: only letters can flip case, so only letters may be the target,
-- and the cursor must not always start at column 1 (#74).
do
    local Whack = require("vim-be-good.games.whackamole")
    local round = Whack:new("easy", { buffer = {} })
    local instant, columns, onTarget, outside = 0, {}, 0, 0
    for _ = 1, 2000 do
        local lines, cursorLine, cursorCol = round:render()
        if lines[1] == round.__winLine then
            instant = instant + 1
        end
        if cursorCol == nil or cursorLine ~= 1 or cursorCol < 0 or cursorCol >= #lines[1] then
            outside = outside + 1
        else
            columns[cursorCol] = true
            if lines[1]:sub(cursorCol + 1, cursorCol + 1) ~= round.__winLine:sub(cursorCol + 1, cursorCol + 1) then
                onTarget = onTarget + 1
            end
        end
    end

    local distinct = 0
    for _ in pairs(columns) do
        distinct = distinct + 1
    end

    check("whackamole: no round wins without a move", instant == 0, instant .. " of 2000")
    check("whackamole: cursor starts at a random column", distinct > 10 and outside == 0,
        distinct .. " columns, " .. outside .. " outside the line")
    check("whackamole: cursor never on the target character", onTarget == 0, onTarget .. " of 2000")
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

-- round count: option names and the endless noob mode.
do
    local GameUtils = require("vim-be-good.game-utils")

    vim.g.vim_be_good_round_count = nil
    vim.g["vim-be-good-round-count"] = nil
    check("rounds: 10 by default", GameUtils.getRoundCount("easy") == 10, GameUtils.getRoundCount("easy"))

    vim.g.vim_be_good_round_count = 3
    check("rounds: underscore option is read", GameUtils.getRoundCount("easy") == 3, GameUtils.getRoundCount("easy"))

    vim.g.vim_be_good_round_count = "7"
    check("rounds: a string value is converted", GameUtils.getRoundCount("easy") == 7, GameUtils.getRoundCount("easy"))

    vim.g.vim_be_good_round_count = 0
    check("rounds: a value below 1 counts as 1", GameUtils.getRoundCount("easy") == 1, GameUtils.getRoundCount("easy"))

    vim.g.vim_be_good_round_count = nil
    vim.g["vim-be-good-round-count"] = 4
    check("rounds: dashed option still works", GameUtils.getRoundCount("easy") == 4, GameUtils.getRoundCount("easy"))

    vim.g.vim_be_good_round_count = 3
    check("rounds: noob stays endless", GameUtils.getRoundCount("noob") == 100000, GameUtils.getRoundCount("noob"))

    vim.g.vim_be_good_round_count = nil
    vim.g["vim-be-good-round-count"] = nil
end

-- hints: every game states the goal and the keys, taken from the loaded config.
do
    vim.keymap.set("i", "jj", "<Esc>", { desc = "Exit insert mode" })

    local games = {
        ["ci{"] = "vim-be-good.games.ci",
        relative = "vim-be-good.games.relative",
        whackamole = "vim-be-good.games.whackamole",
        hjkl = "vim-be-good.games.hjkl",
        words = "vim-be-good.games.words",
    }

    local short, missing = {}, {}
    for name, module in pairs(games) do
        local round = require(module):new("easy", { config = { width = 80, height = 34 } })
        if round.getConfig then
            pcall(round.getConfig, round)
        end

        local hint = round:getInstructions()
        local joined = table.concat(hint, " | ")
        if #hint > 4 then
            short[#short + 1] = name .. ":" .. #hint
        end
        if not joined:find("Goal:", 1, true) or not joined:find("Keys:", 1, true) then
            missing[#missing + 1] = name
        end
    end

    check("hints: every game keeps the hint to 4 lines", #short == 0, table.concat(short, " "))
    check("hints: every game names a goal and keys", #missing == 0, table.concat(missing, " "))

    local ci = require("vim-be-good.games.ci"):new("easy", { config = { width = 80, height = 34 } })
    ci:getConfig()
    local ciHint = table.concat(ci:getInstructions(), " | ")
    check("hints: ci{ names ci{ and ci[", ciHint:find("ci{", 1, true) and ciHint:find("ci[", 1, true) ~= nil)
    check("hints: ci{ uses the configured escape key", ciHint:find("jj", 1, true) ~= nil, ciHint)
end

-- hints: the lookup must report only keys that really leave insert mode.
do
    local Hints = require("vim-be-good.hints")

    vim.keymap.del("i", "jj")
    check("hints: no mapping falls back to Esc", Hints.escape() == "Esc", Hints.escape())

    vim.keymap.set("i", "jk", "<Esc>a")
    check("hints: a mapping that re-enters insert mode is refused", Hints.escape() == "Esc", Hints.escape())

    vim.keymap.del("i", "jk")
    vim.keymap.set("i", "kj", "<Esc>")
    check("hints: a plain Esc mapping is used", Hints.escape() == "kj", Hints.escape())
    vim.keymap.del("i", "kj")
end

-- ci{: the keys named in the hint must actually win the round.
do
    local Ci = require("vim-be-good.games.ci")
    local escape = vim.api.nvim_replace_termcodes("<Esc>", true, false, true)
    local wins = 0

    for variant = 1, 2 do
        local bufnr, window, buffer = newBuffer()
        vim.api.nvim_win_set_buf(0, bufnr)

        local round = Ci:new("easy", window)
        round:getConfig()
        round.config.ifStatement = variant == 1

        local board = round:render()
        buffer:setInstructions(round:getInstructions())
        buffer:render(board)

        local firstLine
        for idx, text in ipairs(board) do
            if text == "[" or text:match("^if %(.*%) {$") then
                firstLine = idx
                break
            end
        end

        local row = #round:getInstructions() + firstLine + 2
        vim.api.nvim_win_set_cursor(0, { row, 0 })
        vim.cmd("stopinsert")
        vim.cmd("silent! normal! " .. (variant == 1 and "ci{bar" or "ci[bar") .. escape)

        if round:checkForWin() then
            wins = wins + 1
        end
    end

    check("hints: ci{ wins with the hinted keys in both variants", wins == 2, wins .. " of 2")
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
