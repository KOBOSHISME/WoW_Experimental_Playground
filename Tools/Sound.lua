local _, WEP = ...

WEP.Tools = WEP.Tools or {}

local Sound = {
	gameSounds = {},
	customSounds = {},
	activeHandles = {},
	stats = {
		played = 0,
		failed = 0,
		skipped = 0,
		stopped = 0,
	},
}

WEP.Tools.Sound = Sound

local Timer = WEP.Tools.Timer

WEP:Log("Sound", "loaded")

local DEFAULT_CHANNEL = "Master"
local DEFAULT_CUSTOM_DIR = "Sounds\\Custom"
local ADDON_SOUND_PREFIX = "Interface\\AddOns\\"
local VOLUME_SUPPORTED = false

local CHANNELS = {
	ambience = "Ambience",
	dialog = "Dialog",
	master = "Master",
	music = "Music",
	sfx = "SFX",
}

local DEFAULT_GAME_SOUNDS = {
	checkbox_off = {
		label = "Checkbox Off",
		soundKit = "IG_MAINMENU_OPTION_CHECKBOX_OFF",
		fallback = 857,
	},
	checkbox_on = {
		label = "Checkbox On",
		soundKit = "IG_MAINMENU_OPTION_CHECKBOX_ON",
		fallback = 856,
	},
	ui_close = {
		label = "UI Close",
		soundKit = "IG_MAINMENU_CLOSE",
		fallback = 851,
	},
	ui_open = {
		label = "UI Open",
		soundKit = "IG_MAINMENU_OPEN",
		fallback = 850,
	},
	ui_select = {
		label = "UI Select",
		soundKit = "IG_MAINMENU_OPTION",
		fallback = 852,
	},
}

local function isBlank(value)
	return value == nil or tostring(value) == ""
end

local function clamp(value, minValue, maxValue)
	value = tonumber(value) or maxValue

	if value < minValue then
		return minValue
	end

	if value > maxValue then
		return maxValue
	end

	return value
end

local function countEntries(values)
	local count = 0

	for _ in pairs(values) do
		count = count + 1
	end

	return count
end

local function copyNamedSounds(sounds)
	local copied = {}

	for name, sound in pairs(sounds) do
		copied[#copied + 1] = {
			name = name,
			label = sound.label or name,
			kind = sound.kind,
			path = sound.path,
			relativePath = sound.relativePath,
			soundKit = sound.soundKit,
		}
	end

	table.sort(copied, function(left, right)
		return left.name < right.name
	end)

	return copied
end

local function normalizeChannel(channel)
	if isBlank(channel) then
		return DEFAULT_CHANNEL
	end

	return CHANNELS[string.lower(tostring(channel))] or tostring(channel)
end

local function normalizeVolume(volume)
	if volume == nil or volume == "" then
		return 100
	end

	volume = tonumber(volume)
	if not volume then
		return 100
	end

	if volume > 0 and volume <= 1 then
		volume = volume * 100
	end

	return clamp(volume, 0, 100)
end

local function normalizeDuration(duration)
	duration = tonumber(duration)

	if not duration or duration <= 0 then
		return nil
	end

	return duration
end

local function normalizeOptions(options)
	options = options or {}

	return {
		channel = normalizeChannel(options.channel),
		duration = normalizeDuration(options.duration or options.seconds),
		fadeOut = clamp(options.fadeOut or options.fadeout or 0, 0, 60),
		volume = normalizeVolume(options.volume),
	}
end

local function normalizeRelativePath(relativePath)
	if isBlank(relativePath) then
		return nil, "sound path is required"
	end

	local path = tostring(relativePath):gsub("/", "\\")

	while path:sub(1, 1) == "\\" do
		path = path:sub(2)
	end

	if path:find(":", 1, true) or path:find("..", 1, true) then
		return nil, "custom sound path must be relative to the addon"
	end

	return path
end

local function makeAddonPath(relativePath)
	local path, err = normalizeRelativePath(relativePath)
	if not path then
		return nil, err
	end

	return ADDON_SOUND_PREFIX .. WEP.name .. "\\" .. path
end

local function makeCustomPath(fileName)
	local path, err = normalizeRelativePath(fileName)
	if not path then
		return nil, err
	end

	local lowerPath = string.lower(path)
	local lowerCustomDir = string.lower(DEFAULT_CUSTOM_DIR)

	if lowerPath:sub(1, #lowerCustomDir + 1) == lowerCustomDir .. "\\" then
		return makeAddonPath(path)
	end

	return makeAddonPath(DEFAULT_CUSTOM_DIR .. "\\" .. path)
end

local function makeCustomRelativePath(fileName)
	local path, err = normalizeRelativePath(fileName)
	if not path then
		return nil, err
	end

	local lowerPath = string.lower(path)
	local lowerCustomDir = string.lower(DEFAULT_CUSTOM_DIR)

	if lowerPath:sub(1, #lowerCustomDir + 1) == lowerCustomDir .. "\\" then
		return path
	end

	return DEFAULT_CUSTOM_DIR .. "\\" .. path
end

local function resolveSoundKit(sound)
	if type(sound.soundKit) == "number" then
		return sound.soundKit
	end

	if type(sound.soundKit) == "string" then
		if SOUNDKIT and SOUNDKIT[sound.soundKit] then
			return SOUNDKIT[sound.soundKit]
		end

		return tonumber(sound.soundKit) or sound.fallback or sound.soundKit
	end

	return sound.fallback
end

local function makePlayback(resolved, options, handle)
	Sound.playbackCounter = (Sound.playbackCounter or 0) + 1

	return {
		id = Sound.playbackCounter,
		name = resolved.name,
		kind = resolved.kind,
		channel = options.channel,
		duration = options.duration,
		durationApplied = false,
		fadeOut = options.fadeOut,
		handle = handle,
		startedAt = Timer.Now(),
		volume = options.volume,
		volumeApplied = VOLUME_SUPPORTED,
		volumeSupported = VOLUME_SUPPORTED,
	}
end

local function trackDuration(playback)
	if not playback.duration or not playback.handle or not StopSound or not C_Timer or not C_Timer.After then
		return
	end

	Sound.activeHandles[playback.handle] = playback
	playback.durationApplied = true

	Timer.After(playback.duration, function()
		if Sound.activeHandles[playback.handle] == playback then
			Sound.Stop(playback.handle, playback.fadeOut)
		end
	end)
end

local function playWith(playFunction, resolved, options, ...)
	if type(playFunction) ~= "function" then
		Sound.stats.failed = Sound.stats.failed + 1
		WEP:Log("Sound", "play_failed", {
			name = resolved and resolved.name or "unknown",
			error = "sound playback API is unavailable",
		}, "error")
		return false, "sound playback API is unavailable"
	end

	if options.volume <= 0 then
		local playback = makePlayback(resolved, options)
		playback.skipped = true
		playback.reason = "volume is 0"
		Sound.stats.skipped = Sound.stats.skipped + 1
		WEP:Log("Sound", "play_skipped", {
			name = playback.name,
			reason = playback.reason,
			volume = playback.volume,
		}, "warn")
		return true, playback
	end

	local ok, willPlay, handle = pcall(playFunction, ...)
	if not ok then
		Sound.stats.failed = Sound.stats.failed + 1
		WEP:Log("Sound", "play_failed", {
			name = resolved and resolved.name or "unknown",
			error = willPlay,
		}, "error")
		return false, willPlay
	end

	if handle == nil and type(willPlay) == "number" then
		handle = willPlay
	end

	if willPlay == false then
		Sound.stats.failed = Sound.stats.failed + 1
		WEP:Log("Sound", "play_failed", {
			name = resolved and resolved.name or "unknown",
			error = "sound did not play",
		}, "error")
		return false, "sound did not play"
	end

	local playback = makePlayback(resolved, options, handle)
	trackDuration(playback)
	Sound.stats.played = Sound.stats.played + 1
	WEP:Log("Sound", "played", {
		name = playback.name,
		kind = playback.kind,
		channel = playback.channel,
		handle = playback.handle or "none",
		duration = playback.duration or "none",
	})

	return true, playback
end

function Sound.RegisterGame(name, soundKit, label)
	if isBlank(name) then
		WEP:Log("Sound", "register_game_failed", {
			error = "sound name is required",
		}, "error")
		return false, "sound name is required"
	end

	if isBlank(soundKit) then
		WEP:Log("Sound", "register_game_failed", {
			name = name,
			error = "sound kit is required",
		}, "error")
		return false, "sound kit is required"
	end

	local soundName = tostring(name)
	Sound.gameSounds[soundName] = {
		kind = "game",
		name = soundName,
		label = label or soundName,
		soundKit = soundKit,
	}

	WEP:Log("Sound", "register_game", {
		name = soundName,
		label = label or soundName,
	})
	return true
end

function Sound.RegisterCustom(name, relativePath, label)
	if isBlank(name) then
		WEP:Log("Sound", "register_custom_failed", {
			error = "sound name is required",
		}, "error")
		return false, "sound name is required"
	end

	local customRelativePath, relativePathErr = makeCustomRelativePath(relativePath)
	if not customRelativePath then
		WEP:Log("Sound", "register_custom_failed", {
			name = name,
			error = relativePathErr,
		}, "error")
		return false, relativePathErr
	end

	local path, pathErr = makeAddonPath(customRelativePath)
	if not path then
		WEP:Log("Sound", "register_custom_failed", {
			name = name,
			error = pathErr,
		}, "error")
		return false, pathErr
	end

	local soundName = tostring(name)
	Sound.customSounds[soundName] = {
		kind = "custom",
		name = soundName,
		label = label or soundName,
		path = path,
		relativePath = customRelativePath,
	}

	WEP:Log("Sound", "register_custom", {
		name = soundName,
		path = customRelativePath,
	})
	return true
end

function Sound.GetGameSounds()
	return copyNamedSounds(Sound.gameSounds)
end

function Sound.GetCustomSounds()
	return copyNamedSounds(Sound.customSounds)
end

function Sound.Resolve(sound)
	if type(sound) == "number" then
		return {
			kind = "game",
			name = tostring(sound),
			soundKit = sound,
		}
	end

	if type(sound) == "table" then
		return sound
	end

	if isBlank(sound) then
		return nil, "sound is required"
	end

	local soundName = tostring(sound)
	local gameSound = Sound.gameSounds[soundName]
	if gameSound then
		return gameSound
	end

	local customSound = Sound.customSounds[soundName]
	if customSound then
		return customSound
	end

	local prefix = soundName:match("^([^:]+):")
	local value = prefix and soundName:sub(#prefix + 2) or nil
	prefix = prefix and string.lower(prefix) or nil

	if prefix == "game" then
		if isBlank(value) then
			return nil, "game sound kit is required"
		end

		return {
			kind = "game",
			name = soundName,
			soundKit = tonumber(value) or value,
		}
	end

	if prefix == "custom" then
		local path, pathErr = makeCustomPath(value)
		if not path then
			return nil, pathErr
		end

		local relativePath = makeCustomRelativePath(value)

		return {
			kind = "custom",
			name = soundName,
			path = path,
			relativePath = relativePath,
		}
	end

	if prefix == "file" then
		if isBlank(value) then
			return nil, "file path is required"
		end

		return {
			kind = "file",
			name = soundName,
			path = value:gsub("/", "\\"),
		}
	end

	local soundKit = tonumber(soundName)
	if soundKit then
		return {
			kind = "game",
			name = soundName,
			soundKit = soundKit,
		}
	end

	return nil, "unknown sound: " .. soundName
end

function Sound.Play(sound, options)
	local resolved, resolveErr = Sound.Resolve(sound)
	if not resolved then
		WEP:Log("Sound", "resolve_failed", {
			sound = sound,
			error = resolveErr,
		}, "error")
		return false, resolveErr
	end

	options = normalizeOptions(options)

	if resolved.kind == "game" then
		local soundKit = resolveSoundKit(resolved)
		if not soundKit then
			WEP:Log("Sound", "play_failed", {
				name = resolved.name,
				error = "game sound kit is unavailable",
			}, "error")
			return false, "game sound kit is unavailable"
		end

		return playWith(PlaySound, resolved, options, soundKit, options.channel)
	end

	if resolved.kind == "custom" or resolved.kind == "file" then
		if isBlank(resolved.path) then
			WEP:Log("Sound", "play_failed", {
				name = resolved.name,
				error = "sound file path is required",
			}, "error")
			return false, "sound file path is required"
		end

		return playWith(PlaySoundFile, resolved, options, resolved.path, options.channel)
	end

	WEP:Log("Sound", "play_failed", {
		name = resolved.name,
		kind = resolved.kind,
		error = "unsupported sound kind",
	}, "error")
	return false, "unsupported sound kind: " .. tostring(resolved.kind)
end

function Sound.PlayGame(soundKit, options)
	return Sound.Play({
		kind = "game",
		name = tostring(soundKit),
		soundKit = soundKit,
	}, options)
end

function Sound.PlayCustom(fileName, options)
	local path, pathErr = makeCustomPath(fileName)
	if not path then
		return false, pathErr
	end

	local relativePath = makeCustomRelativePath(fileName)

	return Sound.Play({
		kind = "custom",
		name = tostring(fileName),
		path = path,
		relativePath = relativePath,
	}, options)
end

function Sound.PlayFile(path, options)
	return Sound.Play({
		kind = "file",
		name = tostring(path),
		path = tostring(path):gsub("/", "\\"),
	}, options)
end

function Sound.Stop(handle, fadeOut)
	if not handle then
		WEP:Log("Sound", "stop_failed", {
			error = "sound handle is required",
		}, "error")
		return false, "sound handle is required"
	end

	if type(StopSound) ~= "function" then
		WEP:Log("Sound", "stop_failed", {
			handle = handle,
			error = "StopSound API is unavailable",
		}, "error")
		return false, "StopSound API is unavailable"
	end

	local ok, err = pcall(StopSound, handle, clamp(fadeOut or 0, 0, 60))
	if not ok then
		Sound.stats.failed = Sound.stats.failed + 1
		WEP:Log("Sound", "stop_failed", {
			handle = handle,
			error = err,
		}, "error")
		return false, err
	end

	Sound.activeHandles[handle] = nil
	Sound.stats.stopped = Sound.stats.stopped + 1
	WEP:Log("Sound", "stopped", {
		handle = handle,
		fadeOut = fadeOut or 0,
	})

	return true
end

function Sound.StopAll(fadeOut)
	local stopped = 0

	for handle in pairs(Sound.activeHandles) do
		local ok = Sound.Stop(handle, fadeOut)
		if ok then
			stopped = stopped + 1
		end
	end

	WEP:Log("Sound", "stop_all", {
		stopped = stopped,
		fadeOut = fadeOut or 0,
	})
	return stopped
end

function Sound.GetStatus()
	return {
		activeCount = countEntries(Sound.activeHandles),
		customSounds = Sound.GetCustomSounds(),
		gameSounds = Sound.GetGameSounds(),
		stats = Sound.stats,
		volumeSupported = VOLUME_SUPPORTED,
	}
end

for name, sound in pairs(DEFAULT_GAME_SOUNDS) do
	Sound.RegisterGame(name, sound.soundKit, sound.label)
	Sound.gameSounds[name].fallback = sound.fallback
end

Sound.RegisterCustom("wep_alert", "wep-alert.wav", "WEP Alert")
