local ffi = require 'ffi'

-- https://stackoverflow.com/questions/3018313/algorithm-to-convert-rgb-to-hsv-and-hsv-to-rgb-in-range-0-255-for-both
local function rgbToHsv(r, g, b)
	r = assert(tonumber(r))
	g = assert(tonumber(g))
	b = assert(tonumber(b))
	
	r = r / 255
	g = g / 255
	b = b / 255
	
	local min = math.min(r,g,b)
	local max = math.max(r,g,b)

	local v = max
	local delta = max - min
	if delta < 1e-5 then
		return 0, 0, v*255		-- h is undefined, maybe nan?
	end
	if max == 0 then 			-- if max is 0, then r = g = b = 0
		return 0, 0, v*255		-- s = 0, h is undefined
	end
	local s = delta / max
	local h
	if r >= max then			-- > is bogus, just keeps compilor happy
		h = (g - b) / delta		-- between yellow & magenta
	elseif g >= max then
		h = 2 + (b - r) / delta	-- between cyan & yellow
	else
		h = 4 + (r - g) / delta	-- between magenta & cyan
	end
	h = (h % 6) / 6

	return h * 255, s * 255, v * 255
end

--[[ testing
print(rgbToHsv(0,0,0))
print(rgbToHsv(255,0,0))
print(rgbToHsv(255,255,0))
print(rgbToHsv(0,255,0))
print(rgbToHsv(0,255,255))
print(rgbToHsv(0,0,255))
print(rgbToHsv(255,0,255))
print(rgbToHsv(255,255,255))
os.exit()
--]]

local function imgRgbToHsv(img)
	img = img:clone()
	assert(img.channels == 3)
	assert(ffi.sizeof(img.format) == 1)
	local p = img.buffer
	for i=0,img.width*img.height-1 do
		p[0], p[1], p[2] = rgbToHsv(p[0], p[1], p[2])
		p = p + 3
	end
	return img
end

return imgRgbToHsv
