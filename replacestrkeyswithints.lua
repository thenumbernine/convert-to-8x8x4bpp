local table = require 'ext.table'
local bintoint = require 'bintoint'

local function replaceStrKeysWithInts(t)
	return table.map(t, function(v,k)
		if type(k) == 'string' then k = bintoint(k) end
		return v,k
	end):setmetatable(nil)
end

return replaceStrKeysWithInts
