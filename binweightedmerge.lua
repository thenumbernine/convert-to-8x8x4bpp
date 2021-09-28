local function binweightedmerge(a, b, s, t)
	local n = #a
	assert(n == #b)
	local c = ''
	for i=1,n do
		local ai = a:byte(i,i)
		local bi = b:byte(i,i)
		local ci = math.floor(ai * s + bi * t)
		c = c .. string.char(ci)
	end
	return c
end

return binweightedmerge
