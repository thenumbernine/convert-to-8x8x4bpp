local ffi = require 'ffi'
local bit = require 'bit'
local vector = require 'ffi.cpp.vector-lua'
local class = require 'ext.class'
local table = require 'ext.table'
local range = require 'ext.range'
local bindistlinf = require 'bindistlinf'
local bintohex = require 'bintohex'

local function buildColorMapOctree(args)
	local hist = assert(args.hist)
	local targetSize = assert(args.targetSize)
	local merge = args.merge or require 'binweightedmerge'

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
		self.depth = 0
		self.pts = table()
		self.min = vector('double', dim)
		self.max = vector('double', dim)
		self.size = vector('double', dim)
		self:clearBounds()
	end

	function Node:clearBounds()
		for i=0,dim-1 do
			self.min.v[i] = math.huge
			self.max.v[i] = -math.huge
		end
	end

	function Node:addPt(pt, weight)
		self.pts:insert{pt=pt, weight=weight or 1}
		self:stretchToPoint(pt)
	end

	-- if we removed a point then gotta do this
	function Node:refreshBoundsToPts()
		self:clearBounds()
		for _,pt in ipairs(self.pts) do
			self:stretchToPoint(pt.pt)
		end
	end

	function Node:refreshBoundsToChildren()
		self:clearBounds()
		for _,ch in ipairs(self.chs) do
			for pt in ch:cornerIter() do
				self:stretchToPoint(pt)
			end
		end
	end

	function Node:cornerIter()
		return coroutine.wrap(function()
			local is = table{1}:rep(dim)
			while true do
				local corner = ''
				for i=1,dim do
					corner = corner .. (is[i] == 1 and string.char(self.min.v[i-1]) or string.char(self.max.v[i-1]))
				end
				coroutine.yield(corner)

				for i=1,dim do
					is[i] = is[i] + 1
					if is[i] <= 2 then break end
					is[i] = 1
					if i == dim then return end
				end
			end
		end)
	end

	function Node:stretchToPoint(pt)
		for i=0,dim-1 do
			local vi = pt:byte(i+1,i+1)
			self.min.v[i] = math.min(self.min.v[i], vi)
			self.max.v[i] = math.max(self.max.v[i], vi)
		end
	end

	function Node:calcSize()
		self.biggestDim = 0
		for i=0,dim-1 do
			self.size.v[i] = self.max.v[i] - self.min.v[i]
			if self.size.v[i] > self.size.v[self.biggestDim] then self.biggestDim = i end
		end
	end

	function Node:split()
		--assert(#self.pts > 1)
		--assert(not self.chs)
		local a = Node()
		local b = Node()
		local k = self.biggestDim
	
		--assert(not self.mid)
		--[[ pick the midpoint of the largest dimension interval
		self.mid = .5 * (self.max.v[k] + self.min.v[k])
		--]]
		-- [[ pick the weighted midpoint to divide the 
		-- sorting the pts array along each axis ... its order doesn't matter, right?
		self.pts:sort(function(a,b) return a.pt:byte(k+1,k+1) < b.pt:byte(k+1,k+1) end)
		local total = self.pts:mapi(function(pt) return pt.weight end):sum()
		local half = .5 * total
		local sofar = 0
		for _,pt in ipairs(self.pts) do
			if sofar > half then 
				self.mid = pt.pt:byte(k+1,k+1) 
				break
			end
			sofar = sofar + pt.weight
		end
		if not self.mid then self.mid = self.pts:last().pt:byte(k+1,k+1) end
		---]]
		for _,pt in ipairs(self.pts) do
			if pt.pt:byte(k+1,k+1) >= self.mid then
				a:addPt(pt.pt, pt.weight)
			else
				b:addPt(pt.pt, pt.weight)
			end
		end
		if #a.pts == 0 then	-- then take some from b and put them in a ?
			local bpt = b.pts:remove(1)
			b:refreshBoundsToPts()
			a:addPt(bpt.pt, bpt.weight)
		elseif #b.pts == 0 then	-- then take some from a and put them in b?
			local apt = a.pts:remove()
			a:refreshBoundsToPts()
			b:addPt(apt.pt, apt.weight)
		end
		a:calcSize()
		b:calcSize()
		a.parent = self
		b.parent = self
		a.depth = self.depth + 1
		b.depth = self.depth + 1
		self.pts = nil
		self.chs = table{a,b}
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

	function Node:count()
		local n = 0
		for node in self:iter() do
			n = n + 1
		end
		return n
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

	-- axis-aligned bounding boxes touch if there is overlap in all dimensions
	function Node:bboxTouches(pt, dist)
		for i=0,dim-1 do
			local v = pt:byte(i+1,i+1)
			if v + dist < self.min.v[i] or self.max.v[i] < v - dist then return false end
		end
		return true
	end
	
	--[[
	TODO instead of searching up the tree from the leaf,
	how about starting at the root and searching child-first, then search favors the findPt , so that the findPt leaf is hit first
	--]]
	function Node:findClosest(findPt, lastChild, closestNode, bestDist, indent)
--[[
indent = indent or ''
print(indent..'findClosest'
	..' self='..tostring(self)
	..' depth='..self.depth
	..' min=('..range(dim):mapi(function(i) return self.min.v[i-1] end):concat', '..')'
	..' max=('..range(dim):mapi(function(i) return self.max.v[i-1] end):concat', '..')'
	..' #chs='..(self.chs and #self.chs or 'nil')
	..' #pts='..(self.pts and #self.pts or 'nil')
	..' closestPt='..(closestNode and bintohex(closestNode.pts[1].pt) or 'nil')
	..' bestDist='..tostring(bestDist)
)
indent = indent .. ' '		
--]]
		--[[
		first time this is called: it is called on a leaf with a pt looking for what pt is closest to it
		--]]
		if not lastChild then
			--assert(self.pts)
			--assert(#self.pts == 1)	-- if we have multiple points then we should have split it first
			--assert(self.pts[1].pt == findPt)	-- only call 'findClosest' on the leaf of where we start searching from
			return self.parent:findClosest(findPt, self, self, nil, indent)
		end
			
		--[[
		no dist? this is the first parent.
		so the findPt will be inside this node's bounding region.
		
		now search through each child of 'self' for neighboring points
		bounds is initialized as this node's bounds
		as you get hits, restrict the mins/maxs of this search.
		
		then once you're done with this node's children, repeat going up the tree and for that node's children (excluding this node)
		]]
		if not bestDist then
			--assert(not self.pts)
			--assert(self.chs)

			bestDist = 0
			for corner in self:cornerIter() do
				-- calc l-inf dist from point within bounds to corner
				-- if I use a L2 dist then I can't cull by box bounds, since corners might be further from a face, and then a point inside the face could be within the bounding radius
				-- so I should use a L-inf dist
				local dist = bindistlinf(findPt, corner)
				-- I want to minimize bestDist , but there is the case when a pt is along each axis, and no corner contains a pt ...
				if not bestDist or bestDist < dist then
					bestDist = dist
				end
			end
		end
		
		--[[
		if we're a branch then
		cycle through all children
		skip a previously-tested child if we are iterating up the tree
		test the child if
			- the find point is inside the childs bbox
			- the closest point on the childs bbox is within 'bestDist' of the findPt
		--]]
		closestNode, bestDist = self:findDown(findPt, lastChild, closestNode, bestDist, indent)
		if bestDist == 0 then return closestNode, bestDist end

		if self.parent then
			return self.parent:findClosest(findPt, self, closestNode, bestDist, indent)
		else
			return closestNode, bestDist
		end
	end
	
	function Node:findDown(findPt, lastChild, closestNode, bestDist, indent)
		-- if we're a leaf then find the closest point among our points
--[[
print(indent..'findDown'
	..' self='..tostring(self)
	..' depth='..self.depth
	..' min=('..range(dim):mapi(function(i) return self.min.v[i-1] end):concat', '..')'
	..' max=('..range(dim):mapi(function(i) return self.max.v[i-1] end):concat', '..')'
	..' #chs='..(self.chs and #self.chs or 'nil')
	..' #pts='..(self.pts and #self.pts or 'nil')
	..' closestPt='..bintohex(closestNode.pts[1].pt)
	..' bestDist='..bestDist
)
indent = indent .. ' '		
--]]	
		if self.pts then
--print(indent..'searching points')
			--assert(not self.chs)
			--assert(#self.pts == 1)
			for _,pt in ipairs(self.pts) do
				local dist = bindistlinf(pt.pt, findPt)
				if dist <= bestDist then
					bestDist = dist
					closestNode = self
					if bestDist == 0 then return closestNode, bestDist end
--print(indent..'closest is '..bintohex(pt.pt)..' dist '..bestDist)
				end
			end
		end

		if self.chs then
--print(indent..'searching children')
			--assert(not self.pts)
			for _,ch in ipairs(self.chs) do
				if ch ~= lastChild then
					if ch:bboxTouches(findPt, bestDist) then	-- findPt +- bestDist is our search bounds
						closestNode, bestDist = ch:findDown(findPt, nil, closestNode, bestDist, indent)
						if bestDist == 0 then return closestNode, bestDist end
					end
				end
			end
		end
		return closestNode, bestDist
	end

	-- removes the leaf node, tosses its points
	-- if the parent has any children then merges them
	function Node:removeLeaf()
--print'removing leaf'	
		--assert(self.pts)
		--assert(#self.pts == 1)
		local parent = self.parent
		if not parent then
			error"removing root - handle this case"
		end
		--assert(not parent.pts)
		local chs = assert(parent.chs)
		parent.chs:removeObject(self)
		--assert(#parent.chs == 1)
		local sibling = assert(parent.chs[1])
		local par2 = parent.parent
		--assert(#par2.chs == 2)
		local chi = assert((par2.chs:find(parent)))
		par2.chs[chi] = sibling
		sibling.parent = par2
		--assert(#par2.chs == 2)
		-- now re-stretch par2's bbox to its children
		par2:refreshBoundsToChildren()
		par2:calcSize()
		--assert(#par2.chs == 2)
		-- 'parent' is now removed as well
	end

	function Node:getSibling()
		local parent = assert(self.parent)
		local chi = assert((parent.chs:find(self)))
		return assert(parent.chs[3 - chi])
	end

	function Node:addPtToLeaf(pt, weight)
		if self.chs then
			--assert(not self.pts)
			if #self.chs ~= 2 then
				error("somehow we found a node with #chs == "..#self.chs.." != 2 "
					.." at depth "..self.depth
				)
			end
			self:stretchToPoint(pt)
			local k = self.biggestDim
			local a,b = table.unpack(self.chs)
			if pt:byte(k+1,k+1) >= self.mid then
				return a:addPtToLeaf(pt, weight)
			else
				return b:addPtToLeaf(pt, weight)
			end
			-- TODO redo self.biggestDim and self.mid here? otherwise balance might drift
		else
			--assert(self.pts)
			--assert(#self.pts == 1)
			self.pts:insert{pt=pt, weight=weight}
			self:split()
			for _,ch in ipairs(self.chs) do
				if ch.pts[1].pt == pt then return ch end
			end
			error"I don't know which child we added the new point to"
		end
	end

	local root = Node()
	for color,count in pairs(hist) do
		root:addPt(color,count)
	end
	root:calcSize()

	local tosplit = table{root}
	while #tosplit > 0 do
		local node = tosplit:remove(1)
		if #node.pts > 1 then
			node:split()
			tosplit:append(node.chs)
		end
	end

	local nodeForColor = {}
	for node in root:iter() do
		if node.pts then
			for _,pt in ipairs(node.pts) do
--print("mapping color "..bintohex(pt.pt).." to node "..tostring(node))
				nodeForColor[pt.pt] = node
			end
		end
	end

	local colors = table.keys(hist):sort()

	-- remapping colors
	local fromto = {}
	for _,c in ipairs(colors) do
		fromto[c] = c
	end

-- [=[ re-insertion takes forever
--print('for '..#colors..' colors')
--print('created '..root:count()..' nodes')
--print('created '..root:countleaves()..' leaves')
	local pairsForDists = table()
	for _,color in ipairs(colors) do
		--assert(type(color) == 'string')
		--assert(#color == dim)
--print('searching for '..bintohex(color))		
		local node = nodeForColor[color]
		local closest, dist = node:findClosest(color)
		local closestColor = closest.pts[1].pt
		--assert(color ~= closestColor)
		--assert(type(closestColor) == 'string')
		--assert(#closestColor == dim)
		pairsForDists:insert{color, closestColor, dist}
--print(bintohex(color)..' '..bintohex(closestColor)..' '..dist)
	end
	pairsForDists:sort(function(a,b) return a[3] > b[3] end)

	while root:countleaves() > targetSize do
print(root:countleaves())		
		local ci, cj = table.unpack(pairsForDists:remove())
		--assert(type(ci) == 'string')
		--assert(type(cj) == 'string')
		local ni = nodeForColor[ci]
		local nj = nodeForColor[cj]
--print("merging colors "..bintohex(ci).." and "..bintohex(cj)..' with nodes '..tostring(ni)..' and '..tostring(nj))
		--assert(ni)
		--assert(ni.pts)
		if #ni.pts ~= 1 then
			error("got a node with #pts "..#ni.pts)
		end
		--assert(nj)
		--assert(nj.pts)
		if #nj.pts ~= 1 then
			error("got a node with #pts "..#nj.pts)
		end
		local wi = ni.pts[1].weight
		local wj = nj.pts[1].weight
		local wk = wi + wj
		ni:removeLeaf()
		nj:removeLeaf()
--print("clearing nodes associated w/ colors "..bintohex(ci).." and "..bintohex(cj))
		nodeForColor[ni] = nil
		nodeForColor[nj] = nil
		local ck = merge(ci, cj, wi/wk, wj/wk)
	
		-- TODO do I want to rebalance the tree after insertion?
		-- or do I want to just insert it willy nilly?
		-- or just redo the whole thing?
		local nk = root:addPtToLeaf(ck, wk)
--print("assigning new merged color "..bintohex(ck)..' to node '..tostring(nk))
		nodeForColor[ck] = nk
		local sibling = nk:getSibling()
		--assert(sibling.pts)
		--assert(#sibling.pts == 1)
--print("re-assigning old color "..bintohex(sibling.pts[1].pt)..' to node '..tostring(sibling))
		nodeForColor[sibling.pts[1].pt] = sibling
		
		-- if there was an old entry mappig into ci or cj then now it should map into ck
		for _,from in ipairs(table.keys(fromto)) do
			local to = fromto[from]
			if to == ci or to == cj then
				fromto[from] = ck
			end
		end
		fromto[ci] = ck
		fromto[cj] = ck
	
		local dontAdd
		if hist[ck] then
			-- if there is hist[ck] here then *DONT* add to colors and *DO* just inc the hist weight
			hist[ck] = hist[ck] + wk
			dontAdd = true
		else
			hist[ck] = wk
			colors:insert(ck)
		end
		colors:removeObject(cj)	-- remove larger of the two first
		colors:removeObject(ci)
		
		-- remove old pairs that included these colors
		for m=#pairsForDists,1,-1 do
			local p = pairsForDists[m]
			if p[1] == ci or p[2] == ci
			or p[1] == cj or p[2] == cj then
				pairsForDists:remove(m)
			end
		end

		if dontAdd then
			for _,p in ipairs(pairsForDists) do
				if p[1] == ck or p[2] == ck then
					p[3] = bindistlinf(p[1], p[2])
				end
			end
		else
			-- add new entries to pairsForDists
			local k = #colors
			for i=1,#colors-1 do
				local ci = colors[i]
				local dist = bindistlinf(ci, ck)
			
				for i=1,#pairsForDists do
					if pairsForDists[i][3] < dist then
						pairsForDists:insert(i, {ci,ck,dist})
						break
					end
					if i == #pairsForDists then
						pairsForDists:insert{ci,ck,dist}
					end
				end
			end
		end
	end
--]=]
--[=[ instead of re-insertion, just sort by closest distance, and combine
	-- wait, how am I using the tree?
	-- isn't this the same as the O(n^2) version? but without weighted merging ...
	local pairsForDists = table()
	for i=1,#colors-1 do
		local ci = colors[i]
		for j=i+1,#colors do
			local cj = colors[j]
			assert(ci ~= cj)
			-- not enough memory
			pairsForDists:insert{ci, cj, require 'bindistsq'(ci, cj)}
		end
	end
	pairsForDists:sort(function(a,b) return a[3] > b[3] end)

	while #colors > targetSize do
		print('#colors', #colors, '#pairsForDists', #pairsForDists)
		local ci, cj, dist = table.unpack(pairsForDists:remove())
		fromto[ci] = cj
		colors:removeObject(ci)	-- which is slower? counting keys, or finding objects to remove?
		-- now remove all pairsForDists with ci
		for k=#pairsForDists,1,-1 do
			local p = pairsForDists[k]
			if p[1] == ci or p[2] == ci then
				pairsForDists:remove(k)
			end
		end
		-- no need to sort, already sorted
	end
--]=]
print('done, made '..root:countleaves()..' leaves')
os.exit()

--[[
ok now we have one leaf per pt
now we re-merge them based on closest nodes
do this by iterating through all leaves
then comparing them to ... ...
... all other nodes? ...
... other siblings of this parent?
... or how about, go up the tree, search children as we go, and restrict bounding sphere of search as we go too
	then after 1 or 2 branches up the tree and the bounding region should be so small that only parents are searched
--]]
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
