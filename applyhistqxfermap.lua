local function applyHistogramQuantizationTransferMap (img, fromto)
	local newimg = img:clone()
	local p = newimg.buffer
	for i=0,newimg.width*newimg.height-1 do
		local key = string.char(p[0], p[1], p[2])
		local dstkey = fromto[key]
		if not dstkey then
			error("no fromto for color "..bintohex(key))
		end
		p[0], p[1], p[2] = dstkey:byte(1,3)
		p = p + 3
	end
	return newimg
end

return applyHistogramQuantizationTransferMap 
