local GameUtils = require("vim-be-good.game-utils")
local log = require("vim-be-good.log")

local instructions = {
    "Test your ability to hop by relative line numbers",
    "To win the game, delete the line that says \"DELETE_ME\"",
}

local maxBoardRows = 20
local minBoardRows = 3

-- The window also shows the debug line and the instructions above the board,
-- so a small terminal gets a shorter board instead of an unreachable target.
-- shortcut: below a 12-line terminal the header alone does not fit, upgrade to
-- hiding the instructions when the window is that small.
local function boardRows(window)
    local height = window and window.config and window.config.height
    if not height then
        return maxBoardRows
    end

    local rows = math.floor(height) - 1 - #instructions
    return math.max(minBoardRows, math.min(maxBoardRows, rows))
end

local RelativeRound = {}
function RelativeRound:new(difficulty, window)
    log.info("New", difficulty, window)
    local round = {
        window = window,
        difficulty = difficulty,
    }

    self.__index = self
    return setmetatable(round, self)
end

function RelativeRound:getInstructions()
    return instructions
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

    lines[deleteMeIdx] = " DELETE_ME"

    return lines, cursorIdx
end

function RelativeRound:name()
    return "relative"
end

return RelativeRound


