local _, WEP = ...

local PartyInterference = {
	durationSeconds = 8,
	percent = 70,
	customMessage = "",
	includeSender = true,
	selectedTarget = nil,
	selectedActionIndex = 1,
	selectedSoundIndex = 1,
	counter = 0,
}

WEP.PartyInterference = PartyInterference

local FEATURE_ID = "partyInterference"

PartyInterference.title = "Party Interference"
PartyInterference.description = "Send temporary screen, UI, and sound interference to party friends."

local Player = WEP.Tools.Player
local Party = WEP.Tools.Party
local Interference = WEP.Tools.Interference
local Timer = WEP.Tools.Timer
local UIVisibility = WEP.Tools.UIVisibility
local WindowTool = WEP.Tools.Window
local Form = WEP.Tools.Form
local List = WEP.Tools.List
local Sound = WEP.Tools.Sound

WEP:Log("PartyInterference", "loaded")

local MSG_ACTION = "party_interference_action"

local MIN_DURATION_SECONDS = 1
local MAX_DURATION_SECONDS = 30
local DEFAULT_DURATION_SECONDS = 8
local MIN_PERCENT = 10
local MAX_PERCENT = 95
local DEFAULT_PERCENT = 70
local MAX_MESSAGE_LENGTH = 60
local DEFAULT_SOUND = "wep_alert"
local NOTICE_SECONDS = 3
local ACTION_ROW_HEIGHT = 22

local ALLOWED_UI_GROUPS = {
	actionbars = true,
	chat = true,
	minimap = true,
	unitframes = true,
}

local ACTIONS = {
	{
		text = "Darken Screen",
		action = "darken",
		detail = "Screen overlay",
		percentLabel = "Intensity",
	},
	{
		text = "Hide Health",
		action = "hide_ui",
		group = "unitframes",
		detail = "Unit frames",
	},
	{
		text = "Hide Bars",
		action = "hide_ui",
		group = "actionbars",
		detail = "Action bars",
	},
	{
		text = "Hide Minimap",
		action = "hide_ui",
		group = "minimap",
		detail = "Minimap",
	},
	{
		text = "Hide Chat",
		action = "hide_ui",
		group = "chat",
		detail = "Chat frame",
	},
	{
		text = "Play Alert",
		action = "sound",
		sound = DEFAULT_SOUND,
		detail = "Repeating sound",
	},
	{
		text = "Boom Walk",
		action = "sound_trap",
		wireAction = "trap",
		trigger = "walk",
		wireTrigger = "w",
		usesSelectedSound = true,
		detail = "Sound while moving",
		percentLabel = "Chance",
	},
	{
		text = "Target Sting",
		action = "sound_trap",
		wireAction = "trap",
		trigger = "target",
		wireTrigger = "t",
		usesSelectedSound = true,
		detail = "Sound on party target",
		percentLabel = "Chance",
	},
	{
		text = "Combat Drop",
		action = "sound_trap",
		wireAction = "trap",
		trigger = "combat",
		wireTrigger = "c",
		usesSelectedSound = true,
		detail = "Sound entering combat",
		percentLabel = "Chance",
	},
	{
		text = "Cast Heckle",
		action = "sound_trap",
		wireAction = "trap",
		trigger = "cast",
		wireTrigger = "s",
		usesSelectedSound = true,
		detail = "Sound when casting",
		percentLabel = "Chance",
	},
	{
		text = "Low Health Panic",
		action = "sound_trap",
		wireAction = "trap",
		trigger = "low_health",
		wireTrigger = "h",
		usesSelectedSound = true,
		detail = "Sound below health %",
		percentLabel = "Health %",
	},
}

local actionLabels = {
	clear = "Clear Effects",
	darken = "Darken Screen",
	hide_ui = "Hide UI",
	sound = "Play Alert",
	sound_trap = "Sound Trap",
	trap = "Sound Trap",
}

local trapLabels = {
	cast = "Cast Heckle",
	combat = "Combat Drop",
	low_health = "Low Health Panic",
	target = "Target Sting",
	walk = "Boom Walk",
}

local interferenceWindow
local screenNoticeFrame

local function isBlank(value)
	return value == nil or tostring(value) == ""
end

local function trim(value)
	return (tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function clamp(value, minValue, maxValue, defaultValue)
	value = tonumber(value) or defaultValue

	if value < minValue then
		return minValue
	end

	if value > maxValue then
		return maxValue
	end

	return math.floor(value)
end

local function sanitizeMessage(value)
	local message = trim(value):gsub("[%c%%~|;=]", " "):gsub("%s+", " ")

	if #message > MAX_MESSAGE_LENGTH then
		message = message:sub(1, MAX_MESSAGE_LENGTH)
	end

	return message
end

local function getCheckedValue(checkButton)
	if not checkButton or not checkButton.GetChecked then
		return false
	end

	local checked = checkButton:GetChecked()
	return checked == true or checked == 1
end

local function shortName(name)
	local normalized = Player.NormalizeName(name)
	local dashIndex = normalized:find("-", 1, true)

	if dashIndex then
		normalized = normalized:sub(1, dashIndex - 1)
	end

	return normalized
end

local function nameKey(name)
	return string.lower(shortName(name))
end

local function namesMatch(left, right)
	local leftKey = nameKey(left)
	return leftKey ~= "" and leftKey == nameKey(right)
end

local function setButtonEnabled(button, enabled)
	if not button then
		return
	end

	if enabled == false then
		if button.Disable then
			button:Disable()
		end

		if button.SetAlpha then
			button:SetAlpha(0.45)
		end
	else
		if button.Enable then
			button:Enable()
		end

		if button.SetAlpha then
			button:SetAlpha(1)
		end
	end
end

local function setInputValueIfNotFocused(input, value)
	if not input or not input.editBox then
		return
	end

	if input.editBox.HasFocus and input.editBox:HasFocus() then
		return
	end

	input:SetValue(value)
end

local function normalizeGroup(group)
	if not UIVisibility or not UIVisibility.NormalizeGroup then
		return nil
	end

	local groupName = UIVisibility.NormalizeGroup(group)
	if groupName and ALLOWED_UI_GROUPS[groupName] then
		return groupName
	end

	return nil
end

local function normalizeTrapTrigger(trigger)
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

	if normalized == "h" then
		return "low_health"
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

	if normalized == "health" or normalized == "lowhealth" or normalized == "low_health_panic" then
		return "low_health"
	end

	if trapLabels[normalized] then
		return normalized
	end

	return nil
end

local function getPayloadNumber(payload, key, minValue, maxValue, defaultValue)
	return clamp(payload and payload[key], minValue, maxValue, defaultValue)
end

local function shouldShowSender(payload)
	return tostring(payload and payload.n or "1") ~= "0"
end

local function setSolidColor(texture, red, green, blue, alpha)
	if texture.SetColorTexture then
		texture:SetColorTexture(red, green, blue, alpha)
	else
		texture:SetTexture(red, green, blue, alpha)
	end
end

local function ensureScreenNoticeFrame()
	if screenNoticeFrame then
		return screenNoticeFrame
	end

	if not CreateFrame or not UIParent then
		WEP:Log("PartyInterference", "screen_notice_unavailable", nil, "warn")
		return nil
	end

	local frame = CreateFrame("Frame", "WEPPartyInterferenceScreenNotice", UIParent)
	frame:SetAllPoints(UIParent)
	frame:SetFrameStrata("FULLSCREEN_DIALOG")
	frame:SetFrameLevel(95)
	frame:EnableMouse(false)
	frame:Hide()

	frame.text = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
	frame.text:SetPoint("CENTER", frame, "CENTER", 0, 150)
	frame.text:SetWidth(620)
	frame.text:SetJustifyH("CENTER")
	frame.text:SetJustifyV("MIDDLE")
	frame.text:SetTextColor(1, 0.86, 0.1, 1)

	screenNoticeFrame = frame
	WEP:Log("PartyInterference", "screen_notice_created")
	return screenNoticeFrame
end

function PartyInterference:IsEnabled()
	return WEP:IsFeatureEnabled(FEATURE_ID)
end

function PartyInterference:Initialize()
	if self.initialized then
		return
	end

	self.initialized = true
	WEP:Log("PartyInterference", "initialize")

	WEP.Comm:RegisterHandler(MSG_ACTION, function(message)
		if self:IsEnabled() then
			self:OnActionMessage(message)
		end
	end)
end

function PartyInterference:MakeEffectId()
	self.counter = self.counter + 1
	return tostring(self.counter)
end

function PartyInterference:MakeIncomingEffectId(message, payload)
	local payloadId = payload and payload.id
	if isBlank(payloadId) then
		payloadId = message and message.id or self:MakeEffectId()
	end

	return "pi:" .. shortName(message and message.sender or "unknown") .. ":" .. tostring(payloadId)
end

function PartyInterference:GetPartyMembers()
	return Party.GetMembers()
end

function PartyInterference:IsSelectedTargetInParty()
	if isBlank(self.selectedTarget) then
		return false
	end

	for _, member in ipairs(self:GetPartyMembers()) do
		if namesMatch(member.name, self.selectedTarget) then
			self.selectedTarget = member.name
			return true
		end
	end

	return false
end

function PartyInterference:GetSelectedTarget()
	if self:IsSelectedTargetInParty() then
		return self.selectedTarget
	end

	return nil
end

function PartyInterference:SelectTarget(target)
	if isBlank(target) then
		return false
	end

	for _, member in ipairs(self:GetPartyMembers()) do
		if namesMatch(member.name, target) or namesMatch(member.shortName, target) then
			self.selectedTarget = member.name
			WEP:Log("PartyInterference", "target_selected", {
				target = self.selectedTarget,
			})
			self:RefreshWindow()
			return true
		end
	end

	WEP:Print("Party Interference target must be a current party member.")
	WEP:Log("PartyInterference", "target_select_failed", {
		target = target,
		error = "not in party",
	}, "warn")
	return false
end

function PartyInterference:GetPartyItems()
	local items = {}
	local selectedTarget = self:GetSelectedTarget()

	for _, member in ipairs(self:GetPartyMembers()) do
		local selected = selectedTarget and namesMatch(member.name, selectedTarget)

		items[#items + 1] = {
			name = member.shortName or shortName(member.name),
			state = member.connected == false and "Offline" or "Ready",
			unit = member.unit,
			color = selected and {
				r = 0.15,
				g = 0.45,
				b = 0.25,
				a = 0.45,
			} or nil,
			onClick = function()
				self:SelectTarget(member.name)
			end,
		}
	end

	return items
end

function PartyInterference:GetSelectedAction()
	local selectedIndex = tonumber(self.selectedActionIndex) or 1

	if not ACTIONS[selectedIndex] then
		selectedIndex = 1
	end

	self.selectedActionIndex = selectedIndex
	return ACTIONS[selectedIndex], selectedIndex
end

function PartyInterference:GetSoundOptions()
	if Sound and Sound.GetCustomSounds then
		local sounds = Sound.GetCustomSounds()

		if #sounds > 0 then
			return sounds
		end
	end

	return {
		{
			name = DEFAULT_SOUND,
			label = "WEP Alert",
		},
	}
end

function PartyInterference:GetSelectedSound()
	local sounds = self:GetSoundOptions()
	local selectedIndex = tonumber(self.selectedSoundIndex) or 1

	if selectedIndex < 1 then
		selectedIndex = 1
	end

	if selectedIndex > #sounds then
		selectedIndex = #sounds
	end

	self.selectedSoundIndex = selectedIndex
	return sounds[selectedIndex], selectedIndex, #sounds
end

function PartyInterference:GetSelectedSoundName()
	local sound = self:GetSelectedSound()
	return sound and sound.name or DEFAULT_SOUND
end

function PartyInterference:SelectSoundOffset(offset)
	local sounds = self:GetSoundOptions()
	local selectedIndex = tonumber(self.selectedSoundIndex) or 1

	if #sounds == 0 then
		return false
	end

	selectedIndex = selectedIndex + (tonumber(offset) or 0)

	if selectedIndex < 1 then
		selectedIndex = #sounds
	elseif selectedIndex > #sounds then
		selectedIndex = 1
	end

	self.selectedSoundIndex = selectedIndex
	WEP:Log("PartyInterference", "sound_selected", {
		index = selectedIndex,
		sound = sounds[selectedIndex] and sounds[selectedIndex].name or "none",
	})
	self:RefreshWindow()
	return true
end

function PartyInterference:GetPercentLabel()
	local actionConfig = self:GetSelectedAction()
	return actionConfig and actionConfig.percentLabel or "Percent"
end

function PartyInterference:SelectAction(index)
	index = tonumber(index) or 1

	if not ACTIONS[index] then
		return false
	end

	self.selectedActionIndex = index
	WEP:Log("PartyInterference", "action_selected", {
		index = index,
		action = ACTIONS[index].action,
		group = ACTIONS[index].group or "none",
		trigger = ACTIONS[index].trigger or "none",
	})
	self:RefreshWindow()
	return true
end

function PartyInterference:ReadWindowSettings()
	local window = interferenceWindow

	if window and window.durationInput then
		self.durationSeconds = clamp(
			window.durationInput:GetValue(),
			MIN_DURATION_SECONDS,
			MAX_DURATION_SECONDS,
			self.durationSeconds or DEFAULT_DURATION_SECONDS
		)
	end

	if window and window.percentInput then
		self.percent = clamp(
			window.percentInput:GetValue(),
			MIN_PERCENT,
			MAX_PERCENT,
			self.percent or DEFAULT_PERCENT
		)
	end

	if window and window.messageInput then
		self.customMessage = sanitizeMessage(window.messageInput:GetValue())
	end

	if window and window.senderCheck then
		self.includeSender = getCheckedValue(window.senderCheck)
	end

	return self.durationSeconds, self.percent
end

function PartyInterference:SendAction(actionConfig)
	if not self:IsEnabled() then
		WEP:Print("Party Interference is disabled. Open /wep to enable it.")
		return false
	end

	local target = self:GetSelectedTarget()
	if not target then
		WEP:Print("Select a party member first.")
		self:RefreshWindow()
		return false
	end

	self:ReadWindowSettings()

	local payload = {
		t = shortName(target),
		a = actionConfig.wireAction or actionConfig.action,
		d = self.durationSeconds,
		i = self.percent,
		n = self.includeSender and "1" or "0",
		id = self:MakeEffectId(),
	}

	if not isBlank(self.customMessage) then
		payload.m = self.customMessage
	end

	if actionConfig.group then
		payload.g = actionConfig.group
	end

	if actionConfig.usesSelectedSound then
		payload.s = self:GetSelectedSoundName()
	elseif actionConfig.sound then
		payload.s = actionConfig.sound
	end

	if actionConfig.trigger then
		payload.k = actionConfig.wireTrigger or actionConfig.trigger
	end

	local ok, messageIdOrErr = WEP.Comm:Send(MSG_ACTION, payload, WEP.Comm:GetDefaultBroadcastOptions())
	if not ok then
		WEP:Log("PartyInterference", "send_failed", {
			target = target,
			action = actionConfig.action,
			error = messageIdOrErr,
		}, "error")
		WEP:Print("Party Interference failed:", messageIdOrErr)
		self:RefreshWindow()
		return false
	end

	WEP:Log("PartyInterference", "send_queued", {
		target = target,
		action = actionConfig.action,
		group = actionConfig.group or "none",
		trigger = actionConfig.trigger or "none",
		sound = payload.s or "none",
		messageId = messageIdOrErr,
	})
	WEP:Print("Interference sent to", shortName(target) .. ":", actionConfig.text or actionConfig.action)
	self:RefreshWindow("Queued " .. (actionConfig.text or actionConfig.action) .. " for " .. shortName(target) .. ".")
	return true
end

function PartyInterference:SendSelectedAction()
	local actionConfig = self:GetSelectedAction()

	if not actionConfig then
		WEP:Print("Select an effect first.")
		return false
	end

	return self:SendAction(actionConfig)
end

function PartyInterference:SendClear()
	return self:SendAction({
		text = "Clear Effects",
		action = "clear",
	})
end

function PartyInterference:ApplyIncomingAction(message, payload)
	local action = tostring(payload.a or "")

	if action == "clear" then
		local count = Interference.ClearBySource(message.sender)
		WEP:Log("PartyInterference", "incoming_clear_applied", {
			sender = message.sender,
			count = count,
		})
		return true, count
	end

	if action == "darken" then
		return Interference.Apply({
			id = self:MakeIncomingEffectId(message, payload),
			action = "blackout",
			source = message.sender,
			duration = getPayloadNumber(payload, "d", MIN_DURATION_SECONDS, MAX_DURATION_SECONDS, DEFAULT_DURATION_SECONDS),
			intensity = getPayloadNumber(payload, "i", MIN_PERCENT, MAX_PERCENT, DEFAULT_PERCENT),
		})
	end

	if action == "hide_ui" then
		local groupName = normalizeGroup(payload.g)
		if not groupName then
			return false, "unknown or disallowed UI group"
		end

		return Interference.Apply({
			id = self:MakeIncomingEffectId(message, payload),
			action = "hide_ui",
			source = message.sender,
			duration = getPayloadNumber(payload, "d", MIN_DURATION_SECONDS, MAX_DURATION_SECONDS, DEFAULT_DURATION_SECONDS),
			group = groupName,
		})
	end

	if action == "sound" then
		return Interference.Apply({
			id = self:MakeIncomingEffectId(message, payload),
			action = "sound",
			source = message.sender,
			duration = getPayloadNumber(payload, "d", MIN_DURATION_SECONDS, MAX_DURATION_SECONDS, DEFAULT_DURATION_SECONDS),
			sound = isBlank(payload.s) and DEFAULT_SOUND or tostring(payload.s),
		})
	end

	if action == "sound_trap" or action == "trap" then
		local percent = getPayloadNumber(payload, "i", MIN_PERCENT, MAX_PERCENT, DEFAULT_PERCENT)

		return Interference.Apply({
			id = self:MakeIncomingEffectId(message, payload),
			action = "sound_trap",
			source = message.sender,
			duration = getPayloadNumber(payload, "d", MIN_DURATION_SECONDS, MAX_DURATION_SECONDS, DEFAULT_DURATION_SECONDS),
			trigger = normalizeTrapTrigger(payload.k) or tostring(payload.k or ""),
			sound = isBlank(payload.s) and DEFAULT_SOUND or tostring(payload.s),
			chance = percent,
			threshold = percent,
		})
	end

	return false, "unknown action"
end

function PartyInterference:BuildIncomingNotice(message, payload, result)
	local customMessage = sanitizeMessage(payload and payload.m)
	local includeSender = shouldShowSender(payload)
	local senderName = shortName(message and message.sender or "unknown")
	local action = payload and payload.a or ""
	local actionText = actionLabels[action] or action or "Interference"
	local trigger = normalizeTrapTrigger(payload and payload.k)

	if action == "sound_trap" or action == "trap" then
		actionText = trigger and trapLabels[trigger] or actionText
	end

	if customMessage ~= "" then
		if includeSender then
			return senderName .. ": " .. customMessage
		end

		return customMessage
	end

	if action == "clear" then
		if includeSender then
			return "Interference cleared by " .. senderName .. ". Effects: " .. tostring(result or 0)
		end

		return "Interference cleared. Effects: " .. tostring(result or 0)
	end

	if includeSender then
		return "Interference from " .. senderName .. ": " .. actionText
	end

	return "Interference: " .. actionText
end

function PartyInterference:ShowScreenNotice(text)
	if isBlank(text) then
		return false
	end

	local frame = ensureScreenNoticeFrame()
	if not frame then
		return false
	end

	self.noticeToken = (self.noticeToken or 0) + 1
	local token = self.noticeToken

	frame.text:SetText(text)
	frame:Show()

	Timer.After(NOTICE_SECONDS, function()
		if self.noticeToken == token and frame then
			frame:Hide()
		end
	end)

	WEP:Log("PartyInterference", "screen_notice_shown")
	return true
end

function PartyInterference:PrintIncomingNotice(message, payload, result)
	local notice = self:BuildIncomingNotice(message, payload, result)

	if isBlank(notice) then
		return
	end

	WEP:Print(notice)
	self:ShowScreenNotice(notice)
end

function PartyInterference:RefreshActionRows()
	local window = interferenceWindow
	if not window or not window.actionRows then
		return
	end

	local _, selectedIndex = self:GetSelectedAction()

	for index, row in ipairs(window.actionRows) do
		local actionConfig = ACTIONS[index]
		local selected = index == selectedIndex

		row.name:SetText(actionConfig.text)
		row.detail:SetText(actionConfig.detail or "")

		if selected then
			setSolidColor(row.background, 0.15, 0.45, 0.25, 0.42)
		else
			setSolidColor(row.background, 0, 0, 0, index % 2 == 0 and 0.12 or 0.04)
		end
	end
end

function PartyInterference:OnActionMessage(message)
	local payload = message and message.payload or {}

	if type(payload) ~= "table" then
		return
	end

	if not Player.IsSelf(payload.t) then
		WEP:Log("PartyInterference", "incoming_ignored", {
			sender = message.sender,
			target = payload.t or "none",
			reason = "target mismatch",
		})
		return
	end

	if not Party.IsPartyMember(message.sender) then
		WEP:Log("PartyInterference", "incoming_ignored", {
			sender = message.sender or "none",
			reason = "sender not in party",
		}, "warn")
		return
	end

	local ok, idOrErr = self:ApplyIncomingAction(message, payload)
	if not ok then
		WEP:Log("PartyInterference", "incoming_apply_failed", {
			sender = message.sender,
			action = payload.a or "none",
			error = idOrErr,
		}, "warn")
		return
	end

	WEP:Log("PartyInterference", "incoming_applied", {
		sender = message.sender,
		action = payload.a or "none",
		effectId = idOrErr or "none",
	})

	self:PrintIncomingNotice(message, payload, idOrErr)
end

function PartyInterference:EnsureWindow()
	if interferenceWindow then
		return interferenceWindow
	end

	if not WindowTool then
		WEP:Log("PartyInterference", "window_unavailable", nil, "error")
		WEP:Print("Party Interference UI tools are unavailable.")
		return nil
	end

	local window, err = WindowTool.Create({
		name = "WEPPartyInterferenceWindow",
		title = "Party Interference",
		width = 420,
		height = 560,
		minWidth = 400,
		minHeight = 520,
		resizable = true,
		onShow = function()
			self:RefreshWindow()
		end,
	})

	if not window then
		WEP:Log("PartyInterference", "window_failed", {
			error = err,
		}, "error")
		WEP:Print("Party Interference failed:", err)
		return nil
	end

	local content = window.content

	window.statusText = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	window.statusText:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
	window.statusText:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, 0)
	window.statusText:SetJustifyH("LEFT")

	window.selectedText = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	window.selectedText:SetPoint("TOPLEFT", window.statusText, "BOTTOMLEFT", 0, -10)
	window.selectedText:SetPoint("RIGHT", content, "RIGHT", 0, 0)
	window.selectedText:SetJustifyH("LEFT")

	window.partyList = List.Create(content, {
		width = 150,
		visibleRows = 2,
		rowHeight = 24,
		emptyText = "No party members.",
		columns = {
			{
				key = "name",
				width = 86,
			},
			{
				key = "state",
				width = 42,
			},
		},
	})
	window.partyList.frame:SetPoint("TOPLEFT", window.selectedText, "BOTTOMLEFT", 0, -8)

	window.durationInput = Form.CreateInput(content, {
		label = "Duration",
		value = self.durationSeconds,
		numeric = true,
		width = 72,
	})
	window.durationInput:SetPoint("TOPLEFT", window.partyList.frame, "TOPRIGHT", 16, 0)

	window.percentInput = Form.CreateInput(content, {
		label = "Percent",
		value = self.percent,
		numeric = true,
		width = 72,
	})
	window.percentInput:SetPoint("LEFT", window.durationInput, "RIGHT", 12, 0)

	window.messageInput = Form.CreateInput(content, {
		label = "Message",
		value = self.customMessage,
		width = 156,
		maxLetters = MAX_MESSAGE_LENGTH,
	})
	window.messageInput:SetPoint("TOPLEFT", window.durationInput, "BOTTOMLEFT", 0, -8)

	window.senderCheck = CreateFrame("CheckButton", nil, content, "UICheckButtonTemplate")
	window.senderCheck:SetPoint("TOPLEFT", window.messageInput, "BOTTOMLEFT", -4, -2)
	window.senderCheck:SetChecked(self.includeSender ~= false)

	window.senderCheckLabel = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	window.senderCheckLabel:SetPoint("LEFT", window.senderCheck, "RIGHT", 0, 0)
	window.senderCheckLabel:SetText("Include sender name")

	window.soundTitle = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	window.soundTitle:SetPoint("TOPLEFT", window.senderCheck, "BOTTOMLEFT", 4, -8)
	window.soundTitle:SetText("Sound")

	window.soundPrevButton = Form.CreateButton(content, {
		text = "<",
		width = 28,
		onClick = function()
			self:SelectSoundOffset(-1)
		end,
	})
	window.soundPrevButton:SetPoint("TOPLEFT", window.soundTitle, "BOTTOMLEFT", 0, -4)

	window.soundText = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	window.soundText:SetPoint("LEFT", window.soundPrevButton, "RIGHT", 8, 0)
	window.soundText:SetWidth(220)
	window.soundText:SetJustifyH("LEFT")

	window.soundNextButton = Form.CreateButton(content, {
		text = ">",
		width = 28,
		onClick = function()
			self:SelectSoundOffset(1)
		end,
	})
	window.soundNextButton:SetPoint("LEFT", window.soundText, "RIGHT", 8, 0)

	window.actionTitle = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	window.actionTitle:SetPoint("TOPLEFT", window.soundPrevButton, "BOTTOMLEFT", 0, -8)
	window.actionTitle:SetText("Effect")

	window.actionFrame = CreateFrame("Frame", nil, content)
	window.actionFrame:SetPoint("TOPLEFT", window.actionTitle, "BOTTOMLEFT", -4, -6)
	window.actionFrame:SetPoint("RIGHT", content, "RIGHT", 0, 0)
	window.actionFrame:SetHeight(#ACTIONS * ACTION_ROW_HEIGHT)

	window.actionRows = {}

	for index, actionConfig in ipairs(ACTIONS) do
		local row = CreateFrame("Button", nil, window.actionFrame)
		row:SetHeight(ACTION_ROW_HEIGHT)
		row:SetPoint("LEFT", window.actionFrame, "LEFT", 0, 0)
		row:SetPoint("RIGHT", window.actionFrame, "RIGHT", 0, 0)
		row:SetPoint("TOP", window.actionFrame, "TOP", 0, -((index - 1) * ACTION_ROW_HEIGHT))

		row.background = row:CreateTexture(nil, "BACKGROUND")
		row.background:SetAllPoints(row)

		row.name = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
		row.name:SetPoint("LEFT", row, "LEFT", 8, 0)
		row.name:SetWidth(142)
		row.name:SetJustifyH("LEFT")
		row.name:SetText(actionConfig.text)

		row.detail = row:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
		row.detail:SetPoint("LEFT", row.name, "RIGHT", 12, 0)
		row.detail:SetPoint("RIGHT", row, "RIGHT", -8, 0)
		row.detail:SetJustifyH("LEFT")
		row.detail:SetText(actionConfig.detail or "")

		row:SetScript("OnClick", function()
			self:SelectAction(index)
		end)

		window.actionRows[index] = row
	end

	window.startButton = Form.CreateButton(window.footer, {
		text = "Start",
		width = 92,
		onClick = function()
			self:SendSelectedAction()
		end,
	})
	window.startButton:SetPoint("LEFT", window.footer, "LEFT", 0, 0)

	window.clearButton = Form.CreateButton(window.footer, {
		text = "Clear Mine",
		width = 100,
		onClick = function()
			self:SendClear()
		end,
	})
	window.clearButton:SetPoint("LEFT", window.startButton, "RIGHT", 8, 0)

	window.refreshButton = Form.CreateButton(window.footer, {
		text = "Refresh",
		width = 88,
		onClick = function()
			self:RefreshWindow("Party list refreshed.")
		end,
	})
	window.refreshButton:SetPoint("LEFT", window.clearButton, "RIGHT", 8, 0)

	interferenceWindow = window
	self:RefreshActionRows()
	WEP:Log("PartyInterference", "window_created")
	return interferenceWindow
end

function PartyInterference:RefreshWindow(statusText)
	local window = interferenceWindow
	if not window or not window:IsShown() then
		return
	end

	self:ReadWindowSettings()

	local members = self:GetPartyMembers()
	local selectedTarget = self:GetSelectedTarget()
	local hasTarget = selectedTarget ~= nil
	local activeCount = Interference.GetStatus().activeCount
	local actionConfig = self:GetSelectedAction()
	local selectedSound, selectedSoundIndex, soundCount = self:GetSelectedSound()
	local soundSelectorEnabled = actionConfig and actionConfig.usesSelectedSound == true

	window.statusText:SetText(statusText or ("Party members: " .. #members .. "  Active effects on you: " .. activeCount))
	window.selectedText:SetText("Selected: " .. (selectedTarget and shortName(selectedTarget) or "none"))
	window.partyList:SetItems(self:GetPartyItems())
	self:RefreshActionRows()

	setInputValueIfNotFocused(window.durationInput, self.durationSeconds)
	setInputValueIfNotFocused(window.percentInput, self.percent)
	setInputValueIfNotFocused(window.messageInput, self.customMessage)

	if window.percentInput and window.percentInput.label then
		window.percentInput.label:SetText(self:GetPercentLabel())
	end

	if window.senderCheck then
		window.senderCheck:SetChecked(self.includeSender ~= false)
	end

	if window.soundText then
		local soundLabel = selectedSound and (selectedSound.label or selectedSound.name) or DEFAULT_SOUND
		window.soundText:SetText(soundLabel .. " (" .. selectedSoundIndex .. "/" .. soundCount .. ")")
		window.soundText:SetTextColor(soundSelectorEnabled and 1 or 0.55, soundSelectorEnabled and 0.82 or 0.55, 0.2)
	end

	setButtonEnabled(window.startButton, hasTarget)
	setButtonEnabled(window.clearButton, hasTarget)
	setButtonEnabled(window.refreshButton, true)
	setButtonEnabled(window.soundPrevButton, soundSelectorEnabled and soundCount > 1)
	setButtonEnabled(window.soundNextButton, soundSelectorEnabled and soundCount > 1)
end

function PartyInterference:ShowWindow()
	local window = self:EnsureWindow()
	if not window then
		return
	end

	window:Show()
	self:RefreshWindow()
	WEP:Log("PartyInterference", "window_shown")
end

function PartyInterference:ShowMenu()
	self:ShowWindow()
end

function PartyInterference:OpenUI()
	self:ShowWindow()
end

function PartyInterference:PrintStatus()
	local members = self:GetPartyMembers()
	local status = Interference.GetStatus()

	WEP:Print("Party Interference:", #members, "party members,", status.activeCount, "active effects on you.")
end

function PartyInterference:OnDisabled()
	WEP:Log("PartyInterference", "disabled")

	if interferenceWindow then
		interferenceWindow:Hide()
	end

	for _, effect in ipairs(Interference.GetStatus().effects) do
		Interference.Clear(effect.id)
	end
end

function PartyInterference:HandleSlash(args)
	if not self:IsEnabled() then
		WEP:Print("Party Interference is disabled. Open /wep to enable it.")
		return
	end

	local action = args[2]
	WEP:Log("PartyInterference", "slash", {
		action = action or "menu",
	})

	if not action or action == "menu" or action == "open" then
		self:ShowWindow()
		return
	end

	if action == "status" then
		self:PrintStatus()
		return
	end

	WEP:Print("Usage: /wep interfere")
	WEP:Print("Usage: /wep interfere status")
end

WEP:RegisterFeature(FEATURE_ID, PartyInterference)
WEP:RegisterModule("PartyInterference", PartyInterference)
