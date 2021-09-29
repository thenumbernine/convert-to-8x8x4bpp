local vector = require 'ffi.cpp.vector'
local table = require 'ext.table'
local quantizeOctree = require 'quantizeoctree'
local buildHistogram = require 'buildhistogram'
local applyColorMap = require 'applycolormap'

local function reduceColorsOctree(args)
	local img = assert(args.img)
	local targetSize = assert(args.targetSize)
	local hist = args.hist or buildHistogram(img)

	local dim = 3

	local root = quantizeOctree{
		dim = dim,
		targetSize = targetSize,
		minv = 0,
		maxv = 255,
		splitSize = 1,	-- pt per node
		buildRoot = function(root)
			for key,v in pairs(hist) do
				root:addToTree{
					key = key,
					pos = vector('double', {key:byte(1,dim)}),
					weight = v,
				}
			end
		end,
	}

	-- ok now we can map pixel values and histogram keys via 'fromto'
	local fromto = {}
	for node in root:iter() do
		if node.pts then
			-- pick target by weight not just the first
			local _, i = node.pts:sup(function(a,b) return a.weight > b.weight end)
			-- reduce to the first node in the list
			for _,pt in ipairs(node.pts) do
				fromto[pt.key] = node.pts[i].key
			end
		end
	end
	
	-- TODO convert 'dest' *HERE* into an indexed image
	img, hist = applyColorMap(img, fromto, hist)
	assert(#table.keys(hist) <= targetSize)

	return img, hist
end

return reduceColorsOctree
