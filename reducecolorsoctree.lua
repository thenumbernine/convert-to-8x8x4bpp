local bit = require 'bit'
local vector = require 'ffi.cpp.vector'
local table = require 'ext.table'
local quantizeOctree = require 'quantizeoctree'
local buildHistogram = require 'buildhistogram'
local applyColorMap = require 'applycolormap'
local replaceIntKeysWithStrs = require 'replaceintkeyswithstrs'
local replaceStrKeysWithInts = require 'replacestrkeyswithints'
local inttobin = require 'inttobin'

local function reduceColorsOctree(args)
	local img = assert(args.img)
	local targetSize = assert(args.targetSize)
	local hist = args.hist or buildHistogram(img)

	img = img:clone()
	
	quantizeOctree{
		dim = 3,
		targetSize = targetSize,
		minv = 0,
		maxv = 255,
		splitSize = 1,	-- pt per node
		buildRoot = function(root)
			for k,v in pairs(hist) do
				local key = inttobin(k, 3)
				root:addToTree{
					key = key,
					pos = vector('double', {key:byte(1,3)}),
					weight = v,
				}
			end
		end,
		nodeGetChildIndex = function(node, pt)
			return bit.bor(
				pt.pos.v[0] >= node.mid.v[0] and 1 or 0,
				pt.pos.v[1] >= node.mid.v[1] and 2 or 0,
				pt.pos.v[2] >= node.mid.v[2] and 4 or 0)		
		end,
		nodeChildIndexHasBit = function(node, childIndex, b)
			return bit.band(childIndex, bit.lshift(1,b)) ~= 0
		end,
		done = function(root)
			-- ok now we can map pixel values and histogram keys via 'fromto'
			local fromto = {}
			for node in root:iter() do
				if node.pts then
					-- pick target by weight not just the first
					node.pts:sort(function(a,b) return a.weight > b.weight end)
					-- reduce to the first node in the list
					for _,pt in ipairs(node.pts) do
						fromto[pt.key] = node.pts[1].key
					end
				end
			end				
			
			-- TODO convert 'dest' *HERE* into an indexed image
			hist = replaceIntKeysWithStrs(hist, 3)
			img, hist = applyColorMap(img, fromto, hist)
			hist = replaceStrKeysWithInts(hist)
			assert(#table.keys(hist) <= targetSize)
		end,
	}

	return img, hist
end

return reduceColorsOctree
