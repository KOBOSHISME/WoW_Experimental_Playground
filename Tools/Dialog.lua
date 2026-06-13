local _, WEP = ...

WEP.Tools = WEP.Tools or {}

local Dialog = {
	counter = 0,
}

WEP.Tools.Dialog = Dialog

local DIALOG_FRAME_NAME = "WEPDialogFrame"
local DEFAULT_TITLE = "WoW Experimental Playground"
local DEFAULT_WIDTH = 360
local MIN_WIDTH = 260
local MAX_WIDTH = 560
local PADDING = 16
local BUTTON_HEIGHT = 24
local BUTTON_SPACING = 8

local dialogFrame
local suppressHideResult = false

local function clamp(value, minValue, maxValue)
	value = tonumber(value) or minValue

	if value < minValue then
		return minValue
	end

	if value > maxValue then
		return maxValue
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

local function isBlank(value)
	return type(value) ~= "string" or value == ""
end

local function makeDialogId()
	Dialog.counter = Dialog.counter + 1
	return "dialog-" .. Dialog.counter
end

local function normalizeOption(option, index)
	local optionType = type(option)

	if optionType == "string" or optionType == "number" or optionType == "boolean" then
		local text = tostring(option)

		if text == "" then
			return nil, "dialog option text cannot be empty"
		end

		return {
			index = index,
			text = text,
			value = text,
		}
	end

	if optionType ~= "table" then
		return nil, "dialog option must be a string or table"
	end

	local value = option.value
	local text = option.text or option.label

	if text == nil and value ~= nil then
		text = tostring(value)
	end

	if isBlank(text) then
		return nil, "dialog option text is required"
	end

	return {
		index = index,
		text = text,
		value = value ~= nil and value or text,
	}
end

local function normalizeOptions(rawOptions)
	if rawOptions == nil then
		return {
			{
				index = 1,
				text = "Okay",
				value = "ok",
			},
		}
	end

	if type(rawOptions) ~= "table" then
		return nil, "dialog options must be a table"
	end

	local options = {}

	for index, option in ipairs(rawOptions) do
		local normalized, err = normalizeOption(option, index)
		if not normalized then
			return nil, err
		end

		options[#options + 1] = normalized
	end

	if #options == 0 then
		return nil, "dialog must have at least one option"
	end

	return options
end

local function callResultHandler(request, result)
	if type(request.onSelect) ~= "function" then
		return
	end

	local ok, err = pcall(request.onSelect, result)
	if not ok then
		WEP:Print("Dialog result handler failed:", err)
	end
end

local function finishDialog(option, canceled, reason)
	local request = Dialog.active
	if not request then
		return nil
	end

	Dialog.active = nil

	local result = {
		id = request.id,
		title = request.title,
		message = request.message,
		canceled = canceled == true,
		reason = reason,
	}

	if option then
		result.index = option.index
		result.text = option.text
		result.value = option.value
	elseif request.cancelValue ~= nil then
		result.value = request.cancelValue
	end

	if dialogFrame and dialogFrame.Hide and dialogFrame:IsShown() then
		suppressHideResult = true
		dialogFrame:Hide()
		suppressHideResult = false
	end

	callResultHandler(request, result)

	return result
end

local function ensureButton(frame, index)
	frame.optionButtons = frame.optionButtons or {}

	if frame.optionButtons[index] then
		return frame.optionButtons[index]
	end

	local button = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	button:SetHeight(BUTTON_HEIGHT)
	button:SetScript("OnClick", function(self)
		Dialog.Select(self.optionIndex)
	end)

	frame.optionButtons[index] = button
	return button
end

local function ensureDialogFrame()
	if dialogFrame then
		return dialogFrame
	end

	if not CreateFrame or not UIParent then
		return nil
	end

	local template = BackdropTemplateMixin and "BackdropTemplate" or nil
	local frame = CreateFrame("Frame", DIALOG_FRAME_NAME, UIParent, template)
	frame:SetPoint("CENTER")
	frame:SetFrameStrata("DIALOG")
	frame:SetFrameLevel(100)
	frame:EnableMouse(true)
	frame:SetMovable(true)
	frame:SetToplevel(true)
	frame:Hide()

	if frame.RegisterForDrag then
		frame:RegisterForDrag("LeftButton")
		frame:SetScript("OnDragStart", frame.StartMoving)
		frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	end

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
	else
		frame.background = frame:CreateTexture(nil, "BACKGROUND")
		frame.background:SetAllPoints(frame)
		setSolidColor(frame.background, 0.02, 0.02, 0.02, 0.92)
	end

	frame.title = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	frame.title:SetJustifyH("LEFT")
	frame.title:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING, -PADDING)
	frame.title:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -42, -PADDING)

	frame.closeButton = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
	frame.closeButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)
	frame.closeButton:SetScript("OnClick", function()
		Dialog.Hide("closed")
	end)

	frame.message = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	frame.message:SetJustifyH("LEFT")
	frame.message:SetJustifyV("TOP")
	frame.message:SetPoint("TOPLEFT", frame.title, "BOTTOMLEFT", 0, -14)

	if frame.message.SetWordWrap then
		frame.message:SetWordWrap(true)
	end

	frame:SetScript("OnHide", function()
		if not suppressHideResult and Dialog.active then
			finishDialog(nil, true, "hidden")
		end
	end)

	if UISpecialFrames then
		UISpecialFrames[#UISpecialFrames + 1] = DIALOG_FRAME_NAME
	end

	dialogFrame = frame
	return dialogFrame
end

local function layoutFrame(frame, request)
	local width = clamp(request.width or DEFAULT_WIDTH, MIN_WIDTH, MAX_WIDTH)
	local contentWidth = width - (PADDING * 2)

	frame:SetWidth(width)
	frame.title:SetText(request.title)
	frame.message:SetText(request.message)
	frame.message:SetWidth(contentWidth)

	local messageHeight = frame.message:GetStringHeight() or 0
	if messageHeight < 28 then
		messageHeight = 28
	end

	local nextY = PADDING + 22 + 14 + messageHeight + 18

	for index, option in ipairs(request.options) do
		local button = ensureButton(frame, index)
		button.optionIndex = index
		button:SetText(option.text)
		button:SetWidth(contentWidth)
		button:ClearAllPoints()
		button:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING, -nextY)
		button:Show()

		nextY = nextY + BUTTON_HEIGHT + BUTTON_SPACING
	end

	for index = #request.options + 1, #(frame.optionButtons or {}) do
		frame.optionButtons[index]:Hide()
	end

	frame:SetHeight(nextY + PADDING - BUTTON_SPACING)
end

function Dialog.Show(config)
	if type(config) ~= "table" then
		return false, "dialog config is required"
	end

	local options, optionsErr = normalizeOptions(config.options)
	if not options then
		return false, optionsErr
	end

	local frame = ensureDialogFrame()
	if not frame then
		return false, "dialog frame is unavailable"
	end

	if Dialog.active then
		Dialog.Hide("replaced")
	end

	local request = {
		id = config.id or makeDialogId(),
		title = config.title or DEFAULT_TITLE,
		message = config.message or config.text or "",
		options = options,
		onSelect = config.onSelect or config.callback,
		cancelValue = config.cancelValue,
		width = config.width,
	}

	Dialog.active = request
	layoutFrame(frame, request)
	frame:Show()

	return true, request.id
end

function Dialog.Select(index)
	local request = Dialog.active
	if not request then
		return false, "no active dialog"
	end

	local option = request.options[tonumber(index) or 0]
	if not option then
		return false, "unknown dialog option: " .. tostring(index)
	end

	return true, finishDialog(option, false, "selected")
end

function Dialog.Hide(reason)
	if not Dialog.active then
		return false, "no active dialog"
	end

	return true, finishDialog(nil, true, reason or "canceled")
end

function Dialog.GetStatus()
	local active = Dialog.active

	if not active then
		return {
			active = false,
		}
	end

	return {
		active = true,
		id = active.id,
		title = active.title,
		optionCount = #active.options,
	}
end
