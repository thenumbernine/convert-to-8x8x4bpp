local ffi = require 'ffi'
local int8x8x8to24 = require 'int8x8x8to24'

local function buildHistogram(img)
	assert(img.channels == 3)
	assert(ffi.sizeof(img.format) == 1)
	local hist = {}
	for i=0,img.height*img.width-1 do
		local p = ffi.cast('uint8_t*', img.buffer) + 3 * i
		local key = int8x8x8to24(p[0], p[1], p[2])
		hist[key] = (hist[key] or 0) + 1
	end
	return hist
end

return buildHistogram
