local table = require 'ext.table'
local buildColorMapOctree = require 'buildcolormapoctree'
local buildHistogram = require 'buildhistogram'
local applyColorMap = require 'applycolormap'

local function reduceColorsOctree(args)
	local targetSize = assert(args.targetSize)
	
	local img = assert(args.img)
	local hist = args.hist or buildHistogram(img)

	local fromto = buildColorMapOctree{
		hist = hist,
		targetSize = targetSize,
	}
	
	-- TODO convert 'dest' *HERE* into an indexed image
	img, hist = applyColorMap(img, fromto, hist)
	assert(#table.keys(hist) <= targetSize)

	return img, hist
end

return reduceColorsOctree
