local _, WEP = ...

local Pranks = {
	durationSeconds = 8,
	percent = 70,
	customMessage = "",
	includeSender = true,
	includeSound = false,
	selectedTarget = nil,
	selectedTargets = {},
	selectedActionIndex = 1,
	selectedSound = "wep_alert",
	counter = 0,
}
local PartyInterference = Pranks

WEP.Pranks = Pranks
WEP.PartyInterference = Pranks

local FEATURE_ID = "pranks"

Pranks.title = "Pranks"
Pranks.description = "Send temporary screen, UI, and sound pranks to party friends."

local Player = WEP.Tools.Player
local Party = WEP.Tools.Party
local Interference = WEP.Tools.Interference
local Timer = WEP.Tools.Timer
local UIVisibility = WEP.Tools.UIVisibility
local Sound = WEP.Tools.Sound
local SoundTriggers = WEP.Tools.SoundTriggers
local WindowTool = WEP.Tools.Window
local Form = WEP.Tools.Form
local List = WEP.Tools.List

WEP:Log("Pranks", "loaded")

local MSG_ACTION = "party_interference_action"

local MIN_DURATION_SECONDS = 1
local MAX_DURATION_SECONDS = 900
local DEFAULT_DURATION_SECONDS = 8
local MIN_PERCENT = 10
local MAX_PERCENT = 95
local DEFAULT_PERCENT = 70
local MAX_MESSAGE_LENGTH = 60
local DEFAULT_SOUND = "wep_alert"
local NOTICE_SECONDS = 3
local ACTION_ROW_HEIGHT = 38
local COLUMN_GAP = 12
local PARTY_LIST_WIDTH = 166
local ACTION_COLUMN_WIDTH = 300
local CONFIG_INPUT_WIDTH = 218
local PARTY_LIST_VISIBLE_ROWS = 10
local PARTY_LIST_ROW_HEIGHT = 20
local WINDOW_BASE_WIDTH = 760
local WINDOW_BASE_HEIGHT = 390
local WINDOW_MIN_WIDTH = 760
local WINDOW_MIN_HEIGHT = 390
local WINDOW_COLLAPSED_WIDTH = 170

local ALLOWED_UI_GROUPS = {
	actionbars = true,
	bags = true,
	buffs = true,
	casting = true,
	chat = true,
	micromenu = true,
	minimap = true,
	questtracker = true,
	unitframes = true,
}

local ACTIONS = {
	{
		category = "visual",
		text = "Darken Screen",
		action = "darken",
		percentLabel = "Intensity",
		usesPercent = true,
	},
	{
		category = "visual",
		text = "Red Alert",
		action = "tint",
		variant = "red",
		percentLabel = "Intensity",
		usesPercent = true,
	},
	{
		category = "visual",
		text = "Fel Goggles",
		action = "tint",
		variant = "fel",
		percentLabel = "Intensity",
		usesPercent = true,
	},
	{
		category = "visual",
		text = "Arcane Haze",
		action = "tint",
		variant = "arcane",
		percentLabel = "Intensity",
		usesPercent = true,
	},
	{
		category = "visual",
		text = "Snowblind",
		action = "tint",
		variant = "snow",
		percentLabel = "Intensity",
		usesPercent = true,
	},
	{
		category = "visual",
		text = "Panic Flash",
		action = "pulse",
		variant = "panic",
		percentLabel = "Intensity",
		usesPercent = true,
	},
	{
		category = "visual",
		text = "Tunnel Vision",
		action = "vignette",
		variant = "tunnel",
		percentLabel = "Intensity",
		usesPercent = true,
	},
	{
		category = "visual",
		text = "Letterbox",
		action = "letterbox",
		percentLabel = "Intensity",
		usesPercent = true,
	},
	{
		category = "visual",
		text = "Fake Raid Warning",
		action = "fake_notice",
		variant = "raid",
		percentLabel = "Intensity",
		usesPercent = true,
	},
	{
		category = "visual",
		text = "Error Storm",
		action = "fake_notice",
		variant = "error",
		percentLabel = "Intensity",
		usesPercent = true,
	},
	{
		category = "visual",
		text = "Loot Mirage",
		action = "fake_notice",
		variant = "loot",
		percentLabel = "Intensity",
		usesPercent = true,
	},
	{
		category = "ui",
		text = "Hide Health",
		action = "hide_ui",
		group = "unitframes",
	},
	{
		category = "ui",
		text = "Hide Bars",
		action = "hide_ui",
		group = "actionbars",
	},
	{
		category = "ui",
		text = "Hide Minimap",
		action = "hide_ui",
		group = "minimap",
	},
	{
		category = "ui",
		text = "Hide Chat",
		action = "hide_ui",
		group = "chat",
	},
	{
		category = "ui",
		text = "Hide Buffs",
		action = "hide_ui",
		group = "buffs",
	},
	{
		category = "ui",
		text = "Hide Cast Bars",
		action = "hide_ui",
		group = "casting",
	},
	{
		category = "ui",
		text = "Hide Bags",
		action = "hide_ui",
		group = "bags",
	},
	{
		category = "ui",
		text = "Hide Micro Menu",
		action = "hide_ui",
		group = "micromenu",
	},
	{
		category = "ui",
		text = "Hide Quest Tracker",
		action = "hide_ui",
		group = "questtracker",
	},
	{
		category = "sound",
		text = "Play Sound",
		action = "sound",
		sound = DEFAULT_SOUND,
		usesSoundSelection = true,
	},
	{
		category = "sound_traps",
		text = "Boom Walk",
		action = "sound_trap",
		wireAction = "trap",
		trigger = "walk",
		wireTrigger = "w",
		sound = "wep_vine_boom",
	},
	{
		category = "sound_traps",
		text = "Target Sting",
		action = "sound_trap",
		wireAction = "trap",
		trigger = "target",
		wireTrigger = "t",
		sound = "wep_hello_there",
	},
	{
		category = "sound_traps",
		text = "Combat Drop",
		action = "sound_trap",
		wireAction = "trap",
		trigger = "combat",
		wireTrigger = "c",
		sound = "wep_fbi_open_up",
	},
	{
		category = "sound_traps",
		text = "Cast Heckle",
		action = "sound_trap",
		wireAction = "trap",
		trigger = "cast",
		wireTrigger = "s",
		sound = "wep_error",
	},
	{
		category = "sound_traps",
		text = "Enemy Sting",
		action = "sound_trap",
		wireAction = "trap",
		trigger = "enemy_target",
		wireTrigger = "e",
		sound = "wep_nani",
	},
}

local actionLabels = {
	clear = "Clear Effects",
	darken = "Darken Screen",
	fake_notice = "Fake Notice",
	hide_ui = "Hide UI",
	letterbox = "Letterbox",
	pulse = "Panic Flash",
	sound = "Play Alert",
	sound_trap = "Sound Trap",
	tint = "Screen Tint",
	trap = "Sound Trap",
	vignette = "Tunnel Vision",
}

local categoryLabels = {
	sound = "Sound",
	sound_traps = "Sound Trap",
	ui = "Hide UI",
	visual = "Visual",
}

local actionDescriptions = {
	darken = "Darkens their screen briefly.",
	fake_notice = {
		error = "Shows fake red error spam.",
		loot = "Shows a fake loot message.",
		raid = "Shows a fake raid warning.",
	},
	hide_ui = {
		actionbars = "Hides their action bars.",
		bags = "Hides bag buttons.",
		buffs = "Hides buff and debuff icons.",
		casting = "Hides cast bars.",
		chat = "Hides their chat frame.",
		micromenu = "Hides the micro menu.",
		minimap = "Hides their minimap.",
		questtracker = "Hides the quest tracker.",
		unitframes = "Hides unit frames and health.",
	},
	letterbox = "Adds black cinematic bars.",
	pulse = {
		panic = "Pulses a red panic flash.",
	},
	sound = "Plays the selected sound for the duration.",
	sound_trap = {
		cast = "Plays Error when they cast.",
		combat = "Plays FBI Open Up in combat.",
		enemy_target = "Plays Nani on hostile target.",
		target = "Plays Hello There on party target.",
		walk = "Plays Vine Boom while they move.",
	},
	tint = {
		arcane = "Tints their screen purple.",
		fel = "Tints their screen fel green.",
		red = "Tints their screen red.",
		snow = "Tints their screen white.",
	},
	vignette = {
		tunnel = "Darkens screen edges heavily.",
	},
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
	if not SoundTriggers or not SoundTriggers.NormalizeTrigger then
		return nil
	end

	return SoundTriggers.NormalizeTrigger(trigger)
end

local function normalizeVariant(variant)
	local value = trim(variant):lower():gsub("[^a-z0-9_%-]", "")

	if value == "" then
		return nil
	end

	if #value > 20 then
		value = value:sub(1, 20)
	end

	return value
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

local function getActionTypeLabel(actionConfig)
	if not actionConfig then
		return ""
	end

	return categoryLabels[actionConfig.category] or actionLabels[actionConfig.action] or ""
end

local function getActionDescription(actionConfig)
	if not actionConfig then
		return ""
	end

	local actionDescription = actionDescriptions[actionConfig.action]
	if type(actionDescription) == "table" then
		return actionDescription[actionConfig.group]
			or actionDescription[actionConfig.trigger]
			or actionDescription[actionConfig.variant]
			or ""
	end

	return actionDescription or ""
end

local function ensureScreenNoticeFrame()
	if screenNoticeFrame then
		return screenNoticeFrame
	end

	if not CreateFrame or not UIParent then
		WEP:Log("Pranks", "screen_notice_unavailable", nil, "warn")
		return nil
	end

	local frame = CreateFrame("Frame", "WEPPranksScreenNotice", UIParent)
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
	WEP:Log("Pranks", "screen_notice_created")
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
	WEP:Log("Pranks", "initialize")

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

function PartyInterference:EnsureSelectedTargets()
	self.selectedTargets = self.selectedTargets or {}

	if not isBlank(self.selectedTarget) then
		local key = nameKey(self.selectedTarget)
		if key ~= "" then
			self.selectedTargets[key] = self.selectedTarget
		end

		self.selectedTarget = nil
	end

	return self.selectedTargets
end

function PartyInterference:FindPartyMember(target)
	if isBlank(target) then
		return nil
	end

	for _, member in ipairs(self:GetPartyMembers()) do
		if namesMatch(member.name, target) or namesMatch(member.shortName, target) then
			return member
		end
	end

	return nil
end

function PartyInterference:GetSelectedTargets()
	local selectedTargets = self:EnsureSelectedTargets()
	local selected = {}
	local currentKeys = {}

	for _, member in ipairs(self:GetPartyMembers()) do
		local key = nameKey(member.name)

		if key ~= "" then
			currentKeys[key] = true

			if selectedTargets[key] or selectedTargets[nameKey(member.shortName)] then
				selectedTargets[key] = member.name
				selected[#selected + 1] = member.name
			end
		end
	end

	for key in pairs(selectedTargets) do
		if not currentKeys[key] then
			selectedTargets[key] = nil
		end
	end

	return selected
end

function PartyInterference:IsSelectedTargetInParty()
	return self:GetSelectedTargets()[1] ~= nil
end

function PartyInterference:GetSelectedTarget()
	return self:GetSelectedTargets()[1]
end

function PartyInterference:IsTargetSelected(target)
	local key = nameKey(target)
	return key ~= "" and self:EnsureSelectedTargets()[key] ~= nil
end

function PartyInterference:SetTargetSelected(target, selected)
	local member = self:FindPartyMember(target)
	if not member then
		WEP:Print("Prank target must be a current party member.")
		WEP:Log("Pranks", "target_select_failed", {
			target = target,
			error = "not in party",
		}, "warn")
		return false
	end

	local key = nameKey(member.name)
	if selected == false then
		self:EnsureSelectedTargets()[key] = nil
	else
		self:EnsureSelectedTargets()[key] = member.name
	end

	WEP:Log("Pranks", "target_selection_changed", {
		target = member.name,
		selected = selected ~= false,
	})
	self:RefreshWindow()
	return true
end

function PartyInterference:SelectTarget(target)
	return self:SetTargetSelected(target, not self:IsTargetSelected(target))
end

function PartyInterference:SelectAllTargets()
	local selectedTargets = self:EnsureSelectedTargets()

	for _, member in ipairs(self:GetPartyMembers()) do
		local key = nameKey(member.name)
		if key ~= "" then
			selectedTargets[key] = member.name
		end
	end

	WEP:Log("Pranks", "targets_all_selected", {
		count = #self:GetSelectedTargets(),
	})
	self:RefreshWindow()
	return true
end

function PartyInterference:ClearSelectedTargets()
	self.selectedTarget = nil
	self.selectedTargets = {}
	WEP:Log("Pranks", "targets_cleared")
	self:RefreshWindow()
	return true
end

function PartyInterference:GetSelectedTargetLabel(targets)
	targets = targets or self:GetSelectedTargets()

	if #targets == 0 then
		return "none"
	end

	local names = {}
	for _, target in ipairs(targets) do
		names[#names + 1] = shortName(target)
	end

	return table.concat(names, ", ")
end

function PartyInterference:GetPartyItems(members)
	local items = {}

	for _, member in ipairs(members or self:GetPartyMembers()) do
		local selected = self:IsTargetSelected(member.name)
		local state = "Ready"

		if selected then
			state = "Picked"
		elseif member.connected == false then
			state = "Offline"
		end

		items[#items + 1] = {
			name = member.shortName or shortName(member.name),
			state = state,
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

function PartyInterference:GetSoundChoices()
	local choices = {}

	if Sound and Sound.GetCustomSounds then
		for _, sound in ipairs(Sound.GetCustomSounds()) do
			choices[#choices + 1] = {
				name = sound.name,
				label = sound.label or sound.name,
			}
		end
	end

	if #choices == 0 then
		choices[#choices + 1] = {
			name = DEFAULT_SOUND,
			label = "WEP Alert",
		}
	end

	table.sort(choices, function(left, right)
		return string.lower(left.label or left.name) < string.lower(right.label or right.name)
	end)

	return choices
end

function PartyInterference:GetSelectedSound()
	local choices = self:GetSoundChoices()
	local selectedSound = isBlank(self.selectedSound) and DEFAULT_SOUND or tostring(self.selectedSound)

	for index, sound in ipairs(choices) do
		if sound.name == selectedSound then
			self.selectedSound = sound.name
			return sound.name, sound.label or sound.name, index, #choices
		end
	end

	self.selectedSound = choices[1].name
	return choices[1].name, choices[1].label or choices[1].name, 1, #choices
end

function PartyInterference:SelectSoundOffset(offset)
	local choices = self:GetSoundChoices()
	if #choices == 0 then
		return false
	end

	local _, _, selectedIndex = self:GetSelectedSound()
	local nextIndex = selectedIndex + offset

	if nextIndex < 1 then
		nextIndex = #choices
	elseif nextIndex > #choices then
		nextIndex = 1
	end

	self.selectedSound = choices[nextIndex].name
	WEP:Log("Pranks", "sound_selected", {
		sound = self.selectedSound,
	})
	self:RefreshWindow()
	return true
end

function PartyInterference:SelectPreviousSound()
	return self:SelectSoundOffset(-1)
end

function PartyInterference:SelectNextSound()
	return self:SelectSoundOffset(1)
end

function PartyInterference:TestSelectedSound()
	if not Sound or not Sound.Play then
		WEP:Print("Sound tool unavailable.")
		return false
	end

	local sound = self:GetSelectedSound()
	local ok, playbackOrErr = Sound.Play(sound, {
		duration = 1,
	})

	if not ok then
		WEP:Print("Sound failed:", playbackOrErr)
		return false
	end

	return true
end

function PartyInterference:GetSelectedAction()
	local selectedIndex = tonumber(self.selectedActionIndex) or 1

	if not ACTIONS[selectedIndex] then
		selectedIndex = 1
	end

	self.selectedActionIndex = selectedIndex
	return ACTIONS[selectedIndex], selectedIndex
end

function PartyInterference:IsSelectedActionVisible()
	return self:GetSelectedAction() ~= nil
end

function PartyInterference:GetVisibleActionItems()
	local items = {}

	for index, actionConfig in ipairs(ACTIONS) do
		items[#items + 1] = {
			index = index,
			action = actionConfig,
		}
	end

	return items
end

function PartyInterference:ApplyWindowFit()
	local window = interferenceWindow
	if not window or not window.frame then
		return
	end

	if window.IsCollapsed and window:IsCollapsed() then
		return
	end

	if window.SetSize then
		window:SetSize(WINDOW_BASE_WIDTH, WINDOW_BASE_HEIGHT)
	end
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
	WEP:Log("Pranks", "action_selected", {
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

	if window and window.soundCheck then
		self.includeSound = getCheckedValue(window.soundCheck)
	end

	return self.durationSeconds, self.percent
end

function PartyInterference:ShouldAttachSelectedSound(actionConfig)
	if self.includeSound ~= true or not actionConfig then
		return false
	end

	local action = actionConfig.action
	return action ~= "sound" and action ~= "sound_trap" and action ~= "clear"
end

function PartyInterference:SendAction(actionConfig)
	if not self:IsEnabled() then
		WEP:Print("Pranks is disabled. Open /wep to enable it.")
		return false
	end

	local targets = self:GetSelectedTargets()
	if #targets == 0 then
		WEP:Print("Select at least one party member first.")
		self:RefreshWindow()
		return false
	end

	self:ReadWindowSettings()

	local actionSound = actionConfig.sound
	if actionConfig.usesSoundSelection then
		actionSound = self:GetSelectedSound()
	end
	local shouldAttachSound = self:ShouldAttachSelectedSound(actionConfig)
	local attachedSound = shouldAttachSound and self:GetSelectedSound() or nil

	local sentCount = 0
	local failedCount = 0
	local lastError

	for _, target in ipairs(targets) do
		local payload = {
			t = shortName(target),
			a = actionConfig.wireAction or actionConfig.action,
			d = self.durationSeconds,
			n = self.includeSender and "1" or "0",
			id = self:MakeEffectId(),
		}

		if actionConfig.usesPercent then
			payload.i = self.percent
		end

		if actionConfig.variant then
			payload.v = actionConfig.variant
		end

		if not isBlank(self.customMessage) then
			payload.m = self.customMessage
		end

		if actionConfig.group then
			payload.g = actionConfig.group
		end

		if actionSound then
			payload.s = actionSound
		end

		if actionConfig.trigger then
			payload.k = actionConfig.wireTrigger or actionConfig.trigger
		end

		local ok, messageIdOrErr = WEP.Comm:Send(MSG_ACTION, payload, WEP.Comm:GetDefaultBroadcastOptions())
		if ok then
			sentCount = sentCount + 1
			WEP:Log("Pranks", "send_queued", {
				target = target,
				action = actionConfig.action,
				group = actionConfig.group or "none",
				trigger = actionConfig.trigger or "none",
				variant = actionConfig.variant or "none",
				sound = payload.s or "none",
				messageId = messageIdOrErr,
			})

			if shouldAttachSound then
				local soundPayload = {
					t = shortName(target),
					a = "sound",
					d = self.durationSeconds,
					n = self.includeSender and "1" or "0",
					id = self:MakeEffectId(),
					s = attachedSound,
				}

				local soundOk, soundMessageIdOrErr = WEP.Comm:Send(MSG_ACTION, soundPayload, WEP.Comm:GetDefaultBroadcastOptions())
				if soundOk then
					WEP:Log("Pranks", "attached_sound_queued", {
						target = target,
						sound = soundPayload.s or "none",
						messageId = soundMessageIdOrErr,
					})
				else
					failedCount = failedCount + 1
					lastError = soundMessageIdOrErr
					WEP:Log("Pranks", "attached_sound_failed", {
						target = target,
						sound = soundPayload.s or "none",
						error = soundMessageIdOrErr,
					}, "error")
				end
			end
		else
			failedCount = failedCount + 1
			lastError = messageIdOrErr
			WEP:Log("Pranks", "send_failed", {
				target = target,
				action = actionConfig.action,
				error = messageIdOrErr,
			}, "error")
		end
	end

	if sentCount == 0 then
		WEP:Print("Prank failed:", lastError)
		self:RefreshWindow()
		return false
	end

	local actionText = actionConfig.text or actionConfig.action
	local targetLabel = self:GetSelectedTargetLabel(targets)
	if failedCount > 0 then
		WEP:Print("Prank sent to", sentCount, "target(s); failed", failedCount .. ":", lastError)
	else
		WEP:Print("Prank sent to", targetLabel .. ":", actionText)
	end

	self:RefreshWindow("Queued " .. actionText .. " for " .. targetLabel .. ".")
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

function PartyInterference:ClearSelf()
	local effects = Interference.GetStatus().effects
	local cleared = 0

	for _, effect in ipairs(effects) do
		local ok = Interference.Clear(effect.id)
		if ok then
			cleared = cleared + 1
		end
	end

	WEP:Log("Pranks", "self_cleared", {
		count = cleared,
	})

	if cleared > 0 then
		WEP:Print("Cleared", cleared, "prank(s) from you.")
	else
		WEP:Print("No active pranks on you.")
	end

	self:RefreshWindow()
	return cleared
end

function PartyInterference:ApplyIncomingAction(message, payload)
	local action = tostring(payload.a or "")

	if action == "clear" then
		local count = Interference.ClearBySource(message.sender)
		WEP:Log("Pranks", "incoming_clear_applied", {
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

	if action == "tint" or action == "pulse" or action == "vignette" or action == "letterbox" or action == "fake_notice" then
		return Interference.Apply({
			id = self:MakeIncomingEffectId(message, payload),
			action = action,
			source = message.sender,
			duration = getPayloadNumber(payload, "d", MIN_DURATION_SECONDS, MAX_DURATION_SECONDS, DEFAULT_DURATION_SECONDS),
			intensity = getPayloadNumber(payload, "i", MIN_PERCENT, MAX_PERCENT, DEFAULT_PERCENT),
			variant = normalizeVariant(payload.v),
			message = sanitizeMessage(payload.m),
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
		local chance = getPayloadNumber(payload, "i", 0, 100, 100)

		return Interference.Apply({
			id = self:MakeIncomingEffectId(message, payload),
			action = "sound_trap",
			source = message.sender,
			duration = getPayloadNumber(payload, "d", MIN_DURATION_SECONDS, MAX_DURATION_SECONDS, DEFAULT_DURATION_SECONDS),
			trigger = normalizeTrapTrigger(payload.k) or tostring(payload.k or ""),
			sound = isBlank(payload.s) and DEFAULT_SOUND or tostring(payload.s),
			chance = chance,
		})
	end

	return false, "unknown action"
end

function PartyInterference:BuildIncomingNotice(message, payload, result)
	local customMessage = sanitizeMessage(payload and payload.m)
	local includeSender = shouldShowSender(payload)
	local senderName = shortName(message and message.sender or "unknown")

	if customMessage ~= "" then
		if includeSender then
			return senderName .. ": " .. customMessage
		end

		return customMessage
	end

	return nil
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

	WEP:Log("Pranks", "screen_notice_shown")
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

local function ensureActionRow(window, index)
	window.actionRows = window.actionRows or {}

	if window.actionRows[index] then
		return window.actionRows[index]
	end

	local row = CreateFrame("Button", nil, window.actionFrame)
	row:SetHeight(ACTION_ROW_HEIGHT)
	row:SetPoint("LEFT", window.actionFrame, "LEFT", 0, 0)
	row:SetPoint("RIGHT", window.actionFrame, "RIGHT", 0, 0)

	row.background = row:CreateTexture(nil, "BACKGROUND")
	row.background:SetAllPoints(row)

	row.check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
	row.check:SetPoint("LEFT", row, "LEFT", -2, 0)

	row.title = row:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	row.title:SetPoint("TOPLEFT", row.check, "TOPRIGHT", 2, -4)
	row.title:SetWidth(132)
	row.title:SetJustifyH("LEFT")

	row.description = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	row.description:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -1)
	row.description:SetWidth(160)
	row.description:SetJustifyH("LEFT")
	row.description:SetJustifyV("TOP")
	if row.description.SetWordWrap then
		row.description:SetWordWrap(false)
	end
	if row.description.SetTextColor then
		row.description:SetTextColor(0.72, 0.72, 0.72, 1)
	end

	row.type = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	row.type:SetPoint("TOPRIGHT", row, "TOPRIGHT", -66, -5)
	row.type:SetWidth(72)
	row.type:SetJustifyH("RIGHT")

	row.sendButton = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
	row.sendButton:SetSize(54, 20)
	row.sendButton:SetPoint("RIGHT", row, "RIGHT", -8, 0)
	row.sendButton:SetText("Send")

	row.check:SetScript("OnClick", function()
		if row.actionIndex then
			PartyInterference:SelectAction(row.actionIndex)
		end
	end)

	row:SetScript("OnClick", function()
		if row.actionIndex then
			PartyInterference:SelectAction(row.actionIndex)
		end
	end)

	row.sendButton:SetScript("OnClick", function()
		if row.actionIndex and ACTIONS[row.actionIndex] then
			PartyInterference:SelectAction(row.actionIndex)
			PartyInterference:SendAction(ACTIONS[row.actionIndex])
		end
	end)

	window.actionRows[index] = row
	return row
end

function PartyInterference:RefreshActionRows()
	local window = interferenceWindow
	if not window or not window.actionRows then
		return
	end

	local _, selectedIndex = self:GetSelectedAction()
	local items = self:GetVisibleActionItems()
	local hasTarget = self:GetSelectedTargets()[1] ~= nil

	window.actionFrame:SetHeight(#items * ACTION_ROW_HEIGHT)

	if window.scrollFrame and window.scrollFrame.GetWidth and window.scrollFrame:GetWidth() > 0 then
		window.actionFrame:SetWidth(window.scrollFrame:GetWidth())
	end

	for index, item in ipairs(items) do
		local row = ensureActionRow(window, index)
		local actionConfig = item.action
		local selected = item.index == selectedIndex

		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", window.actionFrame, "TOPLEFT", 0, -((index - 1) * ACTION_ROW_HEIGHT))
		row:SetPoint("RIGHT", window.actionFrame, "RIGHT", 0, 0)
		row:Show()
		row.actionIndex = item.index

		if selected then
			setSolidColor(row.background, 0.15, 0.45, 0.25, 0.5)
		else
			setSolidColor(row.background, 0, 0, 0, index % 2 == 0 and 0.18 or 0.08)
		end

		row.check:SetChecked(selected)
		row.title:SetText(actionConfig.text)
		row.description:SetText(getActionDescription(actionConfig))
		row.type:SetText(getActionTypeLabel(actionConfig))
		setButtonEnabled(row.sendButton, hasTarget)
	end

	for index = #items + 1, #window.actionRows do
		window.actionRows[index]:Hide()
	end
end

function PartyInterference:OnActionMessage(message)
	local payload = message and message.payload or {}

	if type(payload) ~= "table" then
		return
	end

	if not Player.IsSelf(payload.t) then
		WEP:Log("Pranks", "incoming_ignored", {
			sender = message.sender,
			target = payload.t or "none",
			reason = "target mismatch",
		})
		return
	end

	if not Party.IsPartyMember(message.sender) then
		WEP:Log("Pranks", "incoming_ignored", {
			sender = message.sender or "none",
			reason = "sender not in party",
		}, "warn")
		return
	end

	local ok, idOrErr = self:ApplyIncomingAction(message, payload)
	if not ok then
		WEP:Log("Pranks", "incoming_apply_failed", {
			sender = message.sender,
			action = payload.a or "none",
			error = idOrErr,
		}, "warn")
		return
	end

	WEP:Log("Pranks", "incoming_applied", {
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
		WEP:Log("Pranks", "window_unavailable", nil, "error")
		WEP:Print("Pranks UI tools are unavailable.")
		return nil
	end

	local window, err = WindowTool.Create({
		name = "WEPPranksWindow",
		title = "Pranks",
		width = WINDOW_BASE_WIDTH,
		height = WINDOW_BASE_HEIGHT,
		minWidth = WINDOW_MIN_WIDTH,
		minHeight = WINDOW_MIN_HEIGHT,
		collapsedWidth = WINDOW_COLLAPSED_WIDTH,
		collapsible = true,
		closeOnEscape = false,
		onShow = function()
			self:RefreshWindow()
		end,
	})

	if not window then
		WEP:Log("Pranks", "window_failed", {
			error = err,
		}, "error")
		WEP:Print("Pranks failed:", err)
		return nil
	end

	local content = window.content

	window.statusText = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	window.statusText:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
	window.statusText:SetPoint("TOPRIGHT", content, "TOPRIGHT", -90, 0)
	window.statusText:SetJustifyH("LEFT")

	window.clearSelfButton = Form.CreateButton(content, {
		text = "Clear Me",
		width = 82,
		onClick = function()
			self:ClearSelf()
		end,
	})
	window.clearSelfButton:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, 2)

	window.partyColumn = CreateFrame("Frame", nil, content)
	window.partyColumn:SetPoint("TOPLEFT", window.statusText, "BOTTOMLEFT", 0, -10)
	window.partyColumn:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", 0, 0)
	window.partyColumn:SetWidth(PARTY_LIST_WIDTH)

	window.actionColumn = CreateFrame("Frame", nil, content)
	window.actionColumn:SetPoint("TOPLEFT", window.partyColumn, "TOPRIGHT", COLUMN_GAP, 0)
	window.actionColumn:SetPoint("BOTTOMLEFT", window.partyColumn, "BOTTOMRIGHT", COLUMN_GAP, 0)
	window.actionColumn:SetWidth(ACTION_COLUMN_WIDTH)

	window.configColumn = CreateFrame("Frame", nil, content)
	window.configColumn:SetPoint("TOPLEFT", window.actionColumn, "TOPRIGHT", COLUMN_GAP, 0)
	window.configColumn:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", 0, 0)

	window.partyTitle = window.partyColumn:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	window.partyTitle:SetPoint("TOPLEFT", window.partyColumn, "TOPLEFT", 0, 0)
	window.partyTitle:SetPoint("RIGHT", window.partyColumn, "RIGHT", 0, 0)
	window.partyTitle:SetJustifyH("LEFT")
	window.partyTitle:SetText("Party Members")

	window.selectedText = window.partyColumn:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	window.selectedText:SetPoint("TOPLEFT", window.partyTitle, "BOTTOMLEFT", 0, -6)
	window.selectedText:SetPoint("RIGHT", window.partyColumn, "RIGHT", 0, 0)
	window.selectedText:SetJustifyH("LEFT")

	window.partyList = List.Create(window.partyColumn, {
		width = PARTY_LIST_WIDTH,
		visibleRows = PARTY_LIST_VISIBLE_ROWS,
		rowHeight = PARTY_LIST_ROW_HEIGHT,
		emptyText = "No party members.",
		columns = {
			{
				key = "name",
				width = 102,
			},
			{
				key = "state",
				width = 50,
				justifyH = "RIGHT",
			},
		},
	})
	window.partyList.frame:SetPoint("TOPLEFT", window.selectedText, "BOTTOMLEFT", 0, -8)

	window.actionTitle = window.actionColumn:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	window.actionTitle:SetPoint("TOPLEFT", window.actionColumn, "TOPLEFT", 0, 0)
	window.actionTitle:SetText("Prank List")

	window.scrollFrame = CreateFrame("ScrollFrame", nil, window.actionColumn, "UIPanelScrollFrameTemplate")
	window.scrollFrame:SetPoint("TOPLEFT", window.actionTitle, "BOTTOMLEFT", -4, -4)
	window.scrollFrame:SetPoint("BOTTOMRIGHT", window.actionColumn, "BOTTOMRIGHT", -24, 0)

	window.actionFrame = CreateFrame("Frame", nil, window.scrollFrame)
	window.actionFrame:SetSize(ACTION_COLUMN_WIDTH, ACTION_ROW_HEIGHT * #ACTIONS)
	window.scrollFrame:SetScrollChild(window.actionFrame)
	window.actionRows = {}

	window.configTitle = window.configColumn:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	window.configTitle:SetPoint("TOPLEFT", window.configColumn, "TOPLEFT", 0, 0)
	window.configTitle:SetPoint("RIGHT", window.configColumn, "RIGHT", 0, 0)
	window.configTitle:SetJustifyH("LEFT")
	window.configTitle:SetText("Configuration")

	window.durationInput = Form.CreateInput(window.configColumn, {
		label = "Duration",
		value = self.durationSeconds,
		numeric = true,
		width = 64,
	})
	window.durationInput:SetPoint("TOPLEFT", window.configTitle, "BOTTOMLEFT", 0, -8)

	window.percentInput = Form.CreateInput(window.configColumn, {
		label = "Percent",
		value = self.percent,
		numeric = true,
		width = 64,
	})
	window.percentInput:SetPoint("LEFT", window.durationInput, "RIGHT", 8, 0)

	window.messageInput = Form.CreateInput(window.configColumn, {
		label = "Message",
		value = self.customMessage,
		width = CONFIG_INPUT_WIDTH,
		maxLetters = MAX_MESSAGE_LENGTH,
	})
	window.messageInput:SetPoint("TOPLEFT", window.durationInput, "BOTTOMLEFT", 0, -2)

	window.soundSelectorLabel = window.configColumn:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	window.soundSelectorLabel:SetPoint("TOPLEFT", window.messageInput, "BOTTOMLEFT", 0, -1)
	window.soundSelectorLabel:SetText("Sound")

	window.soundSelectedText = window.configColumn:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	window.soundSelectedText:SetPoint("TOPLEFT", window.soundSelectorLabel, "BOTTOMLEFT", 0, -6)
	window.soundSelectedText:SetWidth(CONFIG_INPUT_WIDTH)
	window.soundSelectedText:SetJustifyH("LEFT")

	window.soundPreviousButton = Form.CreateButton(window.configColumn, {
		text = "<",
		width = 28,
		onClick = function()
			self:SelectPreviousSound()
		end,
	})
	window.soundPreviousButton:SetPoint("TOPLEFT", window.soundSelectedText, "BOTTOMLEFT", 0, -6)

	window.soundNextButton = Form.CreateButton(window.configColumn, {
		text = ">",
		width = 28,
		onClick = function()
			self:SelectNextSound()
		end,
	})
	window.soundNextButton:SetPoint("LEFT", window.soundPreviousButton, "RIGHT", 4, 0)

	window.soundTestButton = Form.CreateButton(window.configColumn, {
		text = "Test",
		width = 50,
		onClick = function()
			self:TestSelectedSound()
		end,
	})
	window.soundTestButton:SetPoint("LEFT", window.soundNextButton, "RIGHT", 6, 0)

	window.senderCheck = CreateFrame("CheckButton", nil, window.configColumn, "UICheckButtonTemplate")
	window.senderCheck:SetPoint("TOPLEFT", window.soundPreviousButton, "BOTTOMLEFT", 0, -8)
	window.senderCheck:SetChecked(self.includeSender ~= false)

	window.senderCheckLabel = window.configColumn:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	window.senderCheckLabel:SetPoint("LEFT", window.senderCheck, "RIGHT", 0, 0)
	window.senderCheckLabel:SetText("Show sender")

	window.soundCheck = CreateFrame("CheckButton", nil, window.configColumn, "UICheckButtonTemplate")
	window.soundCheck:SetPoint("LEFT", window.senderCheckLabel, "RIGHT", 18, 0)
	window.soundCheck:SetChecked(self.includeSound == true)

	window.soundCheckLabel = window.configColumn:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	window.soundCheckLabel:SetPoint("LEFT", window.soundCheck, "RIGHT", 0, 0)
	window.soundCheckLabel:SetText("Add sound")

	window.startButton = Form.CreateButton(window.footer, {
		text = "Send Selected",
		width = 112,
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

	window.selectAllButton = Form.CreateButton(window.footer, {
		text = "All Party",
		width = 76,
		onClick = function()
			self:SelectAllTargets()
		end,
	})
	window.selectAllButton:SetPoint("LEFT", window.clearButton, "RIGHT", 8, 0)

	window.clearTargetsButton = Form.CreateButton(window.footer, {
		text = "None",
		width = 58,
		onClick = function()
			self:ClearSelectedTargets()
		end,
	})
	window.clearTargetsButton:SetPoint("LEFT", window.selectAllButton, "RIGHT", 8, 0)

	window.refreshButton = Form.CreateButton(window.footer, {
		text = "Refresh",
		width = 88,
		onClick = function()
			self:RefreshWindow("Party list refreshed.")
		end,
	})
	window.refreshButton:SetPoint("LEFT", window.clearTargetsButton, "RIGHT", 8, 0)

	interferenceWindow = window
	self:RefreshActionRows()
	WEP:Log("Pranks", "window_created")
	return interferenceWindow
end

function PartyInterference:RefreshWindow(statusText)
	local window = interferenceWindow
	if not window or not window:IsShown() then
		return
	end

	self:ReadWindowSettings()

	local members = self:GetPartyMembers()
	local selectedTargets = self:GetSelectedTargets()
	local hasTarget = #selectedTargets > 0
	local activeCount = Interference.GetStatus().activeCount
	local actionConfig = self:GetSelectedAction()
	local usesPercent = actionConfig and actionConfig.usesPercent == true
	local canStart = hasTarget and self:IsSelectedActionVisible()
	local _, soundLabel, soundIndex, soundCount = self:GetSelectedSound()
	local soundText = soundLabel .. " (" .. soundIndex .. "/" .. soundCount .. ")"

	if #soundText > 28 then
		soundText = soundText:sub(1, 25) .. "..."
	end

	window.statusText:SetText(statusText or ("Party members: " .. #members .. "  Active effects on you: " .. activeCount))
	window.selectedText:SetText("Targets: " .. self:GetSelectedTargetLabel(selectedTargets))
	window.partyList:SetItems(self:GetPartyItems(members))
	self:RefreshActionRows()
	self:ApplyWindowFit()

	setInputValueIfNotFocused(window.durationInput, self.durationSeconds)
	setInputValueIfNotFocused(window.percentInput, self.percent)
	setInputValueIfNotFocused(window.messageInput, self.customMessage)

	if window.percentInput and window.percentInput.label then
		window.percentInput.label:SetText(self:GetPercentLabel())
	end

	if window.percentInput then
		if usesPercent then
			window.percentInput:Show()
			window.percentInput:SetEnabled(true)
		else
			window.percentInput:Hide()
		end
	end

	if window.senderCheck then
		window.senderCheck:SetChecked(self.includeSender ~= false)
	end

	if window.soundCheck then
		window.soundCheck:SetChecked(self.includeSound == true)
	end

	if window.soundSelectedText then
		window.soundSelectedText:SetText(soundText)
	end

	setButtonEnabled(window.startButton, canStart)
	setButtonEnabled(window.clearButton, hasTarget)
	setButtonEnabled(window.clearSelfButton, activeCount > 0)
	setButtonEnabled(window.selectAllButton, #members > 0)
	setButtonEnabled(window.clearTargetsButton, hasTarget)
	setButtonEnabled(window.refreshButton, true)
	setButtonEnabled(window.soundPreviousButton, soundCount > 1)
	setButtonEnabled(window.soundNextButton, soundCount > 1)
	setButtonEnabled(window.soundTestButton, Sound ~= nil and Sound.Play ~= nil)
end

function PartyInterference:ShowWindow()
	local window = self:EnsureWindow()
	if not window then
		return
	end

	window:Show()
	self:RefreshWindow()
	WEP:Log("Pranks", "window_shown")
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

	WEP:Print("Pranks:", #members, "party members,", status.activeCount, "active effects on you.")
end

function PartyInterference:OnDisabled()
	WEP:Log("Pranks", "disabled")

	if interferenceWindow then
		interferenceWindow:Hide()
	end

	for _, effect in ipairs(Interference.GetStatus().effects) do
		Interference.Clear(effect.id)
	end
end

function PartyInterference:HandleSlash(args)
	local action = args[2]

	if action == "clearself" or action == "clearme" or action == "clear-self" or action == "clear-me" then
		self:ClearSelf()
		return
	end

	if not self:IsEnabled() then
		WEP:Print("Pranks is disabled. Open /wep to enable it.")
		return
	end

	WEP:Log("Pranks", "slash", {
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

	WEP:Print("Usage: /wep pranks")
	WEP:Print("Usage: /wep pranks status")
	WEP:Print("Usage: /wep pranks clearself")
end

WEP:RegisterFeature(FEATURE_ID, Pranks)
WEP:RegisterModule("Pranks", Pranks)
