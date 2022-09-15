local vector = require 'ffi.cpp.vector'
local table = require 'ext.table'
local class = require 'ext.class'
local range = require 'ext.range'
local bindistsq = require 'bindistsq'

--[[
args:
	mergeMethod = options:
		weighted
		replaceRandom
		replaceHighestWeight
--]]
local function buildColorMapMedianCut(args)
	local hist = assert(args.hist)
	local targetSize = assert(args.targetSize)
	
	local mergeMethod = args.mergeMethod or 'weighted'

	local dim
	for color,weight in pairs(hist) do
		if not dim then
			dim = #color
		else
			assert(dim == #color)
		end
	end

	-- [=[ TODO put this in its own function?  "buildColorMapMedianCut"
	-- build the from->to color mapping
	local Node = class()
	function Node:init()
		self.pts = table()
		self.min = vector('double', dim)
		self.max = vector('double', dim)
		self.size = vector('double', dim)
		for i=0,dim-1 do
			self.min.v[i] = math.huge
			self.max.v[i] = -math.huge
		end
	end
	function Node:addPt(pt, weight)
		self.pts:insert{pt=pt, weight=weight or 1}
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
		local a = Node()
		local b = Node()
		local k = self.biggestDim
	
		--[=[ aabb based
		--[[ pick the midpoint of the largest dimension interval
		local mid = .5 * (self.max.v[k] + self.min.v[k])
		--]]
		-- [[ pick the weighted midpoint to divide the 
		-- sorting the pts array along each axis ... its order doesn't matter, right?
		self.pts:sort(function(a,b) return a.pt:byte(k+1,k+1) < b.pt:byte(k+1,k+1) end)
		local total = self.pts:mapi(function(pt) return pt.weight end):sum()
		local half = .5 * total
		local sofar = 0
		local mid
		for _,pt in ipairs(self.pts) do
			if sofar > half then 
				mid = pt.pt:byte(k+1,k+1) 
				break
			end
			sofar = sofar + pt.weight
		end
		if not mid then mid = self.pts:last().pt:byte(k+1,k+1) end
		---]]
		for _,pt in ipairs(self.pts) do
			if pt.pt:byte(k+1,k+1) >= mid then
				a:addPt(pt.pt, pt.weight)
			else
				b:addPt(pt.pt, pt.weight)
			end
		end
		--]=]
		-- [=[ oriented plane
		-- find the longest distance between two points
		local bestDist, bestci, bestcj
		for i=1,#self.pts-1 do
			local ci = self.pts[i].pt
			for j=i+1,#self.pts do
				local cj = self.pts[j].pt
				local dist = bindistsq(ci, cj)
				-- find the plane that maximizes the distance between any (all?) two points
				if not bestDist or bestDist < dist then
					bestDist = dist
					bestci = ci
					bestcj = cj
				end
			end
		end
		local planeNormal = vector('double', dim)	-- normal points to ci from cj
		local planeConst = 0	-- dist = -p dot n for some point p on the normal ... cj for now, 
		-- so cj should eval to 0 dist from the plane and ci should be + dist
		for k=1,dim do
			local cik = bestci:byte(k,k)
			local cjk = bestcj:byte(k,k)
			local nk = cik - cjk 
			planeNormal.v[k-1] = nk
			planeConst = planeConst - cjk * nk
			--for cj: dist = -cjk * nk + cjk * nk = 0
			--for ci: dist = (cik - cjk) * nk = (cik - cjk)*(cik - cjk) = |ci - cj|^2
		end
		local function calcPlaneDist(c)
			local dist = planeConst
			for k=1,dim do
				 dist = dist + planeNormal.v[k-1] * c:byte(k,k)
			end
			return dist
		end
		-- now pick the midpoint distance along the plane that divides two groups
		-- use a temp variable
		for _,pt in ipairs(self.pts) do
			pt.planeDist = calcPlaneDist(pt.pt)
		end
		self.pts:sort(function(a,b) return a.planeDist < b.planeDist end)
		local total = self.pts:mapi(function(pt) return pt.weight end):sum()	-- hmm, should weight bias the plane normal?
		local half = .5 * total
		local sofar = 0
		local mid
		for _,pt in ipairs(self.pts) do
			if sofar > half then 
				mid = pt.planeDist
				break
			end
			sofar = sofar + pt.weight
		end
		if not mid then mid = self.pts:last().planeDist end
		-- now separate into two children
		for _,pt in ipairs(self.pts) do
			if pt.planeDist >= mid then
				a:addPt(pt.pt, pt.weight)
			else
				b:addPt(pt.pt, pt.weight)
			end
		end
		--]=]

		if #a.pts == 0 then	-- then take some from b and put them in a ?
			a.pts:insert(b.pts:remove(1))
		elseif #b.pts == 0 then	-- then take some from a and put them in b?
			b.pts:insert(1, a.pts:remove())
		end
		a:calcSize()
		b:calcSize()
		return a, b
	end

	local root = Node()
	for color,count in pairs(hist) do
		root:addPt(color, count)
	end
	root:calcSize()
	
	local nodes = table{root}

	while #nodes < targetSize do
		nodes:sort(function(a,b) 
			return a.size.v[a.biggestDim] < b.size.v[b.biggestDim] 
		end)
		if #nodes:last().pts <= 1 then break end	-- the biggest range node has 1 pt, so nothing more can be split
		local node = nodes:remove()
		local a,b = node:split()
		nodes:insert(a)
		nodes:insert(b)
	end	
	-- TODO convert to hsv beforehand?
	-- TODO find the best plane to divide by instead of axis-aligned?
	-- ... to do that you need to do eigen decomposition of the adjacency matrix

	-- ok now we have 'targetSize' nodes, now map each pt in the node onto one pt in the node
	local fromto = {}
	for _,node in ipairs(nodes) do
		local tokey
		-- use weighted average
		if mergeMethod == 'weighted' then
			local avg = vector('double', dim)
			local norm = 0
			for _,pt in ipairs(node.pts) do
				local weight = pt.weight
				for i=0,dim-1 do
					avg.v[i] = avg.v[i] + pt.pt:byte(i+1,i+1) * weight
				end
				norm = norm + weight
			end
			norm = 1 / norm
			for i=0,dim-1 do
				avg.v[i] = math.floor(avg.v[i] * norm)
			end
			tokey = range(0,dim-1):mapi(function(i) return string.char(avg.v[i]) end):concat()
		-- pick a random replacement
		elseif mergeMethod == 'replaceRandom' then
			local pts = node.pts:mapi(function(pt) return pt.pt end)
			tokey = pts[math.random(#pts)]
		-- pick the largest weighted
		elseif mergeMethod == 'replaceHighestWeight' then
			tokey = node.pts:sup(function(a,b) return a.weight > b.weight end).pt
		else
			error("here")
		end
		for _,pt in ipairs(node.pts) do
			fromto[pt.pt] = tokey
		end
	end
	--]=]
	
	return fromto
end

return buildColorMapMedianCut
