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
	log = {
		enabled = true,
		echo = false,
		maxEntries = 300,
	},
	logs = {},
}

local DEFAULT_LOG_MAX_ENTRIES = 300
local MIN_LOG_MAX_ENTRIES = 50
local MAX_LOG_MAX_ENTRIES = 1000
local MAX_LOG_DETAILS_LENGTH = 240

local function getFeatureUIHandler(feature)
	if type(feature) ~= "table" then
		return nil
	end

	if type(feature.OpenUI) == "function" then
		return feature.OpenUI
	end

	if type(feature.ShowMenu) == "function" then
		return feature.ShowMenu
	end

	if type(feature.ShowWindow) == "function" then
		return feature.ShowWindow
	end

	return nil
end

local function clampLogLimit(limit)
	limit = tonumber(limit) or DEFAULT_LOG_MAX_ENTRIES

	if limit < MIN_LOG_MAX_ENTRIES then
		return MIN_LOG_MAX_ENTRIES
	end

	if limit > MAX_LOG_MAX_ENTRIES then
		return MAX_LOG_MAX_ENTRIES
	end

	return math.floor(limit)
end

local function getLogTime()
	if date then
		return date("%Y-%m-%d %H:%M:%S")
	end

	if time then
		return tostring(time())
	end

	return "unknown-time"
end

local function formatLogValue(value)
	if value == nil then
		return "nil"
	end

	local valueType = type(value)
	if valueType == "string" or valueType == "number" or valueType == "boolean" then
		return tostring(value)
	end

	return "<" .. valueType .. ">"
end

local function formatLogDetails(details)
	if details == nil then
		return nil
	end

	if type(details) ~= "table" then
		local text = tostring(details)

		if #text > MAX_LOG_DETAILS_LENGTH then
			return text:sub(1, MAX_LOG_DETAILS_LENGTH) .. "..."
		end

		return text
	end

	local parts = {}

	for key, value in pairs(details) do
		parts[#parts + 1] = tostring(key) .. "=" .. formatLogValue(value)
	end

	table.sort(parts)

	local text = table.concat(parts, " ")
	if #text > MAX_LOG_DETAILS_LENGTH then
		return text:sub(1, MAX_LOG_DETAILS_LENGTH) .. "..."
	end

	return text
end

function WEP:RegisterModule(name, module)
	if not self.modules[name] then
		self.moduleOrder[#self.moduleOrder + 1] = name
	end

	self.modules[name] = module
	self:Log("Core", "module_registered", {
		name = name,
	})
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
	self:Log("Core", "feature_registered", {
		id = id,
		title = feature.title or id,
	})
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
		self:Log("Core", "feature_toggled", {
			id = id,
			enabled = enabled,
		})

		local callback = enabled and feature.OnEnabled or feature.OnDisabled

		if type(callback) == "function" then
			local ok, err = pcall(callback, feature)
			if not ok then
				self:Log("Core", "feature_toggle_callback_failed", {
					id = id,
					error = err,
				}, "error")
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
				hasUI = getFeatureUIHandler(feature) ~= nil,
			}
		end
	end

	return features
end

function WEP:OpenFeatureUI(id)
	local feature = self.features[id]

	if not feature then
		return false, "unknown feature"
	end

	if not self:IsFeatureEnabled(id) then
		return false, "feature disabled"
	end

	local handler = getFeatureUIHandler(feature)
	if not handler then
		return false, "feature has no UI"
	end

	local ok, err = pcall(handler, feature)
	if not ok then
		self:Log("Core", "feature_ui_open_failed", {
			id = id,
			error = err,
		}, "error")
		return false, err
	end

	self:Log("Core", "feature_ui_opened", {
		id = id,
	})
	return true
end

function WEP:Print(...)
	local message = "|cff33ff99" .. self.printPrefix .. "|r " .. self.Utils.Text.Join(...)

	if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
		DEFAULT_CHAT_FRAME:AddMessage(message)
	elseif print then
		print(message)
	end
end

function WEP:Log(component, event, details, level)
	WEPDB = WEPDB or {}
	self.db = self.db or WEPDB
	self.db.log = self.db.log or {}
	self.db.logs = self.db.logs or {}

	if self.db.log.enabled == false then
		return nil
	end

	self.logSequence = (self.logSequence or 0) + 1

	local entry = {
		sequence = self.logSequence,
		time = getLogTime(),
		level = level or "info",
		component = tostring(component or "Core"),
		event = tostring(event or "event"),
		details = formatLogDetails(details),
	}

	local logs = self.db.logs
	logs[#logs + 1] = entry

	local maxEntries = clampLogLimit(self.db.log.maxEntries)
	self.db.log.maxEntries = maxEntries

	while #logs > maxEntries do
		table.remove(logs, 1)
	end

	if self.db.log.echo == true and self.Print then
		self:Print("Log:", self:FormatLogEntry(entry))
	end

	return entry
end

function WEP:GetLogs(limit)
	local logs = self.db and self.db.logs or {}
	local copied = {}
	local count = tonumber(limit) or #logs

	if count < 0 then
		count = 0
	end

	local startIndex = #logs - math.floor(count) + 1
	if startIndex < 1 then
		startIndex = 1
	end

	for index = startIndex, #logs do
		copied[#copied + 1] = logs[index]
	end

	return copied
end

function WEP:ClearLogs()
	WEPDB = WEPDB or {}
	self.db = self.db or WEPDB

	local count = self.db.logs and #self.db.logs or 0
	self.db.logs = {}
	return count
end

function WEP:FormatLogEntry(entry)
	if not entry then
		return ""
	end

	local text = "[" .. tostring(entry.time or "?") .. "] "
		.. tostring(entry.level or "info")
		.. " "
		.. tostring(entry.component or "Core")
		.. ":"
		.. tostring(entry.event or "event")

	if entry.details and entry.details ~= "" then
		text = text .. " " .. entry.details
	end

	return text
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
	self:Log("Core", "initialize_start", {
		version = self.version,
		modules = #self.moduleOrder,
	})

	for _, moduleName in ipairs(self.moduleOrder) do
		local module = self.modules[moduleName]

		if module and module.Initialize then
			self:Log("Core", "module_initialize_start", {
				name = moduleName,
			})

			local ok, err = pcall(module.Initialize, module)
			if not ok then
				self:Log("Core", "module_initialize_failed", {
					name = moduleName,
					error = err,
				}, "error")
				self:Print("Module failed:", moduleName, err)
			else
				self:Log("Core", "module_initialize_done", {
					name = moduleName,
				})
			end
		end
	end

	self:Debug("Initialized", self.version)
	self:Log("Core", "initialize_done", {
		version = self.version,
	})
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(_, event, loadedAddonName)
	if event == "ADDON_LOADED" and loadedAddonName == addonName then
		WEP:Initialize()
	end
end)
