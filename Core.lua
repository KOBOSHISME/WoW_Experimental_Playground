local addonName, WEP = ...

WEP.name = addonName
WEP.printPrefix = "WEP"
WEP.version = "0.1.0"
WEP.modules = WEP.modules or {}
WEP.moduleOrder = WEP.moduleOrder or {}

local DEFAULTS = {
	comm = {
		enabled = true,
		debug = false,
		discoveryChannel = true,
		addonMessages = true,
	},
}

local function copyDefaults(target, defaults)
	for key, value in pairs(defaults) do
		if type(value) == "table" then
			if type(target[key]) ~= "table" then
				target[key] = {}
			end
			copyDefaults(target[key], value)
		elseif target[key] == nil then
			target[key] = value
		end
	end
end

local function valueToString(value)
	if value == nil then
		return "nil"
	end

	if type(value) == "boolean" then
		return value and "true" or "false"
	end

	return tostring(value)
end

local function joinText(...)
	local parts = {}

	for i = 1, select("#", ...) do
		parts[#parts + 1] = valueToString(select(i, ...))
	end

	return table.concat(parts, " ")
end

local function normalizeRealmName(realmName)
	if not realmName or realmName == "" then
		return nil
	end

	return (tostring(realmName):gsub("%s+", ""))
end

function WEP:RegisterModule(name, module)
	if not self.modules[name] then
		self.moduleOrder[#self.moduleOrder + 1] = name
	end

	self.modules[name] = module
end

function WEP:Print(...)
	local message = "|cff33ff99" .. self.printPrefix .. "|r " .. joinText(...)

	if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
		DEFAULT_CHAT_FRAME:AddMessage(message)
	elseif print then
		print(message)
	end
end

function WEP:Debug(...)
	if self.db and self.db.comm and self.db.comm.debug then
		self:Print("|cff999999Debug:|r", ...)
	end
end

function WEP.GetPlayerShortName()
	if UnitName then
		local name = UnitName("player")
		if name and name ~= "" then
			return name
		end
	end

	return "Unknown"
end

function WEP:GetPlayerFullName()
	local name, realm

	if UnitFullName then
		name, realm = UnitFullName("player")
	end

	if not name or name == "" then
		name = self:GetPlayerShortName()
	end

	if (not realm or realm == "") and GetNormalizedRealmName then
		realm = GetNormalizedRealmName()
	end

	if (not realm or realm == "") and GetRealmName then
		realm = GetRealmName()
	end

	realm = normalizeRealmName(realm)

	if realm and realm ~= "" then
		return name .. "-" .. realm
	end

	return name
end

function WEP.NormalizePlayerName(_, name)
	if not name then
		return ""
	end

	return (tostring(name):gsub("%s+", ""))
end

function WEP:IsSelf(sender)
	local normalizedSender = self:NormalizePlayerName(sender)
	if normalizedSender == "" then
		return false
	end

	local fullName = self:NormalizePlayerName(self:GetPlayerFullName())
	local shortName = self:NormalizePlayerName(self:GetPlayerShortName())

	return normalizedSender == fullName or normalizedSender == shortName
end

function WEP:Initialize()
	if self.initialized then
		return
	end

	WEPDB = WEPDB or {}
	copyDefaults(WEPDB, DEFAULTS)

	self.db = WEPDB
	self.initialized = true

	for _, moduleName in ipairs(self.moduleOrder) do
		local module = self.modules[moduleName]

		if module and module.Initialize then
			local ok, err = pcall(module.Initialize, module)
			if not ok then
				self:Print("Module failed:", moduleName, err)
			end
		end
	end

	self:Debug("Initialized", self.version)
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(_, event, loadedAddonName)
	if event == "ADDON_LOADED" and loadedAddonName == addonName then
		WEP:Initialize()
	end
end)
