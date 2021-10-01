local bit = require 'bit'
local vector = require 'ffi.cpp.vector'
local class = require 'ext.class'
local table = require 'ext.table'
local range = require 'ext.range'

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

	local childKeySizeInBytes = bit.rshift(dim, 3)
	if bit.band(dim, 7) ~= 0 then
		childKeySizeInBytes = childKeySizeInBytes + 1 
	end


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
			min = vector('double', dim),
			mid = vector('double', dim),
			max = vector('double', dim),
			pts = table(),
		}
		self.chs[k] = ch
		
		for j=0,dim-1 do
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

	--[[
	assumes pt has a member named 'pos' which is a vector'double'
	--]]
	function Node:getChildIndex(pt)
		local k = range(childKeySizeInBytes):mapi(function() return 0 end)
		for i=0,dim-1 do
			local byteindex = bit.rshift(i, 3)
			local bitindex = bit.band(i, 7)
			if pt.pos.v[i] >= self.mid.v[i] then
				k[byteindex+1] = bit.bor(k[byteindex+1], bit.lshift(1, bitindex))
			end
		end
		return k:mapi(function(ch) return string.char(ch) end):concat()
	end
		
	--[[
	childIndex in 0..2^dim-1
	b in 0..dim-1
	TODO pick an axis/plane of the parent node, and just use 2 children
	--]]
	function Node:childIndexHasBit(childIndexKey, i)
		local byteindex = bit.rshift(i, 3)
		local bitindex = bit.band(i, 7)
		local bytevalue = childIndexKey:byte(byteindex+1, byteindex+1)
		return bit.band(bytevalue, bit.lshift(1,bitindex)) ~= 0
	end
		
	local splitSize = 1	-- pt per node

	function Node:addToTree(pt)
		if self.chs then
			assert(not self.pts)
			self:getChildForIndex(self:getChildIndex(pt)):addToTree(pt)
		else
			assert(not self.chs)
			self.pts:insert(pt)
	-- [[ don't split until manually split		
			if #self.pts > splitSize then	-- split
	-- NOTICE I CAN'T HANDLE MULTIPLE IDENTICAL POINTS
	-- how to fix this ... 
	-- TODO assert pt has 'weight' as well, and for identical points, combine 'weight' values?			
				-- create upon request
				self.chs = {}
				local pts = self.pts
				self.pts = nil
				for _,pt in ipairs(pts) do
					self:addToTree(pt)
				end
			end
	--]]	
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

	local root = Node{
		depth = 0,
		min = vector('double', dim),
		mid = vector('double', dim),
		max = vector('double', dim),
		pts = table(),	-- .pt, .weight
	}
	local minv = 0
	local maxv = 255
	for i=0,dim-1 do
		root.min.v[i] = minv
		root.max.v[i] = maxv
		root.mid.v[i] = (minv + maxv) * .5
	end

	for key,v in pairs(hist) do
		root:addToTree{
			key = key,
			pos = vector('double', {key:byte(1,dim)}),
			weight = v,
		}
	end

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
