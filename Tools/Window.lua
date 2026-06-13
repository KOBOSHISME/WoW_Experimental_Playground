local _, WEP = ...

WEP.Tools = WEP.Tools or {}

local Window = {}
WEP.Tools.Window = Window

local DEFAULT_WIDTH = 420
local DEFAULT_HEIGHT = 360
local MIN_WIDTH = 240
local MIN_HEIGHT = 160
local PADDING = 14
local HEADER_HEIGHT = 32
local FOOTER_HEIGHT = 34

local counter = 0

local function clamp(value, minValue, defaultValue)
	value = tonumber(value) or defaultValue

	if value < minValue then
		return minValue
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

local function applyBackdrop(frame)
	if frame.SetBackdrop then
		frame:SetBackdrop({
			bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
			edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
			tile = true,
			tileSize = 32,
			edgeSize = 32,
			insets = {
				left = 11,
				right = 12,
				top = 12,
				bottom = 11,
			},
		})
		return
	end

	frame.background = frame:CreateTexture(nil, "BACKGROUND")
	frame.background:SetAllPoints(frame)
	setSolidColor(frame.background, 0.02, 0.02, 0.02, 0.92)
end

local function makeName(prefix)
	counter = counter + 1
	return (prefix or "WEPWindow") .. counter
end

function Window.Create(config)
	if type(config) ~= "table" then
		config = {}
	end

	if not CreateFrame or not UIParent then
		return nil, "window frame is unavailable"
	end

	local name = config.name or makeName("WEPWindow")
	local template = BackdropTemplateMixin and "BackdropTemplate" or nil
	local frame = CreateFrame("Frame", name, config.parent or UIParent, template)
	local width = clamp(config.width, MIN_WIDTH, DEFAULT_WIDTH)
	local height = clamp(config.height, MIN_HEIGHT, DEFAULT_HEIGHT)

	frame:SetSize(width, height)
	frame:SetPoint(config.point or "CENTER")
	frame:SetFrameStrata(config.strata or "DIALOG")
	frame:SetFrameLevel(config.level or 90)
	frame:EnableMouse(true)
	frame:SetMovable(config.movable ~= false)
	frame:SetToplevel(true)
	frame:Hide()

	if frame.RegisterForDrag then
		frame:RegisterForDrag("LeftButton")
		frame:SetScript("OnDragStart", frame.StartMoving)
		frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	end

	applyBackdrop(frame)

	frame.title = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	frame.title:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING, -PADDING)
	frame.title:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -42, -PADDING)
	frame.title:SetJustifyH("LEFT")
	frame.title:SetText(config.title or "Window")

	frame.closeButton = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
	frame.closeButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)

	frame.content = CreateFrame("Frame", nil, frame)
	frame.content:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING, -(PADDING + HEADER_HEIGHT))
	frame.content:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PADDING, PADDING + FOOTER_HEIGHT)

	frame.footer = CreateFrame("Frame", nil, frame)
	frame.footer:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", PADDING, PADDING)
	frame.footer:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PADDING, PADDING)
	frame.footer:SetHeight(FOOTER_HEIGHT)

	local controller = {
		frame = frame,
		content = frame.content,
		footer = frame.footer,
	}

	frame.closeButton:SetScript("OnClick", function()
		controller:Hide()
	end)

	if config.onHide then
		frame:SetScript("OnHide", function()
			config.onHide(controller)
		end)
	end

	function controller:SetTitle(title)
		frame.title:SetText(title or "")
	end

	function controller:SetSize(newWidth, newHeight)
		frame:SetSize(clamp(newWidth, MIN_WIDTH, DEFAULT_WIDTH), clamp(newHeight, MIN_HEIGHT, DEFAULT_HEIGHT))
	end

	function controller:Show()
		frame:Show()

		if type(config.onShow) == "function" then
			config.onShow(self)
		end
	end

	function controller:Hide()
		frame:Hide()
	end

	function controller:Toggle()
		if frame:IsShown() then
			self:Hide()
		else
			self:Show()
		end
	end

	function controller:IsShown()
		return frame:IsShown() == true
	end

	if UISpecialFrames and name then
		UISpecialFrames[#UISpecialFrames + 1] = name
	end

	return controller
end
