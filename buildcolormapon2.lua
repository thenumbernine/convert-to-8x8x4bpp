local table = require 'ext.table'

--[[
build map from src to dest color to reduce number of colors
using O(n^2) brute force search for closest colors
--]]
local function buildColorMapOn2(args)
	local hist = assert(args.hist)
	local targetSize = assert(args.targetSize)

	-- just needs to be increasing wrt the actual dist, doesn't need to be exact, used for comparison for merging closest points
	local calcPtDist = assert(args.dist)
	local merge = args.merge or require 'binweightedmerge'
	local progress = args.progress

	local colors = table.keys(hist):sort(function(a,b)
		return hist[a] < hist[b]	-- sorting doesn't matter
	end)

	-- infer dim from key sizes of hist -- all should be of size dim
	local dim = #colors[1]
	for i=2,#colors do
		assert(#colors[i] == dim)
	end

--print('colors: #'..#colors)
--print(colors:mapi(function(c) return ' '..bintohex(c) end):concat'\n')
	local distSqs = colors:mapi(function(ci,i)
		return colors:mapi(function(cj,j)
			return i == j and 0 or calcPtDist(ci, cj)
		end)
	end)
	
	local pairsForDists = table()
	for i=1,#distSqs-1 do
		for j=i+1,#distSqs do
			pairsForDists:insert{i,j,distSqs[i][j]}	-- i < j
		end
	end

	-- remapping colors
	local fromto = {}
	for _,c in ipairs(colors) do
		fromto[c] = c
	end

	local startTime = os.time()
	local lastTime = startTime 
	local initNumColors = #colors

	while #colors > targetSize do
		if progress then
			local thisTime = os.time()
			if thisTime ~= lastTime then
				lastTime = thisTime
				progress( (#colors - initNumColors) / (targetSize - initNumColors), thisTime - startTime, #colors)
			end
		end

		pairsForDists:sort(function(a,b) return a[3] > b[3] end)
	
		-- now merge closest pairs, lerp by weights of each
		local i, j = table.unpack(pairsForDists:remove())
		local ci = colors[i]
		if not ci then
			error("pairsForDists had "..i.." but there is no color")
		end
		local cj = colors[j]
		if not cj then
			error("pairsForDists had "..j.." but there is no color")
		end
--print('combining '..bintohex(ci)..' and '..bintohex(cj))
		local wi = hist[ci]
		if not wi then
			error("couldn't find weight for color key "..bintohex(ci))
		end
		local wj = assert(hist[cj])
		if not wj then
			error("couldn't find weight for color key "..bintohex(cj))
		end
		hist[ci] = nil
		hist[cj] = nil

--print('and clearing their hist weights, hist keys are now: #'..#table.keys(hist))
--print(table.keys(hist):mapi(function(c) return ' '..bintohex(c) end):concat'\n')
		local wk = wi + wj
		-- weight by most popular colors
		local ck = merge(ci, cj, wi/wk, wj/wk)
--print('adding new color key '..('%06x'):format(ck)..' weight '..wk)
	
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
		colors:remove(j)	-- remove larger of the two first
		colors:remove(i)
	
		-- remove distSqs for i and j ...
		for _,row in ipairs(distSqs) do
			row:remove(j)
			row:remove(i)
		end
		distSqs:remove(j)
		distSqs:remove(i)
	
		-- remove old pairs that included these colors
		for m=#pairsForDists,1,-1 do
			local p = pairsForDists[m]
			if p[1] == i or p[2] == i
			or p[1] == j or p[2] == j then
				pairsForDists:remove(m)
			end
		end
		-- decrement existing pairs indexes
		for _,p in ipairs(pairsForDists) do
			for m=1,2 do
				if p[m] > j then 
					p[m] = p[m] - 2 
				elseif p[m] > i then
					p[m] = p[m] - 1
				end
			end
		end

		if dontAdd then
			local k = assert(colors:find(ck))	-- hist[ck] exists, so colors[k] == ck should exist too
			for i=1,#colors do
				local ci = colors[i]
				local distSq = calcPtDist(ci,ck)
				distSqs[i][k] = distSq
				distSqs[k][i] = distSq
			end
			for _,p in ipairs(pairsForDists) do
				if p[1] == k or p[2] == k then
					p[3] = distSqs[p[1]][p[2]]
				end
			end
		else
			-- add new entries for distSqs[*][k] and pairsForDists
			local k = #colors
--print('made new color '..bintohex(ck)..' .. # colors '..#colors)
			distSqs[k] = table()
			for i=1,#colors-1 do
				local ci = colors[i]
				assert(distSqs[i][k] == nil)
				local distSq = calcPtDist(ci, ck)
				distSqs[i][k] = distSq
				distSqs[k][i] = distSq
				pairsForDists:insert{i,k,distSq}
			end
			distSqs[k][k] = 0
		end
	end
--print'done'
	return fromto, hist
end

return buildColorMapOn2
