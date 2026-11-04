-- Hints are built from the configuration that is loaded right now, so a player
-- who remapped a key sees the key that actually works for them.

local Hints = {}

local function leaves_insert(rhs)
    if not rhs then
        return false
    end

    -- Only a plain <Esc> leaves insert mode; "<Esc>a" would re-enter it.
    return rhs:lower():gsub("%s", "") == "<esc>"
end

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
        if leaves_insert(mapping(lhs, "i")) then
            return lhs
        end
    end

    for _, keymap in ipairs(vim.api.nvim_get_keymap("i")) do
        if leaves_insert(keymap.rhs) then
            return vim.fn.keytrans(keymap.lhs)
        end
    end

    return "Esc"
end

return Hints
