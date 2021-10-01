#!/usr/bin/env luajit
local math = require 'ext.math'
local Image = require 'image'

--[[
gimp adjust color curves, 80 -> 180
I'm guessing this is cubic ....

y = ax^3 + bx^2 + cx + d

(x1,y1) = (0,0)
0 = d

(x2,y2) = (1,1)
1 = a + b + c
c = (1 - a - b)

(x3,y3) within (0,1)x(0,1)
y = x(ax^2 + bx + 1 - a - b)
y = x(a(x^2-1) + b(x-1) + 1)
y = x(a(x-1)(x+1) + b(x-1) + 1)
y = x((a(x+1) + b)(x-1) + 1)

looks good for a=1.1, b=-3
--]]
local function f(x)
	return x*((1.1 * (x+1) - 3)*(x - 1) + 1)
end
local function brighten(src)
	local dst = src:clone()
	local p = src.buffer
	local q = dst.buffer
	for i=0,src.width*src.height*src.channels-1 do
		q[0] = math.floor(255 * math.clamp(f(p[0]/255), 0, 1))
		p = p + 1
		q = q + 1
	end
	return dst
end

for _,info in ipairs{
	{'map-tex-small.png', 'map-tex-small-brighter.png'},
	{'map-tex-region-0-small.png', 'map-tex-region-0-small-brighter.png'},
	{'map-tex-region-1-small.png', 'map-tex-region-1-small-brighter.png'},
	{'map-tex-region-2-small.png', 'map-tex-region-2-small-brighter.png'},
	{'map-tex-region-3-small.png', 'map-tex-region-3-small-brighter.png'},
	{'map-tex-region-4-small.png', 'map-tex-region-4-small-brighter.png'},
	{'map-tex-region-5-small.png', 'map-tex-region-5-small-brighter.png'},
	{'map-tex-region-6-small.png', 'map-tex-region-6-small-brighter.png'},
	{'map-tex-region-7-small.png', 'map-tex-region-7-small-brighter.png'},
} do
	local srcfn, dstfn = table.unpack(info)
	brighten(Image(srcfn)):save(dstfn)
end
