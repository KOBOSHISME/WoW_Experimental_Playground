local _, WEP = ...

WEP.Utils = WEP.Utils or {}

local Table = {}
WEP.Utils.Table = Table

function Table.ApplyDefaults(target, defaults)
	for key, value in pairs(defaults) do
		if type(value) == "table" then
			if type(target[key]) ~= "table" then
				target[key] = {}
			end

			Table.ApplyDefaults(target[key], value)
		elseif target[key] == nil then
			target[key] = value
		end
	end

	return target
end
