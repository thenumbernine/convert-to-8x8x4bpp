local table = require 'ext.table'
local buildHistogram = require 'buildhistogram'
local applyColorMap = require 'applycolormap'
local buildColorMapMedianCut = require 'buildcolormapmediancut'

local function reduceColorsMedianCut(args)
	local dim = 3
	local img = assert(args.img)
	local targetSize = assert(args.targetSize)
	local hist = args.hist or buildHistogram(img)

	fromto, hist = buildColorMapMedianCut{
		hist = hist,
		targetSize = args.targetSize,
	}

	img, hist = applyColorMap(img, fromto, hist)
	assert(#table.keys(hist) <= targetSize)
	return img, hist
end

return reduceColorsMedianCut
