#!/usr/bin/env luajit
local path = require 'ext.path'
local Image = require 'image'
local function shrink(fn)
	local img = Image(fn)
	img = img:resize(img.width/32, img.height/32)	-- from 256x256 pixels to 8x8 pixels
	local basename = path(fn):getext()
	img:save(basename..'-small.png')
end

local fn = ...
if fn then
	shrink(fn)
else
	for i=0,7 do
		shrink('map-tex-region-'..i..'.png')
	end
end
