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

local reduceColorsOn2 = require 'reducecolorson2'
local reduceColorsOctree = require 'reducecolorsoctree'
local reduceColorsImageMagick = require 'reducecolorsimagemagick'
local reduceColorsMedianCut = require 'reducecolorsmediancut'
local buildColorMapOctree = require 'buildcolormapoctree'
local buildColorMapMedianCut = require 'buildcolormapmediancut'
local buildHistogram = require 'buildhistogram'
local bintohex = require 'bintohex'
local binweightedmerge = require 'binweightedmerge'

-- map-tex-small.png is made from map-tex.png of super-metroid-randomizer, then box average downsample by 1/32 such that 8x8 pixels is 1 region map block
-- map-tex-small-brighter.png is made from map-tex-small.png, then in Gimp adjust color levels, input=75, output=180 or so, plus or minus
local filename = ... or 'map-tex-small-brighter.png'
local img = Image(filename):setChannels(3)
local basefilename = filename:sub(1,-5)

Image.hsvToRgb = require 'imghsvtorgb'
Image.rgbToHsv = require 'imgrgbtohsv'

-- [[ testing out my reduceColors methods.  rgb seems to work better than hsv.
--reduceColorsOn2{img=img:rgbToHsv(), targetSize=16}:hsvToRgb():save'test-quant-octree.png'				-- very very slow
--reduceColorsOctree{img=img:rgbToHsv(), targetSize=16}:hsvToRgb():save'test-quant-octree-hsv.png'		-- very slow
reduceColorsOctree{img=img, targetSize=16}:save'test-quant-octree.png'								-- very slow
--reduceColorsMedianCut{img=img, targetSize=16, mergeMethod='replaceRandom'}:save'test-quant-mediancut-replaceRandom.png'
--reduceColorsMedianCut{img=img, targetSize=16, mergeMethod='replaceHighestWeight'}:save'test-quant-mediancut-replaceHighestWeight.png'
--reduceColorsMedianCut{img=img, targetSize=16, mergeMethod='weighted'}:save'test-quant-mediancut-weighted.png'
--reduceColorsMedianCut{img=img:rgbToHsv(), targetSize=16, mergeMethod='replaceRandom'}:hsvToRgb():save'test-quant-mediancut-replaceRandom-hsv.png'
--reduceColorsMedianCut{img=img:rgbToHsv(), targetSize=16, mergeMethod='replaceHighestWeight'}:hsvToRgb():save'test-quant-mediancut-replaceHighestWeight-hsv.png'
--reduceColorsMedianCut{img=img:rgbToHsv(), targetSize=16, mergeMethod='weighted'}:hsvToRgb():save'test-quant-mediancut-weighted-hsv.png'
--reduceColorsImageMagick{img=img, targetSize=16}:save'test-quant-imagemagick.png'	-- fast
os.exit()
--]]


--[[
TODO algo:
1) chop up pic into 8x8 tiles
2) reduce tiles to 1px
3) quantize resulting colors into 16 colors.  only use hue? or HS? or HSV?
4) quantize each tile ... by gradient pyramdi? DoG pyramid?  reduce to # of tiles desiresd .. 768 max, 80 free in the tileset.
		maybe somehow merge and rebuild the averaged tiles?
5) for each tile, match each rgb color to the associated 16-color palette previously associated with this tile.
--]]

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
			if #keys == 1 and keys[1] == string.char(0,0,0) then
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


-- taken from super-metroid-randomizer/sm-graphics.lua
-- expects the image to be one column, and one tile per row
local function graphicsWrapRows(
	srcImg,
	tileHeight,
	numDstTileCols
)
	local channels = srcImg.channels
	local tileWidth = srcImg.width
	local numSrcTileRows = math.ceil(srcImg.height / tileHeight)
	local numDstTileRows = math.ceil(numSrcTileRows / numDstTileCols)
	local sizeofChannels = channels * ffi.sizeof(srcImg.format)
	local dstImg = Image(
		tileWidth * numDstTileCols,
		tileHeight * numDstTileRows,
		channels,
		srcImg.format)
	dstImg:clear()
	for j=0,numDstTileRows-1 do
		for i=0,numDstTileCols-1 do
			for k=0,tileHeight-1 do
				local srcY = k
					+ i * tileHeight
					+ j * tileHeight * numDstTileCols
				if srcY < srcImg.height then
					local dstX = tileWidth * i
					local dstY = k + tileHeight * j
					ffi.copy(
						dstImg.buffer + channels * (dstX + dstImg.width * dstY),
						srcImg.buffer + channels * (srcImg.width * srcY),
						sizeofChannels * tileWidth)
				end
			end
		end
	end
	return dstImg
end

local function removeLumInPlace(p)
	p[0], p[1], p[2] = (vec3d(p[0], p[1], p[2]):normalize() * 255):map(math.floor):unpack()
end

local greyweights = vec3d(.3, .55, .15)
local planes = table()
for i=0,2 do
	for j=0,1 do
		local v = vec3d()
		v.s[i] = 2*j-1
		local p = vec3d(1-j,1-j,1-j)
		local w = -p:dot(v)
		planes:insert{v=v, w=w}
	end
end	
local function removeSatLumInPlace(p)
	local c = vec3d(p[0], p[1], p[2]):normalize()
	local l = c:dot(greyweights)
	local a = vec3d(l,l,l)
	local b = c - a
	-- v + s * d, s >= 0, intersect with [0,1] cube
	-- (a + s * b) = point on line, intersect with a plane (v, w) where a dot v + w = 0, w = -v dot p, p = point on plane, such that p dot v + w = p dot v + (-p dot v) = 0
	-- (a + s * b) dot v + w = 0 <=> a dot v + s * b dot v = -w <=> s = -(w + a dot v) / (b dot v)
	local bests = math.huge
	for _,plane in ipairs(planes) do
		local s = -(plane.w + plane.v:dot(a)) / b:dot(plane.v)
		if s >= 0 and s < bests then
			bests = s
		end
	end
	local v = a + b * bests
	p[0], p[1], p[2] = v:map(function(x) return math.clamp(math.floor(x * 255), 0, 255) end):unpack()
end

-- i might have SatVal and SatLum names mixed up
local function removeSatValInPlace(p)
	local v = vec3d(p[0], p[1], p[2])
	v = v * (255 / v:lInfLength())
	p[0], p[1], p[2] = v:map(math.floor):unpack()
end

local function flipHorizontal(src)
	local dst = src:clone()
	for y=0,src.height-1 do
		for x=0,src.width-1 do
			ffi.copy(
				dst.buffer + src.channels * (x + src.width * y),
				src.buffer + src.channels * (src.width - 1 - x + src.width * y),
				src.channels * ffi.sizeof(src.format))
		end
	end
	return dst
end

local function flipVertical(src)
	local dst = src:clone()
	for y=0,src.height-1 do
		for x=0,src.width-1 do
			ffi.copy(
				dst.buffer + src.channels * (x + src.width * y),
				src.buffer + src.channels * (x + src.width * (src.height - 1 - y)),
				src.channels * ffi.sizeof(src.format))
		end
	end
	return dst
end

--[[
ok now I have too many tiles ... 1303 versus a max possible of 768 in the tileset, or only about 80 or so if you only want to use map+free tiles in the tileset
now to reduce those
how to reduce those
for each tile, make a 7x7 luminance gradient image, then quantize those
	
ok now I'm reducing the palettes LATER -- first reduce the # of unique 8x8 RGB tiles
but quantizing tiles in RGB *FIRST* then quantizing palettes LATER ... that forces a 1-1 mapping between tiles (lower 4bpp) and the upper 4bpp

TODO now, how to quantize *ONLY* the lower 4bpp ... esp if you consider merges of tiles, how to equate palettes?

TODO right now this is destructive to 'tiles' ... make it return based
--]]
local function quantizeTiles(args)
	local targetSize = assert(args.targetSize)
	
	local tilesForCmpImgStrs = {}
	local function pickRandomTile(newCmpImgStr)
		local newtiles = tilesForCmpImgStrs[newCmpImgStr]
		return newtiles[math.random(#newtiles)].img:clone()
	end
	local function strToRGB(newCmpImgStr)
		local newimg = Image(ts,ts,3,'unsigned char')
		ffi.copy(newimg.buffer, ffi.cast('char*', newCmpImgStr), ts*ts*3)
		return newimg
	end

	local offsets = {{1,0},{0,1}}
	local tileCompareMethods = {
		greyscaleGradient = {
			cmpImgStr = function(img)
				local greyimg = img:greyscale()
				local cmpimg = Image(ts-1, ts-1, 2, 'char')
				local p = cmpimg.buffer
				for j=0,ts-2 do
					for i=0,ts-2 do
						for side,ofs in ipairs(offsets) do
							p[0] = greyimg.buffer[i + ofs[1] + ts * (j + ofs[2])] - greyimg.buffer[i + ts * j]
							p = p + 1
						end
					end
				end		
				return ffi.string(cmpimg.buffer, cmpimg.channels * cmpimg.width * cmpimg.height)
			end,
			mergeMethod = 'replaceHighestWeight',
			reconstruct = pickRandomTile,
		},
		rgbGradient = {
			cmpImgStr = function(img)
				local greyimg = img:greyscale()
				local cmpimg = Image(ts-1, ts-1, 6, 'char')
				local p = cmpimg.buffer
				for j=0,ts-2 do
					for i=0,ts-2 do
						for k=0,2 do
							for side,ofs in ipairs(offsets) do
								p[0] = img.buffer[k + 3 * (i + ofs[1] + ts * (j + ofs[2]))] - img.buffer[k + 3 * (i + ts * j)]
								p = p + 1
							end
						end
					end
				end
				return ffi.string(cmpimg.buffer, cmpimg.channels * cmpimg.width * cmpimg.height)
			end,
			mergeMethod = 'replaceHighestWeight',
			reconstruct = pickRandomTile,
		},
		greyscaleCurvature = {
			cmpImgStr = function(img)
				local cmpimg = img:greyscale():curvature()
				return ffi.string(cmpimg.buffer, cmpimg.channels * cmpimg.width * cmpimg.height)
			end,
			mergeMethod = 'replaceHighestWeight',
			reconstruct = pickRandomTile,
		},
		rgbCurvature = {
			cmpImgStr = function(img)
				local cmpimg = Image.combine(table{img:split()}:mapi(function(img)
					return img:curvature()
				end):unpack())
				return ffi.string(cmpimg.buffer, cmpimg.channels * cmpimg.width * cmpimg.height)
			end,
			mergeMethod = 'replaceHighestWeight',
			reconstruct = pickRandomTile,
		},
		-- [[ TODO hsv curvature
		--]]
		-- pyramids of some kind ... difference pyramids maybe?  in HSL maybe ... 8, 4, 2, 1
		greyscaleCurvaturePyramids = {
			cmpImgStr = function(img)
				local cmpimg = img:greyscale():curvature()
				local cmpImgStr = ''
				while cmpimg.width >= 1 and cmpimg.height >= 1 do
					cmpImgStr = cmpImgStr .. ffi.string(cmpimg.buffer, cmpimg.channels * cmpimg.width * cmpimg.height)
					cmpimg = cmpimg:resize(cmpimg.width/2, cmpimg.height/2)
				end
				return cmpImgStr 
			end,
			mergeMethod = 'replaceHighestWeight',
			reconstruct = pickRandomTile,
		},
		original = {
			cmpImgStr = function(img)
				local cmpimg = img:clone()
				return ffi.string(cmpimg.buffer, cmpimg.channels * cmpimg.width * cmpimg.height)
			end,
			--mergeMethod = 'weighted',	-- doesn't look good
			mergeMethod = 'replaceHighestWeight',
			reconstruct = strToRGB,
		},
		originalPyramid = {
			cmpImgStr = function(img)
				local cmpimg = img:clone()
				local cmpImgStr = ''
				local rep = 1
				while cmpimg.width >= 1 and cmpimg.height >= 1 do
					local s = ffi.string(cmpimg.buffer, cmpimg.channels * cmpimg.width * cmpimg.height)
					cmpImgStr = cmpImgStr .. s
						-- repeat to have higher pyramid levels equally weighted as lower? 
						-- that might make a difference when doing octree node collapsing and using a distance function, but with median-cut it makes no difference 
						-- the distance along unique dimensions will be the same regardless of the # of duplicated dimensions
						--.. s:rep(rep)	
					cmpimg = cmpimg:resize(cmpimg.width/2, cmpimg.height/2)
					rep = rep * 4
				end
				return cmpImgStr 
			end,
			
			-- can do, but looks uglier.  has a more definite tile look
			-- maybe if I averaged graident-space and reconstructed, it'd look better?
			-- I keep saying that, but if I average gradient-space, then what boundaries can I use to rebuild it? 
			-- the boundaries will either have to be picked as a distinct tile, or will have to be averaged too,
			-- and if the grad and boundaries are both averaged, how is it dif than just averaging the rgb?
			--mergeMethod = 'weighted', 
			
			-- looks better
			-- but if we're using replace as the merge method, why not use a merge technique that matches visual quality better, like curvature or gradient magnitude?
			mergeMethod = 'replaceHighestWeight',
			
			reconstruct = strToRGB,
		},
		greyscalePyramid = {
			cmpImgStr = function(img)
				local cmpimg = img:greyscale():rgb()
				local cmpImgStr = ''
				local rep = 1
				while cmpimg.width >= 1 and cmpimg.height >= 1 do
					local s = ffi.string(cmpimg.buffer, cmpimg.channels * cmpimg.width * cmpimg.height)
					cmpImgStr = cmpImgStr .. s
						-- repeat to have higher pyramid levels equally weighted as lower? 
						-- that might make a difference when doing octree node collapsing and using a distance function, but with median-cut it makes no difference 
						-- the distance along unique dimensions will be the same regardless of the # of duplicated dimensions
						--.. s:rep(rep)	
					cmpimg = cmpimg:resize(cmpimg.width/2, cmpimg.height/2)
					rep = rep * 4
				end
				return cmpImgStr 
			end,
			
			--mergeMethod = 'weighted', 
			mergeMethod = 'replaceHighestWeight',
		
			-- if we're greyscale then reconstructing doesn't work so well
			-- this is where our distinct 4bits per tile come in handy
			reconstruct = pickRandomTile,
			--reconstruct = strToRGB,
		},
	}

	-- [[ use greyscale tiles for determining tile quantization?  
	-- and then later use color for palette quantization
	tiles, tw, th = splitImageIntoTiles(img:greyscale():rgb(), ts)
	--]]
	--[[ or use gradient magnitude?
	local imggrey = img:greyscale()
	tiles, tw, th = splitImageIntoTiles(Image.combine(imggrey:gradient()):l2norm():rgb(), ts)
	--]]

	--local tileCompareMethod = tileCompareMethods.greyscaleGradient
	--local tileCompareMethod = tileCompareMethods.greyscaleCurvature
	--local tileCompareMethod = tileCompareMethods.greyscaleCurvaturePyramids 	-- not so much
	--local tileCompareMethod = tileCompareMethods.original
	local tileCompareMethod = tileCompareMethods.originalPyramid
	--local tileCompareMethod = tileCompareMethods.greyscalePyramid

	for _,tile in pairs(tiles) do
		-- to make this invariant wrt flipping horizontal and vertical ... flip the image horz, then vert, then both
		-- then of the four image strings, sort them (so that matching flips will match)
		-- however ... will this still accurately compare between flips?
		tile.cmpImgStrs = table()
		for _,hflip in ipairs{false,true} do
			for _,vflip in ipairs{false,true} do
				local img = tile.img:clone()
				if hflip then img = flipHorizontal(img) end
				if vflip then img = flipVertical(img) end
				local cmpImgStr = tileCompareMethod.cmpImgStr(img)
				
				-- since I'm quantizing using median-cut, the median-cut doesn't use a distance function to group them, so nevermind custom distances that consider all combinations of horz and vert flip
				-- in fact, in concatenating the string of each flip and then doing median-cut of that string's bytes as a vector space, there's a risk that I'll ignore dimensions that group some tiles better
				--  for the reason, maybe entering all flips of a tile is better than combining tiles?
				tilesForCmpImgStrs[cmpImgStr] = tilesForCmpImgStrs[cmpImgStr] or table()
				tilesForCmpImgStrs[cmpImgStr]:insert(tile)
			
				tile.cmpImgStrs:insert{
					str = cmpImgStr,
					hflip = hflip,
					vflip = vflip,
				}
			end
		end
	end

	local tileCmpImgHist = table.map(tilesForCmpImgStrs, function(tiles) return #tiles end):setmetatable(nil)
	-- don't use median cut, that will just pick one pixel in one miplevel and sort by its one value
	local fromto = buildColorMapMedianCut{
	-- instead do something that merges by distance between points
	--local fromto = buildColorMapOctree{
		hist = tileCmpImgHist,
		targetSize = targetSize,	-- target number of tiles
		
		-- directly replace the more popular point.  this way all target colors are among the source colors.
		-- if you do average the replacement then get ready to rebuild the 8x8 pic using gauss seidel inverse laplacian ... very tempting since it'll be quick ...
		-- TODO rebuild the tile 8x8x3 image from the gradient
		mergeMethod = tileCompareMethod.mergeMethod,
	}
		
	--[[
	if we do average instead of replace
	then, for tile quantization after color quantization, I'll need to restrict new merged tiles to only use the palette of the old tiles
	but instead, I think I should be doing tile quantization before color quanitzation
	--]]

	local bindistsq = require 'bindistsq'
	for _,tile in pairs(tiles) do
		local bestNewCmpImgStr
		local bestIndex
		local bestDist
		for index,cmpImgStr in ipairs(tile.cmpImgStrs) do
			local newCmpImgStr = fromto[cmpImgStr.str]
			local dist = bindistsq(newCmpImgStr, cmpImgStr.str)
			if not bestDist or dist < bestDist then
				bestDist = dist
				bestNewCmpImgStr = newCmpImgStr
				bestIndex = index
			end
		end
		
		-- TODO a better solution might be rebuild the image based on the newCmpImg
		-- some gauss seidel using the boundary conditions (like my gradient based copy paste trick)
		tile.img = tileCompareMethod.reconstruct(bestNewCmpImgStr)
		if tile.cmpImgStrs[bestIndex].vflip then
			tile.img = flipVertical(tile.img)
		end
		if tile.cmpImgStrs[bestIndex].hflip then
			tile.img = flipHorizontal(tile.img)
		end
		-- TODO if I am now matching against all flips ... determine which one matched the source image best.
	end

	-- [[ debug - show the resulting tiles
	local quantizedTiles = table.map(fromto, function(v,k) 
		return true, v
	end):keys():sort():map(function(newCmpImgStr)
		return tileCompareMethod.reconstruct(newCmpImgStr)
	end)
	print('#quantized Tiles', #quantizedTiles)
	local tmpimg = Image(ts, ts * #quantizedTiles, 3, 'unsigned char')
	for i,img in ipairs(quantizedTiles) do
		tmpimg:pasteInto{x=0, y=ts*(i-1), image=img}
	end
	graphicsWrapRows(tmpimg, ts, 32):save(basefilename..'-quantized-tiles.png')
	--]]

	-- [[ debug - show a map of the resulting tiles, and their source tiles
	local tofroms = {}
	for from,to in pairs(fromto) do
		tofroms[to] = tofroms[to] or table()
		tofroms[to]:insert(from)
	end
	local tos = table.keys(tofroms):sort()
	local tmpimg = Image(
		ts * (tos:mapi(function(to) return #tofroms[to] end):sup() + 1) + 4,
		ts * #tos,
		3, 'unsigned char')
	for j,to in ipairs(tos) do
		local froms = tofroms[to]
		tmpimg:pasteInto{
			x=0,
			y=(j-1) * ts,
			image = tileCompareMethod.reconstruct(to),
		}
		for i,from in ipairs(froms) do
			tmpimg:pasteInto{
				x=i * ts + 4,
				y=(j-1) * ts,
				image = tileCompareMethod.reconstruct(from),
			}
		end
	end
	tmpimg:save(basefilename..'-quantize-tile-map.png')
	--]]
end

-- quantize first ... but this locks in a 1-1 betwen upper nibbles and unique tiles ...
--quantizeTiles{targetSize=math.huge}
quantizeTiles{targetSize=768}
--quantizeTiles{targetSize=256}
--quantizeTiles{targetSize=80}
rebuildTiles(tiles, ts, tw, th):save(basefilename..'-16tiles-16colors-dsqa-quant-tiles-before.png')

--[[
TODO
for quantizing tiles separate of palettes, I am using the current trick of 
1) quantize (and possibly average) tiles 
2) quantize downsampled to 16 colors to create 16 unique palettes
3) cluster tiles by palette, quantize colors to 15 to create each gruop's palette
... but this locks in 1 palette per tile
i should want to keep the two separately
so here's the new idea


--]]


-- still seeing too many final images get dark ... 
--[[ maybe I should remove lum up front? nah, too bright
do
	local p = img.buffer
	for i=0,img.width*img.height-1 do
		removeLumInPlace(p)
		p = p + 3
	end
end
tiles, tw, th = splitImageIntoTiles(img, ts)
--]]
--[[ remove lum and sat up front? 
do
	local p = img.buffer
	for i=0,img.width*img.height-1 do
		removeSatLumInPlace(p)
		p = p + 3
	end
	-- seems to draw out some extra tiles and make our tile count not match up ...
	local blankTile = Image(ts, ts, 3, 'unsigned char'):clear()
	for y=0,th-1 do
		for x=0,tw-1 do
			if not tiles[1 + x + tw * y] then
				img:pasteInto{image=blankTile, x=x*ts, y=y*ts}
			end
		end
	end
	-- this doesn't fix that... hmm...
	-- oh well, the before-downsample looks as bad as it does with removing lum alone
end
tiles, tw, th = splitImageIntoTiles(img, ts)
--]]

print'sizing down image...'
--[[
local img1pixpertile = img:resize(img.width / ts, img.height / ts)
--]]
-- [=[ need to remove the black tiles
local img1pixpertile = Image(ts, ts*#table.keys(tiles), 3, 'unsigned char')
local img1pixelIndexToXY = table()
for y=0,th-1 do
	for x=0,tw-1 do
		local tileIndex = 1 + x + tw * y
		local tile = tiles[tileIndex]
		if tile then
			img1pixpertile:pasteInto{
				x = 0,
				y = #img1pixelIndexToXY * ts,
				-- if you use tile.img and it was tile-quantized then you are using a tile different from the original image 
				-- (and subsequently a color different from the original image color)
				--image = tile.img,
				-- so instead, copy the subregion straight out of the image here
				image = img:copy{x=x*ts, y=y*ts, width=ts, height=ts}
				-- HOWEVER IF YOU DO THIS then you no longer have distinct tiles - you will increase your # of distinct tiles as some get shifted to one palette and some shift to another
				-- unless, somehow I reduce the tiles to 4bpp and then match their indexes to all palettes that they use ... sounds tough
				-- might help if I make some generalizations about my palettes .. like have one palette per hue and sort their colors by lum, and then map tile rgb to 4bpp indexes, and hope the coherency beteween tiles makes them "just work" as the palettes are switched 
			}
			img1pixelIndexToXY:insert{x,y}
		end
	end
end

-- show the tiles as wrapped rows
graphicsWrapRows(img1pixpertile, ts, 32):save(basefilename..'-1pix-per-tile-before-downsample.png') 

-- downsample
img1pixpertile = img1pixpertile:resize(img1pixpertile.width / ts, img1pixpertile.height / ts)

local function convertDownsampledTileSeqToImg(img1pixpertile)
	local temp = Image(tw, th, 3, 'unsigned char'):clear()
	assert(img1pixpertile.height == #img1pixelIndexToXY)
	assert(img1pixpertile.width == 1)
	assert(img1pixpertile.channels == 3)
	assert(img1pixpertile.format == 'unsigned char')
	for i,xy in ipairs(img1pixelIndexToXY) do
		local x, y = table.unpack(xy)
		assert(x >= 0 and x < tw and y >= 0 and y < th)
		local src = img1pixpertile.buffer + 3 * (i-1)
		local dst = temp.buffer + 3 * (x + tw * y)
		ffi.copy(dst, src, 3)
	end
	return temp
end
convertDownsampledTileSeqToImg(img1pixpertile):save(basefilename..'-1pix-per-tile-after-downsample.png')

--local invWeightMerge = true
local invWeightMerge = false

-- [[ without tweaking downsampled colors
local img1pixpertilefilename = 'img1pixpertilefilename-cache.png'..(invWeightMerge and '-invweight' or '')
--]]
--[[ even with linear search of closest downsampled colors per tile (which takes 12 mins), i'm still getting a lot of clustering together of darker tiles, whether they are predominantly green, red, pink, etc
-- so instead, how about here we look at only hue? or only hue and saturation (i.e. just normalize the color vector)
-- with this, removing lum only (just 'normalize')
local img1pixpertilefilename = 'img1pixpertilefilename'..(invWeightMerge and '-invweight' or '')..'-cache-removing-lum.png'
do
	local p = img1pixpertile.buffer
	for i=0,img1pixpertile.width-1 do
		removeLumInPlace(p)
		p = p + 3
	end
end
--]]
--[[ with this, removing both lum and sat ('normalize', then project outward from (l,l,l) grey line)
local img1pixpertilefilename = 'img1pixpertilefilename'..(invWeightMerge and '-invweight' or '')..'-cache-removing-lum-and-sat.png'
do
	local p = img1pixpertile.buffer
	for i=0,img1pixpertile.width-1 do
		removeSatLumInPlace(p)
		p = p + 3
	end
end
--]]
--[[
local img1pixpertilefilename = 'img1pixpertilefilename'..(invWeightMerge and '-invweight' or '')..'-cache-removing-val-and-sat.png'
do
	local p = img1pixpertile.buffer
	for i=0,img1pixpertile.width-1 do
		removeSatValInPlace(p)
		p = p + 3
	end
end
--]]
if img1pixpertile.height ~= #img1pixelIndexToXY then
	error("expected img1pixpertile.height =="..img1pixpertile.height.." to equal #img1pixelIndexToXY=="..#img1pixelIndexToXY)
end
assert(img1pixpertile.width == 1)
--]=]

-- output a debug image
convertDownsampledTileSeqToImg(img1pixpertile):save(basefilename..'-1pix-per-tile-after-color-adjust.png')

print'quantizing to 16 colors...'
local hist

local function progress(percent, s, numColors)
	print(('%d%%'):format(100*percent), s..'s', 'numColors='..numColors)
end

--[[ using my slow methods
-- linear goes slow for this sized pic, cuz it is O(n^2) ... takes 12 mins for reducing 1200 colors
if os.fileexists(img1pixpertilefilename) then
	img1pixpertile = Image(img1pixpertilefilename)
	hist = buildHistogram(img1pixpertile)
else
	img1pixpertile, hist = reduceColorsOn2{
		img = img1pixpertile,
		targetSize = 16,	-- 16 unique palettes
		progress = progress,
		merge = invWeightMerge 
			and function(a,b,s,t)
				s, t = 1/s, 1/t
				sum = s + t
				return binweightedmerge(a, b, s/sum, t/sum)
			end
			or binweightedmerge,
	}
	img1pixpertile:save(img1pixpertilefilename)
end
--]]
--[[ octree seems to group all the tiles up to the first entry ... hmm, why is this ...
-- TODO instead of merging octree leafs (which gives ugly performance), do a legit nearest search, start with the deepest and closest nodes, prune nodes too far away, and also re-insert the weighted merged point instead of just replacing points 
-- then this would have better performance but same results as the linear search
img1pixpertile, hist = reduceColorsOctree{img=img1pixpertile, targetSize=16}	-- 16 unique palettes
--]]
--[[ using imagemagick
img1pixpertile, hist = reduceColorsImageMagick{img=img1pixpertile, targetSize=16}	-- 16 unique palettes
--]]
-- [[
img1pixpertile, hist = reduceColorsMedianCut{img=img1pixpertile, targetSize=16}	-- 16 unique palettes
--]]

-- output a debug image
convertDownsampledTileSeqToImg(img1pixpertile):save(basefilename..'-1pix-per-tile-after-quant.png')

-- now for each unique color, make a list of all tiles, put them into the same image, and quantize that image
local colors = table.keys(hist):sort()
print'palette:'
for _,color in ipairs(colors) do
	print('',vec3ub(color:byte(1,3)))
end
local indexForColor = colors:mapi(function(key,i) return i-1,key end)	-- map from 24-bit color to 0-based index
print'grouping tiles by downsampled image unique 16-color quantization...' 
local tilesForColor = range(16):mapi(function() return table() end)
local p = img1pixpertile.buffer
for i,xy in ipairs(img1pixelIndexToXY) do
	local x,y = table.unpack(img1pixelIndexToXY[i])
	local color = ffi.string(p, 3)
	local index = indexForColor[color]
	local ctiles = tilesForColor[index+1]
	if not index or not ctiles then
		error("couldn't find index for color "..vec3ub(color:byte(1,3)))
	end
	local tileIndex = 1 + x + tw * y
	ctiles:insert{
		x = x,
		y = y,
		-- use original image
		img = img:copy{x=x*ts, y=y*ts, width=ts, height=ts},
		-- use current tile - needed for tile-quantization-before
		-- but these aren't stored for solid-black, so ...
		--img = tiles[tileIndex] and tiles[tileIndex].img:clone() or Image(ts,ts,3,'unsigned char'):clear(),
	}
	p = p + 3
end

local finalPalette = Image(16,16,3,'unsigned char'):clear()
local numTiles = tilesForColor:mapi(function(ctiles) return #ctiles end):sum()
print('we have a total of '..numTiles..' tiles')
for j,ctiles in ipairs(tilesForColor) do
print('high-nibble '..(j-1)..' has '..#ctiles..' tiles')
	local timg = Image(ts, #ctiles * ts, 3, 'unsigned char')
	for i,tile in ipairs(ctiles) do
		timg:pasteInto{image=tile.img, x=0, y=(i-1)*ts}
	end
	if #ctiles > 0 then
		local wrapped = graphicsWrapRows(timg, ts, 16)
		wrapped:save('color '..(j-1)..' tiles.png')
	end
	
	-- now quantize each img-per-regionmap palette into 15 colors
	--local qimg = reduceColorsOn2{img=timg, targetSize=15, progress=progress}	-- if 1200 -> 16 points above took 12 mins, this is 3000 points .. soo  .... much longer 
	--local qimg, hist = reduceColorsOctree{img=timg, targetSize=15}	-- ugly, as octree search is ugly atm. TODO fixme, do a real search (not approximate) and real merge (re-insert, don't just remove/replace points), use octree for pruning
	--local qimg, hist = reduceColorsImageMagick{img=timg, targetSize=15}
	local qimg, hist = reduceColorsMedianCut{img=timg, targetSize=15}

	if #ctiles > 0 then
		local wrapped = graphicsWrapRows(qimg, ts, 16)
		wrapped:save('color quant15 '..(j-1)..' tiles.png')
	end
	-- now that the imgs have been quantized as well, paste everything back together
	for i,tile in ipairs(ctiles) do
		assert((i-1)*ts < qimg.height)
		local tileIndex = 1 + tile.x + tw * tile.y
		local tileimg = qimg:copy{x=0, y=(i-1)*ts, width=ts, height=ts}
		tiles[tileIndex].img = tileimg
	end
	
	local p = finalPalette.buffer + 3 * 16 * (j-1)
	for i,c in ipairs(table.keys(hist):sort()) do
		ffi.copy(p, ffi.cast('unsigned char*', c), 3)
		p = p + 3
	end
end

rebuildTiles(tiles, ts, tw, th):save(basefilename..'-16tiles-16colors-dsqa.png')	-- dsqa = "downsample quanization association of tiles"
finalPalette:save(basefilename..'-dsqa-palette.png')

--[=[ quantize last ... but using 'replace' merge looks ugly, and any sort of averaging will screw up the unique palettes per tile that had just been established
-- [[
quantizeTiles{targetSize=768}
rebuildTiles(tiles, ts, tw, th):save(basefilename..'-16tiles-16colors-dsqa-quanttiles768after.png')
--]]
--[[
quantizeTiles{targetSize=256}
rebuildTiles(tiles, ts, tw, th):save(basefilename..'-16tiles-16colors-dsqa-quanttiles256after.png')
--]]
--[[
quantizeTiles{targetSize=80}
rebuildTiles(tiles, ts, tw, th):save(basefilename..'-16tiles-16colors-dsqa-quanttiles80after.png')
--]]
--]=]



print'done'
