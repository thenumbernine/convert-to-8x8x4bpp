local table = require 'ext.table'
local Image = require 'image'
local buildHistogram = require 'buildhistogram'

local function reduceColorsImageMagick(args)
	local img = assert(args.img)
	local targetSize = assert(args.targetSize)

	img:save'tmp.png'
	os.execute('convert tmp.png -dither none -colors '..targetSize..' tmp2.png')
	os.remove'tmp.png'

	os.execute('convert tmp2.png -type TrueColor png24:tmp3.png')
	os.remove'tmp2.png'

	local newimg = Image'tmp3.png'
	print('new channels', newimg.channels)	
	os.remove'tmp3.png'
	
	local hist = buildHistogram(newimg)
	assert(#table.keys(hist) <= targetSize)
	return newimg, hist
end

return reduceColorsImageMagick
