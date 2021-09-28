local bit = require 'bit'
local function int24to8x8x8(i)
	return bit.band(0xff, i),
		bit.band(0xff, bit.rshift(i, 8)),
		bit.band(0xff, bit.rshift(i, 16))
end
return int24to8x8x8
