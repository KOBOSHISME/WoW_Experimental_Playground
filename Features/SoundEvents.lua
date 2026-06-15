local _, WEP = ...

local SoundEvents = {
	lastFiredAt = {},
	wasInDungeon = false,
	hasSeenDungeonState = false,
	wasResting = false,
	hasSeenRestingState = false,
	partyGuids = {},
	partyLeaderGuid = nil,
	hasSeenGroupState = false,
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
local TRIGGER_DIVINE_SHIELD = "paladinDivineShield"
local TRIGGER_MIND_CONTROL = "priestMindControl"
local TRIGGER_FEIGN_DEATH = "hunterFeignDeath"
local TRIGGER_PLAYER_DEATH = "playerDeath"
local TRIGGER_PARTY_DEATH = "partyDeath"
local TRIGGER_PLAYER_CONTROLLED = "playerControlled"
local TRIGGER_PARTY_JOIN = "partyJoin"
local TRIGGER_PARTY_LEADER = "partyLeader"
local TRIGGER_FALLING_DAMAGE = "fallingDamage"
local TRIGGER_RESTED_AREA = "restedArea"
local TRIGGER_LEVEL_UP = "levelUp"
local TRIGGER_RARE_LOOT = "rareLoot"

local DEFAULT_COOLDOWN_SECONDS = 2
local STATE_CHECK_DELAY = 0.5
local ROW_HEIGHT = 46
local WINDOW_WIDTH = 560
local WINDOW_HEIGHT = 430

local PLAYER_UNITS = {
	"player",
	"party1",
	"party2",
	"party3",
	"party4",
}

local PARTY_UNITS = {
	"party1",
	"party2",
	"party3",
	"party4",
}

local SPELL_CHARGE = {
	[100] = true,
	[6178] = true,
	[11578] = true,
}

local SPELL_DIVINE_SHIELD = {
	[642] = true,
	[1020] = true,
}

local SPELL_MIND_CONTROL = {
	[605] = true,
	[10911] = true,
	[10912] = true,
}

local SPELL_FEIGN_DEATH = {
	[5384] = true,
}

local CONTROL_AURA_SPELL_IDS = {
	[408] = true,
	[853] = true,
	[1330] = true,
	[1513] = true,
	[1833] = true,
	[5211] = true,
	[5246] = true,
	[5484] = true,
	[5782] = true,
	[6213] = true,
	[6215] = true,
	[6358] = true,
	[6798] = true,
	[7922] = true,
	[8122] = true,
	[8124] = true,
	[8643] = true,
	[8983] = true,
	[9005] = true,
	[10308] = true,
	[10888] = true,
	[10890] = true,
	[12809] = true,
	[14326] = true,
	[14327] = true,
	[15487] = true,
	[17928] = true,
	[18469] = true,
	[18498] = true,
	[20253] = true,
	[20549] = true,
}

local CONTROL_AURA_NAMES = {
	["arcane torrent"] = true,
	["bash"] = true,
	["cheap shot"] = true,
	["charge stun"] = true,
	["concussion blow"] = true,
	["counterspell - silenced"] = true,
	["fear"] = true,
	["garrote - silence"] = true,
	["hammer of justice"] = true,
	["howl of terror"] = true,
	["impact"] = true,
	["improved counterspell"] = true,
	["intimidating shout"] = true,
	["intercept stun"] = true,
	["kick - silenced"] = true,
	["kidney shot"] = true,
	["pounce"] = true,
	["psychic scream"] = true,
	["scare beast"] = true,
	["seduction"] = true,
	["silence"] = true,
	["spell lock"] = true,
	["war stomp"] = true,
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
		combatLog = true,
		cast = {
			classFile = "WARRIOR",
			spellIds = SPELL_CHARGE,
			names = {
				"Charge",
			},
		},
	},
	{
		id = TRIGGER_DUNGEON,
		title = "Dungeon Entry",
		description = "You enter a dungeon instance.",
		sound = "wep_okay_lets_go",
		soundLabel = "Okay Lets Go",
		defaultEnabled = true,
		cooldown = DEFAULT_COOLDOWN_SECONDS,
		dungeon = true,
	},
	{
		id = TRIGGER_DIVINE_SHIELD,
		title = "Divine Shield",
		description = "Player or party paladins cast Divine Shield.",
		sound = "wep_heavenly_music",
		soundLabel = "Heavenly Music",
		defaultEnabled = true,
		cooldown = DEFAULT_COOLDOWN_SECONDS,
		combatLog = true,
		cast = {
			classFile = "PALADIN",
			spellIds = SPELL_DIVINE_SHIELD,
			names = {
				"Divine Shield",
			},
		},
	},
	{
		id = TRIGGER_MIND_CONTROL,
		title = "Mind Control",
		description = "Player or party priests cast Mind Control.",
		sound = "wep_among_us",
		soundLabel = "Among Us",
		defaultEnabled = true,
		cooldown = DEFAULT_COOLDOWN_SECONDS,
		combatLog = true,
		cast = {
			classFile = "PRIEST",
			spellIds = SPELL_MIND_CONTROL,
			names = {
				"Mind Control",
			},
		},
	},
	{
		id = TRIGGER_FEIGN_DEATH,
		title = "Feign Death",
		description = "Player or party hunters cast Feign Death.",
		sound = "wep_ack",
		soundLabel = "Ack",
		defaultEnabled = true,
		cooldown = DEFAULT_COOLDOWN_SECONDS,
		combatLog = true,
		cast = {
			classFile = "HUNTER",
			spellIds = SPELL_FEIGN_DEATH,
			names = {
				"Feign Death",
			},
		},
	},
	{
		id = TRIGGER_PLAYER_DEATH,
		title = "You Die",
		description = "Your character dies.",
		sound = "wep_auughhh",
		soundLabel = "Auughhh",
		defaultEnabled = true,
		cooldown = DEFAULT_COOLDOWN_SECONDS,
		playerDeath = true,
	},
	{
		id = TRIGGER_PARTY_DEATH,
		title = "Party Death",
		description = "A party member dies.",
		sound = "wep_faaah",
		soundLabel = "Faaah",
		defaultEnabled = true,
		cooldown = DEFAULT_COOLDOWN_SECONDS,
		combatLog = true,
		partyDeath = true,
	},
	{
		id = TRIGGER_PLAYER_CONTROLLED,
		title = "Hard Crowd Control",
		description = "You are stunned, feared, or silenced.",
		sound = "wep_error",
		soundLabel = "Error",
		defaultEnabled = true,
		cooldown = DEFAULT_COOLDOWN_SECONDS,
		combatLog = true,
		playerControlled = true,
	},
	{
		id = TRIGGER_PARTY_JOIN,
		title = "Party Join",
		description = "A new party member joins.",
		sound = "wep_hello_there",
		soundLabel = "Hello There",
		defaultEnabled = true,
		cooldown = DEFAULT_COOLDOWN_SECONDS,
		groupState = true,
	},
	{
		id = TRIGGER_PARTY_LEADER,
		title = "Party Leader",
		description = "Party leader changes.",
		sound = "wep_among_us",
		soundLabel = "Among Us",
		defaultEnabled = true,
		cooldown = DEFAULT_COOLDOWN_SECONDS,
		groupState = true,
	},
	{
		id = TRIGGER_FALLING_DAMAGE,
		title = "Falling Damage",
		description = "You take fall damage.",
		sound = "wep_vine_boom",
		soundLabel = "Vine Boom",
		defaultEnabled = true,
		cooldown = DEFAULT_COOLDOWN_SECONDS,
		combatLog = true,
		fallingDamage = true,
	},
	{
		id = TRIGGER_RESTED_AREA,
		title = "Rested Area",
		description = "You enter a rested area or inn.",
		sound = "wep_hub_intro",
		soundLabel = "Hub Intro",
		defaultEnabled = true,
		cooldown = DEFAULT_COOLDOWN_SECONDS,
		resting = true,
	},
	{
		id = TRIGGER_LEVEL_UP,
		title = "Level Up",
		description = "You gain a level.",
		sound = "wep_anime_wow",
		soundLabel = "Anime Wow",
		defaultEnabled = true,
		cooldown = DEFAULT_COOLDOWN_SECONDS,
		levelUp = true,
	},
	{
		id = TRIGGER_RARE_LOOT,
		title = "Rare Loot",
		description = "You loot a rare, epic, or better item.",
		sound = "wep_rizz",
		soundLabel = "Rizz",
		defaultEnabled = true,
		cooldown = DEFAULT_COOLDOWN_SECONDS,
		rareLoot = true,
	},
}

local triggerById = {}
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

local function getUnitFromList(units, guid, name)
	for _, unit in ipairs(units) do
		if UnitExists and UnitExists(unit) then
			if not isBlank(guid) and UnitGUID and UnitGUID(unit) == guid then
				return unit
			end

			if not isBlank(name) and namesMatch(name, getUnitFullName(unit)) then
				return unit
			end
		end
	end

	return nil
end

local function getSourceUnit(sourceGUID, sourceName)
	return getUnitFromList(PLAYER_UNITS, sourceGUID, sourceName)
end

local function getPartyUnit(guid, name)
	return getUnitFromList(PARTY_UNITS, guid, name)
end

local function isUnitClass(unit, classFile)
	if isBlank(unit) or isBlank(classFile) or not UnitClass then
		return false
	end

	local _, unitClassFile = UnitClass(unit)
	return unitClassFile == classFile
end

local function getSpellNameSet(trigger)
	if trigger.spellNameSet then
		return trigger.spellNameSet
	end

	local spellNameSet = {}
	local castConfig = trigger.cast or {}

	for _, spellName in ipairs(castConfig.names or {}) do
		spellNameSet[string.lower(tostring(spellName))] = true
	end

	if type(GetSpellInfo) == "function" then
		for spellId in pairs(castConfig.spellIds or {}) do
			local spellName = GetSpellInfo(spellId)
			if not isBlank(spellName) then
				spellNameSet[string.lower(tostring(spellName))] = true
			end
		end
	end

	trigger.spellNameSet = spellNameSet
	return spellNameSet
end

local function spellMatchesTrigger(trigger, spellId, spellName)
	local castConfig = trigger.cast or {}

	if castConfig.spellIds and castConfig.spellIds[tonumber(spellId)] then
		return true
	end

	if isBlank(spellName) then
		return false
	end

	return getSpellNameSet(trigger)[string.lower(tostring(spellName))] == true
end

local function isControlAura(spellId, spellName)
	if CONTROL_AURA_SPELL_IDS[tonumber(spellId)] then
		return true
	end

	if isBlank(spellName) then
		return false
	end

	return CONTROL_AURA_NAMES[string.lower(tostring(spellName))] == true
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

local function isResting()
	return safeCall(IsResting) == true
end

local function isGroupLeader(unit)
	if isBlank(unit) or not UnitExists or not UnitExists(unit) then
		return false
	end

	if UnitIsGroupLeader then
		return UnitIsGroupLeader(unit) == true
	end

	if UnitIsPartyLeader then
		return UnitIsPartyLeader(unit) == true
	end

	return false
end

local function getGroupState()
	local partyGuids = {}
	local leaderGuid

	for _, unit in ipairs(PARTY_UNITS) do
		if UnitExists and UnitExists(unit) then
			local guid = UnitGUID and UnitGUID(unit) or nil

			if not isBlank(guid) then
				partyGuids[guid] = unit
			end

			if isGroupLeader(unit) then
				leaderGuid = guid or getUnitFullName(unit)
			end
		end
	end

	if UnitExists and UnitExists("player") and isGroupLeader("player") then
		leaderGuid = (UnitGUID and UnitGUID("player")) or Player.GetFullName()
	end

	return partyGuids, leaderGuid
end

local function getItemLinkFromLootText(text)
	if isBlank(text) then
		return nil
	end

	return tostring(text):match("(|c%x%x%x%x%x%x%x%x|Hitem:.-|h%[.-%]|h|r)")
end

local function getItemQualityFromLink(itemLink)
	if isBlank(itemLink) then
		return nil
	end

	local quality = select(3, safeCall(GetItemInfo, itemLink))
	if type(quality) == "number" then
		return quality
	end

	if C_Item and C_Item.GetItemInfo then
		quality = select(3, safeCall(C_Item.GetItemInfo, itemLink))
		if type(quality) == "number" then
			return quality
		end
	end

	local color = string.lower(tostring(itemLink):match("^|c(%x%x%x%x%x%x%x%x)") or "")

	if color == "ff0070dd" then
		return 3
	end

	if color == "ffa335ee" then
		return 4
	end

	if color == "ffff8000" then
		return 5
	end

	if color == "ffe6cc80" then
		return 7
	end

	return nil
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
	row.check:SetPoint("LEFT", row, "LEFT", -4, 0)

	row.title = row:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	row.title:SetPoint("TOPLEFT", row.check, "TOPRIGHT", 2, -4)
	row.title:SetWidth(250)
	row.title:SetJustifyH("LEFT")

	row.description = row:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	row.description:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -2)
	row.description:SetWidth(305)
	row.description:SetJustifyH("LEFT")

	row.sound = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	row.sound:SetPoint("RIGHT", row, "RIGHT", -74, 0)
	row.sound:SetWidth(110)
	row.sound:SetJustifyH("RIGHT")

	row.testButton = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
	row.testButton:SetSize(58, 22)
	row.testButton:SetPoint("RIGHT", row, "RIGHT", -8, 0)
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

function SoundEvents:IsAnyTriggerEnabled(predicate)
	for _, trigger in ipairs(TRIGGERS) do
		if self:IsTriggerEnabled(trigger.id) and predicate(trigger) then
			return true
		end
	end

	return false
end

function SoundEvents:AreGroupTriggersEnabled()
	return self:IsTriggerEnabled(TRIGGER_PARTY_JOIN) or self:IsTriggerEnabled(TRIGGER_PARTY_LEADER)
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

	local events = {}

	if self:IsAnyTriggerEnabled(function(trigger)
		return trigger.combatLog == true
	end) then
		events.COMBAT_LOG_EVENT_UNFILTERED = true
	end

	if self:IsTriggerEnabled(TRIGGER_DUNGEON) then
		events.PLAYER_ENTERING_WORLD = true
		events.ZONE_CHANGED_NEW_AREA = true

		if not self.hasSeenDungeonState then
			self:QueueDungeonCheck("runtime", true)
		end
	else
		self.hasSeenDungeonState = false
		self.wasInDungeon = false
		self.lastDungeonKey = nil
	end

	if self:IsTriggerEnabled(TRIGGER_RESTED_AREA) then
		events.PLAYER_ENTERING_WORLD = true
		events.ZONE_CHANGED_NEW_AREA = true
		events.PLAYER_UPDATE_RESTING = true

		if not self.hasSeenRestingState then
			self:QueueRestingCheck("runtime", true)
		end
	else
		self.hasSeenRestingState = false
		self.wasResting = false
	end

	if self:AreGroupTriggersEnabled() then
		events.PLAYER_ENTERING_WORLD = true
		events.GROUP_ROSTER_UPDATE = true
		events.PARTY_LEADER_CHANGED = true

		if not self.hasSeenGroupState then
			self:QueueGroupStateCheck("runtime", true)
		end
	else
		self.hasSeenGroupState = false
		self.partyGuids = {}
		self.partyLeaderGuid = nil
	end

	if self:IsTriggerEnabled(TRIGGER_PLAYER_DEATH) then
		events.PLAYER_DEAD = true
	end

	if self:IsTriggerEnabled(TRIGGER_LEVEL_UP) then
		events.PLAYER_LEVEL_UP = true
	end

	if self:IsTriggerEnabled(TRIGGER_RARE_LOOT) then
		events.CHAT_MSG_LOOT = true
	end

	for event in pairs(events) do
		registerEvent(frame, event)
	end

	WEP:Log("SoundEvents", "runtime_updated", {
		combatLog = events.COMBAT_LOG_EVENT_UNFILTERED == true,
		dungeon = self:IsTriggerEnabled(TRIGGER_DUNGEON),
		group = self:AreGroupTriggersEnabled(),
		rested = self:IsTriggerEnabled(TRIGGER_RESTED_AREA),
	})
end

function SoundEvents:Initialize()
	if self.initialized then
		return
	end

	self.initialized = true
	self:GetDB()

	for _, trigger in ipairs(TRIGGERS) do
		if trigger.cast then
			getSpellNameSet(trigger)
		end
	end

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

function SoundEvents:HandleCastCombatLog(sourceGUID, sourceName, spellId, spellName)
	local unit = getSourceUnit(sourceGUID, sourceName)
	if not unit then
		return
	end

	for _, trigger in ipairs(TRIGGERS) do
		if trigger.cast
			and self:IsTriggerEnabled(trigger.id)
			and isUnitClass(unit, trigger.cast.classFile)
			and spellMatchesTrigger(trigger, spellId, spellName)
		then
			self:PlayTrigger(trigger.id, unit .. "_cast")
			return
		end
	end
end

function SoundEvents:HandlePartyDeath(destGUID, destName)
	if not self:IsTriggerEnabled(TRIGGER_PARTY_DEATH) then
		return
	end

	local unit = getPartyUnit(destGUID, destName)
	if unit then
		self:PlayTrigger(TRIGGER_PARTY_DEATH, unit .. "_death")
	end
end

function SoundEvents:HandlePlayerControlled(destGUID, spellId, spellName)
	if not self:IsTriggerEnabled(TRIGGER_PLAYER_CONTROLLED) then
		return
	end

	if UnitGUID and destGUID ~= UnitGUID("player") then
		return
	end

	if isControlAura(spellId, spellName) then
		self:PlayTrigger(TRIGGER_PLAYER_CONTROLLED, "control_" .. tostring(spellId or spellName or "unknown"))
	end
end

function SoundEvents:HandleFallingDamage(destGUID, environmentalType)
	if not self:IsTriggerEnabled(TRIGGER_FALLING_DAMAGE) then
		return
	end

	if UnitGUID and destGUID ~= UnitGUID("player") then
		return
	end

	if string.lower(tostring(environmentalType or "")) == "falling" then
		self:PlayTrigger(TRIGGER_FALLING_DAMAGE, "falling_damage")
	end
end

function SoundEvents:OnCombatLogEvent(...)
	local _, subevent, _, sourceGUID, sourceName, _, _, destGUID, destName, _, _, arg12, arg13 = getCombatLogInfo(...)

	if subevent == "SPELL_CAST_SUCCESS" then
		self:HandleCastCombatLog(sourceGUID, sourceName, arg12, arg13)
		return
	end

	if subevent == "UNIT_DIED" or subevent == "UNIT_DESTROYED" then
		self:HandlePartyDeath(destGUID, destName)
		return
	end

	if subevent == "SPELL_AURA_APPLIED" or subevent == "SPELL_AURA_REFRESH" then
		self:HandlePlayerControlled(destGUID, arg12, arg13)
		return
	end

	if subevent == "ENVIRONMENTAL_DAMAGE" then
		self:HandleFallingDamage(destGUID, arg12)
	end
end

function SoundEvents:QueueDungeonCheck(reason, primeOnly)
	self.dungeonCheckToken = (self.dungeonCheckToken or 0) + 1
	local token = self.dungeonCheckToken

	Timer.After(STATE_CHECK_DELAY, function()
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

function SoundEvents:QueueRestingCheck(reason, primeOnly)
	self.restingCheckToken = (self.restingCheckToken or 0) + 1
	local token = self.restingCheckToken

	Timer.After(STATE_CHECK_DELAY, function()
		if token == self.restingCheckToken and self:IsEnabled() and self:IsTriggerEnabled(TRIGGER_RESTED_AREA) then
			self:CheckRestingState(reason, primeOnly)
		end
	end)
end

function SoundEvents:CheckRestingState(reason, primeOnly)
	local resting = isResting()

	if not self.hasSeenRestingState then
		self.hasSeenRestingState = true
		self.wasResting = resting
		WEP:Log("SoundEvents", "resting_state_primed", {
			resting = resting,
			reason = reason or "none",
		})
		return false
	end

	local enteredResting = resting == true and self.wasResting ~= true
	self.wasResting = resting

	if enteredResting and primeOnly ~= true then
		return self:PlayTrigger(TRIGGER_RESTED_AREA, reason or "rested_area")
	end

	return false
end

function SoundEvents:QueueGroupStateCheck(reason, primeOnly)
	self.groupCheckToken = (self.groupCheckToken or 0) + 1
	local token = self.groupCheckToken

	Timer.After(STATE_CHECK_DELAY, function()
		if token == self.groupCheckToken and self:IsEnabled() and self:AreGroupTriggersEnabled() then
			self:CheckGroupState(reason, primeOnly)
		end
	end)
end

function SoundEvents:CheckGroupState(reason, primeOnly)
	local partyGuids, leaderGuid = getGroupState()

	if not self.hasSeenGroupState then
		self.hasSeenGroupState = true
		self.partyGuids = partyGuids
		self.partyLeaderGuid = leaderGuid
		WEP:Log("SoundEvents", "group_state_primed", {
			members = self:GetPartyGuidCount(partyGuids),
			leader = leaderGuid or "none",
			reason = reason or "none",
		})
		return false
	end

	if primeOnly ~= true and self:IsTriggerEnabled(TRIGGER_PARTY_JOIN) then
		for guid in pairs(partyGuids) do
			if not self.partyGuids[guid] then
				self:PlayTrigger(TRIGGER_PARTY_JOIN, reason or "party_join")
				break
			end
		end
	end

	if primeOnly ~= true
		and self:IsTriggerEnabled(TRIGGER_PARTY_LEADER)
		and self.partyLeaderGuid
		and leaderGuid
		and self.partyLeaderGuid ~= leaderGuid
	then
		self:PlayTrigger(TRIGGER_PARTY_LEADER, reason or "party_leader")
	end

	self.partyGuids = partyGuids
	self.partyLeaderGuid = leaderGuid
	return true
end

function SoundEvents:GetPartyGuidCount(partyGuids)
	local count = 0

	for _ in pairs(partyGuids or {}) do
		count = count + 1
	end

	return count
end

function SoundEvents:OnLootMessage(text)
	if not self:IsTriggerEnabled(TRIGGER_RARE_LOOT) then
		return
	end

	if tostring(text or ""):find("You", 1, true) ~= 1 then
		return
	end

	local itemLink = getItemLinkFromLootText(text)
	local quality = getItemQualityFromLink(itemLink)

	if quality and quality >= 3 then
		self:PlayTrigger(TRIGGER_RARE_LOOT, "quality_" .. tostring(quality))
	end
end

function SoundEvents:OnEvent(event, ...)
	if event == "COMBAT_LOG_EVENT_UNFILTERED" then
		self:OnCombatLogEvent(...)
		return
	end

	if event == "PLAYER_ENTERING_WORLD" then
		if self:IsTriggerEnabled(TRIGGER_DUNGEON) then
			self:QueueDungeonCheck(event)
		end

		if self:IsTriggerEnabled(TRIGGER_RESTED_AREA) then
			self:QueueRestingCheck(event)
		end

		if self:AreGroupTriggersEnabled() and not self.hasSeenGroupState then
			self:QueueGroupStateCheck(event, true)
		end

		return
	end

	if event == "ZONE_CHANGED_NEW_AREA" then
		if self:IsTriggerEnabled(TRIGGER_DUNGEON) then
			self:QueueDungeonCheck(event)
		end

		if self:IsTriggerEnabled(TRIGGER_RESTED_AREA) then
			self:QueueRestingCheck(event)
		end

		return
	end

	if event == "PLAYER_UPDATE_RESTING" then
		self:QueueRestingCheck(event)
		return
	end

	if event == "GROUP_ROSTER_UPDATE" or event == "PARTY_LEADER_CHANGED" then
		self:QueueGroupStateCheck(event)
		return
	end

	if event == "PLAYER_DEAD" then
		self:PlayTrigger(TRIGGER_PLAYER_DEATH, "player_dead")
		return
	end

	if event == "PLAYER_LEVEL_UP" then
		self:PlayTrigger(TRIGGER_LEVEL_UP, "level_up")
		return
	end

	if event == "CHAT_MSG_LOOT" then
		self:OnLootMessage(...)
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

	window.scrollFrame = CreateFrame("ScrollFrame", nil, content, "UIPanelScrollFrameTemplate")
	window.scrollFrame:SetPoint("TOPLEFT", window.summaryText, "BOTTOMLEFT", 0, -12)
	window.scrollFrame:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -24, 0)

	window.rowsFrame = CreateFrame("Frame", nil, window.scrollFrame)
	window.rowsFrame:SetSize(WINDOW_WIDTH - 58, ROW_HEIGHT * getTriggerCount())
	window.scrollFrame:SetScrollChild(window.rowsFrame)

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
	window.rowsFrame:SetHeight(ROW_HEIGHT * getTriggerCount())

	if window.scrollFrame.GetWidth and window.scrollFrame:GetWidth() > 0 then
		window.rowsFrame:SetWidth(window.scrollFrame:GetWidth())
	end

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
	self.hasSeenRestingState = false
	self.wasResting = false
	self.hasSeenGroupState = false
	self.partyGuids = {}
	self.partyLeaderGuid = nil
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
