--[[
TODO replace 24-bit integer keys with 3-byte string keys
and then replace vec3ub with the strings
and vec3d with vector'double'
and then generalize by dimension
--]]
local table = require 'ext.table'
	
local buildHistogramQuantizationTransferMap = require 'buildhistqxfermap'
local applyHistogramQuantizationTransferMap = require 'applyhistqxfermap'

-- size = how many bytes to use
local function inttobin(i, size)
	local s = ''
	for j=1,size do
		s = s .. string.char(bit.band(0xff, i))
		i = bit.rshift(i, 8)
	end
	return s
end

local function bintoint(s)
	local i = 0
	for j=#s,1,-1 do
		i = bit.bor(bit.lshift(i, 8), s:byte(j,j))
	end
	return i
end

-- size = how many bytes to use
local function replaceIntKeysWithStrs(t, size)
	return table.map(t, function(v,k)
		if type(k) == 'number' then k = inttobin(k, size) end
		return v,k
	end):setmetatable(nil)
end

local function replaceStrKeysWithInts(t)
	return table.map(t, function(v,k)
		if type(k) == 'string' then k = bintoint(k) end
		return v,k
	end):setmetatable(nil)
end



local function reduceColorsLinear(img, targetPaletteSize, hist)

	hist = replaceIntKeysWithStrs(hist, 3)
	
	local fromto
	hist, fromto = buildHistogramQuantizationTransferMap{
		hist = hist,
		targetSize = targetPaletteSize,
		dist = require 'bindistsq',
		merge = require 'binweightedmerge',
	}
	
	img = applyHistogramQuantizationTransferMap(img, fromto)
	
	hist = replaceStrKeysWithInts(hist)

	return img, hist
end

return reduceColorsLinear
