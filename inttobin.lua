local bit = require 'bit'

-- size = how many bytes to use
local function inttobin(i, size)
	local s = ''
	for j=1,size do
		s = s .. string.char(bit.band(0xff, i))
		i = bit.rshift(i, 8)
	end
	return s
end

return inttobin
