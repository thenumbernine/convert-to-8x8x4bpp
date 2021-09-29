--[[
TODO replace 24-bit integer keys with 3-byte string keys
and then replace vec3ub with the strings
and vec3d with vector'double'
and then generalize by dimension
--]]
local table = require 'ext.table'

local buildHistogram = require 'buildhistogram'
local buildColorMapOn2 = require 'buildcolormapon2'
local applyColorMap = require 'applycolormap'

local replaceIntKeysWithStrs = require 'replaceintkeyswithstrs'
local replaceStrKeysWithInts = require 'replacestrkeyswithints'

local function reduceColorsOn2(args)
	local img = assert(args.img)
	local targetSize = assert(args.targetSize)
	local hist = args.hist or buildHistogram(img)

	hist = replaceIntKeysWithStrs(hist, 3)

	-- TODO should buildColorMapOn2 replace hist,or should applyColorMap do it?
	local fromto
	hist, fromto = buildColorMapOn2{
		hist = hist,
		targetSize = targetSize,
		dist = arg.dist or require 'bindistsq',
		merge = args.merge or require 'binweightedmerge',
		progress = args.progress,
	}
	
	img = applyColorMap(img, fromto)
	
	hist = replaceStrKeysWithInts(hist)

	return img, hist
end

return reduceColorsOn2
