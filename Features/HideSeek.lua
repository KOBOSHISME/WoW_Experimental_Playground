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

local FEATURE_ID = "hideSeek"

HideSeek.title = "Hide and Seek"
HideSeek.description = "Addon-managed challenge lobby and seeker UI."

local Timer = WEP.Tools.Timer
local Player = WEP.Tools.Player
local Requests = WEP.Tools.Requests
local Dialog = WEP.Tools.Dialog
local ScreenOverlay = WEP.Tools.ScreenOverlay
local UIVisibility = WEP.Tools.UIVisibility
local Sound = WEP.Tools.Sound
local WindowTool = WEP.Tools.Window
local Form = WEP.Tools.Form
local List = WEP.Tools.List

WEP:Log("HideSeek", "loaded")

local REQUEST_INVITE = "hide_seek_invite"
local MSG_STATE = "hide_seek_state"
local MSG_ROSTER = "hide_seek_roster"
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

local countdownFrame
local gameWindow
local trackerWindow

local TRACKER_MAX_NAMES = 4

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

local function messageSentBy(message, playerName)
	if isBlank(playerName) then
		return false
	end

	local sender = message and message.sender
	if isBlank(sender) then
		sender = message and message.claimedSender
	end

	return namesMatch(sender, playerName)
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

local function playSound(name)
	if Sound and Sound.Play then
		Sound.Play(name, { duration = 1 })
	end
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

function HideSeek:IsEnabled()
	return WEP:IsFeatureEnabled(FEATURE_ID)
end

function HideSeek:Initialize()
	if self.initialized then
		return
	end

	self.initialized = true
	self.status = STATUS_IDLE
	WEP:Log("HideSeek", "initialize")

	if math.randomseed then
		local seed = Timer.Now()

		if GetTime then
			seed = math.floor(GetTime() * 1000)
		end

		math.randomseed(seed + string.len(Player.GetFullName()))
	end

	Requests.RegisterRequestHandler(REQUEST_INVITE, function(request)
		if not self:IsEnabled() then
			return
		end

		self:OnInviteRequest(request)
	end)

	Requests.RegisterResponseHandler(REQUEST_INVITE, function(response)
		if not self:IsEnabled() then
			return
		end

		self:OnInviteResponse(response)
	end)

	WEP.Comm:RegisterHandler(MSG_STATE, function(message)
		if not self:IsEnabled() then
			return
		end

		self:OnStateMessage(message)
	end)

	WEP.Comm:RegisterHandler(MSG_ROSTER, function(message)
		if not self:IsEnabled() then
			return
		end

		self:OnRosterMessage(message)
	end)

	WEP.Comm:RegisterHandler(MSG_START, function(message)
		if not self:IsEnabled() then
			return
		end

		self:OnStartMessage(message)
	end)

	WEP.Comm:RegisterHandler(MSG_FOUND, function(message)
		if not self:IsEnabled() then
			return
		end

		self:OnFoundMessage(message)
	end)

	WEP.Comm:RegisterHandler(MSG_END, function(message)
		if not self:IsEnabled() then
			return
		end

		self:OnEndMessage(message)
	end)

	WEP.Comm:RegisterHandler(MSG_LEAVE, function(message)
		if not self:IsEnabled() then
			return
		end

		self:OnLeaveMessage(message)
	end)

	self.frame = CreateFrame("Frame")
	self.frame:RegisterEvent("PLAYER_TARGET_CHANGED")
	self.frame:SetScript("OnEvent", function(_, event)
		if event == "PLAYER_TARGET_CHANGED" and self:IsEnabled() then
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
	self.hideEndsAt = nil
	self.resultReason = nil
	self:ResetRoster()
	self:AddPlayer(Player.GetFullName(), false)
	self:RefreshWindow()
	WEP:Log("HideSeek", "lobby_created", {
		gameId = self.gameId,
		host = self.host,
	})
	return self.gameId
end

function HideSeek:EnsureHostLobby()
	if not self.gameId or self.status == STATUS_IDLE or self.status == STATUS_ENDED then
		self:CreateLobby()
	end

	if not self:IsHost() then
		WEP:Log("HideSeek", "host_control_denied", {
			gameId = self.gameId or "none",
			host = self.host or "none",
		}, "warn")
		WEP:Print("Only the Hide and Seek host can change this game.")
		return false
	end

	if self.status ~= STATUS_LOBBY and self.status ~= STATUS_ENDED then
		WEP:Log("HideSeek", "host_control_busy", {
			gameId = self.gameId or "none",
			status = self.status or "none",
		}, "warn")
		WEP:Print("Hide and Seek is already in progress.")
		return false
	end

	if self.status == STATUS_ENDED then
		self.status = STATUS_LOBBY
		self.seeker = nil
		self:ClearFound()
		WEP:Log("HideSeek", "ended_game_reopened", {
			gameId = self.gameId,
		})
	end

	return true
end

function HideSeek:IsHost()
	return self.host and isSelfName(self.host)
end

function HideSeek:IsMessageFromHost(message, hostName)
	return messageSentBy(message, hostName or self.host)
end

function HideSeek:IsSeeker()
	return self.seeker and isSelfName(self.seeker)
end

function HideSeek:IsMessageFromSeeker(message)
	return messageSentBy(message, self.seeker)
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

function HideSeek:IsBusy()
	return self.gameId ~= nil and self.status ~= STATUS_IDLE and self.status ~= STATUS_ENDED
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
		WEP:Log("HideSeek", "player_added", {
			gameId = self.gameId or "none",
			player = name,
			found = found == true,
		})
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

	WEP:Log("HideSeek", "player_removed", {
		gameId = self.gameId or "none",
		player = name,
	})
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

function HideSeek:GetRemainingHideSeconds()
	if self.status ~= STATUS_HIDING or not self.hideEndsAt then
		return nil
	end

	local remaining = self.hideEndsAt - Timer.Now()
	if remaining < 0 then
		return 0
	end

	return remaining
end

function HideSeek:GetRemainingSeekSeconds()
	if self.status ~= STATUS_SEEKING or not self.seekEndsAt then
		return nil
	end

	local remaining = self.seekEndsAt - Timer.Now()
	if remaining < 0 then
		return 0
	end

	return remaining
end

function HideSeek:CanHostControl()
	if self.status ~= STATUS_IDLE and self.status ~= STATUS_LOBBY and self.status ~= STATUS_ENDED then
		return false
	end

	return not self.gameId or self:IsHost()
end

function HideSeek:GetPlayerRoleText(player)
	local parts = {}

	if self.seeker and namesMatch(player.name, self.seeker) then
		parts[#parts + 1] = "Seeker"
	elseif self.status == STATUS_LOBBY or self.status == STATUS_IDLE then
		parts[#parts + 1] = "Player"
	else
		parts[#parts + 1] = "Hider"
	end

	if self.host and namesMatch(player.name, self.host) then
		parts[#parts + 1] = "Host"
	end

	if isSelfName(player.name) then
		parts[#parts + 1] = "You"
	end

	return table.concat(parts, ", ")
end

function HideSeek:GetPlayerStateText(player)
	if self.status == STATUS_IDLE then
		return "Idle"
	end

	if self.status == STATUS_LOBBY then
		return "Waiting"
	end

	if self.seeker and namesMatch(player.name, self.seeker) then
		if self.status == STATUS_HIDING then
			return "Counting"
		end

		if self.status == STATUS_SEEKING then
			return "Seeking"
		end

		return "Seeker"
	end

	if player.found then
		return "Found"
	end

	if self.status == STATUS_HIDING then
		return "Hiding"
	end

	if self.status == STATUS_SEEKING then
		return "Hidden"
	end

	if self.status == STATUS_ENDED then
		return "Done"
	end

	return "Waiting"
end

function HideSeek:GetRosterItems()
	local items = {}

	for _, key in ipairs(self.playerOrder) do
		local player = self.players[key]

		if player then
			local color

			if self.seeker and namesMatch(player.name, self.seeker) then
				color = {
					r = 0.22,
					g = 0.10,
					b = 0.02,
					a = 0.28,
				}
			elseif player.found then
				color = {
					r = 0.12,
					g = 0.12,
					b = 0.12,
					a = 0.35,
				}
			elseif isSelfName(player.name) then
				color = {
					r = 0.02,
					g = 0.12,
					b = 0.20,
					a = 0.30,
				}
			end

			items[#items + 1] = {
				columns = {
					name = player.name,
					role = self:GetPlayerRoleText(player),
					state = self:GetPlayerStateText(player),
				},
				color = color,
			}
		end
	end

	return items
end

function HideSeek:GetGameDetailText()
	local details = {
		"Host " .. (self.host or "none"),
		"Players " .. self:GetPlayerCount(),
		"Hide " .. formatDuration(self.hideSeconds),
		"Seek " .. formatDuration(self.seekSeconds),
	}

	if self.seeker then
		details[#details + 1] = "Seeker " .. self.seeker
	end

	if self.status == STATUS_SEEKING then
		details[#details + 1] = "Found " .. self:GetFoundCount() .. "/" .. self:GetHiderCount()
	end

	return table.concat(details, "  |  ")
end

function HideSeek:GetTimerText()
	local hideRemaining = self:GetRemainingHideSeconds()
	if hideRemaining then
		return "Seeker released in " .. formatDuration(hideRemaining)
	end

	local seekRemaining = self:GetRemainingSeekSeconds()
	if seekRemaining then
		return "Time left " .. formatDuration(seekRemaining)
	end

	if self.status == STATUS_ENDED and self.resultReason then
		if self.resultReason == "found" then
			return "Result: seeker wins"
		end

		if self.resultReason == "time" then
			return "Result: hiders win"
		end

		return "Result: ended"
	end

	return "No active timer"
end

local function setInputEnabled(input, enabled)
	if input and input.SetEnabled then
		input:SetEnabled(enabled)
	end
end

local function setButtonEnabled(button, enabled)
	if button and button.SetButtonEnabled then
		button:SetButtonEnabled(enabled)
	elseif button then
		if enabled == false and button.Disable then
			button:Disable()
		elseif button.Enable then
			button:Enable()
		end
	end
end

local function setInputValueIfNotFocused(input, value)
	if not input then
		return
	end

	if input.editBox and input.editBox.HasFocus and input.editBox:HasFocus() then
		return
	end

	input:SetValue(value)
end

local function formatTrackerNames(names)
	if #names == 0 then
		return "none"
	end

	local values = {}
	local limit = math.min(#names, TRACKER_MAX_NAMES)

	for index = 1, limit do
		values[#values + 1] = names[index]
	end

	if #names > limit then
		values[#values + 1] = "+" .. (#names - limit)
	end

	return table.concat(values, ", ")
end

function HideSeek:GetTrackerNames()
	local playing = {}
	local hiders = {}
	local seeker
	local rolesAssigned = self.seeker and self.status ~= STATUS_LOBBY and self.status ~= STATUS_IDLE

	for _, key in ipairs(self.playerOrder) do
		local player = self.players[key]

		if player then
			local name = shortName(player.name)
			playing[#playing + 1] = name

			if self.seeker and namesMatch(player.name, self.seeker) then
				seeker = name
			elseif rolesAssigned and not player.found then
				hiders[#hiders + 1] = name
			end
		end
	end

	return playing, seeker, hiders
end

function HideSeek:EnsureTrackerWindow()
	if trackerWindow then
		return trackerWindow
	end

	if not WindowTool or not Form then
		WEP:Log("HideSeek", "tracker_window_unavailable", nil, "error")
		return nil
	end

	local window, err = WindowTool.Create({
		name = "WEPHideSeekTrackerWindow",
		title = "Hide and Seek",
		width = 280,
		height = 220,
		level = 85,
		onShow = function()
			self:RefreshTrackerWindow()
			self:ScheduleWindowRefresh()
		end,
	})

	if not window then
		WEP:Log("HideSeek", "tracker_window_failed", {
			error = err,
		}, "error")
		return nil
	end

	if window.frame.closeButton then
		window.frame.closeButton:Hide()
	end

	local content = window.content

	window.statusText = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	window.statusText:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
	window.statusText:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, 0)
	window.statusText:SetJustifyH("LEFT")

	window.timerText = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightLarge")
	window.timerText:SetPoint("TOPLEFT", window.statusText, "BOTTOMLEFT", 0, -8)
	window.timerText:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, 0)
	window.timerText:SetJustifyH("LEFT")

	window.playingText = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	window.playingText:SetPoint("TOPLEFT", window.timerText, "BOTTOMLEFT", 0, -10)
	window.playingText:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, 0)
	window.playingText:SetJustifyH("LEFT")

	window.seekerText = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	window.seekerText:SetPoint("TOPLEFT", window.playingText, "BOTTOMLEFT", 0, -6)
	window.seekerText:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, 0)
	window.seekerText:SetJustifyH("LEFT")

	window.hidingText = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	window.hidingText:SetPoint("TOPLEFT", window.seekerText, "BOTTOMLEFT", 0, -6)
	window.hidingText:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, 0)
	window.hidingText:SetJustifyH("LEFT")

	window.leaveButton = Form.CreateButton(window.footer, {
		text = "Leave",
		width = 72,
		height = 22,
		onClick = function()
			self:LeaveGame()
		end,
	})
	window.leaveButton:SetPoint("RIGHT", window.footer, "RIGHT", 0, 0)

	trackerWindow = window
	WEP:Log("HideSeek", "tracker_window_created")
	return trackerWindow
end

function HideSeek:RefreshTrackerWindow()
	if not self.gameId or self.status == STATUS_IDLE then
		if trackerWindow and trackerWindow:IsShown() then
			trackerWindow:Hide()
			WEP:Log("HideSeek", "tracker_window_hidden")
		end

		return
	end

	local window = self:EnsureTrackerWindow()
	if not window then
		return
	end

	local playing, seeker, hiders = self:GetTrackerNames()
	local hidingText = "Not started"

	if self.seeker and self.status ~= STATUS_LOBBY and self.status ~= STATUS_IDLE then
		hidingText = formatTrackerNames(hiders)
	end

	window.statusText:SetText(getStatusLabel(self.status))
	window.timerText:SetText(self:GetTimerText())
	window.playingText:SetText("Playing: " .. formatTrackerNames(playing))
	window.seekerText:SetText("Seeking: " .. (seeker or "Not chosen"))
	window.hidingText:SetText("Hiding: " .. hidingText)
	setButtonEnabled(window.leaveButton, self.gameId ~= nil)

	if not window:IsShown() then
		window:Show()
		WEP:Log("HideSeek", "tracker_window_shown", {
			gameId = self.gameId,
		})
	end

	self:ScheduleWindowRefresh()
end

function HideSeek:EnsureWindow()
	if gameWindow then
		return gameWindow
	end

	if not WindowTool or not Form or not List then
		WEP:Log("HideSeek", "window_tools_unavailable", nil, "error")
		WEP:Print("Hide and Seek UI tools are unavailable.")
		return nil
	end

	local window, err = WindowTool.Create({
		name = "WEPHideSeekWindow",
		title = "Hide and Seek",
		width = 600,
		height = 430,
		onShow = function()
			self:RefreshWindow()
			self:ScheduleWindowRefresh()
		end,
	})

	if not window then
		WEP:Log("HideSeek", "window_failed", {
			error = err,
		}, "error")
		WEP:Print("Hide and Seek window failed:", err)
		return nil
	end

	local content = window.content

	window.statusText = content:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	window.statusText:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
	window.statusText:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, 0)
	window.statusText:SetJustifyH("LEFT")

	window.detailText = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	window.detailText:SetPoint("TOPLEFT", window.statusText, "BOTTOMLEFT", 0, -8)
	window.detailText:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, 0)
	window.detailText:SetJustifyH("LEFT")

	window.timerText = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	window.timerText:SetPoint("TOPLEFT", window.detailText, "BOTTOMLEFT", 0, -6)
	window.timerText:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, 0)
	window.timerText:SetJustifyH("LEFT")

	window.inviteInput = Form.CreateInput(content, {
		label = "Invite player",
		width = 170,
		onEnterPressed = function()
			self:InviteFromWindow()
		end,
	})
	window.inviteInput:SetPoint("TOPLEFT", window.timerText, "BOTTOMLEFT", 0, -18)

	window.inviteButton = Form.CreateButton(content, {
		text = "Invite",
		width = 80,
		onClick = function()
			self:InviteFromWindow()
		end,
	})
	window.inviteButton:SetPoint("LEFT", window.inviteInput.editBox, "RIGHT", 12, 0)

	window.hideInput = Form.CreateInput(content, {
		label = "Hide seconds",
		width = 92,
		numeric = true,
	})
	window.hideInput:SetPoint("TOPLEFT", window.inviteButton, "TOPRIGHT", 18, 18)

	window.seekInput = Form.CreateInput(content, {
		label = "Seek seconds",
		width = 92,
		numeric = true,
	})
	window.seekInput:SetPoint("TOPLEFT", window.hideInput, "TOPRIGHT", 12, 0)

	window.applyButton = Form.CreateButton(content, {
		text = "Apply",
		width = 78,
		onClick = function()
			self:ApplyWindowSettings()
		end,
	})
	window.applyButton:SetPoint("LEFT", window.seekInput.editBox, "RIGHT", 12, 0)

	window.rosterTitle = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	window.rosterTitle:SetPoint("TOPLEFT", window.inviteInput, "BOTTOMLEFT", 0, -18)
	window.rosterTitle:SetText("Roster")

	window.rosterList = List.Create(content, {
		width = 500,
		visibleRows = 9,
		rowHeight = 24,
		emptyText = "No players in this game.",
		columns = {
			{
				key = "name",
				width = 190,
			},
			{
				key = "role",
				width = 185,
			},
			{
				key = "state",
				width = 100,
			},
		},
	})
	window.rosterList.frame:SetPoint("TOPLEFT", window.rosterTitle, "BOTTOMLEFT", 0, -8)

	window.startButton = Form.CreateButton(window.footer, {
		text = "Start",
		width = 88,
		onClick = function()
			self:StartGame()
		end,
	})
	window.startButton:SetPoint("LEFT", window.footer, "LEFT", 0, 0)

	window.leaveButton = Form.CreateButton(window.footer, {
		text = "Leave",
		width = 88,
		onClick = function()
			self:LeaveGame()
		end,
	})
	window.leaveButton:SetPoint("LEFT", window.startButton, "RIGHT", 8, 0)

	window.refreshButton = Form.CreateButton(window.footer, {
		text = "Refresh",
		width = 88,
		onClick = function()
			self:RefreshWindow()
		end,
	})
	window.refreshButton:SetPoint("LEFT", window.leaveButton, "RIGHT", 8, 0)

	gameWindow = window
	WEP:Log("HideSeek", "window_created")
	return gameWindow
end

function HideSeek:RefreshWindow()
	self:RefreshTrackerWindow()

	local window = gameWindow
	if not window or not window:IsShown() then
		return
	end

	local canHostControl = self:CanHostControl()
	local hasGame = self.gameId ~= nil
	local canStart = canHostControl and self.status == STATUS_LOBBY and self:GetPlayerCount() >= 2

	window.statusText:SetText("Game State: " .. getStatusLabel(self.status))
	window.detailText:SetText(self:GetGameDetailText())
	window.timerText:SetText(self:GetTimerText())
	window.rosterList:SetItems(self:GetRosterItems())

	setInputValueIfNotFocused(window.hideInput, self.hideSeconds)
	setInputValueIfNotFocused(window.seekInput, self.seekSeconds)

	setInputEnabled(window.inviteInput, canHostControl)
	setInputEnabled(window.hideInput, canHostControl)
	setInputEnabled(window.seekInput, canHostControl)
	setButtonEnabled(window.inviteButton, canHostControl)
	setButtonEnabled(window.applyButton, canHostControl)
	setButtonEnabled(window.startButton, canStart)
	setButtonEnabled(window.leaveButton, hasGame)
	setButtonEnabled(window.refreshButton, true)
end

function HideSeek:ScheduleWindowRefresh()
	if self.windowRefreshScheduled then
		return
	end

	if not C_Timer or not C_Timer.After then
		return
	end

	self.windowRefreshScheduled = true

	Timer.After(1, function()
		self.windowRefreshScheduled = false

		if (gameWindow and gameWindow:IsShown()) or (trackerWindow and trackerWindow:IsShown()) then
			self:RefreshWindow()
			self:ScheduleWindowRefresh()
		end
	end)
end

function HideSeek:ShowWindow(focusInvite)
	local window = self:EnsureWindow()
	if not window then
		return
	end

	window:Show()
	WEP:Log("HideSeek", "window_shown", {
		focusInvite = focusInvite == true,
		status = self.status or "none",
	})
	self:RefreshWindow()

	if focusInvite and window.inviteInput and window.inviteInput.editBox then
		window.inviteInput.editBox:SetFocus()
		window.inviteInput.editBox:HighlightText()
	end
end

function HideSeek:InviteFromWindow()
	local window = self:EnsureWindow()
	if not window then
		return
	end

	WEP:Log("HideSeek", "invite_from_window")
	if self:InvitePlayer(window.inviteInput:GetValue()) then
		window.inviteInput:SetValue("")
	end

	self:RefreshWindow()
end

function HideSeek:ReadWindowSettings()
	local window = gameWindow
	if not window then
		return
	end

	self.hideSeconds = clamp(window.hideInput:GetValue(), MIN_HIDE_SECONDS, MAX_HIDE_SECONDS, self.hideSeconds)
	self.seekSeconds = clamp(window.seekInput:GetValue(), MIN_SEEK_SECONDS, MAX_SEEK_SECONDS, self.seekSeconds)
	WEP:Log("HideSeek", "window_settings_read", {
		hideSeconds = self.hideSeconds,
		seekSeconds = self.seekSeconds,
	})
end

function HideSeek:ApplyWindowSettings()
	local window = self:EnsureWindow()
	if not window then
		return
	end

	if not self:EnsureHostLobby() then
		self:RefreshWindow()
		return
	end

	self:ReadWindowSettings()
	WEP:Print("Hide and Seek settings:", "hide", formatDuration(self.hideSeconds), "seek", formatDuration(self.seekSeconds))
	WEP:Log("HideSeek", "settings_applied", {
		gameId = self.gameId or "none",
		hideSeconds = self.hideSeconds,
		seekSeconds = self.seekSeconds,
	})
	self:BroadcastState()
	self:RefreshWindow()
end

function HideSeek:ShowMenu()
	self:ShowWindow()
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

function HideSeek:ShowInvitePrompt()
	self:ShowWindow(true)
end

function HideSeek:ShowSettingsPrompt()
	self:ShowWindow()
end

function HideSeek:InvitePlayer(target)
	target = trim(target)
	WEP:Log("HideSeek", "invite_requested", {
		target = target,
		gameId = self.gameId or "none",
	})

	if target == "" then
		WEP:Log("HideSeek", "invite_failed", {
			error = "missing target",
		}, "warn")
		WEP:Print("Hide and Seek invite needs a player name.")
		self:ShowInvitePrompt()
		return false
	end

	if not self:EnsureHostLobby() then
		return false
	end

	if isSelfName(target) then
		WEP:Log("HideSeek", "invite_failed", {
			target = target,
			error = "self invite",
		}, "warn")
		WEP:Print("You are already in the Hide and Seek lobby.")
		return false
	end

	local ok, requestIdOrErr = Requests.Send(target, REQUEST_INVITE, {
		g = self.gameId,
		h = self.host,
		hs = self.hideSeconds,
		ss = self.seekSeconds,
	})

	if not ok then
		WEP:Log("HideSeek", "invite_failed", {
			target = target,
			error = requestIdOrErr,
		}, "error")
		WEP:Print("Hide and Seek invite failed:", requestIdOrErr)
		return false
	end

	self.pendingInvites[requestIdOrErr] = target
	WEP:Print("Hide and Seek invite sent to", target .. ".")
	WEP:Log("HideSeek", "invite_sent", {
		target = target,
		requestId = requestIdOrErr,
		gameId = self.gameId,
	})
	self:BroadcastState()
	self:RefreshWindow()
	return true
end

function HideSeek:OnInviteRequest(request)
	local data = request.data or {}
	local host = not isBlank(data.h) and namesMatch(data.h, request.sender) and data.h or request.sender
	local hideSeconds = clamp(data.hs, MIN_HIDE_SECONDS, MAX_HIDE_SECONDS, self.hideSeconds)
	local seekSeconds = clamp(data.ss, MIN_SEEK_SECONDS, MAX_SEEK_SECONDS, self.seekSeconds)

	if isBlank(data.g) then
		WEP:Log("HideSeek", "invite_request_ignored", {
			sender = request.sender,
			reason = "missing game id",
		}, "warn")
		return
	end

	WEP:Log("HideSeek", "invite_request_received", {
		sender = request.sender,
		host = host,
		gameId = data.g,
	})

	if self:IsBusy() then
		Requests.Respond(request.id, request.sender, "declined", {
			g = data.g or "",
			p = Player.GetFullName(),
			reason = "busy",
		})
		WEP:Log("HideSeek", "invite_declined_busy", {
			sender = request.sender,
			gameId = data.g,
		}, "warn")
		WEP:Print("Declined Hide and Seek invite from", host .. ":", "already in a game.")
		return
	end

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

			if status == "accepted" and self:IsBusy() then
				Requests.Respond(request.id, request.sender, "declined", {
					g = data.g or "",
					p = Player.GetFullName(),
					reason = "busy",
				})
				WEP:Log("HideSeek", "invite_accept_blocked_busy", {
					sender = request.sender,
					gameId = data.g,
				}, "warn")
				WEP:Print("Declined Hide and Seek invite from", host .. ":", "already in a game.")
				return
			end

			local ok, responseErr = Requests.Respond(request.id, request.sender, status, {
				g = data.g or "",
				p = Player.GetFullName(),
			})

			if not ok then
				WEP:Log("HideSeek", "invite_response_failed", {
					sender = request.sender,
					status = status,
					error = responseErr,
				}, "error")
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
				WEP:Log("HideSeek", "invite_accepted", {
					host = host,
					gameId = self.gameId,
				})
				self:RefreshWindow()
			else
				WEP:Log("HideSeek", "invite_declined", {
					host = host,
					gameId = data.g,
				})
				WEP:Print("Declined Hide and Seek invite from", host .. ".")
			end
		end,
	})

	playSound("wep_alert")
end

function HideSeek:OnInviteResponse(response)
	local request = response.request
	local requestData = request and request.data or {}

	if not request or requestData.g ~= self.gameId then
		WEP:Log("HideSeek", "invite_response_ignored", {
			sender = response.sender,
			reason = "unknown request or game",
		}, "warn")
		return
	end

	if request.target and not namesMatch(response.sender, request.target) then
		WEP:Log("HideSeek", "invite_response_ignored", {
			sender = response.sender,
			target = request.target,
			reason = "sender mismatch",
		}, "warn")
		return
	end

	if response.status == "accepted" then
		local playerName = response.data and response.data.p or response.sender
		if not namesMatch(response.sender, playerName) then
			playerName = response.sender
		end

		self:AddPlayer(playerName, false)
		WEP:Print(playerName, "joined Hide and Seek.")
		WEP:Log("HideSeek", "invite_response_accepted", {
			player = playerName,
			gameId = self.gameId,
		})
		self:BroadcastState()
		return
	end

	if response.status == "declined" then
		WEP:Print(response.sender, "declined Hide and Seek.")
		WEP:Log("HideSeek", "invite_response_declined", {
			player = response.sender,
			gameId = self.gameId,
		})
		self:RefreshWindow()
	end
end

function HideSeek:Broadcast(messageType, payload)
	local ok, messageIdOrErr = WEP.Comm:Send(messageType, payload, WEP.Comm:GetDefaultBroadcastOptions())

	if not ok then
		WEP:Log("HideSeek", "broadcast_failed", {
			type = messageType,
			gameId = payload and payload.g or self.gameId or "none",
			error = messageIdOrErr,
		}, "error")
		WEP:Print("Hide and Seek message failed:", messageIdOrErr)
	else
		WEP:Log("HideSeek", "broadcast_sent", {
			type = messageType,
			gameId = payload and payload.g or self.gameId or "none",
			messageId = messageIdOrErr,
		})
	end

	return ok, messageIdOrErr
end

function HideSeek:BroadcastState()
	if not self.gameId then
		WEP:Log("HideSeek", "broadcast_state_skipped", {
			reason = "no game id",
		}, "warn")
		return false
	end

	local ok, messageIdOrErr = self:Broadcast(MSG_STATE, {
		g = self.gameId,
		h = self.host or "",
		st = self.status or STATUS_IDLE,
		sk = self.seeker or "",
		hs = self.hideSeconds,
		ss = self.seekSeconds,
	})

	if ok then
		self:BroadcastRoster()
	end

	self:RefreshWindow()
	return ok, messageIdOrErr
end

function HideSeek:BroadcastRoster()
	if not self.gameId then
		return false
	end

	local sentAny = false
	local first = true

	for _, key in ipairs(self.playerOrder) do
		local player = self.players[key]

		if player then
			local ok = self:Broadcast(MSG_ROSTER, {
				g = self.gameId,
				p = player.name,
				f = player.found and 1 or 0,
				c = first and 1 or 0,
			})

			sentAny = sentAny or ok
			first = false
		end
	end

	return sentAny
end

function HideSeek:OnStateMessage(message)
	local payload = message.payload or {}

	if isBlank(payload.g) then
		WEP:Log("HideSeek", "state_message_ignored", {
			sender = message.sender,
			reason = "missing game id",
		}, "warn")
		return
	end

	local isKnownGame = self.gameId and payload.g == self.gameId
	if not isKnownGame then
		WEP:Log("HideSeek", "state_message_ignored", {
			sender = message.sender,
			gameId = payload.g,
			reason = "unknown game",
		}, "warn")
		return
	end

	local expectedHost = not isBlank(self.host) and self.host or payload.h
	if not self:IsMessageFromHost(message, expectedHost) then
		WEP:Log("HideSeek", "state_message_ignored", {
			sender = message.sender,
			gameId = payload.g,
			reason = "not host",
		}, "warn")
		return
	end

	self.gameId = payload.g
	self.host = not isBlank(self.host) and self.host or (not isBlank(payload.h) and payload.h or message.sender)
	self.status = payload.st or STATUS_LOBBY
	self.seeker = not isBlank(payload.sk) and payload.sk or nil
	self.hideSeconds = clamp(payload.hs, MIN_HIDE_SECONDS, MAX_HIDE_SECONDS, self.hideSeconds)
	self.seekSeconds = clamp(payload.ss, MIN_SEEK_SECONDS, MAX_SEEK_SECONDS, self.seekSeconds)
	self:ResetRoster()
	self:RefreshWindow()
	WEP:Log("HideSeek", "state_message_applied", {
		gameId = self.gameId,
		status = self.status,
		host = self.host,
	})
end

function HideSeek:OnRosterMessage(message)
	local payload = message.payload or {}

	if payload.g ~= self.gameId or not self:IsMessageFromHost(message) then
		WEP:Log("HideSeek", "roster_message_ignored", {
			sender = message.sender,
			gameId = payload.g or "none",
			reason = "game or host mismatch",
		}, "warn")
		return
	end

	if tostring(payload.c or "") == "1" then
		self:ResetRoster()
	end

	if not isBlank(payload.p) then
		self:AddPlayer(payload.p, tostring(payload.f or "") == "1")
	end

	self:RefreshWindow()
	WEP:Log("HideSeek", "roster_message_applied", {
		gameId = self.gameId,
		player = payload.p or "none",
		count = self:GetPlayerCount(),
	})
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
	WEP:Log("HideSeek", "start_requested", {
		gameId = self.gameId or "none",
		status = self.status or "none",
		players = self:GetPlayerCount(),
	})

	if not self:EnsureHostLobby() then
		return
	end

	self:ReadWindowSettings()

	if self:GetPlayerCount() < 2 then
		WEP:Log("HideSeek", "start_failed", {
			gameId = self.gameId or "none",
			error = "not enough players",
			players = self:GetPlayerCount(),
		}, "warn")
		WEP:Print("Hide and Seek needs at least 2 players.")
		self:ShowMenu()
		return
	end

	local seeker = self:PickRandomSeeker()
	if not seeker then
		WEP:Log("HideSeek", "start_failed", {
			gameId = self.gameId or "none",
			error = "could not choose seeker",
		}, "error")
		WEP:Print("Could not choose a seeker.")
		return
	end

	self.seeker = seeker
	self:ClearFound()
	WEP:Log("HideSeek", "started", {
		gameId = self.gameId,
		seeker = seeker,
		hideSeconds = self.hideSeconds,
		seekSeconds = self.seekSeconds,
	})
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

	if payload.g ~= self.gameId or not self:IsMessageFromHost(message) then
		WEP:Log("HideSeek", "start_message_ignored", {
			sender = message.sender,
			gameId = payload.g or "none",
			reason = "game or host mismatch",
		}, "warn")
		return
	end

	self.seeker = payload.sk
	self.hideSeconds = clamp(payload.hs, MIN_HIDE_SECONDS, MAX_HIDE_SECONDS, self.hideSeconds)
	self.seekSeconds = clamp(payload.ss, MIN_SEEK_SECONDS, MAX_SEEK_SECONDS, self.seekSeconds)
	self:ClearFound()
	WEP:Log("HideSeek", "start_message_applied", {
		gameId = self.gameId,
		seeker = self.seeker or "none",
	})
	self:BeginHiding(self.hideSeconds, self.seekSeconds, tonumber(payload.t) or Timer.Now())
end

function HideSeek:BeginHiding(hideSeconds, seekSeconds, startedAt)
	self.status = STATUS_HIDING
	self.seekSeconds = seekSeconds
	self.seekEndsAt = nil
	self.hideEndsAt = (tonumber(startedAt) or Timer.Now()) + hideSeconds
	self.resultReason = nil
	self.timerToken = (self.timerToken or 0) + 1
	local token = self.timerToken
	local remaining = self.hideEndsAt - Timer.Now()

	if remaining < 0 then
		remaining = 0
	end

	WEP:Log("HideSeek", "hiding_started", {
		gameId = self.gameId or "none",
		seeker = self.seeker or "none",
		hideSeconds = hideSeconds,
		seekSeconds = seekSeconds,
		remaining = remaining,
	})

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

	self:RefreshWindow()
end

function HideSeek:BeginSeeking()
	if self.status ~= STATUS_HIDING and self.status ~= STATUS_SEEKING then
		WEP:Log("HideSeek", "seeking_start_skipped", {
			gameId = self.gameId or "none",
			status = self.status or "none",
		}, "warn")
		return
	end

	self.status = STATUS_SEEKING
	self.seekEndsAt = Timer.Now() + self.seekSeconds
	self.hideEndsAt = nil
	self.timerToken = (self.timerToken or 0) + 1
	local token = self.timerToken

	self:HideCountdown()
	WEP:Log("HideSeek", "seeking_started", {
		gameId = self.gameId or "none",
		seeker = self.seeker or "none",
		seekSeconds = self.seekSeconds,
	})

	if self:IsSeeker() then
		ScreenOverlay.HideBlackout()
		self:HideSeekerUI()
		WEP:Print("Find the hiders. Target them to mark them found.")
	else
		WEP:Print("The seeker is hunting.")
	end

	Timer.After(self.seekSeconds, function()
		if self.timerToken == token and self.status == STATUS_SEEKING and self:IsHost() then
			self:FinishGame("time", true)
		end
	end)

	self:RefreshWindow()
end

function HideSeek:ShowCountdown(seconds, startedAt, onComplete)
	local frame = ensureCountdownFrame()
	if not frame then
		WEP:Log("HideSeek", "countdown_unavailable", {
			seconds = seconds,
		}, "error")
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
	WEP:Log("HideSeek", "countdown_shown", {
		seconds = seconds,
	})
	return true
end

function HideSeek:HideCountdown()
	self.countdownToken = (self.countdownToken or 0) + 1

	if countdownFrame then
		countdownFrame:Hide()
		WEP:Log("HideSeek", "countdown_hidden")
	end
end

function HideSeek:HideSeekerUI()
	self.seekerUiHidden = true

	for _, groupName in ipairs(SEEKER_UI_GROUPS) do
		UIVisibility.Hide(groupName)
	end

	WEP:Log("HideSeek", "seeker_ui_hidden", {
		groups = #SEEKER_UI_GROUPS,
	})
end

function HideSeek:RestoreSeekerUI()
	if not self.seekerUiHidden then
		return
	end

	self.seekerUiHidden = false

	for _, groupName in ipairs(SEEKER_UI_GROUPS) do
		UIVisibility.Show(groupName)
	end

	WEP:Log("HideSeek", "seeker_ui_restored", {
		groups = #SEEKER_UI_GROUPS,
	})
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

	WEP:Log("HideSeek", "target_changed", {
		target = targetName,
		gameId = self.gameId or "none",
	})

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
	WEP:Log("HideSeek", "player_found", {
		gameId = self.gameId or "none",
		player = player.name,
		foundBy = foundBy or self.seeker or "unknown",
		broadcast = broadcast == true,
	})

	if broadcast then
		self:Broadcast(MSG_FOUND, {
			g = self.gameId,
			p = player.name,
			by = foundBy or Player.GetFullName(),
		})
	end

	if self:IsHost() and self:AllHidersFound() then
		self:FinishGame("found", true)
	end

	self:RefreshWindow()
	return true
end

function HideSeek:OnFoundMessage(message)
	local payload = message.payload or {}

	if payload.g ~= self.gameId or self.status ~= STATUS_SEEKING or not self:IsMessageFromSeeker(message) then
		WEP:Log("HideSeek", "found_message_ignored", {
			sender = message.sender,
			gameId = payload.g or "none",
			reason = "state or seeker mismatch",
		}, "warn")
		return
	end

	WEP:Log("HideSeek", "found_message_received", {
		sender = message.sender,
		player = payload.p or "none",
		gameId = self.gameId,
	})
	self:MarkFound(payload.p, message.sender, false)

	if payload.p and isSelfName(payload.p) then
		WEP:Print("You were found.")
	end
end

function HideSeek:FinishGame(reason, broadcast)
	if not self.gameId then
		WEP:Log("HideSeek", "finish_skipped", {
			reason = "no game id",
		}, "warn")
		return
	end

	self.status = STATUS_ENDED
	self.resultReason = reason or "ended"
	self.timerToken = (self.timerToken or 0) + 1
	self:HideCountdown()
	ScreenOverlay.HideBlackout()
	self:RestoreSeekerUI()
	self.hideEndsAt = nil
	self.seekEndsAt = nil
	WEP:Log("HideSeek", "finished", {
		gameId = self.gameId,
		reason = self.resultReason,
		broadcast = broadcast == true,
	})

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

	self:RefreshWindow()
end

function HideSeek:OnEndMessage(message)
	local payload = message.payload or {}

	if payload.g ~= self.gameId or not self:IsMessageFromHost(message) then
		WEP:Log("HideSeek", "end_message_ignored", {
			sender = message.sender,
			gameId = payload.g or "none",
			reason = "game or host mismatch",
		}, "warn")
		return
	end

	WEP:Log("HideSeek", "end_message_received", {
		sender = message.sender,
		gameId = self.gameId,
		reason = payload.r or "ended",
	})
	self:FinishGame(payload.r or "ended", false)
end

function HideSeek:LeaveGame()
	if not self.gameId then
		WEP:Log("HideSeek", "leave_skipped", {
			reason = "no game",
		}, "warn")
		WEP:Print("You are not in a Hide and Seek game.")
		return
	end

	local wasHost = self:IsHost()
	local gameId = self.gameId
	WEP:Log("HideSeek", "leave_requested", {
		gameId = gameId,
		wasHost = wasHost,
	})

	if wasHost then
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
	WEP:Log("HideSeek", "left_game", {
		gameId = gameId,
		wasHost = wasHost,
	})
end

function HideSeek:OnLeaveMessage(message)
	local payload = message.payload or {}

	if payload.g ~= self.gameId or not self:IsHost() then
		WEP:Log("HideSeek", "leave_message_ignored", {
			sender = message.sender,
			gameId = payload.g or "none",
			reason = "game or host mismatch",
		}, "warn")
		return
	end

	local playerName = payload.p or message.sender
	if not messageSentBy(message, playerName) or not self:GetPlayer(playerName) then
		WEP:Log("HideSeek", "leave_message_ignored", {
			sender = message.sender,
			player = playerName or "none",
			reason = "sender or player mismatch",
		}, "warn")
		return
	end

	local playerWasSeeker = self.seeker and namesMatch(playerName, self.seeker)

	if self.status == STATUS_LOBBY or self.status == STATUS_ENDED then
		if self:RemovePlayer(playerName) then
			WEP:Print(playerName, "left Hide and Seek.")
			WEP:Log("HideSeek", "player_left_lobby", {
				gameId = self.gameId,
				player = playerName,
			})
			self:BroadcastState()
		end
		return
	end

	if self:RemovePlayer(playerName) then
		WEP:Print(playerName, "left Hide and Seek.")
		WEP:Log("HideSeek", "player_left_game", {
			gameId = self.gameId,
			player = playerName,
		})
	end

	if playerWasSeeker then
		self:FinishGame("canceled", true)
	elseif self:GetHiderCount() == 0 then
		self:FinishGame("canceled", true)
	elseif self:AllHidersFound() then
		self:FinishGame("found", true)
	else
		self:BroadcastState()
	end
end

function HideSeek:ResetGame()
	local previousGameId = self.gameId
	self:HideCountdown()
	ScreenOverlay.HideBlackout()
	self:RestoreSeekerUI()
	self.status = STATUS_IDLE
	self.gameId = nil
	self.host = nil
	self.seeker = nil
	self.seekEndsAt = nil
	self.hideEndsAt = nil
	self.resultReason = nil
	self.timerToken = (self.timerToken or 0) + 1
	self:ResetRoster()
	self:RefreshWindow()
	WEP:Log("HideSeek", "reset", {
		gameId = previousGameId or "none",
	})
end

function HideSeek:PrintStatus()
	WEP:Print("Hide and Seek:", getStatusLabel(self.status))
	WEP:Print("Host:", self.host or "none", "Players:", self:GetPlayerCount(), "Seeker:", self.seeker or "none")
	WEP:Print("Timers:", "hide", formatDuration(self.hideSeconds), "seek", formatDuration(self.seekSeconds))
	WEP:Print("Roster:", self:GetRosterText())
end

function HideSeek:OnDisabled()
	WEP:Log("HideSeek", "disabled", {
		gameId = self.gameId or "none",
		status = self.status or "none",
	})

	if self.gameId then
		self:LeaveGame()
	else
		self:HideCountdown()
		ScreenOverlay.HideBlackout()
		self:RestoreSeekerUI()
	end

	if gameWindow then
		gameWindow:Hide()
	end

	if trackerWindow then
		trackerWindow:Hide()
	end
end

function HideSeek:HandleSlash(args)
	if not self:IsEnabled() then
		WEP:Log("HideSeek", "slash_blocked_disabled", {
			action = args and args[2] or "none",
		}, "warn")
		WEP:Print("Hide and Seek is disabled. Open /wep to enable it.")
		return
	end

	local action = args[2]
	WEP:Log("HideSeek", "slash", {
		action = action or "menu",
		status = self.status or "none",
		gameId = self.gameId or "none",
	})

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

WEP:RegisterFeature(FEATURE_ID, HideSeek)
WEP:RegisterModule("HideSeek", HideSeek)
