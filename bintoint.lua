local bit = require 'bit'

local function bintoint(s)
	local i = 0
	for j=#s,1,-1 do
		i = bit.bor(bit.lshift(i, 8), s:byte(j,j))
	end
	return i
end

return bintoint
