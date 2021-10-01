local ffi = require 'ffi'

-- https://stackoverflow.com/questions/3018313/algorithm-to-convert-rgb-to-hsv-and-hsv-to-rgb-in-range-0-255-for-both
local function hsvToRgb(h, s, v)
	h = assert(tonumber(h))
	s = assert(tonumber(s))
	v = assert(tonumber(v))

	if s <= 0 then				-- < is bogus, just shuts up warnings
		return v, v, v
	end
	s = s / 255
	
	h = h * 6 / 256	-- so h is [0,6)
	
	local i = math.floor(h)
	local f = h - i
	local p = math.floor(v * (1 - s))
	local q = math.floor(v * (1 - s * f))
	local t = math.floor(v * (1 - s * (1 - f)))
	if i == 0 then
		return v, t, p
	elseif i == 1 then
		return q, v, p
	elseif i == 2 then
		return p, v, t
	elseif i == 3 then
		return p, q, v
	elseif i == 4 then
		return t, p, v
	elseif i == 5 then
		return v, p, q
	end
	error'here'
end

--[[ testing
print(hsvToRgb(0,0,0))
print(hsvToRgb(0,0,255))
print(hsvToRgb(0,255,255))
print(hsvToRgb(42.5,255,255))
print(hsvToRgb(85,255,255))
print(hsvToRgb(127.5,255,255))
print(hsvToRgb(170,255,255))
print(hsvToRgb(212.5,255,255))
print(hsvToRgb(255,255,255))
os.exit()
--]]

local function imgHsvToRgb(img)
	img = img:clone()
	assert(img.channels == 3)
	assert(ffi.sizeof(img.format) == 1)
	local p = img.buffer
	for i=0,img.width*img.height-1 do
		p[0], p[1], p[2] = hsvToRgb(p[0], p[1], p[2])
		p = p + 3
	end
	return img
end

return imgHsvToRgb
