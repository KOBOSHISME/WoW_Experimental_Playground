local addonName, WEP = ...

WEP.name = addonName
WEP.printPrefix = "WEP"
WEP.version = "0.1.0"
WEP.modules = WEP.modules or {}
WEP.moduleOrder = WEP.moduleOrder or {}
WEP.features = WEP.features or {}
WEP.featureOrder = WEP.featureOrder or {}
WEP.Utils = WEP.Utils or {}
WEP.Tools = WEP.Tools or {}

local DEFAULTS = {
	comm = {
		enabled = true,
		debug = false,
		discoveryChannel = true,
		addonMessages = true,
	},
	features = {
		hideSeek = true,
		toolDebug = true,
	},
}

function WEP:RegisterModule(name, module)
	if not self.modules[name] then
		self.moduleOrder[#self.moduleOrder + 1] = name
	end

	self.modules[name] = module
end

function WEP:RegisterFeature(id, feature)
	if type(id) ~= "string" or id == "" then
		return false
	end

	if not self.features[id] then
		self.featureOrder[#self.featureOrder + 1] = id
	end

	feature = feature or {}
	feature.id = id
	self.features[id] = feature
	return true
end

function WEP:IsFeatureEnabled(id)
	local features = self.db and self.db.features

	if not features or features[id] == nil then
		return true
	end

	return features[id] == true
end

function WEP:SetFeatureEnabled(id, enabled)
	local feature = self.features[id]

	if not feature then
		return false, "unknown feature"
	end

	WEPDB = WEPDB or {}
	self.db = self.db or WEPDB
	self.db.features = self.db.features or {}

	enabled = enabled == true
	local wasEnabled = self:IsFeatureEnabled(id)
	self.db.features[id] = enabled

	if wasEnabled ~= enabled then
		local callback = enabled and feature.OnEnabled or feature.OnDisabled

		if type(callback) == "function" then
			local ok, err = pcall(callback, feature)
			if not ok then
				self:Print("Feature toggle failed:", feature.title or id, err)
			end
		end
	end

	return true
end

function WEP:GetFeatures()
	local features = {}

	for _, id in ipairs(self.featureOrder) do
		local feature = self.features[id]

		if feature then
			features[#features + 1] = {
				id = id,
				title = feature.title or id,
				description = feature.description or "",
				enabled = self:IsFeatureEnabled(id),
			}
		end
	end

	return features
end

function WEP:Print(...)
	local message = "|cff33ff99" .. self.printPrefix .. "|r " .. self.Utils.Text.Join(...)

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
	return WEP.Tools.Player.GetShortName()
end

function WEP:GetPlayerFullName()
	return self.Tools.Player.GetFullName()
end

function WEP.NormalizePlayerName(selfOrName, name)
	if name == nil and selfOrName ~= WEP then
		name = selfOrName
	end

	return WEP.Tools.Player.NormalizeName(name)
end

function WEP:IsSelf(sender)
	return self.Tools.Player.IsSelf(sender)
end

function WEP:Initialize()
	if self.initialized then
		return
	end

	WEPDB = WEPDB or {}
	self.Utils.Table.ApplyDefaults(WEPDB, DEFAULTS)

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
