local ffi = require 'ffi'
local vector = require 'ffi.cpp.vector'
local class = require 'ext.class'
local table = require 'ext.table'


local Node = class()

function Node:init(args)
	for k,v in pairs(args) do
		self[k] = v
	end
end

function Node:getChildForIndex(k)
	local ch = self.chs[k]
	if ch then return ch end

	local ch = self.class{
		depth = self.depth + 1,
		min = vector('double', self.dim),
		mid = vector('double', self.dim),
		max = vector('double', self.dim),
		pts = table(),
	}
	self.chs[k] = ch
	
	for j=0,self.dim-1 do
		if not self:childIndexHasBit(k, j) then
			ch.min.v[j] = self.min.v[j]
			ch.max.v[j] = self.mid.v[j]
		else
			ch.min.v[j] = self.mid.v[j]
			ch.max.v[j] = self.max.v[j]
		end
		ch.mid.v[j] = (ch.min.v[j] + ch.max.v[j]) * .5
	end

	return ch
end

function Node:addToTree(pt)
	if self.chs then
		assert(not self.pts)
		self:getChildForIndex(self:getChildIndex(pt)):addToTree(pt)
	else
		assert(not self.chs)
		self.pts:insert(pt)
		if #self.pts > self.splitSize then	-- split
-- NOTICE I CAN'T HANDLE MULTIPLE IDENTICAL POINTS
-- how to fix this ... 
			-- create upon request
			self.chs = {}
			local pts = self.pts
			self.pts = nil
			for _,pt in ipairs(pts) do
				self:addToTree(pt)
			end
		end
	end
end

function Node:iterRecurse()
	coroutine.yield(self)
	if self.chs then
		for _,ch in pairs(self.chs) do
			ch:iterRecurse()
		end
	end
end

function Node:iter()
	return coroutine.wrap(function()
		self:iterRecurse()
	end)
end

function Node:countleaves()
	local n = 0
	for node in self:iter() do
		if node.pts then
			n = n + 1
		end
	end
	return n
end

function Node:countbranches()
	local n = 0
	for node in self:iter() do
		if node.chs then
			n = n + 1
		end
	end
	return n
end

local function quantize(args)
	local dim = assert(args.dim)
	local targetSize = assert(args.targetSize)

	local nodeClass = class(Node)
	nodeClass.dim = dim
	nodeClass.splitSize = assert(args.splitSize)

	-- returns a value that can be uniquely mapped from 0..2^dim-1
	nodeClass.getChildIndex = assert(args.nodeGetChildIndex)
	
	--[[
	childIndex in 0..2^dim-1
	b in 0..dim-1
	--]]
	nodeClass.childIndexHasBit = assert(args.nodeChildIndexHasBit)

	local root = nodeClass{
		depth = 0,
		min = vector('double', dim),
		mid = vector('double', dim),
		max = vector('double', dim),
		pts = table(),	-- .pt, .weight
	}
	local minv = assert(args.minv)
	local maxv = assert(args.maxv)
	for i=0,dim-1 do
		root.min.v[i] = minv
		root.max.v[i] = maxv
		root.mid.v[i] = (minv + maxv) * .5
	end

	args.buildRoot(root)
	
	local n = root:countleaves()
	if n > targetSize then
		local branches = table()
		for node in root:iter() do
			if node.chs then branches:insert(node) end 
		end
		branches:sort(function(a,b)
			-- first sort by depth, so deepest are picked first
			-- this way we always are collapsing leaves into our branch
			if a.depth > b.depth then return true end
			if a.depth < b.depth then return false end
			-- then sort by point count within the nodes, smallest first?
			if a.pts and b.pts then return #a.pts > #b.pts end
			-- then for single points per nodes, sort by euclidian distance of all children?  but only for deepest roots are >1 children-with-points guaranteed
		end)
		
		while n > targetSize do
			local leaf = branches:remove(1)
			assert(leaf, "how did you remove branches nodes without losing branches points?!?!?!?!?!?!?!!?!?")
			leaf.pts = table.append(table.map(leaf.chs, function(ch, _, t) return ch.pts, #t+1 end):unpack())
			leaf.chs = nil
			n = root:countleaves()
		end
	end
		
	args.done(root)
end

local function buildHistogram(img)
	assert(img.channels == 3)
	assert(ffi.sizeof(img.format) == 1)
	local hist = {}
	for i=0,img.height*img.width-1 do
		local p = ffi.cast('uint8_t*', img.buffer) + 3 * i
		local key = bit.bor(p[0], bit.lshift(p[1], 8), bit.lshift(p[2], 16))
		hist[key] = (hist[key] or 0) + 1
	end
	return hist
end

local function reduceColors(img, numColors, hist)
	hist = hist or buildHistogram(img)

	img = img:clone()
	quantize{
		dim = 3,
		targetSize = numColors,
		minv = 0,
		maxv = 255,
		splitSize = 1,	-- pt per node
		buildRoot = function(root)
			for k,v in pairs(hist) do
				root:addToTree{
					key = k,
					pos = vector('double', {
						bit.band(0xff, k),
						bit.band(0xff, bit.rshift(k, 8)),
						bit.band(0xff, bit.rshift(k, 16))
					}),
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
					-- reduce to the first node in the list
					for _,pt in ipairs(node.pts) do
						fromto[pt.key] = node.pts[1].key
					end
				end
			end				
			-- TODO convert 'dest' *HERE* into an indexed image
			for i=0,img.width*img.height-1 do
				local p = img.buffer + 3 * i
				local key = bit.bor(p[0], bit.lshift(p[1], 8), bit.lshift(p[2], 16))
				key = fromto[key]
				p[0] = bit.band(0xff, key)
				p[1] = bit.band(0xff, bit.rshift(key, 8))
				p[2] = bit.band(0xff, bit.rshift(key, 16))
			end
			local newhist = {}
			for k,v in pairs(hist) do
				local tokey = fromto[k]
				newhist[tokey] = (newhist[tokey] or 0) + v
			end
			hist = newhist
			assert(#table.keys(hist) <= numColors)
		end,
	}

	return img, hist
end

return {
	quantize = quantize,
	buildHistogram = buildHistogram,
	reduceColors = reduceColors,
}
