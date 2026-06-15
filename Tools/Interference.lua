local _, WEP = ...

WEP.Tools = WEP.Tools or {}

local Interference = {
	activeEffects = {},
	stats = {
		applied = 0,
		cleared = 0,
		failed = 0,
	},
}

WEP.Tools.Interference = Interference

local Timer = WEP.Tools.Timer
local Player = WEP.Tools.Player
local Party = WEP.Tools.Party
local ScreenOverlay = WEP.Tools.ScreenOverlay
local UIVisibility = WEP.Tools.UIVisibility
local Sound = WEP.Tools.Sound

WEP:Log("Interference", "loaded")

local DEFAULT_DURATION_SECONDS = 8
local MIN_DURATION_SECONDS = 1
local MAX_DURATION_SECONDS = 30
local DEFAULT_INTENSITY = 70
local MIN_INTENSITY = 10
local MAX_INTENSITY = 95
local DEFAULT_SOUND = "wep_alert"
local DEFAULT_SOUND_INTERVAL_SECONDS = 1.5
local SOUND_PLAY_SECONDS = 1
local DEFAULT_SOUND_TRAP_CHANCE = 100
local MAX_SOUND_TRAP_CHANCE = 100
local DEFAULT_SOUND_TRAP_COOLDOWN_SECONDS = 2
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

local function sourceKey(source)
	local normalized = string.lower(Player.NormalizeName(source))
	local dashIndex = normalized:find("-", 1, true)

	if dashIndex then
		normalized = normalized:sub(1, dashIndex - 1)
	end

	return normalized
end

local function makeEffectId()
	Interference.effectCounter = (Interference.effectCounter or 0) + 1
	return "ifx" .. Timer.Now() .. "." .. Interference.effectCounter
end

local function copyEffectStatus(effect)
	return {
		id = effect.id,
		action = effect.action,
		source = effect.source,
		group = effect.group,
		sound = effect.sound,
		trigger = effect.trigger,
		chance = effect.chance,
		intensity = effect.intensity,
		startedAt = effect.startedAt,
		expiresAt = effect.expiresAt,
	}
end

local function stopEffectSounds(effect)
	if not effect.soundHandles then
		return
	end

	for _, handle in ipairs(effect.soundHandles) do
		Sound.Stop(handle, 0)
	end

	effect.soundHandles = {}
end

local trapFrame
local movementCheckElapsed = 0
local handleTrapEvent
local handleTrapUpdate
local updateTrapRuntime

local function normalizeTrigger(trigger)
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

local function isSoundTrap(effect)
	return effect and effect.action == "sound_trap"
end

local function getTrapCooldown(trigger)
	if trigger == "combat" then
		return 0.5
	end

	return DEFAULT_SOUND_TRAP_COOLDOWN_SECONDS
end

local function ensureTrapFrame()
	if trapFrame then
		return trapFrame
	end

	if not CreateFrame then
		WEP:Log("Interference", "sound_trap_frame_unavailable", nil, "warn")
		return nil
	end

	trapFrame = CreateFrame("Frame")
	trapFrame:SetScript("OnEvent", function(_, event, ...)
		if handleTrapEvent then
			handleTrapEvent(event, ...)
		end
	end)
	WEP:Log("Interference", "sound_trap_frame_created")
	return trapFrame
end

local function registerTrapEvent(frame, event)
	local ok, err = pcall(frame.RegisterEvent, frame, event)

	if not ok then
		WEP:Log("Interference", "sound_trap_event_unavailable", {
			event = event,
			error = err,
		}, "warn")
	end
end

local function forEachSoundTrap(trigger, callback)
	for _, effect in pairs(Interference.activeEffects) do
		if isSoundTrap(effect) and effect.trigger == trigger then
			callback(effect)
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

	local moving = Interference.lastMovementMapId == mapId
		and Interference.lastMovementX
		and Interference.lastMovementY
		and (math.abs(x - Interference.lastMovementX) > 0.00001 or math.abs(y - Interference.lastMovementY) > 0.00001)

	Interference.lastMovementMapId = mapId
	Interference.lastMovementX = x
	Interference.lastMovementY = y

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

local function shouldAttemptSound(effect)
	local now = Timer.Now()

	if effect.fired then
		return false
	end

	if effect.lastAttemptAt and now - effect.lastAttemptAt < effect.cooldown then
		return false
	end

	effect.lastAttemptAt = now
	return true
end

local function passesChance(effect)
	if effect.ignoreChance or effect.chance >= 100 then
		return true
	end

	return math.random(100) <= effect.chance
end

local function playTrapSound(effect, reason)
	local ok, playbackOrErr = Sound.Play(effect.sound or DEFAULT_SOUND)

	if ok and playbackOrErr and playbackOrErr.handle then
		effect.soundHandles[#effect.soundHandles + 1] = playbackOrErr.handle
	elseif not ok then
		WEP:Log("Interference", "sound_trap_play_failed", {
			id = effect.id,
			trigger = effect.trigger,
			reason = reason or "none",
			sound = effect.sound or DEFAULT_SOUND,
			error = playbackOrErr,
		}, "warn")
		return false
	end

	effect.lastPlayedAt = Timer.Now()
	WEP:Log("Interference", "sound_trap_played", {
		id = effect.id,
		trigger = effect.trigger,
		reason = reason or "none",
		sound = effect.sound or DEFAULT_SOUND,
	})
	return true
end

local function attemptTrapSound(effect, reason)
	if not shouldAttemptSound(effect) then
		return false
	end

	if effect.oneShot then
		effect.fired = true
	end

	if not passesChance(effect) then
		WEP:Log("Interference", "sound_trap_chance_skipped", {
			id = effect.id,
			trigger = effect.trigger,
			chance = effect.chance,
			reason = reason or "none",
		})
		return false
	end

	return playTrapSound(effect, reason)
end

local function initializeSoundTrap(effect)
	effect.soundHandles = {}
	effect.oneShot = effect.trigger == "combat"

	if updateTrapRuntime then
		updateTrapRuntime()
	end

	return true
end

handleTrapUpdate = function(_, elapsed)
	movementCheckElapsed = movementCheckElapsed + (tonumber(elapsed) or 0)

	if movementCheckElapsed < MOVEMENT_CHECK_SECONDS then
		return
	end

	movementCheckElapsed = 0

	if not isPlayerMoving() then
		return
	end

	forEachSoundTrap("walk", function(effect)
		attemptTrapSound(effect, "moving")
	end)
end

handleTrapEvent = function(event, ...)
	if event == "PLAYER_TARGET_CHANGED" then
		if isTargetPartyMember() then
			forEachSoundTrap("target", function(effect)
				attemptTrapSound(effect, "target_party")
			end)
		end

		if isTargetEnemy() then
			forEachSoundTrap("enemy_target", function(effect)
				attemptTrapSound(effect, "enemy_target")
			end)
		end

		return
	end

	if event == "PLAYER_REGEN_DISABLED" then
		forEachSoundTrap("combat", function(effect)
			attemptTrapSound(effect, "combat")
		end)
		return
	end

	if event == "UNIT_SPELLCAST_START" then
		local unit = ...

		if unit == "player" then
			forEachSoundTrap("cast", function(effect)
				attemptTrapSound(effect, "cast")
			end)
		end

		return
	end
end

updateTrapRuntime = function()
	local needsMovement = false
	local needsTarget = false
	local needsCombat = false
	local needsCast = false
	local hasSoundTrap = false

	for _, effect in pairs(Interference.activeEffects) do
		if isSoundTrap(effect) then
			hasSoundTrap = true

			if effect.trigger == "walk" then
				needsMovement = true
			elseif effect.trigger == "target" or effect.trigger == "enemy_target" then
				needsTarget = true
			elseif effect.trigger == "combat" then
				needsCombat = true
			elseif effect.trigger == "cast" then
				needsCast = true
			end
		end
	end

	if not hasSoundTrap and not trapFrame then
		return
	end

	local frame = ensureTrapFrame()
	if not frame then
		return
	end

	frame:UnregisterAllEvents()

	if needsTarget then
		registerTrapEvent(frame, "PLAYER_TARGET_CHANGED")
	end

	if needsCombat then
		registerTrapEvent(frame, "PLAYER_REGEN_DISABLED")
	end

	if needsCast then
		registerTrapEvent(frame, "UNIT_SPELLCAST_START")
	end

	if needsMovement then
		frame:SetScript("OnUpdate", handleTrapUpdate)
	else
		movementCheckElapsed = 0
		frame:SetScript("OnUpdate", nil)
	end

	WEP:Log("Interference", "sound_trap_runtime_updated", {
		movement = needsMovement,
		target = needsTarget,
		combat = needsCombat,
		cast = needsCast,
	})
end

local function clearEffect(effect)
	if effect.action == "blackout" then
		ScreenOverlay.ClearBlackoutFor(effect.id)
	elseif effect.action == "hide_ui" then
		UIVisibility.ShowFor(effect.id, effect.group)
	elseif effect.action == "sound" then
		effect.soundToken = (effect.soundToken or 0) + 1
		stopEffectSounds(effect)
	elseif effect.action == "sound_trap" then
		stopEffectSounds(effect)
	end
end

local function scheduleExpiry(effect)
	local token = effect.token

	Timer.After(effect.duration, function()
		local activeEffect = Interference.activeEffects[effect.id]

		if activeEffect and activeEffect.token == token then
			Interference.Clear(effect.id)
		end
	end)
end

local function playSoundTick(effect)
	local activeEffect = Interference.activeEffects[effect.id]

	if activeEffect ~= effect then
		return
	end

	local ok, playbackOrErr = Sound.Play(effect.sound or DEFAULT_SOUND, {
		duration = SOUND_PLAY_SECONDS,
	})

	if ok and playbackOrErr and playbackOrErr.handle then
		effect.soundHandles[#effect.soundHandles + 1] = playbackOrErr.handle
	elseif not ok then
		WEP:Log("Interference", "sound_play_failed", {
			id = effect.id,
			sound = effect.sound or DEFAULT_SOUND,
			error = playbackOrErr,
		}, "warn")
	end

	if C_Timer and C_Timer.After and Timer.Now() < effect.expiresAt then
		local token = effect.soundToken

		Timer.After(effect.repeatInterval, function()
			if effect.soundToken == token then
				playSoundTick(effect)
			end
		end)
	end
end

local function applyEffect(effect)
	if effect.action == "blackout" then
		return ScreenOverlay.SetBlackoutFor(effect.id, effect.intensity)
	end

	if effect.action == "hide_ui" then
		return UIVisibility.HideFor(effect.id, effect.group)
	end

	if effect.action == "sound" then
		effect.soundHandles = {}
		effect.soundToken = (effect.soundToken or 0) + 1
		playSoundTick(effect)
		return true
	end

	if effect.action == "sound_trap" then
		return initializeSoundTrap(effect)
	end

	return false, "unknown interference action: " .. tostring(effect.action)
end

function Interference.Apply(effect)
	if type(effect) ~= "table" then
		Interference.stats.failed = Interference.stats.failed + 1
		return false, "effect must be a table"
	end

	local action = effect.action or effect.kind
	if isBlank(action) then
		Interference.stats.failed = Interference.stats.failed + 1
		return false, "effect action is required"
	end

	local trigger
	if action == "sound_trap" then
		trigger = normalizeTrigger(effect.trigger)
		if not trigger then
			Interference.stats.failed = Interference.stats.failed + 1
			return false, "unknown sound trap trigger: " .. tostring(effect.trigger)
		end
	end

	local effectId = isBlank(effect.id) and makeEffectId() or tostring(effect.id)

	if Interference.activeEffects[effectId] then
		Interference.Clear(effectId)
	end

	local normalizedEffect = {
		id = effectId,
		action = tostring(action),
		source = effect.source or "unknown",
		sourceKey = sourceKey(effect.source),
		group = effect.group,
		sound = effect.sound or DEFAULT_SOUND,
		trigger = trigger,
		chance = clamp(effect.chance or effect.intensity, 0, MAX_SOUND_TRAP_CHANCE, DEFAULT_SOUND_TRAP_CHANCE),
		intensity = clamp(effect.intensity, MIN_INTENSITY, MAX_INTENSITY, DEFAULT_INTENSITY),
		duration = clamp(effect.duration, MIN_DURATION_SECONDS, MAX_DURATION_SECONDS, DEFAULT_DURATION_SECONDS),
		repeatInterval = clamp(effect.repeatInterval, 0.5, 5, DEFAULT_SOUND_INTERVAL_SECONDS),
		cooldown = clamp(effect.cooldown, 0.5, 10, trigger and getTrapCooldown(trigger) or DEFAULT_SOUND_TRAP_COOLDOWN_SECONDS),
		startedAt = Timer.Now(),
		token = Timer.Now() .. "." .. effectId,
	}
	normalizedEffect.expiresAt = normalizedEffect.startedAt + normalizedEffect.duration

	Interference.activeEffects[effectId] = normalizedEffect

	local ok, err = applyEffect(normalizedEffect)
	if not ok then
		Interference.activeEffects[effectId] = nil
		Interference.stats.failed = Interference.stats.failed + 1
		WEP:Log("Interference", "apply_failed", {
			id = effectId,
			action = normalizedEffect.action,
			error = err,
		}, "error")
		return false, err
	end

	Interference.stats.applied = Interference.stats.applied + 1
	WEP:Log("Interference", "applied", {
		id = effectId,
		action = normalizedEffect.action,
		source = normalizedEffect.source,
		duration = normalizedEffect.duration,
	})
	scheduleExpiry(normalizedEffect)
	return true, effectId
end

function Interference.Clear(effectId)
	if isBlank(effectId) then
		return false, "effect id is required"
	end

	effectId = tostring(effectId)
	local effect = Interference.activeEffects[effectId]
	if not effect then
		return false, "unknown effect"
	end

	Interference.activeEffects[effectId] = nil
	clearEffect(effect)
	if updateTrapRuntime then
		updateTrapRuntime()
	end
	Interference.stats.cleared = Interference.stats.cleared + 1
	WEP:Log("Interference", "cleared", {
		id = effect.id,
		action = effect.action,
		source = effect.source,
	})
	return true
end

function Interference.ClearBySource(source)
	local key = sourceKey(source)
	local effectIds = {}

	for effectId, effect in pairs(Interference.activeEffects) do
		if key ~= "" and effect.sourceKey == key then
			effectIds[#effectIds + 1] = effectId
		end
	end

	for _, effectId in ipairs(effectIds) do
		Interference.Clear(effectId)
	end

	WEP:Log("Interference", "cleared_by_source", {
		source = source or "none",
		count = #effectIds,
	})
	return #effectIds
end

function Interference.GetStatus()
	local effects = {}

	for _, effect in pairs(Interference.activeEffects) do
		effects[#effects + 1] = copyEffectStatus(effect)
	end

	table.sort(effects, function(left, right)
		return left.id < right.id
	end)

	return {
		activeCount = #effects,
		effects = effects,
		stats = Interference.stats,
	}
end
