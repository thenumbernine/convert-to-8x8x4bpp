local table = require 'ext.table'
local inttobin = require 'inttobin'

-- size = how many bytes to use
local function replaceIntKeysWithStrs(t, size)
	return table.map(t, function(v,k)
		if type(k) == 'number' then k = inttobin(k, size) end
		return v,k
	end):setmetatable(nil)
end

return replaceIntKeysWithStrs
