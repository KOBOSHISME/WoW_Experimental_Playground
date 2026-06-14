local _, WEP = ...

WEP.Tools = WEP.Tools or {}

local Window = {}
WEP.Tools.Window = Window

WEP:Log("Window", "loaded")

local DEFAULT_WIDTH = 420
local DEFAULT_HEIGHT = 360
local MIN_WIDTH = 240
local MIN_HEIGHT = 160
local PADDING = 14
local HEADER_HEIGHT = 32
local FOOTER_HEIGHT = 34
local COLLAPSED_HEIGHT = PADDING + HEADER_HEIGHT
local RESIZE_HANDLE_SIZE = 16

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

local function applyResizeBounds(frame, minWidth, minHeight)
	if frame.SetResizeBounds then
		local ok = pcall(frame.SetResizeBounds, frame, minWidth, minHeight)

		if not ok then
			pcall(frame.SetResizeBounds, frame, minWidth, minHeight, 0, 0)
		end
	elseif frame.SetMinResize then
		frame:SetMinResize(minWidth, minHeight)
	end
end

function Window.Create(config)
	if type(config) ~= "table" then
		config = {}
	end

	if not CreateFrame or not UIParent then
		WEP:Log("Window", "create_failed", {
			error = "window frame is unavailable",
		}, "error")
		return nil, "window frame is unavailable"
	end

	local name = config.name or makeName("WEPWindow")
	local template = BackdropTemplateMixin and "BackdropTemplate" or nil
	local frame = CreateFrame("Frame", name, config.parent or UIParent, template)
	local minWidth = clamp(config.minWidth, MIN_WIDTH, MIN_WIDTH)
	local minHeight = clamp(config.minHeight, MIN_HEIGHT, MIN_HEIGHT)
	local width = clamp(config.width, minWidth, DEFAULT_WIDTH)
	local height = clamp(config.height, minHeight, DEFAULT_HEIGHT)
	local titleRightPadding = config.collapsible and -66 or -42

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
	frame.title:SetPoint("TOPRIGHT", frame, "TOPRIGHT", titleRightPadding, -PADDING)
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
		collapsed = false,
		expandedHeight = height,
	}

	frame.closeButton:SetScript("OnClick", function()
		controller:Hide()
	end)

	if config.collapsible then
		frame.collapseButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
		frame.collapseButton:SetSize(22, 20)
		frame.collapseButton:SetPoint("RIGHT", frame.closeButton, "LEFT", -2, 0)
		frame.collapseButton:SetText("-")
		frame.collapseButton:SetScript("OnClick", function()
			controller:SetCollapsed(not controller.collapsed)
		end)
	end

	if config.resizable then
		if frame.SetResizable then
			frame:SetResizable(true)
		end

		applyResizeBounds(frame, minWidth, minHeight)

		frame.resizeButton = CreateFrame("Button", nil, frame)
		frame.resizeButton:SetSize(RESIZE_HANDLE_SIZE, RESIZE_HANDLE_SIZE)
		frame.resizeButton:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -8, 8)

		if frame.resizeButton.SetNormalTexture then
			frame.resizeButton:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
			frame.resizeButton:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
			frame.resizeButton:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
		end

		frame.resizeButton:SetScript("OnMouseDown", function(_, button)
			if button == "LeftButton" and not controller.collapsed and frame.StartSizing then
				frame:StartSizing("BOTTOMRIGHT")
			end
		end)

		frame.resizeButton:SetScript("OnMouseUp", function()
			if frame.StopMovingOrSizing then
				frame:StopMovingOrSizing()
			end

			controller.expandedHeight = frame:GetHeight()

			if type(config.onResize) == "function" then
				config.onResize(controller, frame:GetWidth(), frame:GetHeight())
			end
		end)
	end

	if config.onHide then
		frame:SetScript("OnHide", function()
			config.onHide(controller)
		end)
	end

	function controller:SetTitle(title)
		frame.title:SetText(title or "")
		WEP:Log("Window", "title_set", {
			name = name,
			title = title or "",
		})
	end

	function controller:SetSize(newWidth, newHeight)
		local nextWidth = clamp(newWidth, minWidth, DEFAULT_WIDTH)
		local nextHeight = clamp(newHeight, minHeight, DEFAULT_HEIGHT)

		if self.collapsed then
			self.expandedHeight = nextHeight
			frame:SetWidth(nextWidth)
		else
			self.expandedHeight = nextHeight
			frame:SetSize(nextWidth, nextHeight)
		end

		WEP:Log("Window", "size_set", {
			name = name,
			width = newWidth,
			height = newHeight,
		})
	end

	function controller:SetCollapsed(collapsed)
		collapsed = collapsed == true

		if self.collapsed == collapsed then
			return
		end

		self.collapsed = collapsed

		if collapsed then
			self.expandedHeight = frame:GetHeight()
			frame.content:Hide()
			frame.footer:Hide()

			if frame.resizeButton then
				frame.resizeButton:Hide()
			end

			if frame.SetResizable then
				frame:SetResizable(false)
			end

			frame:SetHeight(config.collapsedHeight or COLLAPSED_HEIGHT)

			if frame.collapseButton then
				frame.collapseButton:SetText("+")
			end
		else
			frame:SetHeight(self.expandedHeight or height)
			frame.content:Show()
			frame.footer:Show()

			if config.resizable and frame.SetResizable then
				frame:SetResizable(true)
			end

			if frame.resizeButton then
				frame.resizeButton:Show()
			end

			if frame.collapseButton then
				frame.collapseButton:SetText("-")
			end
		end

		WEP:Log("Window", "collapsed_set", {
			name = name,
			collapsed = self.collapsed,
		})
	end

	function controller:IsCollapsed()
		return self.collapsed == true
	end

	function controller:Show()
		frame:Show()
		WEP:Log("Window", "show", {
			name = name,
		})

		if type(config.onShow) == "function" then
			config.onShow(self)
		end
	end

	function controller:Hide()
		frame:Hide()
		WEP:Log("Window", "hide", {
			name = name,
		})
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

	WEP:Log("Window", "created", {
		name = name,
		title = config.title or "Window",
		width = width,
		height = height,
	})

	return controller
end
