local _, WEP = ...

WEP.Tools = WEP.Tools or {}

local Form = {}
WEP.Tools.Form = Form

WEP:Log("Form", "loaded")

local DEFAULT_INPUT_WIDTH = 140
local DEFAULT_INPUT_HEIGHT = 24
local DEFAULT_BUTTON_WIDTH = 96
local DEFAULT_BUTTON_HEIGHT = 24

local function setEnabled(button, enabled)
	enabled = enabled ~= false

	if enabled then
		if button.Enable then
			button:Enable()
		end

		if button.SetAlpha then
			button:SetAlpha(1)
		end
	else
		if button.Disable then
			button:Disable()
		end

		if button.SetAlpha then
			button:SetAlpha(0.45)
		end
	end
end

function Form.CreateLabel(parent, config)
	config = config or {}

	local label = parent:CreateFontString(nil, "ARTWORK", config.font or "GameFontNormal")
	label:SetJustifyH(config.justifyH or "LEFT")
	label:SetJustifyV(config.justifyV or "MIDDLE")
	label:SetText(config.text or "")

	if config.width then
		label:SetWidth(config.width)
	end

	WEP:Log("Form", "label_created", {
		text = config.text or "",
	})
	return label
end

function Form.CreateInput(parent, config)
	config = config or {}

	local frame = CreateFrame("Frame", nil, parent)
	local width = config.width or DEFAULT_INPUT_WIDTH
	local height = config.height or 42
	frame:SetSize(width, height)

	frame.label = Form.CreateLabel(frame, {
		text = config.label or "",
		width = width,
	})
	frame.label:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)

	frame.editBox = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
	frame.editBox:SetSize(width - 8, config.inputHeight or DEFAULT_INPUT_HEIGHT)
	frame.editBox:SetPoint("TOPLEFT", frame.label, "BOTTOMLEFT", 4, -4)
	frame.editBox:SetAutoFocus(config.autoFocus == true)
	frame.editBox:SetText(tostring(config.value or ""))

	if config.numeric and frame.editBox.SetNumeric then
		frame.editBox:SetNumeric(true)
	end

	if config.maxLetters and frame.editBox.SetMaxLetters then
		frame.editBox:SetMaxLetters(config.maxLetters)
	end

	if type(config.onEnterPressed) == "function" then
		frame.editBox:SetScript("OnEnterPressed", function()
			config.onEnterPressed(frame)
		end)
	end

	if type(config.onEscapePressed) == "function" then
		frame.editBox:SetScript("OnEscapePressed", function()
			config.onEscapePressed(frame)
		end)
	end

	function frame:GetValue()
		return self.editBox:GetText()
	end

	function frame:SetValue(value)
		self.editBox:SetText(tostring(value or ""))
	end

	function frame:SetEnabled(enabled)
		enabled = enabled ~= false

		if self.editBox.Enable then
			if enabled then
				self.editBox:Enable()
			else
				self.editBox:Disable()
			end
		end

		if self.editBox.SetAlpha then
			self.editBox:SetAlpha(enabled and 1 or 0.45)
		end

		if self.lastLoggedEnabled ~= enabled then
			self.lastLoggedEnabled = enabled
			WEP:Log("Form", "input_enabled_set", {
				label = config.label or "",
				enabled = enabled,
			})
		end
	end

	WEP:Log("Form", "input_created", {
		label = config.label or "",
		numeric = config.numeric == true,
	})
	return frame
end

function Form.CreateButton(parent, config)
	config = config or {}

	local button = CreateFrame("Button", nil, parent, config.template or "UIPanelButtonTemplate")
	button:SetSize(config.width or DEFAULT_BUTTON_WIDTH, config.height or DEFAULT_BUTTON_HEIGHT)
	button:SetText(config.text or "Button")

	if type(config.onClick) == "function" then
		button:SetScript("OnClick", function()
			WEP:Log("Form", "button_clicked", {
				text = config.text or "Button",
			})
			config.onClick(button)
		end)
	end

	function button:SetButtonEnabled(enabled)
		setEnabled(self, enabled)
	end

	setEnabled(button, config.enabled)

	WEP:Log("Form", "button_created", {
		text = config.text or "Button",
	})
	return button
end
