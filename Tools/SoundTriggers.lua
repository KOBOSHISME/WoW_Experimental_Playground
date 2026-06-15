local _, WEP = ...

WEP.Tools = WEP.Tools or {}

local SoundTriggers = {
	activeTriggers = {},
	stats = {
		registered = 0,
		cleared = 0,
		fired = 0,
		failed = 0,
		skipped = 0,
	},
}

WEP.Tools.SoundTriggers = SoundTriggers

local Timer = WEP.Tools.Timer
local Player = WEP.Tools.Player
local Party = WEP.Tools.Party
local Sound = WEP.Tools.Sound

WEP:Log("SoundTriggers", "loaded")

local DEFAULT_SOUND = "wep_alert"
local DEFAULT_CHANCE = 100
local MAX_CHANCE = 100
local DEFAULT_COOLDOWN_SECONDS = 2
local COMBAT_COOLDOWN_SECONDS = 0.5
local MOVEMENT_CHECK_SECONDS = 0.25

local function isBlank(value)
	return value == nil or tostring(value) == ""
end

local function safeCall(fn, ...)
	if type(fn) ~= "function" then
		return nil
	end

	local ok, first, second, third = pcall(fn, ...)
	if not ok then
		return nil
	end

	return first, second, third
end

local function clamp(value, minValue, maxValue, defaultValue)
	value = tonumber(value) or defaultValue

	if value < minValue then
		return minValue
	end

	if value > maxValue then
		return maxValue
	end

	return value
end

local function makeTriggerId()
	SoundTriggers.triggerCounter = (SoundTriggers.triggerCounter or 0) + 1
	return "snd" .. Timer.Now() .. "." .. SoundTriggers.triggerCounter
end

local function copyTriggerStatus(trigger)
	return {
		id = trigger.id,
		source = trigger.source,
		trigger = trigger.trigger,
		sound = trigger.sound,
		chance = trigger.chance,
		cooldown = trigger.cooldown,
		oneShot = trigger.oneShot,
		fired = trigger.fired,
		startedAt = trigger.startedAt,
	}
end

local function stopTriggerSounds(trigger)
	for _, handle in ipairs(trigger.soundHandles or {}) do
		Sound.Stop(handle, 0)
	end

	trigger.soundHandles = {}
end

local triggerFrame
local movementCheckElapsed = 0
local handleTriggerEvent
local handleTriggerUpdate
local updateTriggerRuntime

function SoundTriggers.NormalizeTrigger(trigger)
	if isBlank(trigger) then
		return nil
	end

	local normalized = string.lower(tostring(trigger)):gsub("[%s_-]+", "_")

	if normalized == "w" then
		return "walk"
	end

	if normalized == "t" then
		return "target"
	end

	if normalized == "c" then
		return "combat"
	end

	if normalized == "s" then
		return "cast"
	end

	if normalized == "e" then
		return "enemy_target"
	end

	if normalized == "move" or normalized == "movement" or normalized == "walking" then
		return "walk"
	end

	if normalized == "party_target" or normalized == "target_party" then
		return "target"
	end

	if normalized == "spellcast" or normalized == "spell_cast" then
		return "cast"
	end

	if normalized == "enemy" or normalized == "hostile" or normalized == "hostile_target" then
		return "enemy_target"
	end

	if normalized == "walk"
		or normalized == "target"
		or normalized == "enemy_target"
		or normalized == "combat"
		or normalized == "cast"
	then
		return normalized
	end

	return nil
end

function SoundTriggers.GetDefaultCooldown(trigger)
	if SoundTriggers.NormalizeTrigger(trigger) == "combat" then
		return COMBAT_COOLDOWN_SECONDS
	end

	return DEFAULT_COOLDOWN_SECONDS
end

local function ensureTriggerFrame()
	if triggerFrame then
		return triggerFrame
	end

	if not CreateFrame then
		WEP:Log("SoundTriggers", "frame_unavailable", nil, "warn")
		return nil
	end

	triggerFrame = CreateFrame("Frame")
	triggerFrame:SetScript("OnEvent", function(_, event, ...)
		if handleTriggerEvent then
			handleTriggerEvent(event, ...)
		end
	end)
	WEP:Log("SoundTriggers", "frame_created")
	return triggerFrame
end

local function registerTriggerEvent(frame, event)
	local ok, err = pcall(frame.RegisterEvent, frame, event)

	if not ok then
		WEP:Log("SoundTriggers", "event_unavailable", {
			event = event,
			error = err,
		}, "warn")
	end
end

local function forEachTrigger(trigger, callback)
	for _, activeTrigger in pairs(SoundTriggers.activeTriggers) do
		if activeTrigger.trigger == trigger then
			callback(activeTrigger)
		end
	end
end

local function isPlayerMoving()
	local speed = safeCall(GetUnitSpeed, "player")

	if type(speed) ~= "number" then
		speed = safeCall(UnitSpeed, "player")
	end

	if type(speed) == "number" then
		return speed > 0
	end

	if not C_Map or not C_Map.GetBestMapForUnit or not C_Map.GetPlayerMapPosition then
		return false
	end

	local mapId = safeCall(C_Map.GetBestMapForUnit, "player")
	local position = mapId and safeCall(C_Map.GetPlayerMapPosition, mapId, "player") or nil
	if not position then
		return false
	end

	local x, y
	if position.GetXY then
		x, y = position:GetXY()
	elseif position.x and position.y then
		x, y = position.x, position.y
	end

	if type(x) ~= "number" or type(y) ~= "number" then
		return false
	end

	local moving = SoundTriggers.lastMovementMapId == mapId
		and SoundTriggers.lastMovementX
		and SoundTriggers.lastMovementY
		and (math.abs(x - SoundTriggers.lastMovementX) > 0.00001 or math.abs(y - SoundTriggers.lastMovementY) > 0.00001)

	SoundTriggers.lastMovementMapId = mapId
	SoundTriggers.lastMovementX = x
	SoundTriggers.lastMovementY = y

	return moving == true
end

local function isTargetPartyMember()
	if not UnitExists or not UnitExists("target") then
		return nil
	end

	if UnitIsUnit then
		for index = 1, 4 do
			local unit = "party" .. index

			if UnitExists(unit) and UnitIsUnit("target", unit) then
				return true
			end
		end

		if UnitIsUnit("target", "player") then
			return true
		end
	end

	if not UnitName then
		return false
	end

	local name, realm
	if UnitFullName then
		name, realm = UnitFullName("target")
	end

	if isBlank(name) then
		name, realm = UnitName("target")
	end

	if isBlank(name) then
		return false
	end

	local fullName = name
	realm = Player.NormalizeRealmName(realm)

	if realm then
		fullName = name .. "-" .. realm
	end

	if Party and Party.IsPartyMember and (Party.IsPartyMember(fullName) or Party.IsPartyMember(name)) then
		return true
	end

	return Player.IsSelf(name) or Player.IsSelf(fullName)
end

local function isTargetEnemy()
	if not UnitExists or not UnitExists("target") then
		return false
	end

	if UnitCanAttack and UnitCanAttack("player", "target") then
		return true
	end

	if UnitIsEnemy and UnitIsEnemy("player", "target") then
		return true
	end

	return false
end

local function shouldAttemptSound(trigger)
	local now = Timer.Now()

	if trigger.fired then
		return false
	end

	if trigger.lastAttemptAt and now - trigger.lastAttemptAt < trigger.cooldown then
		return false
	end

	trigger.lastAttemptAt = now
	return true
end

local function passesChance(trigger)
	if trigger.ignoreChance or trigger.chance >= 100 then
		return true
	end

	return math.random(100) <= trigger.chance
end

local function playTriggerSound(trigger, reason)
	local ok, playbackOrErr = Sound.Play(trigger.sound or DEFAULT_SOUND)

	if ok and playbackOrErr and playbackOrErr.handle then
		trigger.soundHandles[#trigger.soundHandles + 1] = playbackOrErr.handle
	elseif not ok then
		SoundTriggers.stats.failed = SoundTriggers.stats.failed + 1
		WEP:Log("SoundTriggers", "play_failed", {
			id = trigger.id,
			trigger = trigger.trigger,
			reason = reason or "none",
			sound = trigger.sound or DEFAULT_SOUND,
			error = playbackOrErr,
		}, "warn")
		return false
	end

	SoundTriggers.stats.fired = SoundTriggers.stats.fired + 1
	trigger.lastPlayedAt = Timer.Now()
	WEP:Log("SoundTriggers", "played", {
		id = trigger.id,
		trigger = trigger.trigger,
		reason = reason or "none",
		sound = trigger.sound or DEFAULT_SOUND,
	})
	return true
end

local function attemptTriggerSound(trigger, reason)
	if not shouldAttemptSound(trigger) then
		return false
	end

	if trigger.oneShot then
		trigger.fired = true
	end

	if not passesChance(trigger) then
		SoundTriggers.stats.skipped = SoundTriggers.stats.skipped + 1
		WEP:Log("SoundTriggers", "chance_skipped", {
			id = trigger.id,
			trigger = trigger.trigger,
			chance = trigger.chance,
			reason = reason or "none",
		})
		return false
	end

	return playTriggerSound(trigger, reason)
end

function SoundTriggers.Fire(trigger, reason)
	local normalizedTrigger = SoundTriggers.NormalizeTrigger(trigger)
	if not normalizedTrigger then
		return 0
	end

	local fired = 0

	forEachTrigger(normalizedTrigger, function(activeTrigger)
		if attemptTriggerSound(activeTrigger, reason) then
			fired = fired + 1
		end
	end)

	return fired
end

handleTriggerUpdate = function(_, elapsed)
	movementCheckElapsed = movementCheckElapsed + (tonumber(elapsed) or 0)

	if movementCheckElapsed < MOVEMENT_CHECK_SECONDS then
		return
	end

	movementCheckElapsed = 0

	if isPlayerMoving() then
		SoundTriggers.Fire("walk", "moving")
	end
end

handleTriggerEvent = function(event, ...)
	if event == "PLAYER_TARGET_CHANGED" then
		if isTargetPartyMember() then
			SoundTriggers.Fire("target", "target_party")
		end

		if isTargetEnemy() then
			SoundTriggers.Fire("enemy_target", "enemy_target")
		end

		return
	end

	if event == "PLAYER_REGEN_DISABLED" then
		SoundTriggers.Fire("combat", "combat")
		return
	end

	if event == "UNIT_SPELLCAST_START" then
		local unit = ...

		if unit == "player" then
			SoundTriggers.Fire("cast", "cast")
		end

		return
	end
end

updateTriggerRuntime = function()
	local needsMovement = false
	local needsTarget = false
	local needsCombat = false
	local needsCast = false
	local hasTrigger = false

	for _, trigger in pairs(SoundTriggers.activeTriggers) do
		hasTrigger = true

		if trigger.trigger == "walk" then
			needsMovement = true
		elseif trigger.trigger == "target" or trigger.trigger == "enemy_target" then
			needsTarget = true
		elseif trigger.trigger == "combat" then
			needsCombat = true
		elseif trigger.trigger == "cast" then
			needsCast = true
		end
	end

	if not hasTrigger and not triggerFrame then
		return
	end

	local frame = ensureTriggerFrame()
	if not frame then
		return
	end

	frame:UnregisterAllEvents()

	if needsTarget then
		registerTriggerEvent(frame, "PLAYER_TARGET_CHANGED")
	end

	if needsCombat then
		registerTriggerEvent(frame, "PLAYER_REGEN_DISABLED")
	end

	if needsCast then
		registerTriggerEvent(frame, "UNIT_SPELLCAST_START")
	end

	if needsMovement then
		frame:SetScript("OnUpdate", handleTriggerUpdate)
	else
		movementCheckElapsed = 0
		frame:SetScript("OnUpdate", nil)
	end

	WEP:Log("SoundTriggers", "runtime_updated", {
		movement = needsMovement,
		target = needsTarget,
		combat = needsCombat,
		cast = needsCast,
	})
end

function SoundTriggers.Register(config)
	if type(config) ~= "table" then
		SoundTriggers.stats.failed = SoundTriggers.stats.failed + 1
		return false, "sound trigger config must be a table"
	end

	local trigger = SoundTriggers.NormalizeTrigger(config.trigger)
	if not trigger then
		SoundTriggers.stats.failed = SoundTriggers.stats.failed + 1
		return false, "unknown sound trigger: " .. tostring(config.trigger)
	end

	local triggerId = isBlank(config.id) and makeTriggerId() or tostring(config.id)

	if SoundTriggers.activeTriggers[triggerId] then
		SoundTriggers.Clear(triggerId)
	end

	local activeTrigger = {
		id = triggerId,
		source = config.source,
		trigger = trigger,
		sound = isBlank(config.sound) and DEFAULT_SOUND or tostring(config.sound),
		chance = clamp(config.chance, 0, MAX_CHANCE, DEFAULT_CHANCE),
		cooldown = clamp(config.cooldown, 0.5, 10, SoundTriggers.GetDefaultCooldown(trigger)),
		ignoreChance = config.ignoreChance == true,
		oneShot = config.oneShot == true or (config.oneShot ~= false and trigger == "combat"),
		soundHandles = {},
		startedAt = Timer.Now(),
	}

	SoundTriggers.activeTriggers[triggerId] = activeTrigger
	SoundTriggers.stats.registered = SoundTriggers.stats.registered + 1
	updateTriggerRuntime()
	WEP:Log("SoundTriggers", "registered", {
		id = activeTrigger.id,
		trigger = activeTrigger.trigger,
		sound = activeTrigger.sound,
		chance = activeTrigger.chance,
	})
	return true, triggerId
end

function SoundTriggers.Clear(triggerId)
	if isBlank(triggerId) then
		return false, "sound trigger id is required"
	end

	triggerId = tostring(triggerId)
	local trigger = SoundTriggers.activeTriggers[triggerId]
	if not trigger then
		return false, "unknown sound trigger"
	end

	SoundTriggers.activeTriggers[triggerId] = nil
	stopTriggerSounds(trigger)
	updateTriggerRuntime()
	SoundTriggers.stats.cleared = SoundTriggers.stats.cleared + 1
	WEP:Log("SoundTriggers", "cleared", {
		id = trigger.id,
		trigger = trigger.trigger,
		source = trigger.source or "none",
	})
	return true
end

function SoundTriggers.ClearAll()
	local triggerIds = {}

	for triggerId in pairs(SoundTriggers.activeTriggers) do
		triggerIds[#triggerIds + 1] = triggerId
	end

	for _, triggerId in ipairs(triggerIds) do
		SoundTriggers.Clear(triggerId)
	end

	return #triggerIds
end

function SoundTriggers.GetStatus()
	local triggers = {}

	for _, trigger in pairs(SoundTriggers.activeTriggers) do
		triggers[#triggers + 1] = copyTriggerStatus(trigger)
	end

	table.sort(triggers, function(left, right)
		return left.id < right.id
	end)

	return {
		activeCount = #triggers,
		triggers = triggers,
		stats = SoundTriggers.stats,
	}
end
