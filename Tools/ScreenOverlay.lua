local _, WEP = ...

WEP.Tools = WEP.Tools or {}

local ScreenOverlay = {}
WEP.Tools.ScreenOverlay = ScreenOverlay

WEP:Log("ScreenOverlay", "loaded")

local BLACKOUT_FRAME_NAME = "WEPScreenBlackoutOverlay"
local TINT_FRAME_NAME = "WEPScreenTintOverlay"
local PULSE_FRAME_NAME = "WEPScreenPulseOverlay"
local VIGNETTE_FRAME_NAME = "WEPScreenVignetteOverlay"
local LETTERBOX_FRAME_NAME = "WEPScreenLetterboxOverlay"
local FAKE_NOTICE_FRAME_NAME = "WEPScreenFakeNoticeOverlay"
local DEFAULT_FRAME_STRATA = "FULLSCREEN_DIALOG"
local DEFAULT_FRAME_LEVEL = 25
local DEFAULT_VIGNETTE_TEXTURE = "Interface\\FullScreenTextures\\LowHealth"
local DEFAULT_OWNER = "default"
local DEFAULT_TINT_PRESET = "red"
local DEFAULT_PULSE_PRESET = "panic"
local DEFAULT_VIGNETTE_PRESET = "tunnel"
local DEFAULT_NOTICE_PRESET = "raid"

local COLOR_PRESETS = {
	red = {
		r = 1,
		g = 0.03,
		b = 0.02,
		alpha = 0.62,
	},
	fel = {
		r = 0.1,
		g = 1,
		b = 0.18,
		alpha = 0.48,
	},
	arcane = {
		r = 0.58,
		g = 0.18,
		b = 1,
		alpha = 0.5,
	},
	snow = {
		r = 1,
		g = 1,
		b = 1,
		alpha = 0.66,
	},
}
COLOR_PRESETS.redalert = COLOR_PRESETS.red
COLOR_PRESETS.felgoggles = COLOR_PRESETS.fel
COLOR_PRESETS.arcanehaze = COLOR_PRESETS.arcane
COLOR_PRESETS.snowblind = COLOR_PRESETS.snow

local PULSE_PRESETS = {
	panic = {
		r = 1,
		g = 0,
		b = 0,
		minAlpha = 0.04,
		alpha = 0.7,
		speed = 9,
	},
}
PULSE_PRESETS.panicflash = PULSE_PRESETS.panic

local VIGNETTE_PRESETS = {
	tunnel = {
		r = 0,
		g = 0,
		b = 0,
		alpha = 0.92,
	},
}
VIGNETTE_PRESETS.tunnelvision = VIGNETTE_PRESETS.tunnel

local NOTICE_PRESETS = {
	raid = {
		title = "RAID WARNING",
		message = "Move now!",
		r = 1,
		g = 0.08,
		b = 0.05,
	},
	error = {
		title = "ERROR STORM",
		message = "Spell is not ready yet\nAbility is not ready yet\nOut of range",
		r = 1,
		g = 0.05,
		b = 0.05,
	},
	loot = {
		title = "You receive loot",
		message = "[Definitely Real Thunderfury]",
		r = 1,
		g = 0.82,
		b = 0.08,
	},
}
NOTICE_PRESETS.fakeraidwarning = NOTICE_PRESETS.raid
NOTICE_PRESETS.errorstorm = NOTICE_PRESETS.error
NOTICE_PRESETS.lootmirage = NOTICE_PRESETS.loot

local blackoutFrame
local tintFrame
local pulseFrame
local vignetteFrame
local letterboxFrame
local fakeNoticeFrame
local blackoutPercentage = 0
local blackoutOwners = {}
local tintOwners = {}
local pulseOwners = {}
local vignetteOwners = {}
local letterboxOwners = {}
local fakeNoticeOwners = {}

local function clampPercentage(value)
	value = tonumber(value) or 0

	if value < 0 then
		return 0
	end

	if value > 100 then
		return 100
	end

	return value
end

local function setSolidColor(texture, red, green, blue, alpha)
	if texture.SetColorTexture then
		texture:SetColorTexture(red, green, blue, alpha)
	else
		texture:SetTexture(red, green, blue, alpha)
	end
end

local function normalizePresetKey(preset)
	if preset == nil or tostring(preset) == "" then
		return ""
	end

	return tostring(preset):lower():gsub("[%s_%-%+]+", "")
end

local function getPreset(presets, preset, defaultPreset)
	local presetKey = normalizePresetKey(preset)

	if presetKey ~= "" and presets[presetKey] then
		return presets[presetKey], presetKey
	end

	return presets[defaultPreset], defaultPreset
end

local function getStrongestEffect(owners)
	local strongest

	for _, effect in pairs(owners) do
		if not strongest or (effect.intensity or 0) >= (strongest.intensity or 0) then
			strongest = effect
		end
	end

	return strongest
end

local function getNow()
	if GetTime then
		return GetTime()
	end

	if time then
		return time()
	end

	return 0
end

local function getEffectAlpha(effect, preset)
	return ((effect and effect.intensity or 0) / 100) * (preset and preset.alpha or 1)
end

local function normalizeNoticeMessage(message, fallback)
	local text = tostring(message or "")

	if text == "" then
		text = tostring(fallback or "")
	end

	if #text > 120 then
		text = text:sub(1, 120)
	end

	return text
end

local function ensureBlackoutFrame()
	if blackoutFrame then
		return blackoutFrame
	end

	if not CreateFrame or not UIParent then
		WEP:Log("ScreenOverlay", "frame_unavailable", nil, "error")
		return nil
	end

	local frame = CreateFrame("Frame", BLACKOUT_FRAME_NAME, UIParent)
	frame:SetAllPoints(UIParent)
	frame:SetFrameStrata(DEFAULT_FRAME_STRATA)
	frame:SetFrameLevel(DEFAULT_FRAME_LEVEL)
	frame:EnableMouse(false)

	frame.solid = frame:CreateTexture(nil, "BACKGROUND")
	frame.solid:SetAllPoints(frame)
	setSolidColor(frame.solid, 0, 0, 0, 0)

	frame.vignette = frame:CreateTexture(nil, "ARTWORK")
	frame.vignette:SetAllPoints(frame)
	frame.vignette:SetTexture(DEFAULT_VIGNETTE_TEXTURE)
	frame.vignette:SetVertexColor(0, 0, 0, 0)

	if frame.vignette.SetBlendMode then
		frame.vignette:SetBlendMode("BLEND")
	end

	frame:Hide()
	blackoutFrame = frame
	WEP:Log("ScreenOverlay", "frame_created")

	return blackoutFrame
end

local function ensureTintFrame()
	if tintFrame then
		return tintFrame
	end

	if not CreateFrame or not UIParent then
		WEP:Log("ScreenOverlay", "tint_frame_unavailable", nil, "error")
		return nil
	end

	local frame = CreateFrame("Frame", TINT_FRAME_NAME, UIParent)
	frame:SetAllPoints(UIParent)
	frame:SetFrameStrata(DEFAULT_FRAME_STRATA)
	frame:SetFrameLevel(DEFAULT_FRAME_LEVEL - 6)
	frame:EnableMouse(false)

	frame.solid = frame:CreateTexture(nil, "BACKGROUND")
	frame.solid:SetAllPoints(frame)
	setSolidColor(frame.solid, 0, 0, 0, 0)

	frame:Hide()
	tintFrame = frame
	WEP:Log("ScreenOverlay", "tint_frame_created")

	return tintFrame
end

local function ensurePulseFrame()
	if pulseFrame then
		return pulseFrame
	end

	if not CreateFrame or not UIParent then
		WEP:Log("ScreenOverlay", "pulse_frame_unavailable", nil, "error")
		return nil
	end

	local frame = CreateFrame("Frame", PULSE_FRAME_NAME, UIParent)
	frame:SetAllPoints(UIParent)
	frame:SetFrameStrata(DEFAULT_FRAME_STRATA)
	frame:SetFrameLevel(DEFAULT_FRAME_LEVEL - 5)
	frame:EnableMouse(false)

	frame.solid = frame:CreateTexture(nil, "BACKGROUND")
	frame.solid:SetAllPoints(frame)
	setSolidColor(frame.solid, 0, 0, 0, 0)

	frame:SetScript("OnUpdate", function(self)
		local pulse = self.activePulse

		if not pulse then
			return
		end

		local phase = (math.sin(getNow() * (pulse.speed or 8)) + 1) / 2
		local alpha = pulse.minAlpha + ((pulse.maxAlpha - pulse.minAlpha) * phase)
		setSolidColor(self.solid, pulse.r, pulse.g, pulse.b, alpha)
	end)

	frame:Hide()
	pulseFrame = frame
	WEP:Log("ScreenOverlay", "pulse_frame_created")

	return pulseFrame
end

local function ensureVignetteFrame()
	if vignetteFrame then
		return vignetteFrame
	end

	if not CreateFrame or not UIParent then
		WEP:Log("ScreenOverlay", "vignette_frame_unavailable", nil, "error")
		return nil
	end

	local frame = CreateFrame("Frame", VIGNETTE_FRAME_NAME, UIParent)
	frame:SetAllPoints(UIParent)
	frame:SetFrameStrata(DEFAULT_FRAME_STRATA)
	frame:SetFrameLevel(DEFAULT_FRAME_LEVEL - 4)
	frame:EnableMouse(false)

	frame.left = frame:CreateTexture(nil, "ARTWORK")
	frame.left:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
	frame.left:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)

	frame.right = frame:CreateTexture(nil, "ARTWORK")
	frame.right:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
	frame.right:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)

	frame.top = frame:CreateTexture(nil, "ARTWORK")
	frame.top:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
	frame.top:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)

	frame.bottom = frame:CreateTexture(nil, "ARTWORK")
	frame.bottom:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
	frame.bottom:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)

	frame.edges = {
		frame.left,
		frame.right,
		frame.top,
		frame.bottom,
	}

	frame:Hide()
	vignetteFrame = frame
	WEP:Log("ScreenOverlay", "vignette_frame_created")

	return vignetteFrame
end

local function ensureLetterboxFrame()
	if letterboxFrame then
		return letterboxFrame
	end

	if not CreateFrame or not UIParent then
		WEP:Log("ScreenOverlay", "letterbox_frame_unavailable", nil, "error")
		return nil
	end

	local frame = CreateFrame("Frame", LETTERBOX_FRAME_NAME, UIParent)
	frame:SetAllPoints(UIParent)
	frame:SetFrameStrata(DEFAULT_FRAME_STRATA)
	frame:SetFrameLevel(DEFAULT_FRAME_LEVEL + 16)
	frame:EnableMouse(false)

	frame.top = frame:CreateTexture(nil, "OVERLAY")
	frame.top:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
	frame.top:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
	setSolidColor(frame.top, 0, 0, 0, 1)

	frame.bottom = frame:CreateTexture(nil, "OVERLAY")
	frame.bottom:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
	frame.bottom:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
	setSolidColor(frame.bottom, 0, 0, 0, 1)

	frame:Hide()
	letterboxFrame = frame
	WEP:Log("ScreenOverlay", "letterbox_frame_created")

	return letterboxFrame
end

local function ensureFakeNoticeFrame()
	if fakeNoticeFrame then
		return fakeNoticeFrame
	end

	if not CreateFrame or not UIParent then
		WEP:Log("ScreenOverlay", "fake_notice_frame_unavailable", nil, "error")
		return nil
	end

	local frame = CreateFrame("Frame", FAKE_NOTICE_FRAME_NAME, UIParent)
	frame:SetAllPoints(UIParent)
	frame:SetFrameStrata(DEFAULT_FRAME_STRATA)
	frame:SetFrameLevel(DEFAULT_FRAME_LEVEL + 60)
	frame:EnableMouse(false)

	frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
	frame.title:SetPoint("CENTER", frame, "CENTER", 0, 120)
	frame.title:SetWidth(760)
	frame.title:SetJustifyH("CENTER")
	frame.title:SetJustifyV("MIDDLE")

	frame.message = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
	frame.message:SetPoint("TOP", frame.title, "BOTTOM", 0, -16)
	frame.message:SetWidth(760)
	frame.message:SetJustifyH("CENTER")
	frame.message:SetJustifyV("MIDDLE")

	frame:Hide()
	fakeNoticeFrame = frame
	WEP:Log("ScreenOverlay", "fake_notice_frame_created")

	return fakeNoticeFrame
end

local function applyBlackout(frame, percentage)
	local normalized = percentage / 100
	local solidAlpha = normalized * normalized
	local vignetteAlpha = normalized

	setSolidColor(frame.solid, 0, 0, 0, solidAlpha)
	frame.vignette:SetVertexColor(0, 0, 0, vignetteAlpha)
end

local function normalizeOwner(owner)
	if owner == nil or tostring(owner) == "" then
		return DEFAULT_OWNER
	end

	return tostring(owner)
end

local function getHighestBlackoutPercentage()
	local highest = 0

	for _, percentage in pairs(blackoutOwners) do
		if percentage > highest then
			highest = percentage
		end
	end

	return highest
end

local function applyHighestBlackout()
	local previousPercentage = blackoutPercentage
	blackoutPercentage = getHighestBlackoutPercentage()

	local frame = ensureBlackoutFrame()
	if not frame then
		WEP:Log("ScreenOverlay", "blackout_set_failed", {
			percentage = blackoutPercentage,
		}, "error")
		return false
	end

	applyBlackout(frame, blackoutPercentage)

	if blackoutPercentage > 0 then
		frame:Show()
	else
		frame:Hide()
	end

	if previousPercentage ~= blackoutPercentage then
		WEP:Log("ScreenOverlay", "blackout_set", {
			percentage = blackoutPercentage,
		})
	end

	return true
end

local function applyTint()
	local effect = getStrongestEffect(tintOwners)
	local frame = ensureTintFrame()

	if not frame then
		return false
	end

	if not effect then
		setSolidColor(frame.solid, 0, 0, 0, 0)
		frame:Hide()
		return true
	end

	local preset = getPreset(COLOR_PRESETS, effect.preset, DEFAULT_TINT_PRESET)
	setSolidColor(frame.solid, preset.r, preset.g, preset.b, getEffectAlpha(effect, preset))
	frame:Show()
	return true
end

local function applyPulse()
	local effect = getStrongestEffect(pulseOwners)
	local frame = ensurePulseFrame()

	if not frame then
		return false
	end

	if not effect then
		frame.activePulse = nil
		setSolidColor(frame.solid, 0, 0, 0, 0)
		frame:Hide()
		return true
	end

	local preset = getPreset(PULSE_PRESETS, effect.preset, DEFAULT_PULSE_PRESET)
	local maxAlpha = getEffectAlpha(effect, preset)
	frame.activePulse = {
		r = preset.r,
		g = preset.g,
		b = preset.b,
		minAlpha = preset.minAlpha or 0,
		maxAlpha = maxAlpha,
		speed = preset.speed or 8,
	}
	frame:Show()
	return true
end

local function applyVignette()
	local effect = getStrongestEffect(vignetteOwners)
	local frame = ensureVignetteFrame()

	if not frame then
		return false
	end

	if not effect then
		for _, edge in ipairs(frame.edges or {}) do
			setSolidColor(edge, 0, 0, 0, 0)
		end

		frame:Hide()
		return true
	end

	local preset = getPreset(VIGNETTE_PRESETS, effect.preset, DEFAULT_VIGNETTE_PRESET)
	local normalized = (effect.intensity or 0) / 100
	local edgeWidth = math.floor(48 + (normalized * 280))
	local edgeHeight = math.floor(36 + (normalized * 180))
	local frameWidth = frame.GetWidth and frame:GetWidth() or 0
	local frameHeight = frame.GetHeight and frame:GetHeight() or 0

	if frameWidth > 0 then
		edgeWidth = math.min(edgeWidth, math.floor(frameWidth * 0.36))
	end

	if frameHeight > 0 then
		edgeHeight = math.min(edgeHeight, math.floor(frameHeight * 0.36))
	end

	frame.left:SetWidth(edgeWidth)
	frame.right:SetWidth(edgeWidth)
	frame.top:SetHeight(edgeHeight)
	frame.bottom:SetHeight(edgeHeight)

	for _, edge in ipairs(frame.edges or {}) do
		setSolidColor(edge, preset.r, preset.g, preset.b, getEffectAlpha(effect, preset))
	end

	frame:Show()
	return true
end

local function applyLetterbox()
	local effect = getStrongestEffect(letterboxOwners)
	local frame = ensureLetterboxFrame()

	if not frame then
		return false
	end

	if not effect then
		frame:Hide()
		return true
	end

	local normalized = (effect.intensity or 0) / 100
	local height = math.floor(32 + (normalized * 132))
	frame.top:SetHeight(height)
	frame.bottom:SetHeight(height)
	frame:Show()
	return true
end

local function applyFakeNotice()
	local effect = getStrongestEffect(fakeNoticeOwners)
	local frame = ensureFakeNoticeFrame()

	if not frame then
		return false
	end

	if not effect then
		frame:Hide()
		return true
	end

	local preset = getPreset(NOTICE_PRESETS, effect.preset, DEFAULT_NOTICE_PRESET)
	frame.title:SetText(preset.title)
	frame.title:SetTextColor(preset.r, preset.g, preset.b, 1)
	frame.message:SetText(normalizeNoticeMessage(effect.message, preset.message))
	frame.message:SetTextColor(1, 0.92, 0.72, 1)
	frame:SetAlpha(0.45 + (((effect.intensity or 0) / 100) * 0.55))
	frame:Show()
	return true
end

function ScreenOverlay.SetBlackoutFor(owner, percentage)
	local ownerKey = normalizeOwner(owner)
	local nextPercentage = clampPercentage(percentage)

	if nextPercentage > 0 then
		blackoutOwners[ownerKey] = nextPercentage
	else
		blackoutOwners[ownerKey] = nil
	end

	WEP:Log("ScreenOverlay", "owner_blackout_set", {
		owner = ownerKey,
		percentage = nextPercentage,
	})
	return applyHighestBlackout()
end

function ScreenOverlay.ClearBlackoutFor(owner)
	local ownerKey = normalizeOwner(owner)
	blackoutOwners[ownerKey] = nil

	WEP:Log("ScreenOverlay", "owner_blackout_cleared", {
		owner = ownerKey,
	})
	return applyHighestBlackout()
end

function ScreenOverlay.SetTintFor(owner, preset, intensity)
	local ownerKey = normalizeOwner(owner)
	local nextIntensity = clampPercentage(intensity)

	if nextIntensity > 0 then
		tintOwners[ownerKey] = {
			preset = preset,
			intensity = nextIntensity,
		}
	else
		tintOwners[ownerKey] = nil
	end

	WEP:Log("ScreenOverlay", "owner_tint_set", {
		owner = ownerKey,
		preset = preset or DEFAULT_TINT_PRESET,
		intensity = nextIntensity,
	})
	return applyTint()
end

function ScreenOverlay.ClearTintFor(owner)
	local ownerKey = normalizeOwner(owner)
	tintOwners[ownerKey] = nil

	WEP:Log("ScreenOverlay", "owner_tint_cleared", {
		owner = ownerKey,
	})
	return applyTint()
end

function ScreenOverlay.SetPulseFor(owner, preset, intensity)
	local ownerKey = normalizeOwner(owner)
	local nextIntensity = clampPercentage(intensity)

	if nextIntensity > 0 then
		pulseOwners[ownerKey] = {
			preset = preset,
			intensity = nextIntensity,
		}
	else
		pulseOwners[ownerKey] = nil
	end

	WEP:Log("ScreenOverlay", "owner_pulse_set", {
		owner = ownerKey,
		preset = preset or DEFAULT_PULSE_PRESET,
		intensity = nextIntensity,
	})
	return applyPulse()
end

function ScreenOverlay.ClearPulseFor(owner)
	local ownerKey = normalizeOwner(owner)
	pulseOwners[ownerKey] = nil

	WEP:Log("ScreenOverlay", "owner_pulse_cleared", {
		owner = ownerKey,
	})
	return applyPulse()
end

function ScreenOverlay.SetVignetteFor(owner, preset, intensity)
	local ownerKey = normalizeOwner(owner)
	local nextIntensity = clampPercentage(intensity)

	if nextIntensity > 0 then
		vignetteOwners[ownerKey] = {
			preset = preset,
			intensity = nextIntensity,
		}
	else
		vignetteOwners[ownerKey] = nil
	end

	WEP:Log("ScreenOverlay", "owner_vignette_set", {
		owner = ownerKey,
		preset = preset or DEFAULT_VIGNETTE_PRESET,
		intensity = nextIntensity,
	})
	return applyVignette()
end

function ScreenOverlay.ClearVignetteFor(owner)
	local ownerKey = normalizeOwner(owner)
	vignetteOwners[ownerKey] = nil

	WEP:Log("ScreenOverlay", "owner_vignette_cleared", {
		owner = ownerKey,
	})
	return applyVignette()
end

function ScreenOverlay.SetLetterboxFor(owner, intensity)
	local ownerKey = normalizeOwner(owner)
	local nextIntensity = clampPercentage(intensity)

	if nextIntensity > 0 then
		letterboxOwners[ownerKey] = {
			intensity = nextIntensity,
		}
	else
		letterboxOwners[ownerKey] = nil
	end

	WEP:Log("ScreenOverlay", "owner_letterbox_set", {
		owner = ownerKey,
		intensity = nextIntensity,
	})
	return applyLetterbox()
end

function ScreenOverlay.ClearLetterboxFor(owner)
	local ownerKey = normalizeOwner(owner)
	letterboxOwners[ownerKey] = nil

	WEP:Log("ScreenOverlay", "owner_letterbox_cleared", {
		owner = ownerKey,
	})
	return applyLetterbox()
end

function ScreenOverlay.ShowFakeNoticeFor(owner, preset, message, intensity)
	local ownerKey = normalizeOwner(owner)
	local nextIntensity = clampPercentage(intensity)

	if nextIntensity > 0 then
		fakeNoticeOwners[ownerKey] = {
			preset = preset,
			message = message,
			intensity = nextIntensity,
		}
	else
		fakeNoticeOwners[ownerKey] = nil
	end

	WEP:Log("ScreenOverlay", "owner_fake_notice_set", {
		owner = ownerKey,
		preset = preset or DEFAULT_NOTICE_PRESET,
		intensity = nextIntensity,
	})
	return applyFakeNotice()
end

function ScreenOverlay.ClearFakeNoticeFor(owner)
	local ownerKey = normalizeOwner(owner)
	fakeNoticeOwners[ownerKey] = nil

	WEP:Log("ScreenOverlay", "owner_fake_notice_cleared", {
		owner = ownerKey,
	})
	return applyFakeNotice()
end

function ScreenOverlay.SetBlackoutPercentage(percentage)
	return ScreenOverlay.SetBlackoutFor(DEFAULT_OWNER, percentage)
end

function ScreenOverlay.SetBlackout(percentage)
	return ScreenOverlay.SetBlackoutPercentage(percentage)
end

function ScreenOverlay.HideBlackout()
	return ScreenOverlay.ClearBlackoutFor(DEFAULT_OWNER)
end

function ScreenOverlay.GetBlackoutPercentage()
	return blackoutPercentage
end
