local function bintohex(s)
	return (s:gsub('.', function(c) return ('%02x'):format(c:byte()) end))
end
return bintohex 	
