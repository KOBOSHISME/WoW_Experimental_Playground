local _, WEP = ...

local HideSeek = {
	hideSeconds = 30,
	seekSeconds = 300,
	players = {},
	playerOrder = {},
	pendingInvites = {},
	counter = 0,
}

WEP.HideSeek = HideSeek

local Timer = WEP.Tools.Timer
local Player = WEP.Tools.Player
local Requests = WEP.Tools.Requests
local Dialog = WEP.Tools.Dialog
local ScreenOverlay = WEP.Tools.ScreenOverlay
local UIVisibility = WEP.Tools.UIVisibility
local Sound = WEP.Tools.Sound

local REQUEST_INVITE = "hide_seek_invite"
local MSG_STATE = "hide_seek_state"
local MSG_START = "hide_seek_start"
local MSG_FOUND = "hide_seek_found"
local MSG_END = "hide_seek_end"
local MSG_LEAVE = "hide_seek_leave"

local STATUS_IDLE = "idle"
local STATUS_LOBBY = "lobby"
local STATUS_HIDING = "hiding"
local STATUS_SEEKING = "seeking"
local STATUS_ENDED = "ended"

local MIN_HIDE_SECONDS = 5
local MAX_HIDE_SECONDS = 300
local MIN_SEEK_SECONDS = 30
local MAX_SEEK_SECONDS = 3600

local SEEKER_UI_GROUPS = {
	"minimap",
	"map",
	"unitframes",
	"actionbars",
}

local promptFrame
local countdownFrame

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

local function isSelfName(name)
	return namesMatch(name, Player.GetShortName()) or namesMatch(name, Player.GetFullName())
end

local function setSolidColor(texture, red, green, blue, alpha)
	if texture.SetColorTexture then
		texture:SetColorTexture(red, green, blue, alpha)
	else
		texture:SetTexture(red, green, blue, alpha)
	end
end

local function getStatusLabel(status)
	if status == STATUS_LOBBY then
		return "Lobby"
	end

	if status == STATUS_HIDING then
		return "Hiding"
	end

	if status == STATUS_SEEKING then
		return "Seeking"
	end

	if status == STATUS_ENDED then
		return "Ended"
	end

	return "Idle"
end

local function formatDuration(seconds)
	seconds = tonumber(seconds) or 0

	if seconds >= 60 then
		local minutes = math.floor(seconds / 60)
		local rest = seconds - (minutes * 60)

		if rest > 0 then
			return minutes .. "m " .. rest .. "s"
		end

		return minutes .. "m"
	end

	return seconds .. "s"
end

local function splitCsv(text)
	local values = {}

	for value in tostring(text or ""):gmatch("[^,]+") do
		value = trim(value)

		if value ~= "" then
			values[#values + 1] = value
		end
	end

	return values
end

local function joinCsv(values)
	return table.concat(values, ",")
end

local function playSound(name)
	if Sound and Sound.Play then
		Sound.Play(name, { duration = 1 })
	end
end

local function safeHideDialog()
	if Dialog and Dialog.GetStatus and Dialog.GetStatus().active then
		Dialog.Hide("hide_seek")
	end
end

local function ensurePromptFrame()
	if promptFrame then
		return promptFrame
	end

	if not CreateFrame or not UIParent then
		return nil
	end

	local template = BackdropTemplateMixin and "BackdropTemplate" or nil
	local frame = CreateFrame("Frame", "WEPHideSeekPromptFrame", UIParent, template)
	frame:SetPoint("CENTER")
	frame:SetFrameStrata("DIALOG")
	frame:SetFrameLevel(120)
	frame:SetWidth(360)
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
	frame.title:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -16)
	frame.title:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -42, -16)
	frame.title:SetJustifyH("LEFT")

	frame.closeButton = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
	frame.closeButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)
	frame.closeButton:SetScript("OnClick", function()
		HideSeek:HidePrompt()
	end)

	frame.message = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	frame.message:SetPoint("TOPLEFT", frame.title, "BOTTOMLEFT", 0, -14)
	frame.message:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -16, -52)
	frame.message:SetJustifyH("LEFT")
	frame.message:SetJustifyV("TOP")

	if frame.message.SetWordWrap then
		frame.message:SetWordWrap(true)
	end

	frame.labels = {}
	frame.edits = {}

	for index = 1, 2 do
		local label = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
		label:SetJustifyH("LEFT")
		frame.labels[index] = label

		local edit = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
		edit:SetHeight(24)
		edit:SetAutoFocus(false)
		edit:SetScript("OnEnterPressed", function()
			HideSeek:SubmitPrompt()
		end)
		edit:SetScript("OnEscapePressed", function()
			HideSeek:HidePrompt()
		end)
		frame.edits[index] = edit
	end

	frame.okButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	frame.okButton:SetSize(96, 24)
	frame.okButton:SetText("Okay")
	frame.okButton:SetScript("OnClick", function()
		HideSeek:SubmitPrompt()
	end)

	frame.cancelButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	frame.cancelButton:SetSize(96, 24)
	frame.cancelButton:SetText("Cancel")
	frame.cancelButton:SetScript("OnClick", function()
		HideSeek:HidePrompt()
	end)

	if UISpecialFrames then
		UISpecialFrames[#UISpecialFrames + 1] = "WEPHideSeekPromptFrame"
	end

	promptFrame = frame
	return promptFrame
end

local function ensureCountdownFrame()
	if countdownFrame then
		return countdownFrame
	end

	if not CreateFrame or not UIParent then
		return nil
	end

	local frame = CreateFrame("Frame", "WEPHideSeekCountdownFrame", UIParent)
	frame:SetAllPoints(UIParent)
	frame:SetFrameStrata("FULLSCREEN_DIALOG")
	frame:SetFrameLevel(80)
	frame:EnableMouse(false)
	frame:Hide()

	frame.text = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
	frame.text:SetPoint("CENTER", frame, "CENTER", 0, 0)
	frame.text:SetJustifyH("CENTER")
	frame.text:SetJustifyV("MIDDLE")

	countdownFrame = frame
	return countdownFrame
end

function HideSeek:Initialize()
	if self.initialized then
		return
	end

	self.initialized = true
	self.status = STATUS_IDLE

	if math.randomseed then
		local seed = Timer.Now()

		if GetTime then
			seed = math.floor(GetTime() * 1000)
		end

		math.randomseed(seed + string.len(Player.GetFullName()))
	end

	Requests.RegisterRequestHandler(REQUEST_INVITE, function(request)
		self:OnInviteRequest(request)
	end)

	Requests.RegisterResponseHandler(REQUEST_INVITE, function(response)
		self:OnInviteResponse(response)
	end)

	WEP.Comm:RegisterHandler(MSG_STATE, function(message)
		self:OnStateMessage(message)
	end)

	WEP.Comm:RegisterHandler(MSG_START, function(message)
		self:OnStartMessage(message)
	end)

	WEP.Comm:RegisterHandler(MSG_FOUND, function(message)
		self:OnFoundMessage(message)
	end)

	WEP.Comm:RegisterHandler(MSG_END, function(message)
		self:OnEndMessage(message)
	end)

	WEP.Comm:RegisterHandler(MSG_LEAVE, function(message)
		self:OnLeaveMessage(message)
	end)

	self.frame = CreateFrame("Frame")
	self.frame:RegisterEvent("PLAYER_TARGET_CHANGED")
	self.frame:SetScript("OnEvent", function(_, event)
		if event == "PLAYER_TARGET_CHANGED" then
			self:OnTargetChanged()
		end
	end)
end

function HideSeek:MakeGameId()
	self.counter = self.counter + 1
	return "hs" .. Timer.Now() .. "." .. self.counter
end

function HideSeek:ResetRoster()
	self.players = {}
	self.playerOrder = {}
end

function HideSeek:CreateLobby()
	self.gameId = self:MakeGameId()
	self.host = Player.GetFullName()
	self.status = STATUS_LOBBY
	self.seeker = nil
	self.seekEndsAt = nil
	self:ResetRoster()
	self:AddPlayer(Player.GetFullName(), false)
	return self.gameId
end

function HideSeek:EnsureHostLobby()
	if not self.gameId or self.status == STATUS_IDLE or self.status == STATUS_ENDED then
		self:CreateLobby()
	end

	if not self:IsHost() then
		WEP:Print("Only the Hide and Seek host can change this game.")
		return false
	end

	if self.status ~= STATUS_LOBBY and self.status ~= STATUS_ENDED then
		WEP:Print("Hide and Seek is already in progress.")
		return false
	end

	if self.status == STATUS_ENDED then
		self.status = STATUS_LOBBY
		self.seeker = nil
		self:ClearFound()
	end

	return true
end

function HideSeek:IsHost()
	return self.host and isSelfName(self.host)
end

function HideSeek:IsSeeker()
	return self.seeker and isSelfName(self.seeker)
end

function HideSeek:IsParticipant()
	for _, key in ipairs(self.playerOrder) do
		local player = self.players[key]

		if player and isSelfName(player.name) then
			return true
		end
	end

	return false
end

function HideSeek:AddPlayer(name, found)
	if isBlank(name) then
		return nil
	end

	local key = nameKey(name)
	if key == "" then
		return nil
	end

	local player = self.players[key]

	if not player then
		player = {
			name = name,
			found = found == true,
		}
		self.players[key] = player
		self.playerOrder[#self.playerOrder + 1] = key
	else
		player.name = name
		player.found = player.found or found == true
	end

	return player
end

function HideSeek:RemovePlayer(name)
	local key = nameKey(name)
	if key == "" or not self.players[key] then
		return false
	end

	self.players[key] = nil

	for index, orderKey in ipairs(self.playerOrder) do
		if orderKey == key then
			table.remove(self.playerOrder, index)
			break
		end
	end

	return true
end

function HideSeek:ClearFound()
	for _, player in pairs(self.players) do
		player.found = false
	end
end

function HideSeek:GetPlayer(name)
	return self.players[nameKey(name)]
end

function HideSeek:GetPlayerCount()
	local count = 0

	for _, key in ipairs(self.playerOrder) do
		if self.players[key] then
			count = count + 1
		end
	end

	return count
end

function HideSeek:GetHiderCount()
	local count = 0

	for _, key in ipairs(self.playerOrder) do
		local player = self.players[key]

		if player and not namesMatch(player.name, self.seeker) then
			count = count + 1
		end
	end

	return count
end

function HideSeek:GetFoundCount()
	local count = 0

	for _, key in ipairs(self.playerOrder) do
		local player = self.players[key]

		if player and player.found and not namesMatch(player.name, self.seeker) then
			count = count + 1
		end
	end

	return count
end

function HideSeek:AllHidersFound()
	local hiderCount = 0

	for _, key in ipairs(self.playerOrder) do
		local player = self.players[key]

		if player and not namesMatch(player.name, self.seeker) then
			hiderCount = hiderCount + 1

			if not player.found then
				return false
			end
		end
	end

	return hiderCount > 0
end

function HideSeek:SerializePlayers()
	local values = {}

	for _, key in ipairs(self.playerOrder) do
		local player = self.players[key]

		if player then
			values[#values + 1] = player.name
		end
	end

	return joinCsv(values)
end

function HideSeek:SerializeFound()
	local values = {}

	for _, key in ipairs(self.playerOrder) do
		local player = self.players[key]

		if player and player.found then
			values[#values + 1] = player.name
		end
	end

	return joinCsv(values)
end

function HideSeek:ApplyRoster(playersText, foundText)
	local foundByKey = {}

	for _, name in ipairs(splitCsv(foundText)) do
		foundByKey[nameKey(name)] = true
	end

	self:ResetRoster()

	for _, name in ipairs(splitCsv(playersText)) do
		self:AddPlayer(name, foundByKey[nameKey(name)] == true)
	end
end

function HideSeek:SelfInRosterText(playersText)
	for _, name in ipairs(splitCsv(playersText)) do
		if isSelfName(name) then
			return true
		end
	end

	return false
end

function HideSeek:GetRosterText()
	local values = {}

	for _, key in ipairs(self.playerOrder) do
		local player = self.players[key]

		if player then
			local suffix = ""

			if self.seeker and namesMatch(player.name, self.seeker) then
				suffix = " (seeker)"
			elseif player.found then
				suffix = " (found)"
			end

			values[#values + 1] = player.name .. suffix
		end
	end

	if #values == 0 then
		return "none"
	end

	return table.concat(values, ", ")
end

function HideSeek:GetSummary()
	local lines = {
		"Status: " .. getStatusLabel(self.status),
		"Host: " .. (self.host or "none"),
		"Players: " .. self:GetPlayerCount(),
		"Hide: " .. formatDuration(self.hideSeconds) .. ", Seek: " .. formatDuration(self.seekSeconds),
	}

	if self.seeker then
		lines[#lines + 1] = "Seeker: " .. self.seeker
	end

	lines[#lines + 1] = "Roster: " .. self:GetRosterText()

	if self.status == STATUS_SEEKING then
		lines[#lines + 1] = "Found: " .. self:GetFoundCount() .. "/" .. self:GetHiderCount()
	end

	return table.concat(lines, "\n")
end

function HideSeek:ShowMenu()
	local options = {}

	options[#options + 1] = {
		text = "Invite Player",
		value = "invite",
	}
	options[#options + 1] = {
		text = "Game Settings",
		value = "settings",
	}
	options[#options + 1] = {
		text = "Start Game",
		value = "start",
	}
	options[#options + 1] = {
		text = "Print Status",
		value = "status",
	}

	if self.gameId then
		options[#options + 1] = {
			text = "Leave Game",
			value = "leave",
		}
	end

	options[#options + 1] = {
		text = "Close",
		value = "close",
	}

	Dialog.Show({
		title = "Hide and Seek",
		message = self:GetSummary(),
		options = options,
		onSelect = function(result)
			if result.canceled or result.value == "close" then
				return
			end

			self:HandleMenuAction(result.value)
		end,
	})
end

function HideSeek:HandleMenuAction(action)
	if action == "invite" then
		self:ShowInvitePrompt()
		return
	end

	if action == "settings" then
		self:ShowSettingsPrompt()
		return
	end

	if action == "start" then
		self:StartGame()
		return
	end

	if action == "status" then
		self:PrintStatus()
		self:ShowMenu()
		return
	end

	if action == "leave" then
		self:LeaveGame()
		return
	end
end

function HideSeek:ShowPrompt(config)
	local frame = ensurePromptFrame()
	if not frame then
		WEP:Print("Hide and Seek prompt is unavailable.")
		return false
	end

	safeHideDialog()

	local fields = config.fields or {}
	frame.request = config
	frame.title:SetText(config.title or "Hide and Seek")
	frame.message:SetText(config.message or "")

	local y = 84
	local contentWidth = 328

	for index = 1, 2 do
		local field = fields[index]
		local label = frame.labels[index]
		local edit = frame.edits[index]

		if field then
			label:SetText(field.label or "")
			label:ClearAllPoints()
			label:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -y)
			label:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -16, -y)
			label:Show()

			edit:ClearAllPoints()
			edit:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 4, -6)
			edit:SetWidth(contentWidth - 8)
			edit:SetText(tostring(field.value or ""))
			edit:Show()

			y = y + 54
		else
			label:Hide()
			edit:Hide()
		end
	end

	frame.okButton:ClearAllPoints()
	frame.okButton:SetPoint("TOPRIGHT", frame, "TOP", -4, -(y + 12))
	frame.cancelButton:ClearAllPoints()
	frame.cancelButton:SetPoint("LEFT", frame.okButton, "RIGHT", 8, 0)
	frame:SetHeight(y + 52)
	frame:Show()

	if frame.edits[1] and fields[1] then
		frame.edits[1]:SetFocus()
		frame.edits[1]:HighlightText()
	end

	return true
end

function HideSeek:SubmitPrompt()
	local frame = promptFrame
	local request = frame and frame.request

	if not request then
		return false
	end

	local values = {}

	for index, field in ipairs(request.fields or {}) do
		values[field.key or index] = trim(frame.edits[index]:GetText())
	end

	self:HidePrompt()

	if type(request.onSubmit) == "function" then
		request.onSubmit(values)
	end

	return true
end

function HideSeek:HidePrompt()
	if promptFrame then
		promptFrame.request = nil
		promptFrame:Hide()
	end
end

function HideSeek:ShowInvitePrompt()
	if not self:EnsureHostLobby() then
		return
	end

	self:ShowPrompt({
		title = "Invite Hide and Seek Player",
		message = "Enter the player name to invite.",
		fields = {
			{
				key = "name",
				label = "Player name",
				value = "",
			},
		},
		onSubmit = function(values)
			self:InvitePlayer(values.name)
		end,
	})
end

function HideSeek:ShowSettingsPrompt()
	if not self:EnsureHostLobby() then
		return
	end

	self:ShowPrompt({
		title = "Hide and Seek Settings",
		message = "Set the hiding countdown and seeking time in seconds.",
		fields = {
			{
				key = "hide",
				label = "Hiding countdown seconds",
				value = self.hideSeconds,
			},
			{
				key = "seek",
				label = "Seeking time seconds",
				value = self.seekSeconds,
			},
		},
		onSubmit = function(values)
			self.hideSeconds = clamp(values.hide, MIN_HIDE_SECONDS, MAX_HIDE_SECONDS, self.hideSeconds)
			self.seekSeconds = clamp(values.seek, MIN_SEEK_SECONDS, MAX_SEEK_SECONDS, self.seekSeconds)
			WEP:Print("Hide and Seek settings:", "hide", formatDuration(self.hideSeconds), "seek", formatDuration(self.seekSeconds))
			self:BroadcastState()
			self:ShowMenu()
		end,
	})
end

function HideSeek:InvitePlayer(target)
	target = trim(target)

	if target == "" then
		WEP:Print("Hide and Seek invite needs a player name.")
		self:ShowInvitePrompt()
		return
	end

	if not self:EnsureHostLobby() then
		return
	end

	if isSelfName(target) then
		WEP:Print("You are already in the Hide and Seek lobby.")
		return
	end

	local ok, requestIdOrErr = Requests.Send(target, REQUEST_INVITE, {
		g = self.gameId,
		h = self.host,
		hs = self.hideSeconds,
		ss = self.seekSeconds,
	})

	if not ok then
		WEP:Print("Hide and Seek invite failed:", requestIdOrErr)
		return
	end

	self.pendingInvites[requestIdOrErr] = target
	WEP:Print("Hide and Seek invite sent to", target .. ".")
	self:BroadcastState()
end

function HideSeek:OnInviteRequest(request)
	local data = request.data or {}
	local host = data.h or request.sender
	local hideSeconds = clamp(data.hs, MIN_HIDE_SECONDS, MAX_HIDE_SECONDS, self.hideSeconds)
	local seekSeconds = clamp(data.ss, MIN_SEEK_SECONDS, MAX_SEEK_SECONDS, self.seekSeconds)
	local message = host
		.. " invited you to Hide and Seek.\nHide: "
		.. formatDuration(hideSeconds)
		.. ", Seek: "
		.. formatDuration(seekSeconds)

	Dialog.Show({
		title = "Hide and Seek Challenge",
		message = message,
		options = {
			{
				text = "Accept",
				value = "accepted",
			},
			{
				text = "Decline",
				value = "declined",
			},
		},
		onSelect = function(result)
			local status = result.value == "accepted" and "accepted" or "declined"

			local ok, responseErr = Requests.Respond(request.id, request.sender, status, {
				g = data.g or "",
				p = Player.GetFullName(),
			})

			if not ok then
				WEP:Print("Hide and Seek response failed:", responseErr)
				return
			end

			if status == "accepted" then
				self.gameId = data.g
				self.host = host
				self.hideSeconds = hideSeconds
				self.seekSeconds = seekSeconds
				self.status = STATUS_LOBBY
				self.seeker = nil
				self:ResetRoster()
				self:AddPlayer(host, false)
				self:AddPlayer(Player.GetFullName(), false)
				WEP:Print("Joined Hide and Seek lobby hosted by", host .. ".")
			else
				WEP:Print("Declined Hide and Seek invite from", host .. ".")
			end
		end,
	})

	playSound("wep_alert")
end

function HideSeek:OnInviteResponse(response)
	local request = response.request
	local requestData = request and request.data or {}

	if requestData.g ~= self.gameId then
		return
	end

	if response.status == "accepted" then
		local playerName = response.data and response.data.p or response.sender
		self:AddPlayer(playerName, false)
		WEP:Print(playerName, "joined Hide and Seek.")
		self:BroadcastState()
		return
	end

	if response.status == "declined" then
		WEP:Print(response.sender, "declined Hide and Seek.")
	end
end

function HideSeek:Broadcast(messageType, payload)
	local ok, messageIdOrErr = WEP.Comm:Send(messageType, payload, {
		transport = "CHANNEL",
	})

	if not ok then
		WEP:Print("Hide and Seek message failed:", messageIdOrErr)
	end

	return ok, messageIdOrErr
end

function HideSeek:BroadcastState()
	if not self.gameId then
		return false
	end

	return self:Broadcast(MSG_STATE, {
		g = self.gameId,
		h = self.host or "",
		st = self.status or STATUS_IDLE,
		p = self:SerializePlayers(),
		f = self:SerializeFound(),
		sk = self.seeker or "",
		hs = self.hideSeconds,
		ss = self.seekSeconds,
	})
end

function HideSeek:OnStateMessage(message)
	local payload = message.payload or {}

	if isBlank(payload.g) then
		return
	end

	local isKnownGame = self.gameId and payload.g == self.gameId
	if not isKnownGame and not self:SelfInRosterText(payload.p) then
		return
	end

	self.gameId = payload.g
	self.host = payload.h or message.sender
	self.status = payload.st or STATUS_LOBBY
	self.seeker = not isBlank(payload.sk) and payload.sk or nil
	self.hideSeconds = clamp(payload.hs, MIN_HIDE_SECONDS, MAX_HIDE_SECONDS, self.hideSeconds)
	self.seekSeconds = clamp(payload.ss, MIN_SEEK_SECONDS, MAX_SEEK_SECONDS, self.seekSeconds)
	self:ApplyRoster(payload.p, payload.f)
end

function HideSeek:PickRandomSeeker()
	local count = self:GetPlayerCount()

	if count == 0 then
		return nil
	end

	local index = math.random(count)
	local seen = 0

	for _, key in ipairs(self.playerOrder) do
		local player = self.players[key]

		if player then
			seen = seen + 1

			if seen == index then
				return player.name
			end
		end
	end

	return nil
end

function HideSeek:StartGame()
	if not self:EnsureHostLobby() then
		return
	end

	if self:GetPlayerCount() < 2 then
		WEP:Print("Hide and Seek needs at least 2 players.")
		self:ShowMenu()
		return
	end

	local seeker = self:PickRandomSeeker()
	if not seeker then
		WEP:Print("Could not choose a seeker.")
		return
	end

	self.seeker = seeker
	self:ClearFound()
	self:BeginHiding(self.hideSeconds, self.seekSeconds, Timer.Now())
	self:BroadcastState()
	self:Broadcast(MSG_START, {
		g = self.gameId,
		sk = seeker,
		hs = self.hideSeconds,
		ss = self.seekSeconds,
		t = Timer.Now(),
	})
end

function HideSeek:OnStartMessage(message)
	local payload = message.payload or {}

	if payload.g ~= self.gameId then
		return
	end

	self.seeker = payload.sk
	self.hideSeconds = clamp(payload.hs, MIN_HIDE_SECONDS, MAX_HIDE_SECONDS, self.hideSeconds)
	self.seekSeconds = clamp(payload.ss, MIN_SEEK_SECONDS, MAX_SEEK_SECONDS, self.seekSeconds)
	self:ClearFound()
	self:BeginHiding(self.hideSeconds, self.seekSeconds, tonumber(payload.t) or Timer.Now())
end

function HideSeek:BeginHiding(hideSeconds, seekSeconds, startedAt)
	self.status = STATUS_HIDING
	self.seekSeconds = seekSeconds
	self.seekEndsAt = nil
	self.timerToken = (self.timerToken or 0) + 1
	local token = self.timerToken
	local remaining = ((tonumber(startedAt) or Timer.Now()) + hideSeconds) - Timer.Now()

	if remaining < 0 then
		remaining = 0
	end

	if self:IsSeeker() then
		ScreenOverlay.SetBlackoutPercentage(100)
		self:ShowCountdown(hideSeconds, startedAt, function()
			self:BeginSeeking()
		end)
		WEP:Print("You are the seeker. Wait for the countdown.")
	else
		WEP:Print("Hide and Seek started. Hide now. Seeker:", self.seeker or "unknown")
		Timer.After(remaining, function()
			if self.timerToken == token and self.status == STATUS_HIDING then
				self:BeginSeeking()
			end
		end)
	end
end

function HideSeek:BeginSeeking()
	if self.status ~= STATUS_HIDING and self.status ~= STATUS_SEEKING then
		return
	end

	self.status = STATUS_SEEKING
	self.seekEndsAt = Timer.Now() + self.seekSeconds
	self.timerToken = (self.timerToken or 0) + 1
	local token = self.timerToken

	self:HideCountdown()

	if self:IsSeeker() then
		ScreenOverlay.HideBlackout()
		self:HideSeekerUI()
		WEP:Print("Find the hiders. Target them to mark them found.")
	else
		WEP:Print("The seeker is hunting.")
	end

	Timer.After(self.seekSeconds, function()
		if self.timerToken == token and self.status == STATUS_SEEKING and self:IsSeeker() then
			self:FinishGame("time", true)
		end
	end)
end

function HideSeek:ShowCountdown(seconds, startedAt, onComplete)
	local frame = ensureCountdownFrame()
	if not frame then
		return false
	end

	self.countdownToken = (self.countdownToken or 0) + 1
	local token = self.countdownToken
	local endsAt = (tonumber(startedAt) or Timer.Now()) + seconds

	local function update()
		if self.countdownToken ~= token then
			return
		end

		local remaining = endsAt - Timer.Now()

		if remaining <= 0 then
			self:HideCountdown()

			if type(onComplete) == "function" then
				onComplete()
			end

			return
		end

		frame.text:SetText("Hide and Seek\n" .. remaining)
		frame:Show()
		Timer.After(1, update)
	end

	update()
	return true
end

function HideSeek:HideCountdown()
	self.countdownToken = (self.countdownToken or 0) + 1

	if countdownFrame then
		countdownFrame:Hide()
	end
end

function HideSeek:HideSeekerUI()
	self.seekerUiHidden = true

	for _, groupName in ipairs(SEEKER_UI_GROUPS) do
		UIVisibility.Hide(groupName)
	end
end

function HideSeek:RestoreSeekerUI()
	if not self.seekerUiHidden then
		return
	end

	self.seekerUiHidden = false

	for _, groupName in ipairs(SEEKER_UI_GROUPS) do
		UIVisibility.Show(groupName)
	end
end

function HideSeek:GetTargetPlayerName()
	if not UnitExists or not UnitExists("target") then
		return nil
	end

	if UnitIsPlayer and not UnitIsPlayer("target") then
		return nil
	end

	local name, realm = UnitName("target")
	if isBlank(name) then
		return nil
	end

	if realm and realm ~= "" then
		return name .. "-" .. realm
	end

	return name
end

function HideSeek:OnTargetChanged()
	if self.status ~= STATUS_SEEKING or not self:IsSeeker() then
		return
	end

	local targetName = self:GetTargetPlayerName()
	if not targetName then
		return
	end

	local player = self:GetPlayer(targetName)
	if not player or player.found or namesMatch(player.name, self.seeker) then
		return
	end

	self:MarkFound(player.name, Player.GetFullName(), true)
end

function HideSeek:MarkFound(playerName, foundBy, broadcast)
	local player = self:GetPlayer(playerName)
	if not player or player.found then
		return false
	end

	player.found = true
	WEP:Print(player.name, "was found by", foundBy or self.seeker or "the seeker")
	playSound("ui_select")

	if broadcast then
		self:Broadcast(MSG_FOUND, {
			g = self.gameId,
			p = player.name,
			by = foundBy or Player.GetFullName(),
		})
	end

	if self:IsSeeker() and self:AllHidersFound() then
		self:FinishGame("found", true)
	end

	return true
end

function HideSeek:OnFoundMessage(message)
	local payload = message.payload or {}

	if payload.g ~= self.gameId then
		return
	end

	self:MarkFound(payload.p, payload.by or message.sender, false)

	if payload.p and isSelfName(payload.p) then
		WEP:Print("You were found.")
	end
end

function HideSeek:FinishGame(reason, broadcast)
	if not self.gameId then
		return
	end

	self.status = STATUS_ENDED
	self.timerToken = (self.timerToken or 0) + 1
	self:HideCountdown()
	ScreenOverlay.HideBlackout()
	self:RestoreSeekerUI()

	if reason == "found" then
		WEP:Print("Hide and Seek ended: seeker wins.")
	elseif reason == "time" then
		WEP:Print("Hide and Seek ended: hiders win.")
	else
		WEP:Print("Hide and Seek ended.")
	end

	if broadcast then
		self:Broadcast(MSG_END, {
			g = self.gameId,
			r = reason or "ended",
		})
	end
end

function HideSeek:OnEndMessage(message)
	local payload = message.payload or {}

	if payload.g ~= self.gameId then
		return
	end

	self:FinishGame(payload.r or "ended", false)
end

function HideSeek:LeaveGame()
	if not self.gameId then
		WEP:Print("You are not in a Hide and Seek game.")
		return
	end

	local wasHost = self:IsHost()
	local wasActive = self.status == STATUS_HIDING or self.status == STATUS_SEEKING
	local gameId = self.gameId

	if wasHost or wasActive then
		self:Broadcast(MSG_END, {
			g = gameId,
			r = "canceled",
		})
	else
		self:Broadcast(MSG_LEAVE, {
			g = gameId,
			p = Player.GetFullName(),
		})
	end

	self:ResetGame()
	WEP:Print("Left Hide and Seek.")
end

function HideSeek:OnLeaveMessage(message)
	local payload = message.payload or {}

	if payload.g ~= self.gameId or not self:IsHost() then
		return
	end

	if self.status == STATUS_LOBBY or self.status == STATUS_ENDED then
		if self:RemovePlayer(payload.p or message.sender) then
			WEP:Print(payload.p or message.sender, "left Hide and Seek.")
			self:BroadcastState()
		end
		return
	end

	self:FinishGame("canceled", true)
end

function HideSeek:ResetGame()
	self:HideCountdown()
	ScreenOverlay.HideBlackout()
	self:RestoreSeekerUI()
	self.status = STATUS_IDLE
	self.gameId = nil
	self.host = nil
	self.seeker = nil
	self.seekEndsAt = nil
	self.timerToken = (self.timerToken or 0) + 1
	self:ResetRoster()
end

function HideSeek:PrintStatus()
	WEP:Print("Hide and Seek:", getStatusLabel(self.status))
	WEP:Print("Host:", self.host or "none", "Players:", self:GetPlayerCount(), "Seeker:", self.seeker or "none")
	WEP:Print("Timers:", "hide", formatDuration(self.hideSeconds), "seek", formatDuration(self.seekSeconds))
	WEP:Print("Roster:", self:GetRosterText())
end

function HideSeek:HandleSlash(args)
	local action = args[2]

	if not action or action == "menu" then
		self:ShowMenu()
		return
	end

	if action == "status" then
		self:PrintStatus()
		return
	end

	if action == "leave" then
		self:LeaveGame()
		return
	end

	if action == "start" then
		self:StartGame()
		return
	end

	if action == "invite" then
		self:ShowInvitePrompt()
		return
	end

	if action == "settings" then
		self:ShowSettingsPrompt()
		return
	end

	WEP:Print("Usage: /wep hide")
	WEP:Print("Usage: /wep hide status|invite|settings|start|leave")
end

WEP:RegisterModule("HideSeek", HideSeek)
