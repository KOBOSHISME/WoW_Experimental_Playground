local _, WEP = ...

WEP.Utils = WEP.Utils or {}

local Text = {}
WEP.Utils.Text = Text

function Text.ToDisplayString(value)
	if value == nil then
		return "nil"
	end

	if type(value) == "boolean" then
		return value and "true" or "false"
	end

	return tostring(value)
end

function Text.Join(...)
	local parts = {}

	for i = 1, select("#", ...) do
		parts[#parts + 1] = Text.ToDisplayString(select(i, ...))
	end

	return table.concat(parts, " ")
end

function Text.Trim(value)
	return (tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

function Text.RemoveWhitespace(value)
	if not value then
		return ""
	end

	return (tostring(value):gsub("%s+", ""))
end
