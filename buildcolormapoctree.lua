local vector = require 'ffi.cpp.vector'
local quantizeOctree = require 'quantizeoctree'

local function buildColorMapOctree(args)
	local hist = assert(args.hist)
	local targetSize = assert(args.targetSize)

	local dim
	for color,weight in pairs(hist) do
		if not dim then
			dim = #color
		else
			assert(dim == #color)
		end
	end

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

	return fromto
end

return buildColorMapOctree
