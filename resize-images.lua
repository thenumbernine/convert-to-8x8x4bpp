#!/usr/bin/env luajit
local Image = require 'image'
for i=0,7 do
	local img = Image('map-tex-region-'..i..'.png')
	img = img:resize(img.width/32, img.height/32)
	img:save('map-tex-region-'..i..'-small.png')
end
