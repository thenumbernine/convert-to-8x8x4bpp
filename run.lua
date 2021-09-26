#! /usr/bin/env luajit
local ffi = require 'ffi'
local bit = require 'bit'
local table = require 'ext.table'
local range = require 'ext.range'
local class = require 'ext.class'
local tolua = require 'ext.tolua'
local Image = require 'image'

local filename = ... or 'map-tex-small-brighter.png'
local img = Image(filename)

-- alright, now to convert this into a 256-color paletted image such that no 8x8 tile uses more than 16 colors, and no set of 16 colors isn't shared or whatever
local ts = 8
assert(img.channels == 3)
assert(img.width % ts == 0)
assert(img.height % ts == 0)
local tw = math.floor(img.width / ts)
local th = math.floor(img.height / ts)
local tiles = table()

for y=0,th-1 do
	for x=0,tw-1 do
		local tileimg = img:copy{x=x*ts, y=y*ts, width=ts, height=ts}
		local hist = {}	-- key = 0xggbbrr
		for j=0,ts-1 do
			for i=0,ts-1 do
				local p = tileimg.buffer + 3 * (i + ts * j)
				local key = bit.bor(p[0], bit.lshift(p[1], 8), bit.lshift(p[2], 16))
				hist[key] = (hist[key] or 0) + 1
			end
		end
		local keys = table.keys(hist)
		-- all black <-> don't use
		if #keys == 1 and keys[1] == 0 then
			hist = {}
			keys = {}
		end
		if #keys > 0 then
			tiles[1 + x + tw * y] = {
				img = tileimg,
				hist = hist,
			}
		end
	end
end

local vector = require 'ffi.cpp.vector'

local Node = class()

Node.dim = 3

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


local Reduce = class()

function Reduce:init(args)
	local dim = assert(args.dim)
	local targetSize = assert(args.targetSize)

	self.nodeClass = class(Node)
	self.nodeClass.dim = dim
	self.nodeClass.splitSize = assert(args.splitSize)

	-- returns a value that can be uniquely mapped from 0..2^dim-1
	self.nodeClass.getChildIndex = assert(args.nodeGetChildIndex)
	
	--[[
	childIndex in 0..2^dim-1
	b in 0..dim-1
	--]]
	self.nodeClass.childIndexHasBit = assert(args.nodeChildIndexHasBit)

	local root = self.nodeClass{
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

-- quantize each tile into a 16-color palette
local targetPaletteSize = 16
for y=0,th-1 do
	for x=0,tw-1 do
		local tile = tiles[1 + x + tw * y]
		if tile then
			Reduce{
				dim = 3,
				targetSize = targetPaletteSize,
				minv = 0,
				maxv = 255,
				splitSize = 1,
				buildRoot = function(root)
					for k,v in pairs(tile.hist) do
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
					-- TODO convert 'tile' *HERE* into an indexed image
					for i=0,ts*ts-1 do
						local p = tile.img.buffer + 3 * i
						local key = bit.bor(p[0], bit.lshift(p[1], 8), bit.lshift(p[2], 16))
						key = fromto[key]
						p[0] = bit.band(0xff, key)
						p[1] = bit.band(0xff, bit.rshift(key, 8))
						p[2] = bit.band(0xff, bit.rshift(key, 16))
					end
					local newhist = {}
					for k,v in pairs(tile.hist) do
						local tokey = fromto[k]
						newhist[tokey] = (newhist[tokey] or 0) + v
					end
					tile.hist = newhist
					assert(#table.keys(tile.hist) <= targetPaletteSize)
				end,
			}
		end
	end
end

local imgEachTilePalQuantTo16 = img:clone():clear()
for y=0,th-1 do
	for x=0,tw-1 do
		local tile = tiles[1 + x + tw * y]
		if tile then		
			imgEachTilePalQuantTo16:pasteInto{x=x*ts, y=y*ts, image=tile.img}
		end
	end
end
local basefilename = filename:sub(1,-5)
imgEachTilePalQuantTo16:save(basefilename..'-quant.png')

-- now reduce all our palettes, count of up to (w/8) x (h/8) palettes, each with 16 unique colors,
-- down to 16 palettes with 16 colors
do
	local targetNumPalettes = 16
	local dim = 3*targetPaletteSize
	Reduce{
		dim = dim,
		targetSize = targetNumPalettes,
		minv = 0,
		maxv = 255,
		splitSize = 1,	-- if this is too small then I get a stackoverflow ... and if it's too big then the quantization all reduces to a single repeated tile
		buildRoot = function(root)
			for y=0,th-1 do
				for x=0,tw-1 do
					local tile = tiles[1 + x + tw * y]
					if tile then
						local pal = vector('double', dim)
						local keys = table.keys(tile.hist):sort()
						assert(#keys <= targetPaletteSize)
						for i,key in ipairs(keys) do
							pal.v[0 + 3 * (i-1)] = bit.band(0xff, key)
							pal.v[1 + 3 * (i-1)] = bit.band(0xff, bit.rshift(key, 8))
							pal.v[2 + 3 * (i-1)] = bit.band(0xff, bit.rshift(key, 16))
						end
print('root leaves', root:countleaves())
print('adding pal '..range(#pal):mapi(function(i) return pal.v[i-1] end):concat', ')
						root:addToTree{
							tile = tile,
							pal = pal,
						}
					end
				end
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
			-- ok now we can map pixel values and histogram keys via 'fromto'
			local fromto = {}
			for node in root:iter() do
				if node.pts then
					-- reduce to the first node in the list
					for _,pt in ipairs(node.pts) do
						-- if any square in the tilemap has tile pt.tile
						-- then replace it with tile pts[1].tile
						fromto[pt.tile] = node.pts[1].tile
					end
				end
			end
			for y=0,th-1 do
				for x=0,tw-1 do
					local index = 1 + x + tw * y
					local tile = tiles[index]
					if tile then
						-- TODO don't just replace tiles, instead remap palettes
						tiles[index] = fromto[tile]
					end
				end
			end
		end,
	}
end

local imgQuantizedTo16TilesW16ColorsEach = img:clone():clear()
for y=0,th-1 do
	for x=0,tw-1 do
		local tile = tiles[1 + x + tw * y]
		if tile then		
			imgQuantizedTo16TilesW16ColorsEach:pasteInto{x=x*ts, y=y*ts, image=tile.img}
		end
	end
end
local basefilename = filename:sub(1,-5)
imgQuantizedTo16TilesW16ColorsEach:save(basefilename..'-quant-16tiles.png')


-- now quantize each of the tile 16-color palettes (48-element vectors) into 16 unique palettes
-- ok 3-dim vectors means up to 2^3==8 children
-- so 48-dim vectors means up to 2^48 == 2.8147497671066e+14 children
-- so ... 1) load child table sparsely  and 2) key by something with 48 bits of precision (uint64_t eh? if you can key by cdata?  you can but it keys by the obj ptr, so two cdata identical values are different keys ..
--  ... so key children by lua string of concatenated values ... 6 1-byte characters

-- challenge #1: find a set of 256 colors such that every tile is only 16 colors and there are only 16 sets of 16 colors used throughout the image

-- first reduce each tile to only use 16 colors
