-- Hints are built from the configuration that is loaded right now, so a player
-- who remapped a key sees the key that actually works for them.

local Hints = {}

local function mapping(lhs, mode)
    local found = vim.fn.maparg(lhs, mode, false, true)
    if not found or vim.tbl_isempty(found) or not found.rhs or found.rhs == "" then
        return nil
    end

    return found.rhs
end

-- A normal-mode key as the player has it: "j", or "j (-> gj)" when remapped.
function Hints.key(lhs, mode)
    local target = mapping(lhs, mode or "n")
    if not target then
        return lhs
    end

    return string.format("%s (-> %s)", lhs, target)
end

-- The key that leaves insert mode: Esc, or the mapping that points at it.
function Hints.escape()
    for _, lhs in ipairs({ "jj", "jk", "kj" }) do
        local target = mapping(lhs, "i")
        if target and target:lower():find("<esc>", 1, true) then
            return lhs
        end
    end

    for _, keymap in ipairs(vim.api.nvim_get_keymap("i")) do
        if keymap.rhs and keymap.rhs:lower():find("<esc>", 1, true) then
            return vim.fn.keytrans(keymap.lhs)
        end
    end

    return "Esc"
end

return Hints
