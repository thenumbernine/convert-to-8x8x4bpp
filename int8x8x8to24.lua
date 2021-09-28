local bit = require 'bit'
local function int8x8x8to24(r,g,b)
	return bit.bor(
		r,
		bit.lshift(g, 8),
		bit.lshift(b, 16))
end
return int8x8x8to24
