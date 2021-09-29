local ffi = require 'ffi'

local function buildHistogram(img)
	local dim = img.channels * ffi.sizeof(img.format)
	local hist = {}
	local p = ffi.cast('uint8_t*', img.buffer)
	for i=0,img.height*img.width-1 do
		local key = ffi.string(p, dim)
		hist[key] = (hist[key] or 0) + 1
		p = p + dim
	end
	return hist
end

return buildHistogram
