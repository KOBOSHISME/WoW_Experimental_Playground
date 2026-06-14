local _, WEP = ...

WEP.Tools = WEP.Tools or {}

local Party = {}
WEP.Tools.Party = Party

local Player = WEP.Tools.Player

WEP:Log("Party", "loaded")

local PARTY_LIMIT = 4

local function isBlank(value)
	return value == nil or tostring(value) == ""
end

local function shortName(name)
	local normalized = Player.NormalizeName(name)
	local dashIndex = normalized:find("-", 1, true)

	if dashIndex then
		normalized = normalized:sub(1, dashIndex - 1)
	end

	return normalized
end

local function nameKey(name)
	return string.lower(shortName(name))
end

local function namesMatch(left, right)
	local leftKey = nameKey(left)
	return leftKey ~= "" and leftKey == nameKey(right)
end

local function getUnitFullName(unit)
	if isBlank(unit) or not UnitExists or not UnitExists(unit) then
		return nil
	end

	local name, realm
	if UnitFullName then
		name, realm = UnitFullName(unit)
	end

	if isBlank(name) and UnitName then
		name, realm = UnitName(unit)
	end

	if isBlank(name) then
		return nil
	end

	realm = Player.NormalizeRealmName(realm)
	if realm then
		return name .. "-" .. realm
	end

	return name
end

local function getUnitShortName(unit)
	if isBlank(unit) or not UnitName then
		return nil
	end

	local name = UnitName(unit)
	if isBlank(name) then
		return nil
	end

	return name
end

function Party.GetMembers()
	local members = {}

	for index = 1, PARTY_LIMIT do
		local unit = "party" .. index
		local fullName = getUnitFullName(unit)

		if fullName then
			members[#members + 1] = {
				unit = unit,
				name = fullName,
				shortName = getUnitShortName(unit) or shortName(fullName),
				connected = UnitIsConnected and UnitIsConnected(unit) == true or nil,
				class = UnitClass and select(2, UnitClass(unit)) or nil,
			}
		end
	end

	WEP:Log("Party", "members_captured", {
		count = #members,
	})
	return members
end

function Party.IsPartyMember(name)
	if isBlank(name) then
		return false
	end

	for _, member in ipairs(Party.GetMembers()) do
		if namesMatch(name, member.name) or namesMatch(name, member.shortName) then
			return true
		end
	end

	return false
end

