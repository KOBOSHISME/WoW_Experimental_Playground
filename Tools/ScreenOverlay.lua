local _, WEP = ...

WEP.Tools = WEP.Tools or {}

local ScreenOverlay = {}
WEP.Tools.ScreenOverlay = ScreenOverlay

WEP:Log("ScreenOverlay", "loaded")

local BLACKOUT_FRAME_NAME = "WEPScreenBlackoutOverlay"
local DEFAULT_FRAME_STRATA = "FULLSCREEN_DIALOG"
local DEFAULT_FRAME_LEVEL = 25
local DEFAULT_VIGNETTE_TEXTURE = "Interface\\FullScreenTextures\\LowHealth"

local blackoutFrame
local blackoutPercentage = 0

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

local function applyBlackout(frame, percentage)
	local normalized = percentage / 100
	local solidAlpha = normalized * normalized
	local vignetteAlpha = normalized

	setSolidColor(frame.solid, 0, 0, 0, solidAlpha)
	frame.vignette:SetVertexColor(0, 0, 0, vignetteAlpha)
end

function ScreenOverlay.SetBlackoutPercentage(percentage)
	local previousPercentage = blackoutPercentage
	blackoutPercentage = clampPercentage(percentage)

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

function ScreenOverlay.SetBlackout(percentage)
	return ScreenOverlay.SetBlackoutPercentage(percentage)
end

function ScreenOverlay.HideBlackout()
	return ScreenOverlay.SetBlackoutPercentage(0)
end

function ScreenOverlay.GetBlackoutPercentage()
	return blackoutPercentage
end
