#! /usr/bin/env luajit
local ffi = require 'ffi'
local bit = require 'bit'
local os = require 'ext.os'
local class = require 'ext.class'
local table = require 'ext.table'
local range = require 'ext.range'
local math = require 'ext.math'
local tolua = require 'ext.tolua'
local vector = require 'ffi.cpp.vector'
local vec3ub = require 'vec-ffi.vec3ub'
local vec3d = require 'vec-ffi.vec3d'
local Image = require 'image'

local buildHistogram = require 'buildhistogram'
local quantize = require 'quantize'
local reduceColors = require 'reducecolors'
local bintohex = require 'bintohex'
local int24to8x8x8 = require 'int24to8x8x8'
local int8x8x8to24 = require 'int8x8x8to24'

local filename = ... or 'map-tex-small-brighter.png'
local img = Image(filename)
local basefilename = filename:sub(1,-5)

-- alright, now to convert this into a 256-color paletted image such that no 8x8 tile uses more than 16 colors, and no set of 16 colors isn't shared or whatever

local function splitImageIntoTiles(img, tileSize)
	assert(img.channels == 3)
	-- TODO strict enforcement? or just reshape/grow subtiles to be tileSize x tileSize?
	--assert(img.width % tileSize == 0)
	--assert(img.height % tileSize == 0)
	local tilesWide = math.floor(img.width / tileSize)
	local tilesHigh = math.floor(img.height / tileSize)

	local tiles = table()
	for y=0,tilesHigh-1 do
		for x=0,tilesWide-1 do
			local tileimg = img:copy{x=x*tileSize, y=y*tileSize, width=tileSize, height=tileSize}
			local hist = buildHistogram(tileimg)
			local keys = table.keys(hist)
			-- all black <-> don't use
			if #keys == 1 and keys[1] == 0 then
				hist = {}
				keys = {}
			end
			if #keys > 0 then
				tiles[1 + x + tilesWide * y] = {
					img = tileimg,
					hist = hist,
				}
			end
		end
	end
	return tiles, tilesWide, tilesHigh
end

local function rebuildTiles(tiles, tileSize, tilesWide, tilesHigh)
	local first = assert(select(2, tiles:find(nil, function(tile) return tile.img end)), "couldn't find a single tile with an image").img
	local result = Image(tileSize*tilesWide, tileSize*tilesHigh, first.channels, first.format)
	result:clear()
	for y=0,tilesHigh-1 do
		for x=0,tilesWide-1 do
			local tile = tiles[1 + x + tilesWide * y]
			if tile then		
				result:pasteInto{x=x*tileSize, y=y*tileSize, image=tile.img}
			end
		end
	end
	return result
end

local ts = 8
local tiles, tw, th = splitImageIntoTiles(img, ts)

--local option = 'A'
--local option = 'B'
--local option = 'C'
local option = 'D'
--local option = 'E'


-- option A: chop the pic into tiles, quantize each tile to 16 colors, then somehow merge tile palettes and further quantize to get 16 sets of 16 colors
if option == 'A' then 


	-- quantize each tile into a 16-color palette
	-- reduce to 15 colors so we always have 1 transparent color per palette
	local targetPaletteSize = 15
	for _,tile in pairs(tiles) do
		tile.img, tile.hist = reduceColors(tile.img, targetPaletteSize, tile.hist)
	end

	local function histToPal(hist)
		return table.keys(hist):sort():mapi(function(key)
			return string.char(int24to8x8x8(key))
		end):sort():concat()
	end

	-- build palettes for each - as 48-byte strings
	for _,tile in pairs(tiles) do
		tile.pal = histToPal(tile.hist) 
	end

	-- alright now we have our tiles, each with palette of 1 <= #pal <= 16 colors, but some have less, so now lets merge any palettes that are subsets of other palettes
	local tilesForPal = {}
	for _,tile in pairs(tiles) do
		tilesForPal[tile.pal] = tilesForPal[tile.pal] or table()
		tilesForPal[tile.pal]:insert(tile)
	end
	
	local allPalettes = table.keys(tilesForPal)
	allPalettes:sort(sort)
	print('how many unique palettes? '..#allPalettes)

	-- sort, largest first, try to merge smaller into larger palettes
	local function sort(a,b)
		if #a > #b then return true end
		if #a < #b then return false end
		return a < b
	end


--	print("palettes before merges:")
--	print(allPalettes:mapi(bintohex):concat'\n')
	
	local function strToSetOfColors(str)
		local cs = {}
		for i=1,#str,3 do
			cs[str:sub(i,i+2)] = true
		end
		return cs
	end

	for i=#allPalettes,1,-1 do
		local pi = allPalettes[i]
		local ci = strToSetOfColors(pi)
		for j=1,i-1 do
			local pj = allPalettes[j]
			local cj = strToSetOfColors(pj)
			
			local iIsSubsetOfJ = true
			for c,_ in pairs(ci) do
				if not cj[c] then
					iIsSubsetOfJ = false
					break
				end
			end

			if iIsSubsetOfJ then
				-- merge tiles of pi into tiles of pj
				tilesForPal[pj]:append(tilesForPal[pi])
				tilesForPal[pi] = nil
				-- remove palette pi
				allPalettes:remove(i)
				-- reassign palettes
				for _,tile in ipairs(tilesForPal[pj]) do
					tile.pal = pj
				end
				break
			end
		end
	end

	allPalettes:sort(sort)
	
	print('after merge, how many unique palettes? '..#allPalettes)
--	print("palettes after merges:")
--	print(allPalettes:mapi(bintohex):concat'\n')

	-- recombine smaller palettes
	do
		local found = false
		repeat
			found = false
			for i=#allPalettes,1,-1 do
				local pi = allPalettes[i]
				for j=i-1,1,-1 do
					local pj = allPalettes[j]
					if #pi + #pj <= 2*3*targetPaletteSize then		-- 2 chars per hex byte * 3 r g b bytes * 16 colors in the tile palette
						local pk = pi .. pj
						-- sort the colors?
						local cs = table()
						for w in pk:gmatch'...' do cs:insert(w) end
						cs:sort()
						pk = cs:concat()

						assert(pk ~= pi and pk ~= pj)
						tilesForPal[pk] = tilesForPal[pi]:append(tilesForPal[pj])
						tilesForPal[pi] = nil
						tilesForPal[pj] = nil
						allPalettes:removeObject(pi)
						allPalettes:removeObject(pj)
						allPalettes:insert(pk)
						-- reassign palettes
						for _,tile in ipairs(tilesForPal[pk]) do
							tile.pal = pk
print('reassigning tile')
print('hist', bintohex(histToPal(tile.hist)))
print('pal', bintohex(tile.pal))
						end
						found = true
						break
					end
				end
				if found then break end
			end
		until not found
	end
	allPalettes:sort(sort)

	print('after combining smaller palettes, how many unique palettes? '..#allPalettes)
--	print("palettes after combine:")
--	print(allPalettes:mapi(bintohex):concat'\n')

	

	-- rebuild and see what it looks like
	rebuildTiles(tiles, ts, tw, th):save(basefilename..'-tiles-16colors.png')

	-- now reduce all our palettes, count of up to (w/8) x (h/8) palettes, each with 16 unique colors,
	-- down to 16 palettes with 16 colors
	do
		local targetNumPalettes = 16
		local dim = 3*targetPaletteSize
		quantize{
			dim = dim,
			targetSize = targetNumPalettes,
			minv = 0,
			maxv = 255,
			splitSize = 1,	-- if this is too small then I get a stackoverflow ... and if it's too big then the quantization all reduces to a single repeated tile
			buildRoot = function(root)
				for _,palstr in pairs(allPalettes) do
					
					local keys = table()
					for w in palstr:gmatch'......' do
						keys:insert(w)
					end
					keys:sort()
					assert(#keys <= targetPaletteSize)
					
					local pal = vector('double', dim)
					for i,key in ipairs(keys) do
						pal.v[0 + 3 * (i-1)] = key:byte(1,1)
						pal.v[1 + 3 * (i-1)] = key:byte(2,2)
						pal.v[2 + 3 * (i-1)] = key:byte(3,3)
					end
					root:addToTree{
						palstr = palstr,
						pal = pal,
					}
				end
			end,
			nodeGetChildIndex = function(node, pt)
				-- 48-bit vector ...
				--				pt.pos.v[0] >= node.mid.v[0] and 1 or 0,
				--				pt.pos.v[1] >= node.mid.v[1] and 2 or 0,
				--				pt.pos.v[2] >= node.mid.v[2] and 4 or 0)		
				-- but just convert 6 uint8's into chars and concat them
				local numbytes = bit.rshift(dim, 3)
				if bit.band(dim, 7) ~= 0 then numbytes = numbytes + 1 end
assert(numbytes == 6)			
				local k = range(numbytes):mapi(function() return 0 end)
				for i=0,dim-1 do
					local byteindex = bit.rshift(i, 3)
					local bitindex = bit.band(i, 7)
					if pt.pal.v[i] >= node.mid.v[i] then
						k[byteindex+1] = bit.bor(k[byteindex+1], bit.lshift(1, bitindex))
					end
				end
				return k:mapi(function(ch) return string.char(ch) end):concat()
			end,
			nodeChildIndexHasBit = function(node, childIndexKey, i)
				local byteindex = bit.rshift(i, 3)
				local bitindex = bit.band(i, 7)
				local bytevalue = childIndexKey:byte(byteindex+1, byteindex+1)
				
				return bit.band(bytevalue, bit.lshift(1,bitindex)) ~= 0
			end,
			done = function(root)
				
				print('done')

				print('creating mapping of palstrs back to first in node ...')
				-- ok now we can map pixel values and histogram keys via 'fromtoPals'
				local fromtoPals = {}
				for node in root:iter() do
					if node.pts then
						-- TODO INSTEAD reduce the palettes, and then do the remapping to the palettes of each tile
						-- reduce to the first node in the list
						for _,pt in ipairs(node.pts) do
							-- if any square in the tilemap has tile pt.tile
							-- then replace it with tile pts[1].tile
							fromtoPals[pt.palstr] = node.pts[1].palstr
						end
					end
				end
			
				--[[
				print('consolidating tiles in tilesForPal...')
				for from, to in pairs(fromtoPals) do
					tilesForPal[to] = (tilesForPal[to] or table()):append(tilesForPal[from])
					tilesForPal[from] = nil
					allPalettes:removeObject(from)
				end
				--]]
				
				print('remapping colors in individual tiles...')

				-- fromtocolorsPerPal[frompalstr][topalstr] = { [fromcolor] = tocolor } where fromcolor and tocolor are 24-bit integers
				local fromtocolorsPerPal = {}
		
				-- reassign palettes
				--for topal,tiles in pairs(tilesForPal) do
				for _,tile in pairs(tiles) do
					local frompal = tile.pal
assert(#frompal % 3 == 0)
					local topal = assert(fromtoPals[frompal])
assert(#topal % 3 == 0)
					if frompal ~= topal then
					
						local toc = table()
						for w in topal:gmatch'......' do
							toc:insert(vec3ub(w:byte(1,3)))
						end

						if not fromtocolorsPerPal[frompal] then fromtocolorsPerPal[frompal] = {} end
						local fromto = fromtocolorsPerPal[frompal][topal]
						if not fromto then
print("building from<->to map for palettes:")
print('frompal', bintohex(frompal))
print('topal',	bintohex(topal))
print('from hist', bintohex(histToPal(tile.hist)))
							fromto = {}
							fromtocolorsPerPal[frompal][topal] = fromto
							for w in frompal:gmatch'...' do
								local fromc = vec3ub(w:byte(1,3))
								local fromcolorint = int8x8x8to24(fromc:unpack())
								local bestDist
								local bestc
								for _,c in ipairs(toc) do
									local dist = (vec3d(fromc:unpack()) - vec3d(c:unpack())):lenSq()
									if not bestDist or dist < bestDist then
										bestDist = dist
										bestc = c
									end
								end
								local tocolorint = int8x8x8to24(bestc:unpack())
print("adding entry from "..("%06x"):format(fromcolorint).." to "..('%06x'):format(tocolorint))
								fromto[fromcolorint] = tocolorint
							end
						end
						for i=0,tile.img.width*tile.img.height-1 do
							local p = tile.img.buffer + 3 * i
							local fromcolorint = int8x8x8to24(p[0], p[1], p[2])
							local tocolorint = fromto[fromcolorint]
							if not tocolorint then
								error("found a color not in the palette (that's why I should index the images) "
									..('%06x'):format(fromcolorint))
							end
							p[0], p[1], p[2] = int24to8x8x8(tocolorint)
						end
					
						tile.pal = topal
					end
				end
				-- TODO now recolor the picture based on the old->new palettes

			end,
		}
	end
	
	-- rebuild and see what it looks like
	rebuildTiles(tiles, ts, tw, th):save(basefilename..'-16tiles-16colors.png')


	-- now quantize each of the tile 16-color palettes (48-element vectors) into 16 unique palettes
	-- ok 3-dim vectors means up to 2^3==8 children
	-- so 48-dim vectors means up to 2^48 == 2.8147497671066e+14 children
	-- so ... 1) load child table sparsely  and 2) key by something with 48 bits of precision (uint64_t eh? if you can key by cdata?  you can but it keys by the obj ptr, so two cdata identical values are different keys ..
	--  ... so key children by lua string of concatenated values ... 6 1-byte characters

	-- challenge #1: find a set of 256 colors such that every tile is only 16 colors and there are only 16 sets of 16 colors used throughout the image

	-- first reduce each tile to only use 16 colors


-- option B: just quantize the whole picture into 256 colors:
elseif option == 'B' then


	local imageQuant256Filename = basefilename..'-256color.png'
	local imageQuant256, hist
	if not os.fileexists(imageQuant256Filename) then
		-- slow
		imageQuant256, hist = reduceColors(img, 256)
		imageQuant256:save(imageQuant256Filename)
	else
		imageQuant256 = Image(imageQuant256Filename)
		hist = buildHistogram(imageQuant256)
	end

	-- then split up the 256 color image into tiles, and group/reduce the palette colors across those tiles
	local tiles, tw, th = splitImageIntoTiles(imageQuant256, ts)

	for y=0,th-1 do
		for x=0,tw-1 do
			local tile = tiles[1 + x + tw * y]
			if tile then
				-- reduce each to 16 colors.  they're almost there.
				-- TODO make sure the reduceColors() algorithm REPLACE and doesn't CHANGE any colors
				-- right now that's what it does.
				-- otherwise this will get out of sync with our pic's overall 256 colors
				tile.img, tile.hist = reduceColors(tile.img, 16, tile.hist)
			end
		end
	end
				
	--print(x, y, #table.keys(tile.hist))	

	rebuildTiles(tiles, ts, tw, th):save(basefilename..'-256color-to-16color-tiles.png')

	-- ok now ... group our colors in 16 groups of 16 colors
	-- with bias for grouping by individual tiles' 16 colors
	-- (but not limited to -- esp if tiles have <16 colors
	-- and then 


-- option C - reduce an error function using a genetic algorithm
elseif option == 'C' then
	

	local tiles, tw, th = splitImageIntoTiles(img, ts)
	for _,tile in pairs(tiles) do
		tile.colors = table.keys(tile.hist):sort()
		tile.indexForColors = tile.colors:mapi(function(color,i) return i, color end)	-- 1-based index for each color, lookup into tile.colors
		assert(#tile.colors < 256)	-- i'm storing colors per tile as indexes, then mapping them to a low nibble using the tileColorMaps
	end

	-- low-nibble indexed version
	local indexedTiles = table.map(tiles, function(tile)
		return {
			img = tile.img:setChannels(1):clear()
		}
	end)

	for ty=0,th-1 do
		for tx=0,tw-1 do
			local tileIndex = 1 + tx + tw * ty
			local tile = tiles[tileIndex]
			if tile then
				local indexedImg = assert(indexedTiles[tileIndex]).img
				local src = tile.img.buffer
				local dst = indexedImg.buffer
				for ofs=0,ts*ts-1 do
					local srccolor = int8x8x8to24(src[0], src[1], src[2])
					dst[0] = assert(tile.indexForColors[srccolor])-1
					src = src + 3
					dst = dst + 1
				end
			end
		end
	end

	-- temporary destination rgb
	local tmptiles = table.map(tiles, function(tile) 
		return {
			img = tile.img:clone(),
		}
	end)

	local changeChance = .2

	local uid = 1
	
	local Unit = class()
	function Unit:init(src)
		self.uid = uid
		uid = uid + 1
		self.palette = ffi.new('uint8_t[?]', 3*256)
		self.tileHiMap = ffi.new('uint8_t[?]', tw*th)	-- per-tile of the high-nibble
		self.tileColorMaps = table.map(tiles, function(tile, tileIndex)
			return ffi.new('uint8_t[?]', #tile.colors, tileIndex)
		end)
		if src then
			ffi.copy(self.palette, src.palette, ffi.sizeof(self.palette))
			ffi.copy(self.tileHiMap, src.tileHiMap, ffi.sizeof(self.tileHiMap))
			for tileIndex,tileColorMap in pairs(self.tileColorMaps) do
				ffi.copy(tileColorMap, src.tileColorMaps[tileIndex], ffi.sizeof(tileColorMap))
			end
			
			-- and now permute each one by a bit
			
			-- skip 0,16, etc (they are transparent)
			for i=0,15 do
				for j=1,15 do
					if math.random() < changeChance then
						self.palette[0 + 3 * (j + 16 * i)] = math.clamp(self.palette[0 + 3 * (j + 16 * i)] + math.random(-15,15), 0, 255)
					end
					if math.random() < changeChance then
						self.palette[1 + 3 * (j + 16 * i)] = math.clamp(self.palette[1 + 3 * (j + 16 * i)] + math.random(-15,15), 0, 255)
					end
					if math.random() < changeChance then
						self.palette[2 + 3 * (j + 16 * i)] = math.clamp(self.palette[2 + 3 * (j + 16 * i)] + math.random(-15,15), 0, 255)
					end
				end
			end

			for i=0,tw*th-1 do
				if math.random() < changeChance then
					self.tileHiMap[i] = math.clamp(self.tileHiMap[i] + math.random(-3, 3), 0, 15)
				end
			end
			for tileIndex,tileColorMap in pairs(self.tileColorMaps) do
				for i=0,ffi.sizeof(tileColorMap)-1 do	-- == #tiles[tileIndex].colors-1
					if math.random() < changeChance then
						tileColorMap[i] = math.clamp(tileColorMap[i] + math.random(-3, 3), 0, 15)
					end
				end
			end
	
		else
			-- skip 0,16, etc (they are transparent)
			for i=0,15 do
				self.palette[0 + 16*i] = 0
				self.palette[1 + 16*i] = 0
				self.palette[2 + 16*i] = 0
				for j=1,15 do
					self.palette[0 + 3 * (j + 16 * i)] = math.random(0,255)
					self.palette[1 + 3 * (j + 16 * i)] = math.random(0,255)
					self.palette[2 + 3 * (j + 16 * i)] = math.random(0,255)
				end
			end

			for i=0,tw*th-1 do
				self.tileHiMap[i] = math.random(0,15)
			end
			for tileIndex,tileColorMap in pairs(self.tileColorMaps) do
				for i=0,ffi.sizeof(tileColorMap)-1 do	-- == #tiles[tileIndex].colors-1
					tileColorMap[i] = math.random(0,15)
				end
			end
		end
	end
	function Unit:calcFitness()
		if self.fitness then return self.fitness end
		local err = 0
		for ty=0,th-1 do
			for tx=0,tw-1 do
				local tileIndex = 1 + tx + tw * ty
				local tile = tiles[tileIndex]
				if tile then
					local tileColorMap = assert(self.tileColorMaps[tileIndex])
					local src = indexedTiles[tileIndex].img.buffer
					local dst = tmptiles[tileIndex].img.buffer
					local cmp = tile.img.buffer
					for ofs=0,ts*ts-1 do
						local colorindexintile = src[0]									-- should be within 0 to #tile.colors-1
						if colorindexintile < 0 or colorindexintile >= ffi.sizeof(tileColorMap) then
							error("got an oob indexed tile value: "..colorindexintile.." for tileColorMap size "..ffi.sizeof(tileColorMap).." and #tile.colors "..#tile.colors)
						end
						local colorindexlo = assert(tileColorMap[colorindexintile])			-- should be within 0 to 15
						local colorindexhi = assert(self.tileHiMap[tileIndex])			-- TODO you can sparely store tileHiMap next to tileColorMap
						local colorindex = bit.bor(bit.lshift(colorindexhi, 4), colorindexlo)	-- should be 0-255.  TODO store the hi bit shifted
						local color = self.palette + 3 * colorindex
						dst[0] = color[0]
						dst[1] = color[1]
						dst[2] = color[2]
						local dx = tonumber(dst[0]) - tonumber(cmp[0])
						local dy = tonumber(dst[1]) - tonumber(cmp[1])
						local dz = tonumber(dst[2]) - tonumber(cmp[2])
						err = err + .5 * (dx * dx + dy * dy + dz * dz)
						src = src + 1
						dst = dst + 3
						cmp = cmp + 3
					end
				end
			end
		end
		self.fitness = err
		return err
	end

	local percentToReproduce = .2
	local populationSize = 400
	local maxGenerations = math.huge
	local units = range(populationSize):mapi(function()
		local unit = Unit()
		unit:calcFitness()
		return unit
	end)

	local oldbest
	for generation=1,maxGenerations do
--print('gen '..generation)
		
		units:sort(function(a,b) return a.fitness < b.fitness end)
		local best = units[1]
		if best ~= oldbest then
			oldbest = best
			print(best.uid, best.fitness)
			-- force copy into tmptiles
			best.fitness = nil
			best:calcFitness()
			rebuildTiles(tmptiles, ts, tw, th):save('ga/'..best.uid..'.png')
		end

		for i=#units,populationSize+1,-1 do
			units[i] = nil
		end

		for i=1,math.ceil(populationSize*percentToReproduce) do
			local srcUnit = units[math.random(#units)]
			local newUnit = Unit(srcUnit)
			newUnit:calcFitness()
			units:insert(newUnit)
		end
	end

-- option D - same as option A but with a linear search for merging colors
elseif option == 'D' then
	
	local reduceColorsLinear = require 'reducecolorslinear'
	local buildHistogramQuantizationTransferMap = require 'buildhistqxfermap'

print'reducing each tile to 15 colors...'
	local targetPaletteSize = 15
	for _,tile in pairs(tiles) do
		tile.img, tile.hist = reduceColorsLinear(tile.img, targetPaletteSize, tile.hist)
	end
	rebuildTiles(tiles, ts, tw, th):save(basefilename..'-quant16linear.png')
	
	-- ok now quantize all the tile's palettes into 16 unique palettes
	do

print'creating palette histogram...'
		local palhist = {}
		for _,tile in pairs(tiles) do
			local histkeys = table.keys(tile.hist)
			
			--[[
			make all palettes equal size, for the quantizer
			TODO don't do this, instead allow for 
			 (1) dist calcs of varying-sized palettes (by closest-subsets)
			 (2) upon merging palettes...
			so for each palette pair, I should find the best match between palette entries ... time to abstract some histogram quantization operations ...
			--]]
			while #histkeys < 15 do histkeys:insert(1, 0) end
			
			local pal = histkeys:sort():mapi(function(c)
				local r,g,b = int24to8x8x8(c)
				return string.char(r,g,b)
			end):concat()
			tile.pal = pal
			palhist[pal] = (palhist[pal] or 0) + 1
		end
		for _,pal in ipairs(table.keys(palhist):sort()) do
			print(palhist[pal], bintohex(pal))
		end

print'reducing all palettes to only 16...'
		local fromto
		palhist, fromto = buildHistogramQuantizationTransferMap{
			hist = palhist,
			targetSize = 16,
			-- TODO replace with a more flexible distance
			-- also TODO abstract the distance return (object) and conversion to number so I can cache the coherency between palette pairs
			dist = require 'bindistsq',	
			merge = require 'binweightedmerge',
		}
		for _,tile in pairs(tiles) do
			local newpal = fromto[tile.pal]
			assert(newpal)
			-- now here, remap colors from til
		end
	end

-- new idea.  1) downsample the pic so 1 pixel = 1 tile, then quantize this pic to 16 colors, then create a map from downsampled colors to tiles, then combine each of these into 1 pic, quantize them each to 15 colors, viola
elseif option == 'E' then

	local img1pixpertile = img:resize(img.width / ts, img.height / ts)

else
	error'here'
end
