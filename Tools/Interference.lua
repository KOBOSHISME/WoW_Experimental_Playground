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
local ScreenOverlay = WEP.Tools.ScreenOverlay
local UIVisibility = WEP.Tools.UIVisibility
local Sound = WEP.Tools.Sound
local SoundTriggers = WEP.Tools.SoundTriggers

WEP:Log("Interference", "loaded")

local DEFAULT_DURATION_SECONDS = 8
local MIN_DURATION_SECONDS = 1
local MAX_DURATION_SECONDS = 900
local DEFAULT_INTENSITY = 70
local MIN_INTENSITY = 10
local MAX_INTENSITY = 95
local DEFAULT_SOUND = "wep_alert"
local DEFAULT_SOUND_INTERVAL_SECONDS = 1.5
local SOUND_PLAY_SECONDS = 1

local function isBlank(value)
	return value == nil or tostring(value) == ""
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
		variant = effect.variant,
		message = effect.message,
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

local function normalizeSoundTrigger(trigger)
	if not SoundTriggers or not SoundTriggers.NormalizeTrigger then
		return nil
	end

	return SoundTriggers.NormalizeTrigger(trigger)
end

local function getSoundTriggerDefaultCooldown(trigger)
	if SoundTriggers and SoundTriggers.GetDefaultCooldown then
		return SoundTriggers.GetDefaultCooldown(trigger)
	end

	return 2
end

local function clearEffect(effect)
	if effect.action == "blackout" then
		ScreenOverlay.ClearBlackoutFor(effect.id)
	elseif effect.action == "tint" then
		ScreenOverlay.ClearTintFor(effect.id)
	elseif effect.action == "pulse" then
		ScreenOverlay.ClearPulseFor(effect.id)
	elseif effect.action == "vignette" then
		ScreenOverlay.ClearVignetteFor(effect.id)
	elseif effect.action == "letterbox" then
		ScreenOverlay.ClearLetterboxFor(effect.id)
	elseif effect.action == "fake_notice" then
		ScreenOverlay.ClearFakeNoticeFor(effect.id)
	elseif effect.action == "hide_ui" then
		UIVisibility.ShowFor(effect.id, effect.group)
	elseif effect.action == "sound" then
		effect.soundToken = (effect.soundToken or 0) + 1
		stopEffectSounds(effect)
	elseif effect.action == "sound_trap" then
		if SoundTriggers and SoundTriggers.Clear then
			SoundTriggers.Clear(effect.soundTriggerId or effect.id)
		end
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

	if effect.action == "tint" then
		return ScreenOverlay.SetTintFor(effect.id, effect.variant, effect.intensity)
	end

	if effect.action == "pulse" then
		return ScreenOverlay.SetPulseFor(effect.id, effect.variant, effect.intensity)
	end

	if effect.action == "vignette" then
		return ScreenOverlay.SetVignetteFor(effect.id, effect.variant, effect.intensity)
	end

	if effect.action == "letterbox" then
		return ScreenOverlay.SetLetterboxFor(effect.id, effect.intensity)
	end

	if effect.action == "fake_notice" then
		return ScreenOverlay.ShowFakeNoticeFor(effect.id, effect.variant, effect.message, effect.intensity)
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
		if not SoundTriggers or not SoundTriggers.Register then
			return false, "sound trigger tool is unavailable"
		end

		local ok, triggerIdOrErr = SoundTriggers.Register({
			id = effect.id,
			source = effect.source,
			trigger = effect.trigger,
			sound = effect.sound,
			chance = effect.chance,
			cooldown = effect.cooldown,
		})

		if ok then
			effect.soundTriggerId = triggerIdOrErr
		end

		return ok, triggerIdOrErr
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
		trigger = normalizeSoundTrigger(effect.trigger)
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
		variant = effect.variant or effect.preset,
		message = effect.message,
		chance = clamp(effect.chance or effect.intensity, 0, 100, 100),
		intensity = clamp(effect.intensity, MIN_INTENSITY, MAX_INTENSITY, DEFAULT_INTENSITY),
		duration = clamp(effect.duration, MIN_DURATION_SECONDS, MAX_DURATION_SECONDS, DEFAULT_DURATION_SECONDS),
		repeatInterval = clamp(effect.repeatInterval, 0.5, 5, DEFAULT_SOUND_INTERVAL_SECONDS),
		cooldown = clamp(effect.cooldown, 0.5, 10, getSoundTriggerDefaultCooldown(trigger)),
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
