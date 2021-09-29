--[[
hist = (optional) histogram, with keys in lua-string binary-blob format
TODO make fromto the first arg (and this a member of its class?)
--]]
local function applyColorMap(img, fromto, hist)
	if img then
		img = img:clone()
		local p = img.buffer
		for i=0,img.width*img.height-1 do
			local key = string.char(p[0], p[1], p[2])
			local dstkey = fromto[key]
			if not dstkey then
				error("no fromto for color "..bintohex(key))
			end
			p[0], p[1], p[2] = dstkey:byte(1,3)
			p = p + 3
		end
	end	
	
	if hist then
		-- map old histogram values
		-- TODO just regen it?
		local newhist = {}
		for fromkey,count in pairs(hist) do
			local tokey = fromto[fromkey]
			newhist[tokey] = (newhist[tokey] or 0) + count
		end
		hist = newhist
	end
	
	return img, hist
end

return applyColorMap 
