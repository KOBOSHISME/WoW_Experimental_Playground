local _, WEP = ...

WEP.Tools = WEP.Tools or {}

local Player = {}
WEP.Tools.Player = Player

local Text = WEP.Utils.Text

WEP:Log("Player", "loaded")

function Player.NormalizeName(name)
	return Text.RemoveWhitespace(name)
end

function Player.NormalizeRealmName(realmName)
	local normalizedRealmName = Text.RemoveWhitespace(realmName)

	if normalizedRealmName == "" then
		return nil
	end

	return normalizedRealmName
end

function Player.GetShortName()
	if UnitName then
		local name = UnitName("player")
		if name and name ~= "" then
			return name
		end
	end

	WEP:Log("Player", "short_name_fallback", nil, "warn")
	return "Unknown"
end

function Player.GetRealmToken()
	if GetNormalizedRealmName then
		local normalizedRealmName = Player.NormalizeRealmName(GetNormalizedRealmName())
		if normalizedRealmName then
			return normalizedRealmName
		end
	end

	if GetRealmName then
		local realmName = Player.NormalizeRealmName(GetRealmName())
		if realmName then
			return realmName
		end
	end

	WEP:Log("Player", "realm_fallback", nil, "warn")
	return "UnknownRealm"
end

function Player.GetFullName()
	local name, realm

	if UnitFullName then
		name, realm = UnitFullName("player")
	end

	if not name or name == "" then
		name = Player.GetShortName()
	end

	realm = Player.NormalizeRealmName(realm) or Player.GetRealmToken()

	if realm and realm ~= "" then
		return name .. "-" .. realm
	end

	return name
end

function Player.IsSelf(sender)
	local normalizedSender = Player.NormalizeName(sender)
	if normalizedSender == "" then
		return false
	end

	local fullName = Player.NormalizeName(Player.GetFullName())
	local shortName = Player.NormalizeName(Player.GetShortName())

	return normalizedSender == fullName or normalizedSender == shortName
end
