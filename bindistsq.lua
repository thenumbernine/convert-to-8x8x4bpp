local function bindistsq(a, b)
	local n = #a
	assert(n == #b)
	local sum = 0
	for i=1,n do
		local ai = a:byte(i,i)
		local bi = b:byte(i,i)
		local d = ai - bi
		sum = sum + d * d
	end
	return sum
end
return bindistsq
