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

function Node:getChildIndex(pt)
	local k = bit.bor(
		pt.pos.v[0] >= self.mid.v[0] and 1 or 0,
		pt.pos.v[1] >= self.mid.v[1] and 2 or 0,
		pt.pos.v[2] >= self.mid.v[2] and 4 or 0)		
	k = k + 1
	return k
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
	k = k - 1	-- 1-based to 0-based for bitflag testing
	for j=0,self.dim-1 do
		if bit.band(k, bit.lshift(1,j)) == 0 then
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

function Node:insert(pt)
	if self.chs then
		local k = self:getChildIndex(pt)
		assert(not self.pts)
		self:getChildForIndex(k):insert(pt)
	else
		self.pts:insert(pt)
		if #self.pts > 1 then	-- split
			-- create upon request
			self.chs = {}
			local pts = self.pts
			self.pts = nil
			for _,pt in ipairs(pts) do
				self:insert(pt)
			end
		end
	end
end

local Reduce = class()

function Reduce:init(args)
	local src = args.src
	self.nodeClass = class(Node)
	local dim = assert(args.dim)
	self.nodeClass.dim = dim
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

	for k,v in pairs(src.hist) do
		root:insert{
			key = k,
			pos = vector('double', {
				bit.band(0xff, k),
				bit.band(0xff, bit.rshift(k, 8)),
				bit.band(0xff, bit.rshift(k, 16))
			}),
			weight = v,
		}
	end
	
	local function map(f, node)
		node = node or root
		f(node)
		if node.chs then
			for _,ch in pairs(node.chs) do
				map(f, ch)
			end
		end
	end
	local function countleaves()
		local n = 0
		map(function(node)
			if node.pts then
				n = n + 1
			end
		end)
		return n
	end
	local n = countleaves()
	if n > 16 then
		local all = table()
		map(function(node) all:insert(node) end)
		all:sort(function(a,b) return a.depth > b.depth end)
		
		local branches = table()
		map(function(node) if node.chs then branches:insert(node) end end)
		branches:sort(function(a,b) return a.depth > b.depth end)
		
		while n > 16 do
			local leaf = branches:remove(1)
			assert(leaf, "how did you remove branches nodes without losing branches points?!?!?!?!?!?!?!!?!?")
			leaf.pts = table.append(table.map(leaf.chs, function(ch, _, t) return ch.pts, #t+1 end):unpack())
			leaf.chs = nil
			n = countleaves()
		end
	end
		
	local fromto = {}
	map(function(node)
		if node.pts then
			-- reduce to the first node in the list
			for _,pt in ipairs(node.pts) do
				fromto[pt.key] = node.pts[1].key
			end
		end
	end)

	-- ok now we can map via 'fromto'
	for i=0,ts*ts-1 do
		local p = src.img.buffer + 3 * i
		local key = bit.bor(p[0], bit.lshift(p[1], 8), bit.lshift(p[2], 16))
		key = fromto[key]
		p[0] = bit.band(0xff, key)
		p[1] = bit.band(0xff, bit.rshift(key, 8))
		p[2] = bit.band(0xff, bit.rshift(key, 16))
	end
	local newhist = {}
	for k,v in pairs(src.hist) do
		local tokey = fromto[k]
		newhist[tokey] = (newhist[tokey] or 0) + v
	end
	src.hist = newhist
end

-- quantize each tile into a 16-color palette
local dst = img:clone():clear()
for y=0,th-1 do
	for x=0,tw-1 do
		local tile = tiles[1 + x + tw * y]
		if tile then
--			print('x', x, 'y', y, 'hist count', #table.keys(tile.hist))
			Reduce{src=tile, dim=3, minv=0, maxv=255}
			dst:pasteInto{x=x*ts, y=y*ts, image=tile.img}
		end
	end
end
local basefilename = filename:sub(1,-5)
dst:save(basefilename..'-quant.png')



-- now quantize each of the tile 16-color palettes (48-element vectors) into 16 unique palettes
-- ok 3-dim vectors means up to 2^3==8 children
-- so 48-dim vectors means up to 2^48 == 2.8147497671066e+14 children
-- so ... 1) load child table sparsely  and 2) key by something with 48 bits of precision (uint64_t eh? if you can key by cdata?  you can but it keys by the obj ptr, so two cdata identical values are different keys ..
--  ... so key children by lua string of concatenated values ... 6 1-byte characters

-- challenge #1: find a set of 256 colors such that every tile is only 16 colors and there are only 16 sets of 16 colors used throughout the image

-- first reduce each tile to only use 16 colors
