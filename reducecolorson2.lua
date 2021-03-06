local buildHistogram = require 'buildhistogram'
local buildColorMapOn2 = require 'buildcolormapon2'
local applyColorMap = require 'applycolormap'

local function reduceColorsOn2(args)
	local img = assert(args.img)
	local targetSize = assert(args.targetSize)
	local hist = args.hist or buildHistogram(img)

	-- should buildColorMapOn2 replace hist,or should applyColorMap do it?
	-- applyColorMap *can* do it, but buildColorMapOn2 is the only buildColorMap* function that remaps hist in the process
	-- so might as well use it
	local fromto, hist = buildColorMapOn2{
		hist = hist,
		targetSize = targetSize,
		dist = arg.dist or require 'bindistsq',
		merge = args.merge or require 'binweightedmerge',
		progress = args.progress,
	}
	
	img = applyColorMap(img, fromto)
	return img, hist
end

return reduceColorsOn2
