local GameUtils = require("vim-be-good.game-utils")
local log = require("vim-be-good.log")

local maxBoardRows = 20
local minBoardRows = 3

-- Keys come from the loaded config, so a remapped motion shows up as mapped.
local function hints()
    local Hints = require("vim-be-good.hints")

    return {
        "Goal: delete the line that says DELETE_ME",
        string.format("Keys: count + %s / %s to hop (12j), then %s on that line",
            Hints.key("j"), Hints.key("k"), Hints.key("dd")),
    }
end

-- The window also shows the debug line and the instructions above the board,
-- so a small terminal gets a shorter board instead of an unreachable target.
-- shortcut: below a 12-line terminal the header alone does not fit, upgrade to
-- hiding the instructions when the window is that small.
local function boardRows(window)
    return GameUtils.boardRows(window, #hints(), maxBoardRows, minBoardRows)
end

-- Right-hand indent for the target, so a harder round needs a longer look at the
-- line number before jumping (upstream #67, #72).
local defaultMaxOffset = {
    noob = 0,
    easy = 10,
    medium = 16,
    hard = 24,
    nightmare = 32,
    tpope = 40,
}

local function readOffset(name)
    local value = tonumber(vim.g[name])
    if not value then
        return nil
    end

    return math.max(0, math.floor(value))
end

local function columnOffset(round)
    local width = (round.window and round.window.config and round.window.config.width) or 80
    -- 9 columns of DELETE_ME plus one spare, so the target line never wraps.
    local limit = math.max(0, math.floor(width) - 10)

    local offset
    if round.fixedOffset then
        offset = round.fixedOffset
    else
        local max = defaultMaxOffset[round.difficulty] or 0
        -- noob always starts at the beginning of the line; the option applies to
        -- the other difficulties, where it replaces their default.
        if round.randomOffset and round.difficulty ~= "noob" then
            max = round.randomOffset
        end
        offset = math.random(0, max)
    end

    return math.min(offset, limit)
end

local RelativeRound = {}
function RelativeRound:new(difficulty, window)
    log.info("New", difficulty, window)
    local round = {
        window = window,
        difficulty = difficulty,
        fixedOffset = readOffset("vim_be_good_delete_me_fixed_offset"),
        randomOffset = readOffset("vim_be_good_delete_me_random_offset"),
    }

    self.__index = self
    return setmetatable(round, self)
end

function RelativeRound:getInstructions()
    return hints()
end

function RelativeRound:getConfig()
    log.info("getConfig", self.difficulty, GameUtils.difficultyToTime[self.difficulty])
    return {
        roundTime = GameUtils.difficultyToTime[self.difficulty]
    }
end

function RelativeRound:checkForWin()
    local lines = self.window.buffer:getGameLines()
    local found = false
    local idx = 1

    while idx <= #lines and not found do
        local line = lines[idx]
        found = string.match(line, "DELETE_ME")

        idx = idx + 1
    end
    log.info("RelativeRound:checkForWin(", idx, "): ", found)

    return not found
end

function RelativeRound:render()
    local rows = boardRows(self.window)
    local lines = GameUtils.createEmpty(rows)
    local deleteMeIdx = math.random(1, rows)
    local goHigh = deleteMeIdx < rows - 3 and math.random() > 0.5

    local cursorIdx
    if goHigh then
        cursorIdx = math.random(deleteMeIdx + 1, rows)
    elseif deleteMeIdx > 1 then
        cursorIdx = math.random(1, deleteMeIdx - 1)
    else
        -- "DELETE_ME" is on line 1, so the cursor has to start below it.
        cursorIdx = 2
    end

    lines[deleteMeIdx] = string.rep(" ", columnOffset(self)) .. "DELETE_ME"

    return lines, cursorIdx
end

function RelativeRound:name()
    return "relative"
end

return RelativeRound


