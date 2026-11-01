local log = require("vim-be-good.log")
local default_config =  {
    plugin = 'VimBeGoodStats',

    save_statistics = vim.g["vim_be_good_save_statistics"] or false,

}

local statistics = {}

function statistics:new(config)
    config = config or {}
    config = vim.tbl_deep_extend("force", default_config, config)

    local stats = {
        file = string.format('%s/%s.log', vim.api.nvim_call_function('stdpath', {'data'}), config.plugin),
        saveStats = config.save_statistics
    }
    self.__index = self
    return setmetatable(stats, self)
end

function statistics:logResult(result)
    if self.saveStats then
        local fp = io.open(self.file, "a")
        if not fp then
            log.warn("Statistics: cannot open", self.file)
            return
        end

        local str = string.format("%s,%s,%s,%s,%s,%f\n",
        result.timestamp, result.roundNum, result.difficulty, result.roundName, result.success, result.time)
        fp:write(str)
        fp:close()
    end
end

return statistics
