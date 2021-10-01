local table = require 'ext.table'
local buildHistogram = require 'buildhistogram'
local applyColorMap = require 'applycolormap'
local buildColorMapMedianCut = require 'buildcolormapmediancut'

local function reduceColorsMedianCut(args)
	local targetSize = assert(args.targetSize)
	local img = assert(args.img)
	local hist = args.hist or buildHistogram(img)

	local fromto = buildColorMapMedianCut{
		hist = hist,
		targetSize = targetSize,
		mergeMethod = args.mergeMethod,
	}

	img, hist = applyColorMap(img, fromto, hist)
	assert(#table.keys(hist) <= targetSize)
	return img, hist
end

return reduceColorsMedianCut
