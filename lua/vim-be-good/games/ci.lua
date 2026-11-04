local GameUtils = require("vim-be-good.game-utils")
local log = require("vim-be-good.log")
local gameLineCount = 20

-- Keys come from the loaded config, so the escape hint matches the player setup.
local function hints()
    local Hints = require("vim-be-good.hints")

    return {
        "Goal: replace what is inside the first { } or [ ] with bar",
        string.format("Keys: cursor inside the brackets -> %s or %s -> bar -> %s",
            Hints.key("ci{"), Hints.key("ci["), Hints.escape()),
        "An if statement keeps its condition: if (x) { bar }",
        "",
    }
end

local CiRound = {}
function CiRound:new(difficulty, window)
   log.info("New", difficulty, window)
    local round = {
        window = window,
        difficulty = difficulty,
    }

    self.__index = self
    return setmetatable(round, self)
end

function CiRound:getInstructions()
    return hints()
end

function CiRound:getConfig()
    log.info("getConfig", self.difficulty, GameUtils.difficultyToTime[self.difficulty])
    self.config = {
        roundTime = GameUtils.difficultyToTime[self.difficulty],
        ifStatement = math.random() > 0.5,
        randomWord = GameUtils.getRandomWord(),
    }

    return self.config
end

function CiRound:checkForWin()
    local lines = self.window.buffer:getGameLines()
    local trimmed = GameUtils.trimLines(lines)
    local concatenated = table.concat(trimmed)
    local lowercased = concatenated:lower()

    log.info("CiRound:checkForWin", lowercased)

    local winner = false
    if self.config.ifStatement then
        winner = lowercased == "if (" .. self.config.randomWord .. ") {bar}"
    else
        winner = lowercased == "[bar]"
    end

    if winner then
        vim.cmd("stopinsert")
    end

    return winner
end

function CiRound:render()
    -- The block takes six rows, so the board always has room for it.
    local rows = GameUtils.boardRows(self.window, #hints(), gameLineCount, 7)
    local lines = GameUtils.createEmpty(rows)
    local linesAfterInstructions = rows - #hints()
    local insertionIndex = GameUtils.getRandomInsertionLocation(rows, 6)
    local goHigh = insertionIndex < rows / 2 and math.random() > 0.5

    local cursorIdx
    if goHigh then
        cursorIdx = math.random(math.floor(linesAfterInstructions / 2))
    else
        cursorIdx = math.random(math.floor(linesAfterInstructions / 2), linesAfterInstructions)
    end

    if self.config.ifStatement then
        lines[insertionIndex] = "if (" .. self.config.randomWord .. ") {"
        lines[insertionIndex + 2] = "    if (" .. GameUtils.getRandomWord() .. ") { "
        lines[insertionIndex + 3] = "        " .. GameUtils.getRandomWord()
        lines[insertionIndex + 4] = "    }";
        lines[insertionIndex + 5] = "}";
    else
        lines[insertionIndex] = "[";
        lines[insertionIndex + 1] = "    " .. GameUtils.getRandomWord() .. ","
        lines[insertionIndex + 2] = "    " .. GameUtils.getRandomWord() .. ","
        lines[insertionIndex + 3] = "    " .. GameUtils.getRandomWord() .. ","
        lines[insertionIndex + 4] = "    " .. GameUtils.getRandomWord() .. ","
        lines[insertionIndex + 5] = "]";
    end

    return lines, cursorIdx
end

function CiRound:name()
    return "ci{"
end

return CiRound
