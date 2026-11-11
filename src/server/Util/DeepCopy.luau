--!strict

local function deepCopy<T>(value: T): T
	if type(value) ~= "table" then
		return value
	end
	local result = {}
	for key, child in value :: any do
		(result :: any)[deepCopy(key)] = deepCopy(child)
	end
	return result :: T
end

return deepCopy
