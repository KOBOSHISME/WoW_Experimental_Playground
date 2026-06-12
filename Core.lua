local addonName, WEP = ...

WEP.name = addonName
WEP.printPrefix = "WEP"
WEP.version = "0.1.0"
WEP.modules = WEP.modules or {}
WEP.moduleOrder = WEP.moduleOrder or {}
WEP.Utils = WEP.Utils or {}
WEP.Tools = WEP.Tools or {}

local DEFAULTS = {
	comm = {
		enabled = true,
		debug = false,
		discoveryChannel = true,
		addonMessages = true,
	},
}

function WEP:RegisterModule(name, module)
	if not self.modules[name] then
		self.moduleOrder[#self.moduleOrder + 1] = name
	end

	self.modules[name] = module
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
