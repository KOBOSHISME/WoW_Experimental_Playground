local _, WEP = ...

local SoundEvents = {
	lastFiredAt = {},
	wasInDungeon = false,
	hasSeenDungeonState = false,
}

WEP.SoundEvents = SoundEvents

local FEATURE_ID = "soundEvents"

SoundEvents.title = "Sound Events"
SoundEvents.description = "Play local sounds when built-in cast and world triggers happen."

local Timer = WEP.Tools.Timer
local Sound = WEP.Tools.Sound
local Player = WEP.Tools.Player
local WindowTool = WEP.Tools.Window
local Form = WEP.Tools.Form

WEP:Log("SoundEvents", "loaded")

local TRIGGER_CHARGE = "warriorCharge"
local TRIGGER_DUNGEON = "dungeonEnter"
local DEFAULT_COOLDOWN_SECONDS = 2
local DUNGEON_CHECK_DELAY = 0.5
local ROW_HEIGHT = 58
local WINDOW_WIDTH = 540
local WINDOW_HEIGHT = 250

local SOURCE_UNITS = {
	"player",
	"party1",
	"party2",
	"party3",
	"party4",
}

local CHARGE_SPELL_IDS = {
	[100] = true,
	[6178] = true,
	[11578] = true,
}

local TRIGGERS = {
	{
		id = TRIGGER_CHARGE,
		title = "Warrior Charge",
		description = "Player or party warriors cast Charge.",
		sound = "wep_deja_vu",
		soundLabel = "Deja Vu",
		defaultEnabled = true,
		cooldown = DEFAULT_COOLDOWN_SECONDS,
	},
	{
		id = TRIGGER_DUNGEON,
		title = "Dungeon Entry",
		description = "You enter a dungeon instance.",
		sound = "wep_okay_lets_go",
		soundLabel = "Okay Lets Go",
		defaultEnabled = true,
		cooldown = DEFAULT_COOLDOWN_SECONDS,
	},
}

local triggerById = {}
local chargeSpellNames
local soundEventsWindow

for _, trigger in ipairs(TRIGGERS) do
	triggerById[trigger.id] = trigger
end

local function isBlank(value)
	return value == nil or tostring(value) == ""
end

local function getCheckedValue(checkButton)
	if not checkButton or not checkButton.GetChecked then
		return false
	end

	local checked = checkButton:GetChecked()
	return checked == true or checked == 1
end

local function setSolidColor(texture, red, green, blue, alpha)
	if texture.SetColorTexture then
		texture:SetColorTexture(red, green, blue, alpha)
	else
		texture:SetTexture(red, green, blue, alpha)
	end
end

local function safeCall(fn, ...)
	if type(fn) ~= "function" then
		return nil
	end

	local ok, first, second, third, fourth, fifth, sixth, seventh, eighth, ninth, tenth = pcall(fn, ...)
	if not ok then
		return nil
	end

	return first, second, third, fourth, fifth, sixth, seventh, eighth, ninth, tenth
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

	local name, realm = safeCall(UnitFullName, unit)

	if isBlank(name) then
		name, realm = safeCall(UnitName, unit)
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

local function getSourceUnit(sourceGUID, sourceName)
	for _, unit in ipairs(SOURCE_UNITS) do
		if UnitExists and UnitExists(unit) then
			if not isBlank(sourceGUID) and UnitGUID and UnitGUID(unit) == sourceGUID then
				return unit
			end

			if not isBlank(sourceName) and namesMatch(sourceName, getUnitFullName(unit)) then
				return unit
			end
		end
	end

	return nil
end

local function isUnitWarrior(unit)
	if isBlank(unit) or not UnitClass then
		return false
	end

	local _, classFile = UnitClass(unit)
	return classFile == "WARRIOR"
end

local function resolveChargeSpellNames()
	if chargeSpellNames then
		return chargeSpellNames
	end

	chargeSpellNames = {
		charge = true,
	}

	if type(GetSpellInfo) == "function" then
		for spellId in pairs(CHARGE_SPELL_IDS) do
			local spellName = GetSpellInfo(spellId)
			if not isBlank(spellName) then
				chargeSpellNames[string.lower(tostring(spellName))] = true
			end
		end
	end

	return chargeSpellNames
end

local function isChargeSpell(spellId, spellName)
	if CHARGE_SPELL_IDS[tonumber(spellId)] then
		return true
	end

	if isBlank(spellName) then
		return false
	end

	return resolveChargeSpellNames()[string.lower(tostring(spellName))] == true
end

local function getCombatLogInfo(...)
	if type(CombatLogGetCurrentEventInfo) == "function" then
		return CombatLogGetCurrentEventInfo()
	end

	return ...
end

local function registerEvent(frame, event)
	local ok, err = pcall(frame.RegisterEvent, frame, event)

	if not ok then
		WEP:Log("SoundEvents", "event_unavailable", {
			event = event,
			error = err,
		}, "warn")
	end
end

local function getDungeonState()
	local inInstance, instanceType = safeCall(IsInInstance)
	local instanceName, infoType, _, _, _, _, _, instanceMapId = safeCall(GetInstanceInfo)

	instanceType = instanceType or infoType

	if inInstance == true and instanceType == "party" then
		return true, tostring(instanceMapId or instanceName or "party")
	end

	return false, nil
end

local function getTriggerCount()
	return #TRIGGERS
end

local function ensureTriggerRow(window, index)
	window.triggerRows = window.triggerRows or {}

	if window.triggerRows[index] then
		return window.triggerRows[index]
	end

	local row = CreateFrame("Frame", nil, window.rowsFrame)
	row:SetHeight(ROW_HEIGHT)
	row:SetPoint("LEFT", window.rowsFrame, "LEFT", 0, 0)
	row:SetPoint("RIGHT", window.rowsFrame, "RIGHT", 0, 0)

	row.background = row:CreateTexture(nil, "BACKGROUND")
	row.background:SetAllPoints(row)

	row.check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
	row.check:SetPoint("LEFT", row, "LEFT", -4, 6)

	row.title = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	row.title:SetPoint("TOPLEFT", row.check, "TOPRIGHT", 2, -6)
	row.title:SetWidth(230)
	row.title:SetJustifyH("LEFT")

	row.description = row:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	row.description:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -4)
	row.description:SetWidth(280)
	row.description:SetJustifyH("LEFT")

	row.sound = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	row.sound:SetPoint("RIGHT", row, "RIGHT", -74, 6)
	row.sound:SetWidth(110)
	row.sound:SetJustifyH("RIGHT")

	row.testButton = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
	row.testButton:SetSize(58, 22)
	row.testButton:SetPoint("RIGHT", row, "RIGHT", -8, 6)
	row.testButton:SetText("Test")

	row.check:SetScript("OnClick", function(button)
		if not row.triggerId then
			return
		end

		SoundEvents:SetTriggerEnabled(row.triggerId, getCheckedValue(button))
	end)

	row.testButton:SetScript("OnClick", function()
		if not row.triggerId then
			return
		end

		SoundEvents:PlayTrigger(row.triggerId, "test", {
			ignoreCooldown = true,
			ignoreTriggerEnabled = true,
		})
	end)

	window.triggerRows[index] = row
	return row
end

function SoundEvents:IsEnabled()
	return WEP:IsFeatureEnabled(FEATURE_ID)
end

function SoundEvents:GetDB()
	WEPDB = WEPDB or {}
	WEP.db = WEP.db or WEPDB
	WEP.db.soundEvents = WEP.db.soundEvents or {}
	WEP.db.soundEvents.triggers = WEP.db.soundEvents.triggers or {}

	return WEP.db.soundEvents
end

function SoundEvents:IsTriggerEnabled(triggerId)
	local trigger = triggerById[triggerId]

	if not trigger then
		return false
	end

	local saved = self:GetDB().triggers[triggerId]
	if saved == nil then
		return trigger.defaultEnabled == true
	end

	return saved == true
end

function SoundEvents:SetTriggerEnabled(triggerId, enabled)
	if not triggerById[triggerId] then
		return false, "unknown trigger"
	end

	self:GetDB().triggers[triggerId] = enabled == true
	WEP:Log("SoundEvents", "trigger_toggled", {
		trigger = triggerId,
		enabled = enabled == true,
	})
	self:RefreshRuntime()
	self:RefreshWindow()
	return true
end

function SoundEvents:GetEnabledTriggerCount()
	local enabledCount = 0

	for _, trigger in ipairs(TRIGGERS) do
		if self:IsTriggerEnabled(trigger.id) then
			enabledCount = enabledCount + 1
		end
	end

	return enabledCount
end

function SoundEvents:EnsureFrame()
	if self.frame then
		return self.frame
	end

	if not CreateFrame then
		WEP:Log("SoundEvents", "frame_unavailable", nil, "warn")
		return nil
	end

	self.frame = CreateFrame("Frame")
	self.frame:SetScript("OnEvent", function(_, event, ...)
		self:OnEvent(event, ...)
	end)
	WEP:Log("SoundEvents", "frame_created")
	return self.frame
end

function SoundEvents:RefreshRuntime()
	local frame = self:EnsureFrame()
	if not frame then
		return
	end

	frame:UnregisterAllEvents()

	if not self:IsEnabled() then
		return
	end

	if self:IsTriggerEnabled(TRIGGER_CHARGE) then
		registerEvent(frame, "COMBAT_LOG_EVENT_UNFILTERED")
	end

	if self:IsTriggerEnabled(TRIGGER_DUNGEON) then
		registerEvent(frame, "PLAYER_ENTERING_WORLD")
		registerEvent(frame, "ZONE_CHANGED_NEW_AREA")

		if not self.hasSeenDungeonState then
			self:QueueDungeonCheck("runtime", true)
		end
	else
		self.hasSeenDungeonState = false
		self.wasInDungeon = false
		self.lastDungeonKey = nil
	end

	WEP:Log("SoundEvents", "runtime_updated", {
		charge = self:IsTriggerEnabled(TRIGGER_CHARGE),
		dungeon = self:IsTriggerEnabled(TRIGGER_DUNGEON),
	})
end

function SoundEvents:Initialize()
	if self.initialized then
		return
	end

	self.initialized = true
	self:GetDB()
	resolveChargeSpellNames()
	self:RefreshRuntime()
	WEP:Log("SoundEvents", "initialize")
end

function SoundEvents:PlayTrigger(triggerId, reason, options)
	local trigger = triggerById[triggerId]
	if not trigger then
		return false, "unknown trigger"
	end

	options = options or {}

	if options.ignoreTriggerEnabled ~= true and (not self:IsEnabled() or not self:IsTriggerEnabled(triggerId)) then
		return false, "trigger disabled"
	end

	if options.ignoreCooldown ~= true then
		local now = Timer.Now()
		local lastFiredAt = self.lastFiredAt[triggerId]
		local cooldown = trigger.cooldown or DEFAULT_COOLDOWN_SECONDS

		if lastFiredAt and now - lastFiredAt < cooldown then
			WEP:Log("SoundEvents", "cooldown_skipped", {
				trigger = triggerId,
				reason = reason or "none",
			})
			return false, "cooldown"
		end

		self.lastFiredAt[triggerId] = now
	end

	local ok, playbackOrErr = Sound.Play(trigger.sound)
	if not ok then
		WEP:Log("SoundEvents", "play_failed", {
			trigger = triggerId,
			sound = trigger.sound,
			error = playbackOrErr,
		}, "warn")
		return false, playbackOrErr
	end

	WEP:Log("SoundEvents", "played", {
		trigger = triggerId,
		sound = trigger.sound,
		reason = reason or "none",
	})
	return true, playbackOrErr
end

function SoundEvents:OnCombatLogEvent(...)
	if not self:IsTriggerEnabled(TRIGGER_CHARGE) then
		return
	end

	local _, subevent, _, sourceGUID, sourceName, _, _, _, _, _, _, spellId, spellName = getCombatLogInfo(...)
	if subevent ~= "SPELL_CAST_SUCCESS" or not isChargeSpell(spellId, spellName) then
		return
	end

	local unit = getSourceUnit(sourceGUID, sourceName)
	if not unit or not isUnitWarrior(unit) then
		return
	end

	self:PlayTrigger(TRIGGER_CHARGE, unit .. "_charge")
end

function SoundEvents:QueueDungeonCheck(reason, primeOnly)
	self.dungeonCheckToken = (self.dungeonCheckToken or 0) + 1
	local token = self.dungeonCheckToken

	Timer.After(DUNGEON_CHECK_DELAY, function()
		if token == self.dungeonCheckToken and self:IsEnabled() and self:IsTriggerEnabled(TRIGGER_DUNGEON) then
			self:CheckDungeonState(reason, primeOnly)
		end
	end)
end

function SoundEvents:CheckDungeonState(reason, primeOnly)
	local inDungeon, dungeonKey = getDungeonState()

	if not self.hasSeenDungeonState then
		self.hasSeenDungeonState = true
		self.wasInDungeon = inDungeon == true
		self.lastDungeonKey = dungeonKey
		WEP:Log("SoundEvents", "dungeon_state_primed", {
			inDungeon = self.wasInDungeon,
			key = dungeonKey or "none",
			reason = reason or "none",
		})
		return false
	end

	local enteredDungeon = inDungeon == true and (self.wasInDungeon ~= true or self.lastDungeonKey ~= dungeonKey)

	self.wasInDungeon = inDungeon == true
	self.lastDungeonKey = dungeonKey

	if enteredDungeon and primeOnly ~= true then
		return self:PlayTrigger(TRIGGER_DUNGEON, reason or "dungeon_enter")
	end

	return false
end

function SoundEvents:OnEvent(event, ...)
	if event == "COMBAT_LOG_EVENT_UNFILTERED" then
		self:OnCombatLogEvent(...)
		return
	end

	if event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
		self:QueueDungeonCheck(event)
	end
end

function SoundEvents:EnsureWindow()
	if soundEventsWindow then
		return soundEventsWindow
	end

	if not WindowTool then
		WEP:Log("SoundEvents", "window_unavailable", nil, "error")
		WEP:Print("Sound Events UI tools are unavailable.")
		return nil
	end

	local window, err = WindowTool.Create({
		name = "WEPSoundEventsWindow",
		title = "Sound Events",
		width = WINDOW_WIDTH,
		height = WINDOW_HEIGHT,
		minWidth = WINDOW_WIDTH,
		minHeight = WINDOW_HEIGHT,
		onShow = function()
			self:RefreshWindow()
		end,
	})

	if not window then
		WEP:Log("SoundEvents", "window_failed", {
			error = err,
		}, "error")
		WEP:Print("Sound Events failed:", err)
		return nil
	end

	local content = window.content

	window.summaryText = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	window.summaryText:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
	window.summaryText:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, 0)
	window.summaryText:SetJustifyH("LEFT")

	window.rowsFrame = CreateFrame("Frame", nil, content)
	window.rowsFrame:SetPoint("TOPLEFT", window.summaryText, "BOTTOMLEFT", 0, -12)
	window.rowsFrame:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, 0)
	window.rowsFrame:SetHeight(ROW_HEIGHT * getTriggerCount())

	window.refreshButton = Form.CreateButton(window.footer, {
		text = "Refresh",
		width = 88,
		onClick = function()
			self:RefreshWindow()
		end,
	})
	window.refreshButton:SetPoint("LEFT", window.footer, "LEFT", 0, 0)

	soundEventsWindow = window
	WEP:Log("SoundEvents", "window_created")
	return soundEventsWindow
end

function SoundEvents:RefreshWindow()
	local window = soundEventsWindow
	if not window or not window:IsShown() then
		return
	end

	window.summaryText:SetText("Enabled sound triggers: " .. self:GetEnabledTriggerCount() .. "/" .. getTriggerCount())

	for index, trigger in ipairs(TRIGGERS) do
		local row = ensureTriggerRow(window, index)
		row.triggerId = trigger.id
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", window.rowsFrame, "TOPLEFT", 0, -((index - 1) * ROW_HEIGHT))
		row:SetPoint("RIGHT", window.rowsFrame, "RIGHT", 0, 0)

		setSolidColor(row.background, 0, 0, 0, index % 2 == 0 and 0.14 or 0.06)
		row.check:SetChecked(self:IsTriggerEnabled(trigger.id))
		row.title:SetText(trigger.title)
		row.description:SetText(trigger.description)
		row.sound:SetText(trigger.soundLabel)
		row:Show()
	end

	for index = #TRIGGERS + 1, #(window.triggerRows or {}) do
		window.triggerRows[index]:Hide()
	end

	WEP:Log("SoundEvents", "window_refreshed", {
		enabled = self:GetEnabledTriggerCount(),
		total = getTriggerCount(),
	})
end

function SoundEvents:ShowWindow()
	local window = self:EnsureWindow()
	if not window then
		return
	end

	window:Show()
	self:RefreshWindow()
	WEP:Log("SoundEvents", "window_shown")
end

function SoundEvents:OpenUI()
	self:ShowWindow()
end

function SoundEvents:ShowMenu()
	self:ShowWindow()
end

function SoundEvents:PrintStatus()
	WEP:Print("Sound Events:", self:GetEnabledTriggerCount(), "of", getTriggerCount(), "triggers enabled.")
end

function SoundEvents:OnEnabled()
	WEP:Log("SoundEvents", "enabled")
	self:RefreshRuntime()
end

function SoundEvents:OnDisabled()
	WEP:Log("SoundEvents", "disabled")

	if self.frame then
		self.frame:UnregisterAllEvents()
	end

	if soundEventsWindow then
		soundEventsWindow:Hide()
	end

	self.hasSeenDungeonState = false
	self.wasInDungeon = false
	self.lastDungeonKey = nil
end

function SoundEvents:HandleSlash(args)
	if not self:IsEnabled() then
		WEP:Print("Sound Events is disabled. Open /wep to enable it.")
		return
	end

	local action = args[2]

	if not action or action == "menu" or action == "open" then
		self:ShowWindow()
		return
	end

	if action == "status" then
		self:PrintStatus()
		return
	end

	WEP:Print("Usage: /wep sounds")
	WEP:Print("Usage: /wep sounds status")
end

WEP:RegisterFeature(FEATURE_ID, SoundEvents)
WEP:RegisterModule("SoundEvents", SoundEvents)
