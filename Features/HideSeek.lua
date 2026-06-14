local _, WEP = ...

local HideSeek = {
	hideSeconds = 30,
	seekSeconds = 300,
	startRadius = 1,
	starRevealUses = 0,
	starRevealUsesRemaining = 0,
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
local Environment = WEP.Tools.Environment

WEP:Log("HideSeek", "loaded")

local REQUEST_INVITE = "hide_seek_invite"
local MSG_STATE = "hide_seek_state"
local MSG_ROSTER = "hide_seek_roster"
local MSG_START = "hide_seek_start"
local MSG_FOUND = "hide_seek_found"
local MSG_END = "hide_seek_end"
local MSG_LEAVE = "hide_seek_leave"
local MSG_START_SPOT_REQUEST = "hide_seek_start_spot_request"
local MSG_START_SPOT = "hide_seek_start_spot"
local MSG_SEEKER_SPOT = "hide_seek_seeker_spot"
local MSG_TAGGED = "hide_seek_tagged"
local MSG_SAFE = "hide_seek_safe"

local STATUS_IDLE = "idle"
local STATUS_LOBBY = "lobby"
local STATUS_HIDING = "hiding"
local STATUS_SEEKING = "seeking"
local STATUS_ENDED = "ended"

local MIN_HIDE_SECONDS = 5
local MAX_HIDE_SECONDS = 300
local MIN_SEEK_SECONDS = 30
local MAX_SEEK_SECONDS = 3600
local MIN_START_RADIUS = 1
local MAX_START_RADIUS = 100
local HOME_CHECK_INTERVAL_SECONDS = 1
local SAFE_CONFIRM_SECONDS = 1
local SEEKER_SPOT_STALE_SECONDS = 3
local START_SPOT_RESPONSE_TIMEOUT_SECONDS = 10
local MIN_STAR_REVEAL_USES = 0
local MAX_STAR_REVEAL_USES = 99
local STAR_REVEAL_ICON = 1
local STAR_REVEAL_SECONDS = 2

local SEEKER_UI_GROUPS = {
	"minimap",
	"map",
	"unitframes",
	"actionbars",
}

local TARGET_BINDING_COMMANDS = {
	"TARGETPARTYMEMBER1",
	"TARGETPARTYMEMBER2",
	"TARGETPARTYMEMBER3",
	"TARGETPARTYMEMBER4",
}

for index = 1, 40 do
	TARGET_BINDING_COMMANDS[#TARGET_BINDING_COMMANDS + 1] = "TARGETRAID" .. index
end

local TARGET_BINDING_OWNER_NAME = "WEPHideSeekTargetBindingOwner"
local TARGET_BINDING_BUTTON_NAME = "WEPHideSeekTargetBindingBlocker"

local countdownFrame
local homeStatusFrame
local gameWindow
local trackerWindow
local targetBindingOwner
local targetBindingButton

local TRACKER_MAX_NAMES = 4
local GAME_WINDOW_MIN_ROSTER_ROWS = 3
local GAME_WINDOW_ROSTER_BASE_HEIGHT = 285

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

local function getAddressableUnitTokens()
	if not Environment or not Environment.GetUnitTokens then
		return {}
	end

	return Environment.GetUnitTokens({
		bossLimit = 0,
		includeNameplates = true,
		nameplateLimit = 40,
		partyLimit = 4,
		raidLimit = 40,
	})
end

local function getUnitPlayerName(unit)
	if isBlank(unit) or not UnitExists or not UnitExists(unit) then
		return nil
	end

	if UnitIsPlayer and not UnitIsPlayer(unit) then
		return nil
	end

	local name, realm
	if UnitFullName then
		name, realm = UnitFullName(unit)
	end

	if isBlank(name) and UnitName then
		name, realm = UnitName(unit)
	end

	if isBlank(name) then
		return nil
	end

	realm = Player.NormalizeRealmName(realm)
	if realm then
		return name .. "-" .. realm
	end

	return name
end

local function getRaidTargetIcon(unit)
	if not GetRaidTargetIndex then
		return nil, false
	end

	local ok, icon = pcall(GetRaidTargetIndex, unit)
	if ok then
		return icon, true
	end

	return nil, false
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

local function formatMapDistance(distance)
	if type(distance) ~= "number" then
		return "unknown"
	end

	if distance < 10 then
		return string.format("%.1f", distance)
	end

	return tostring(math.floor(distance + 0.5))
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

local function ensureHomeStatusFrame()
	if homeStatusFrame then
		return homeStatusFrame
	end

	if not CreateFrame or not UIParent then
		return nil
	end

	local frame = CreateFrame("Frame", "WEPHideSeekHomeStatusFrame", UIParent)
	frame:SetAllPoints(UIParent)
	frame:SetFrameStrata("FULLSCREEN_DIALOG")
	frame:SetFrameLevel(78)
	frame:EnableMouse(false)
	frame:Hide()

	frame.text = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
	frame.text:SetPoint("CENTER", frame, "CENTER", 0, 0)
	frame.text:SetJustifyH("CENTER")
	frame.text:SetJustifyV("MIDDLE")
	frame.text:SetTextColor(0.25, 1, 0.45, 1)

	homeStatusFrame = frame
	return homeStatusFrame
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

	WEP.Comm:RegisterHandler(MSG_START_SPOT_REQUEST, function(message)
		if not self:IsEnabled() then
			return
		end

		self:OnStartSpotRequestMessage(message)
	end)

	WEP.Comm:RegisterHandler(MSG_START_SPOT, function(message)
		if not self:IsEnabled() then
			return
		end

		self:OnStartSpotMessage(message)
	end)

	WEP.Comm:RegisterHandler(MSG_SEEKER_SPOT, function(message)
		if not self:IsEnabled() then
			return
		end

		self:OnSeekerSpotMessage(message)
	end)

	WEP.Comm:RegisterHandler(MSG_TAGGED, function(message)
		if not self:IsEnabled() then
			return
		end

		self:OnTaggedMessage(message)
	end)

	WEP.Comm:RegisterHandler(MSG_SAFE, function(message)
		if not self:IsEnabled() then
			return
		end

		self:OnSafeMessage(message)
	end)

	self.frame = CreateFrame("Frame")
	self.frame:RegisterEvent("PLAYER_TARGET_CHANGED")
	self.frame:SetScript("OnEvent", function(_, event)
		if event == "PLAYER_TARGET_CHANGED" and self:IsEnabled() then
			self:OnTargetChanged()
		elseif event == "PLAYER_REGEN_ENABLED" then
			self:OnPlayerRegenEnabled()
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
	self.nextSeeker = nil
	self.starRevealUsesRemaining = 0
	self:ClearStartSpot()
	self:CancelStarReveal()
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
	if not self.gameId or self.status == STATUS_IDLE then
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
		if self.nextSeeker and self:GetPlayer(self.nextSeeker) then
			self.seeker = self.nextSeeker
		else
			self.seeker = nil
		end
		self.starRevealUsesRemaining = 0
		self:ClearStartSpot()
		self:CancelStarReveal()
		self:ClearFound()
		self.nextSeeker = nil
		WEP:Log("HideSeek", "ended_game_reopened", {
			gameId = self.gameId,
			nextSeeker = self.seeker or "random",
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

function HideSeek:AddPlayer(name, found, safe, pendingFound)
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
			safe = safe == true,
			pendingFound = pendingFound == true,
		}
		self.players[key] = player
		self.playerOrder[#self.playerOrder + 1] = key
		WEP:Log("HideSeek", "player_added", {
			gameId = self.gameId or "none",
			player = name,
			found = found == true,
			safe = safe == true,
			pendingFound = pendingFound == true,
		})
	else
		player.name = name
		player.found = player.found or found == true
		player.safe = player.safe or safe == true
		player.pendingFound = player.pendingFound or pendingFound == true
	end

	return player
end

function HideSeek:RemovePlayer(name)
	local key = nameKey(name)
	if key == "" or not self.players[key] then
		return false
	end

	local clearedSelectedSeeker = self.seeker
		and namesMatch(name, self.seeker)
		and (self.status == STATUS_IDLE or self.status == STATUS_LOBBY or self.status == STATUS_ENDED)

	self.players[key] = nil

	for index, orderKey in ipairs(self.playerOrder) do
		if orderKey == key then
			table.remove(self.playerOrder, index)
			break
		end
	end

	if clearedSelectedSeeker then
		self.seeker = nil
	end

	WEP:Log("HideSeek", "player_removed", {
		gameId = self.gameId or "none",
		player = name,
		clearedSelectedSeeker = clearedSelectedSeeker == true,
	})
	return true
end

function HideSeek:ClearFound()
	for _, player in pairs(self.players) do
		player.found = false
		player.safe = false
		player.pendingFound = false
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

function HideSeek:GetSafeCount()
	local count = 0

	for _, key in ipairs(self.playerOrder) do
		local player = self.players[key]

		if player and player.safe and not namesMatch(player.name, self.seeker) then
			count = count + 1
		end
	end

	return count
end

function HideSeek:GetStarRevealRemaining()
	local maxUses = clamp(self.starRevealUses, MIN_STAR_REVEAL_USES, MAX_STAR_REVEAL_USES, 0)
	local remaining = tonumber(self.starRevealUsesRemaining) or 0

	if remaining < 0 then
		return 0
	end

	if remaining > maxUses then
		return maxUses
	end

	return math.floor(remaining)
end

function HideSeek:GetStarRevealText()
	local maxUses = clamp(self.starRevealUses, MIN_STAR_REVEAL_USES, MAX_STAR_REVEAL_USES, 0)

	if maxUses <= 0 then
		return "off"
	end

	if self.status == STATUS_HIDING or self.status == STATUS_SEEKING then
		return self:GetStarRevealRemaining() .. "/" .. maxUses
	end

	return tostring(maxUses)
end

function HideSeek:ResetStarRevealUses()
	self.starRevealUses = clamp(self.starRevealUses, MIN_STAR_REVEAL_USES, MAX_STAR_REVEAL_USES, 0)
	self.starRevealUsesRemaining = self.starRevealUses
end

function HideSeek:GetStartRadius()
	self.startRadius = clamp(self.startRadius or self.areaRadius, MIN_START_RADIUS, MAX_START_RADIUS, 1)
	return self.startRadius
end

function HideSeek:HasStartSpot()
	return self.startMapId ~= nil and self.startX ~= nil and self.startY ~= nil
end

function HideSeek:AddStartSpotPayload(payload, includeSpot)
	payload.ar = self:GetStartRadius()

	if includeSpot and self:HasStartSpot() then
		payload.am = self.startMapId
		payload.ax = self.startX
		payload.ay = self.startY
	end

	return payload
end

function HideSeek:ApplyStartSpotPayload(payload, clearMissingSpot)
	payload = payload or {}
	self.startRadius = clamp(payload.ar, MIN_START_RADIUS, MAX_START_RADIUS, self.startRadius)

	local mapId = tonumber(payload.am)
	local x = tonumber(payload.ax)
	local y = tonumber(payload.ay)

	if mapId and x and y then
		self.startMapId = mapId
		self.startX = x
		self.startY = y
	elseif clearMissingSpot then
		self.startMapId = nil
		self.startX = nil
		self.startY = nil
	end
end

function HideSeek:ClearStartSpot()
	self.startMapId = nil
	self.startX = nil
	self.startY = nil
	self.startSpotPending = false
	self.seekerAtStartSpot = nil
	self.seekerSpotUpdatedAt = nil
	self.seekerAbsentSince = nil
	self.startLocationUnavailableWarned = false
	self:ClearStartSpotWaypoint()
	self:CancelSafeAttempt()
	self:HideHomeStatus()
end

function HideSeek:CaptureStartSpot()
	if not Environment or not Environment.GetPlayerMapPosition then
		WEP:Log("HideSeek", "start_spot_capture_failed", {
			error = "map position API unavailable",
		}, "error")
		WEP:Print("Could not start Hide and Seek: map coordinates are unavailable.")
		return false
	end

	local mapId, x, y = Environment.GetPlayerMapPosition()
	if not mapId or not x or not y then
		WEP:Log("HideSeek", "start_spot_capture_failed", {
			mapId = mapId or "none",
			x = x or "none",
			y = y or "none",
		}, "warn")
		WEP:Print("Could not start Hide and Seek: the seeker's current map coordinates are unavailable.")
		return false
	end

	self.startMapId = tonumber(mapId)
	self.startX = tonumber(x)
	self.startY = tonumber(y)
	self.seekerAtStartSpot = true
	self.seekerSpotUpdatedAt = Timer.Now()
	self.seekerAbsentSince = nil
	self.startLocationUnavailableWarned = false
	self:HideHomeStatus()

	WEP:Log("HideSeek", "start_spot_captured", {
		gameId = self.gameId or "none",
		mapId = self.startMapId,
		x = self.startX,
		y = self.startY,
		radius = self:GetStartRadius(),
	})
	return true
end

function HideSeek:GetStartSpotDetailText()
	local text = "Start radius " .. self:GetStartRadius()

	if self:HasStartSpot() then
		text = text .. " @ " .. self.startX .. ", " .. self.startY
	end

	return text
end

function HideSeek:GetCurrentMapPosition()
	if Environment and Environment.GetPlayerMapPosition then
		local mapId, x, y = Environment.GetPlayerMapPosition()
		return tonumber(mapId), tonumber(x), tonumber(y)
	end

	if Environment and Environment.GetLocation then
		local location = Environment.GetLocation()
		if location then
			return tonumber(location.mapId), tonumber(location.x), tonumber(location.y)
		end
	end

	return nil, nil, nil
end

function HideSeek:GetStartSpotDistance()
	if not self:HasStartSpot() then
		return nil, "no start spot"
	end

	local mapId, x, y = self:GetCurrentMapPosition()
	if not mapId then
		return nil, "map unavailable"
	end

	if mapId ~= tonumber(self.startMapId) then
		return nil, "wrong map", true
	end

	if not x or not y then
		return nil, "coordinates unavailable"
	end

	local dx = x - self.startX
	local dy = y - self.startY
	return math.sqrt((dx * dx) + (dy * dy))
end

function HideSeek:IsAtStartSpot()
	local distance, reason, wrongMap = self:GetStartSpotDistance()

	if wrongMap then
		return false, reason
	end

	if not distance then
		return nil, reason
	end

	return distance <= self:GetStartRadius(), distance
end

function HideSeek:GetStartSpotNavigationText()
	if not self:HasStartSpot() then
		return "Start: not set"
	end

	local atStart, reasonOrDistance = self:IsAtStartSpot()
	if atStart == true then
		return "Start: here"
	end

	if type(reasonOrDistance) == "number" then
		return "Start: " .. formatMapDistance(reasonOrDistance) .. " away"
	end

	return "Start: " .. tostring(reasonOrDistance or "away")
end

function HideSeek:CanUseStartSpotWaypoint()
	return C_Map
		and C_Map.SetUserWaypoint
		and UiMapPoint
		and UiMapPoint.CreateFromCoordinates
end

function HideSeek:SetStartSpotWaypoint()
	if not self:HasStartSpot() or not self:IsParticipant() then
		return false
	end

	if not self:CanUseStartSpotWaypoint() then
		if not self.startWaypointUnavailableWarned then
			self.startWaypointUnavailableWarned = true
			WEP:Print("Map waypoint unavailable. Use the Hide and Seek tracker for the starting spot.")
			WEP:Log("HideSeek", "start_waypoint_unavailable", {
				gameId = self.gameId or "none",
			}, "warn")
		end

		return false
	end

	local point = UiMapPoint.CreateFromCoordinates(self.startMapId, self.startX / 100, self.startY / 100)
	local ok, err = pcall(C_Map.SetUserWaypoint, point)
	if not ok then
		WEP:Log("HideSeek", "start_waypoint_failed", {
			gameId = self.gameId or "none",
			error = err,
		}, "warn")
		return false
	end

	if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
		pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, true)
	end

	self.startWaypointSet = true
	self.startWaypointUnavailableWarned = false
	WEP:Log("HideSeek", "start_waypoint_set", {
		gameId = self.gameId or "none",
		mapId = self.startMapId,
		x = self.startX,
		y = self.startY,
	})
	return true
end

function HideSeek:ClearStartSpotWaypoint()
	if self.startWaypointSet and C_Map and C_Map.ClearUserWaypoint then
		pcall(C_Map.ClearUserWaypoint)
	end

	self.startWaypointSet = false
end

function HideSeek:ShowHomeStatus(text)
	local frame = ensureHomeStatusFrame()
	if not frame then
		WEP:Log("HideSeek", "home_status_unavailable", nil, "warn")
		return false
	end

	frame.text:SetText(text)
	frame:Show()
	return true
end

function HideSeek:HideHomeStatus()
	if homeStatusFrame then
		homeStatusFrame:Hide()
	end
end

function HideSeek:IsActiveHider(player)
	return player
		and not namesMatch(player.name, self.seeker)
		and player.found ~= true
		and player.safe ~= true
end

function HideSeek:ShouldMonitorHomeSpot()
	if not self:HasStartSpot() or not self:IsParticipant() or self.status ~= STATUS_SEEKING then
		return false
	end

	if self:IsSeeker() then
		return true
	end

	return self:IsActiveHider(self:GetPlayer(Player.GetFullName()))
end

function HideSeek:StartHomeMonitor()
	self.homeMonitorToken = (self.homeMonitorToken or 0) + 1
	local token = self.homeMonitorToken

	local function check()
		if self.homeMonitorToken ~= token then
			return
		end

		if not self:ShouldMonitorHomeSpot() then
			self:CancelSafeAttempt()
			return
		end

		self:CheckHomeSpot()

		if self.homeMonitorToken == token and self:ShouldMonitorHomeSpot() then
			Timer.After(HOME_CHECK_INTERVAL_SECONDS, check)
		end
	end

	check()
end

function HideSeek:StopHomeMonitor()
	self.homeMonitorToken = (self.homeMonitorToken or 0) + 1
	self.startLocationUnavailableWarned = false
	self:CancelSafeAttempt()
end

function HideSeek:CheckHomeSpot()
	local atStart, reasonOrDistance = self:IsAtStartSpot()

	if atStart == nil then
		self:CancelSafeAttempt()

		if not self.startLocationUnavailableWarned then
			self.startLocationUnavailableWarned = true
			WEP:Log("HideSeek", "start_spot_check_waiting", {
				gameId = self.gameId or "none",
				reason = reasonOrDistance or "unknown",
			}, "warn")
			WEP:Print("Hide and Seek start spot check is waiting for map coordinates.")
		end

		return
	end

	self.startLocationUnavailableWarned = false

	if self:IsSeeker() then
		self:ReportSeekerSpot(atStart)

		if atStart and self:IsHost() then
			self:ConfirmPendingFoundAtStart()
		end

		return
	end

	if atStart then
		self:StartSafeAttempt()
	else
		self:CancelSafeAttempt()
	end
end

function HideSeek:CancelSafeAttempt()
	self.safeAttemptToken = (self.safeAttemptToken or 0) + 1
	self.safeAttemptActive = false
	self.safeAttemptStartedAt = nil
	self:HideHomeStatus()
end

function HideSeek:StartSafeAttempt()
	if self.safeAttemptActive then
		return
	end

	self.safeAttemptActive = true
	self.safeAttemptStartedAt = Timer.Now()
	self.safeAttemptToken = (self.safeAttemptToken or 0) + 1
	local token = self.safeAttemptToken

	self:ShowHomeStatus("Hold the start spot\n" .. SAFE_CONFIRM_SECONDS)

	Timer.After(SAFE_CONFIRM_SECONDS, function()
		if self.safeAttemptToken ~= token then
			return
		end

		self.safeAttemptActive = false
		self.safeAttemptStartedAt = nil
		self:HideHomeStatus()

		if self.status ~= STATUS_SEEKING or self:IsSeeker() then
			return
		end

		local player = self:GetPlayer(Player.GetFullName())
		if not self:IsActiveHider(player) then
			return
		end

		local atStart = self:IsAtStartSpot()
		if atStart == true then
			self:RequestSafe()
		end
	end)
end

function HideSeek:RequestSafe()
	local playerName = Player.GetFullName()

	if self:IsHost() then
		return self:ProcessSafeRequest(playerName, playerName)
	end

	return self:Broadcast(MSG_SAFE, {
		g = self.gameId,
		p = playerName,
	})
end

function HideSeek:UpdateSeekerSpotState(atStart, observedAt)
	local now = tonumber(observedAt) or Timer.Now()
	atStart = atStart == true

	if atStart then
		self.seekerAbsentSince = nil
	else
		if self.seekerAtStartSpot ~= false or not self.seekerAbsentSince then
			self.seekerAbsentSince = now
		end
	end

	self.seekerAtStartSpot = atStart
	self.seekerSpotUpdatedAt = now
end

function HideSeek:ReportSeekerSpot(atStart)
	if self.status ~= STATUS_SEEKING or not self:IsSeeker() then
		return false
	end

	local now = Timer.Now()

	if self:IsHost() then
		self:UpdateSeekerSpotState(atStart, now)
		return true
	end

	return self:Broadcast(MSG_SEEKER_SPOT, {
		g = self.gameId,
		at = atStart and 1 or 0,
		t = now,
	})
end

function HideSeek:IsSeekerSpotFresh(now)
	now = tonumber(now) or Timer.Now()
	return self.seekerSpotUpdatedAt ~= nil and now - self.seekerSpotUpdatedAt <= SEEKER_SPOT_STALE_SECONDS
end

function HideSeek:IsSeekerAbsentForSafe(now)
	now = tonumber(now) or Timer.Now()

	return self.status == STATUS_SEEKING
		and self.seekerAtStartSpot == false
		and self:IsSeekerSpotFresh(now)
		and self.seekerAbsentSince ~= nil
		and now - self.seekerAbsentSince >= SAFE_CONFIRM_SECONDS
end

function HideSeek:ConfirmPendingFoundAtStart()
	if not self:IsHost() or self.status ~= STATUS_SEEKING then
		return false
	end

	for _, key in ipairs(self.playerOrder) do
		local player = self.players[key]

		if self:IsActiveHider(player) and player.pendingFound then
			return self:MarkFound(player.name, self.seeker or Player.GetFullName(), true)
		end
	end

	return false
end

function HideSeek:SetRaidTargetIcon(unit, icon)
	if not SetRaidTarget or isBlank(unit) then
		return false
	end

	local ok, err = pcall(SetRaidTarget, unit, icon)
	if not ok then
		WEP:Log("HideSeek", "raid_target_set_failed", {
			unit = unit,
			icon = icon,
			error = err,
		}, "warn")
		return false
	end

	return true
end

function HideSeek:ClearStarRevealMarkers(markedUnits)
	markedUnits = markedUnits or self.starRevealMarkedUnits
	if type(markedUnits) ~= "table" then
		return 0
	end

	local cleared = 0

	for _, marker in ipairs(markedUnits) do
		local unit = marker.unit

		if unit and UnitExists and UnitExists(unit) then
			local currentName = getUnitPlayerName(unit)
			local icon, canReadIcon = getRaidTargetIcon(unit)
			local isSamePlayer = not marker.name or namesMatch(currentName, marker.name)
			local shouldClear = not canReadIcon or icon == STAR_REVEAL_ICON

			if isSamePlayer and shouldClear and self:SetRaidTargetIcon(unit, 0) then
				cleared = cleared + 1
			end
		end
	end

	if markedUnits == self.starRevealMarkedUnits then
		self.starRevealMarkedUnits = nil
	end

	return cleared
end

function HideSeek:CancelStarReveal()
	self.starRevealToken = (self.starRevealToken or 0) + 1
	self:ClearStarRevealMarkers()
end

function HideSeek:ClearAllRaidTargets()
	if not SetRaidTarget then
		WEP:Log("HideSeek", "raid_target_clear_unavailable", nil, "warn")
		return 0
	end

	local cleared = 0
	local seenUnits = {}

	for _, unit in ipairs(getAddressableUnitTokens()) do
		if unit and not seenUnits[unit] and (not UnitExists or UnitExists(unit)) then
			seenUnits[unit] = true

			local icon, canReadIcon = getRaidTargetIcon(unit)
			if (not canReadIcon or (tonumber(icon) or 0) > 0) and self:SetRaidTargetIcon(unit, 0) then
				cleared = cleared + 1
			end
		end
	end

	WEP:Log("HideSeek", "raid_targets_cleared", {
		count = cleared,
	})
	return cleared
end

function HideSeek:FindUnitTokenForPlayer(playerName, usedUnits)
	if isBlank(playerName) then
		return nil
	end

	usedUnits = usedUnits or {}

	for _, unit in ipairs(getAddressableUnitTokens()) do
		if unit and not usedUnits[unit] then
			local unitName = getUnitPlayerName(unit)

			if unitName and namesMatch(unitName, playerName) then
				return unit
			end
		end
	end

	return nil
end

function HideSeek:CanUseStarRevealPower()
	return self.status == STATUS_SEEKING
		and self:IsSeeker()
		and clamp(self.starRevealUses, MIN_STAR_REVEAL_USES, MAX_STAR_REVEAL_USES, 0) > 0
		and self:GetStarRevealRemaining() > 0
end

function HideSeek:UseStarRevealPower()
	if self.status ~= STATUS_SEEKING then
		WEP:Print("Star reveal can only be used while seeking.")
		return false
	end

	if not self:IsSeeker() then
		WEP:Print("Only the seeker can use Star reveal.")
		return false
	end

	if clamp(self.starRevealUses, MIN_STAR_REVEAL_USES, MAX_STAR_REVEAL_USES, 0) <= 0 then
		WEP:Print("Star reveal is disabled for this game.")
		return false
	end

	if self:GetStarRevealRemaining() <= 0 then
		WEP:Print("No Star reveals remaining.")
		return false
	end

	if not SetRaidTarget then
		WEP:Print("Raid target icons are unavailable.")
		return false
	end

	self:CancelStarReveal()

	local markedUnits = {}
	local usedUnits = {}
	local hiderCount = 0
	local missingCount = 0

	for _, key in ipairs(self.playerOrder) do
		local player = self.players[key]

		if self:IsActiveHider(player) then
			hiderCount = hiderCount + 1
			local unit = self:FindUnitTokenForPlayer(player.name, usedUnits)

			if unit then
				usedUnits[unit] = true

				if self:SetRaidTargetIcon(unit, STAR_REVEAL_ICON) then
					markedUnits[#markedUnits + 1] = {
						unit = unit,
						name = player.name,
					}
				end
			else
				missingCount = missingCount + 1
			end
		end
	end

	if hiderCount == 0 then
		WEP:Print("No hidden hiders remain.")
		return false
	end

	if #markedUnits == 0 then
		WEP:Print("No hiders could be marked. Hiders must be addressable as group, target, mouseover, focus, or nameplate units.")
		WEP:Log("HideSeek", "star_reveal_failed", {
			gameId = self.gameId or "none",
			hiders = hiderCount,
			missing = missingCount,
		}, "warn")
		return false
	end

	self.starRevealUsesRemaining = self:GetStarRevealRemaining() - 1
	self.starRevealMarkedUnits = markedUnits
	self.starRevealToken = (self.starRevealToken or 0) + 1
	local token = self.starRevealToken

	Timer.After(STAR_REVEAL_SECONDS, function()
		if self.starRevealToken == token then
			self:ClearStarRevealMarkers(markedUnits)
		end
	end)

	WEP:Print("Star reveal used. Remaining:", self:GetStarRevealRemaining() .. "/" .. self.starRevealUses)
	if missingCount > 0 then
		WEP:Print(missingCount, "hider(s) were not close or grouped enough to mark.")
	end

	WEP:Log("HideSeek", "star_reveal_used", {
		gameId = self.gameId or "none",
		marked = #markedUnits,
		missing = missingCount,
		remaining = self:GetStarRevealRemaining(),
	})
	self:RefreshWindow()
	return true
end

function HideSeek:GetSelectedSeeker()
	if not self.seeker then
		return nil
	end

	local player = self:GetPlayer(self.seeker)
	if not player then
		return nil
	end

	return player.name
end

function HideSeek:SetSelectedSeeker(name, broadcast)
	name = trim(name)

	if name == "" then
		self.seeker = nil
		WEP:Print("Hide and Seek seeker will be chosen randomly.")
		WEP:Log("HideSeek", "selected_seeker_cleared", {
			gameId = self.gameId or "none",
		})

		if broadcast then
			self:BroadcastState()
		else
			self:RefreshWindow()
		end

		return true
	end

	local player = self:GetPlayer(name)
	if not player then
		WEP:Print("Seeker must be in the current Hide and Seek roster.")
		WEP:Log("HideSeek", "selected_seeker_failed", {
			gameId = self.gameId or "none",
			seeker = name,
			error = "not in roster",
		}, "warn")
		return false
	end

	self.seeker = player.name
	WEP:Print("Hide and Seek seeker:", self.seeker)
	WEP:Log("HideSeek", "selected_seeker_set", {
		gameId = self.gameId or "none",
		seeker = self.seeker,
	})

	if broadcast then
		self:BroadcastState()
	else
		self:RefreshWindow()
	end

	return true
end

function HideSeek:AllHidersSafe()
	local hiderCount = 0

	for _, key in ipairs(self.playerOrder) do
		local player = self.players[key]

		if player and not namesMatch(player.name, self.seeker) then
			hiderCount = hiderCount + 1

			if not player.safe then
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
			elseif player.safe then
				suffix = " (safe)"
			elseif player.pendingFound then
				suffix = " (tagged)"
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
		self:GetStartSpotDetailText(),
		"Star reveal: " .. self:GetStarRevealText(),
	}

	if self.seeker then
		lines[#lines + 1] = "Seeker: " .. self.seeker
	end

	lines[#lines + 1] = "Roster: " .. self:GetRosterText()

	if self.status == STATUS_SEEKING then
		lines[#lines + 1] = "Safe: " .. self:GetSafeCount() .. "/" .. self:GetHiderCount()
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

	if self.startSpotPending then
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

	if player.safe then
		return "Safe"
	end

	if player.pendingFound then
		return "Tagged"
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
	local canSelectSeeker = self:CanHostControl()

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
			elseif player.safe then
				color = {
					r = 0.02,
					g = 0.18,
					b = 0.08,
					a = 0.35,
				}
			elseif player.pendingFound then
				color = {
					r = 0.20,
					g = 0.14,
					b = 0.02,
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

			if canSelectSeeker then
				local playerName = player.name

				items[#items].onClick = function()
					self:SelectSeeker(playerName)
				end
			end
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
		self:GetStartSpotDetailText(),
	}

	if clamp(self.starRevealUses, MIN_STAR_REVEAL_USES, MAX_STAR_REVEAL_USES, 0) > 0 then
		details[#details + 1] = "Star " .. self:GetStarRevealText()
	end

	if self.seeker then
		details[#details + 1] = "Seeker " .. self.seeker
	elseif self.status == STATUS_LOBBY then
		details[#details + 1] = "Seeker Random"
	end

	if self.status == STATUS_SEEKING then
		details[#details + 1] = "Safe " .. self:GetSafeCount() .. "/" .. self:GetHiderCount()
		details[#details + 1] = "Found " .. self:GetFoundCount() .. "/" .. self:GetHiderCount()
	end

	return table.concat(details, "  |  ")
end

function HideSeek:GetTimerText()
	if self.startSpotPending then
		return "Waiting for seeker starting spot"
	end

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

		if self.resultReason == "safe" then
			return "Result: hiders safe"
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

local function isInCombatLockdown()
	return InCombatLockdown and InCombatLockdown()
end

local function ensureTargetBindingBlocker()
	if targetBindingOwner and targetBindingButton then
		return targetBindingOwner
	end

	if not CreateFrame or not UIParent then
		return nil
	end

	targetBindingOwner = CreateFrame("Frame", TARGET_BINDING_OWNER_NAME, UIParent)
	targetBindingButton = CreateFrame("Button", TARGET_BINDING_BUTTON_NAME, targetBindingOwner)
	targetBindingButton:SetScript("OnClick", function() end)
	targetBindingButton:Hide()

	return targetBindingOwner
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
			elseif rolesAssigned and self:IsActiveHider(player) then
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
		height = 240,
		level = 85,
		resizable = true,
		collapsible = true,
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

	window.startText = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	window.startText:SetPoint("TOPLEFT", window.hidingText, "BOTTOMLEFT", 0, -6)
	window.startText:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, 0)
	window.startText:SetJustifyH("LEFT")

	window.revealButton = Form.CreateButton(window.footer, {
		text = "Reveal",
		width = 84,
		height = 22,
		onClick = function()
			self:UseStarRevealPower()
		end,
	})
	window.revealButton:SetPoint("LEFT", window.footer, "LEFT", 0, 0)

	window.openButton = Form.CreateButton(window.footer, {
		text = "Open",
		width = 72,
		height = 22,
		onClick = function()
			self:ShowMenu()
		end,
	})
	window.openButton:SetPoint("LEFT", window.revealButton, "RIGHT", 8, 0)

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

function HideSeek:UpdateBindingRegenEvent()
	if not self.frame then
		return
	end

	if self.targetBindingBlockPending or self.targetBindingClearPending then
		self.frame:RegisterEvent("PLAYER_REGEN_ENABLED")
	elseif self.frame.UnregisterEvent then
		self.frame:UnregisterEvent("PLAYER_REGEN_ENABLED")
	end
end

function HideSeek:ShouldBlockTargetBindings()
	return self.status == STATUS_SEEKING and self:IsSeeker()
end

function HideSeek:BlockSeekerTargetBindings()
	if self.targetBindingsBlocked or not self:ShouldBlockTargetBindings() then
		return self.targetBindingsBlocked == true
	end

	if not SetOverrideBinding or not GetBindingKey then
		WEP:Log("HideSeek", "target_binding_block_unavailable", nil, "warn")
		return false
	end

	if isInCombatLockdown() then
		self.targetBindingBlockPending = true
		self:UpdateBindingRegenEvent()
		WEP:Log("HideSeek", "target_binding_block_delayed", {
			reason = "combat lockdown",
		}, "warn")
		WEP:Print("Party target keybind blocking will apply after combat.")
		return false
	end

	local owner = ensureTargetBindingBlocker()
	if not owner then
		WEP:Log("HideSeek", "target_binding_block_unavailable", {
			reason = "binding owner unavailable",
		}, "warn")
		return false
	end

	local command = "CLICK " .. TARGET_BINDING_BUTTON_NAME .. ":LeftButton"
	local blockedCount = 0
	local seenKeys = {}

	for _, bindingCommand in ipairs(TARGET_BINDING_COMMANDS) do
		local keyCount = select("#", GetBindingKey(bindingCommand))

		for index = 1, keyCount do
			local key = select(index, GetBindingKey(bindingCommand))

			if key and not seenKeys[key] then
				local ok, err = pcall(SetOverrideBinding, owner, true, key, command)
				seenKeys[key] = true

				if ok then
					blockedCount = blockedCount + 1
				else
					WEP:Log("HideSeek", "target_binding_block_failed", {
						key = key,
						error = err,
					}, "error")
				end
			end
		end
	end

	self.targetBindingBlockPending = false
	self.targetBindingsBlocked = blockedCount > 0
	self.blockedTargetBindingCount = blockedCount
	self:UpdateBindingRegenEvent()

	WEP:Log("HideSeek", "target_bindings_blocked", {
		count = blockedCount,
	})

	if blockedCount > 0 then
		WEP:Print("Party target keybinds disabled while you seek.")
	end

	return self.targetBindingsBlocked
end

function HideSeek:RestoreSeekerTargetBindings()
	self.targetBindingBlockPending = false

	if not self.targetBindingsBlocked then
		self.targetBindingClearPending = false
		self:UpdateBindingRegenEvent()
		return true
	end

	if not ClearOverrideBindings or not targetBindingOwner then
		self.targetBindingsBlocked = false
		self.targetBindingClearPending = false
		self.blockedTargetBindingCount = nil
		self:UpdateBindingRegenEvent()
		return false
	end

	if isInCombatLockdown() then
		self.targetBindingClearPending = true
		self:UpdateBindingRegenEvent()
		WEP:Log("HideSeek", "target_binding_restore_delayed", {
			reason = "combat lockdown",
		}, "warn")
		return false
	end

	local ok, err = pcall(ClearOverrideBindings, targetBindingOwner)
	if not ok then
		WEP:Log("HideSeek", "target_binding_restore_failed", {
			error = err,
		}, "error")
		return false
	end

	WEP:Log("HideSeek", "target_bindings_restored", {
		count = self.blockedTargetBindingCount or 0,
	})
	self.targetBindingsBlocked = false
	self.targetBindingClearPending = false
	self.blockedTargetBindingCount = nil
	self:UpdateBindingRegenEvent()
	return true
end

function HideSeek:OnPlayerRegenEnabled()
	if self.targetBindingClearPending then
		self:RestoreSeekerTargetBindings()
	elseif self.targetBindingBlockPending then
		if self:ShouldBlockTargetBindings() then
			self:BlockSeekerTargetBindings()
		else
			self.targetBindingBlockPending = false
		end
	end

	self:UpdateBindingRegenEvent()
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
	window.startText:SetText(self:GetStartSpotNavigationText())
	if window.revealButton then
		if self:IsSeeker()
			and self.status == STATUS_SEEKING
			and clamp(self.starRevealUses, MIN_STAR_REVEAL_USES, MAX_STAR_REVEAL_USES, 0) > 0 then
			window.revealButton:SetText("Reveal " .. self:GetStarRevealRemaining())
			window.revealButton:Show()
		else
			window.revealButton:Hide()
		end

		setButtonEnabled(window.revealButton, self:CanUseStarRevealPower())
	end

	setButtonEnabled(window.leaveButton, self.gameId ~= nil)
	setButtonEnabled(window.openButton, true)

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
		width = 620,
		height = 520,
		minWidth = 560,
		minHeight = 360,
		resizable = true,
		collapsible = true,
		onResize = function()
			self:RefreshWindow()
		end,
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
	window.hideInput:SetPoint("TOPLEFT", window.inviteInput, "BOTTOMLEFT", 0, -8)

	window.seekInput = Form.CreateInput(content, {
		label = "Seek seconds",
		width = 92,
		numeric = true,
	})
	window.seekInput:SetPoint("TOPLEFT", window.hideInput, "TOPRIGHT", 12, 0)

	window.starRevealInput = Form.CreateInput(content, {
		label = "Star reveals",
		width = 96,
		numeric = true,
	})
	window.starRevealInput:SetPoint("TOPLEFT", window.seekInput, "TOPRIGHT", 12, 0)

	window.startRadiusInput = Form.CreateInput(content, {
		label = "Start radius",
		width = 96,
		numeric = true,
	})
	window.startRadiusInput:SetPoint("TOPLEFT", window.starRevealInput, "TOPRIGHT", 12, 0)

	window.applyButton = Form.CreateButton(content, {
		text = "Apply",
		width = 78,
		onClick = function()
			self:ApplyWindowSettings()
		end,
	})
	window.applyButton:SetPoint("LEFT", window.startRadiusInput.editBox, "RIGHT", 12, 0)

	window.seekerInput = Form.CreateInput(content, {
		label = "Seeker",
		width = 170,
		onEnterPressed = function()
			self:SetSeekerFromWindow()
		end,
	})
	window.seekerInput:SetPoint("TOPLEFT", window.hideInput, "BOTTOMLEFT", 0, -8)

	window.seekerButton = Form.CreateButton(content, {
		text = "Set",
		width = 72,
		onClick = function()
			self:SetSeekerFromWindow()
		end,
	})
	window.seekerButton:SetPoint("LEFT", window.seekerInput.editBox, "RIGHT", 12, 0)

	window.randomSeekerButton = Form.CreateButton(content, {
		text = "Random",
		width = 86,
		onClick = function()
			self:SelectSeeker("")
		end,
	})
	window.randomSeekerButton:SetPoint("LEFT", window.seekerButton, "RIGHT", 8, 0)

	window.rosterTitle = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	window.rosterTitle:SetPoint("TOPLEFT", window.seekerInput, "BOTTOMLEFT", 0, -18)
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
	window.rosterList.frame:SetPoint("RIGHT", content, "RIGHT", 0, 0)

	window.startButton = Form.CreateButton(window.footer, {
		text = "Start",
		width = 104,
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

function HideSeek:UpdateGameWindowRosterRows()
	local window = gameWindow
	if not window or not window.rosterList or not window.frame or (window.IsCollapsed and window:IsCollapsed()) then
		return
	end

	local height = window.frame.GetHeight and window.frame:GetHeight() or 0
	local visibleRows = math.floor((height - GAME_WINDOW_ROSTER_BASE_HEIGHT) / window.rosterList.rowHeight)

	if visibleRows < GAME_WINDOW_MIN_ROSTER_ROWS then
		visibleRows = GAME_WINDOW_MIN_ROSTER_ROWS
	end

	window.rosterList:SetVisibleRows(visibleRows)
end

function HideSeek:RefreshWindow()
	self:RefreshTrackerWindow()

	local window = gameWindow
	if not window or not window:IsShown() then
		return
	end

	local canHostControl = self:CanHostControl()
	local hasGame = self.gameId ~= nil
	local canStart = canHostControl
		and (self.status == STATUS_LOBBY or self.status == STATUS_ENDED)
		and self:GetPlayerCount() >= 2

	window.statusText:SetText("Game State: " .. getStatusLabel(self.status))
	window.detailText:SetText(self:GetGameDetailText())
	window.timerText:SetText(self:GetTimerText())
	self:UpdateGameWindowRosterRows()
	window.rosterList:SetItems(self:GetRosterItems())

	setInputValueIfNotFocused(window.hideInput, self.hideSeconds)
	setInputValueIfNotFocused(window.seekInput, self.seekSeconds)
	setInputValueIfNotFocused(window.starRevealInput, self.starRevealUses)
	setInputValueIfNotFocused(window.startRadiusInput, self:GetStartRadius())
	setInputValueIfNotFocused(window.seekerInput, self:GetSelectedSeeker() or "")

	setInputEnabled(window.inviteInput, canHostControl)
	setInputEnabled(window.hideInput, canHostControl)
	setInputEnabled(window.seekInput, canHostControl)
	setInputEnabled(window.starRevealInput, canHostControl)
	setInputEnabled(window.startRadiusInput, canHostControl)
	setInputEnabled(window.seekerInput, canHostControl)
	setButtonEnabled(window.inviteButton, canHostControl)
	setButtonEnabled(window.applyButton, canHostControl)
	setButtonEnabled(window.seekerButton, canHostControl)
	setButtonEnabled(window.randomSeekerButton, canHostControl)
	window.startButton:SetText(self.status == STATUS_ENDED and "Start Again" or "Start")
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

function HideSeek:SelectSeeker(name)
	if not self:EnsureHostLobby() then
		self:RefreshWindow()
		return false
	end

	return self:SetSelectedSeeker(name, true)
end

function HideSeek:SetSeekerFromWindow()
	local window = self:EnsureWindow()
	if not window then
		return false
	end

	return self:SelectSeeker(window.seekerInput:GetValue())
end

function HideSeek:ReadWindowSeeker()
	local window = gameWindow
	if not window or not window.seekerInput then
		return true
	end

	local seekerName = trim(window.seekerInput:GetValue())
	if seekerName == "" then
		self.seeker = nil
		return true
	end

	local player = self:GetPlayer(seekerName)
	if not player then
		WEP:Print("Seeker must be in the current Hide and Seek roster.")
		WEP:Log("HideSeek", "window_settings_failed", {
			gameId = self.gameId or "none",
			seeker = seekerName,
			error = "seeker not in roster",
		}, "warn")
		return false
	end

	self.seeker = player.name
	return true
end

function HideSeek:ReadWindowSettings()
	local window = gameWindow
	if not window then
		return true
	end

	self.hideSeconds = clamp(window.hideInput:GetValue(), MIN_HIDE_SECONDS, MAX_HIDE_SECONDS, self.hideSeconds)
	self.seekSeconds = clamp(window.seekInput:GetValue(), MIN_SEEK_SECONDS, MAX_SEEK_SECONDS, self.seekSeconds)
	self.starRevealUses = clamp(window.starRevealInput:GetValue(), MIN_STAR_REVEAL_USES, MAX_STAR_REVEAL_USES, self.starRevealUses)
	self.startRadius = clamp(window.startRadiusInput:GetValue(), MIN_START_RADIUS, MAX_START_RADIUS, self.startRadius)

	if not self:ReadWindowSeeker() then
		return false
	end

	WEP:Log("HideSeek", "window_settings_read", {
		hideSeconds = self.hideSeconds,
		seekSeconds = self.seekSeconds,
		starRevealUses = self.starRevealUses,
		startRadius = self.startRadius,
		seeker = self.seeker or "random",
	})
	return true
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

	if not self:ReadWindowSettings() then
		self:RefreshWindow()
		return
	end

	WEP:Print("Hide and Seek settings:", "hide", formatDuration(self.hideSeconds), "seek", formatDuration(self.seekSeconds), "start", self:GetStartRadius(), "star reveals", self.starRevealUses, "seeker", self.seeker or "random")
	WEP:Log("HideSeek", "settings_applied", {
		gameId = self.gameId or "none",
		hideSeconds = self.hideSeconds,
		seekSeconds = self.seekSeconds,
		starRevealUses = self.starRevealUses,
		startRadius = self.startRadius,
		seeker = self.seeker or "random",
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
		ru = self.starRevealUses,
		ar = self:GetStartRadius(),
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
	local starRevealUses = clamp(data.ru, MIN_STAR_REVEAL_USES, MAX_STAR_REVEAL_USES, self.starRevealUses)
	local startRadius = clamp(data.ar, MIN_START_RADIUS, MAX_START_RADIUS, self.startRadius)

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
		.. ", Start radius: "
		.. startRadius

	if starRevealUses > 0 then
		message = message .. ", Star reveals: " .. starRevealUses
	end

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
				self.starRevealUses = starRevealUses
				self.startRadius = startRadius
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

	local ok, messageIdOrErr = self:Broadcast(MSG_STATE, self:AddStartSpotPayload({
		g = self.gameId,
		h = self.host or "",
		st = self.status or STATUS_IDLE,
		sk = self.seeker or "",
		hs = self.hideSeconds,
		ss = self.seekSeconds,
		ru = self.starRevealUses,
		ns = self.nextSeeker or "",
	}, false))

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
				s = player.safe and 1 or 0,
				t = player.pendingFound and 1 or 0,
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
	self.starRevealUses = clamp(payload.ru, MIN_STAR_REVEAL_USES, MAX_STAR_REVEAL_USES, self.starRevealUses)
	self.nextSeeker = not isBlank(payload.ns) and payload.ns or nil
	self:ApplyStartSpotPayload(payload, self.status == STATUS_LOBBY or self.status == STATUS_IDLE or self.status == STATUS_ENDED)
	self:ResetRoster()
	self:RefreshWindow()
	WEP:Log("HideSeek", "state_message_applied", {
		gameId = self.gameId,
		status = self.status,
		host = self.host,
		starRevealUses = self.starRevealUses,
		startRadius = self.startRadius,
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
		self:AddPlayer(payload.p, tostring(payload.f or "") == "1", tostring(payload.s or "") == "1", tostring(payload.t or "") == "1")
	end

	self:RefreshWindow()
	WEP:Log("HideSeek", "roster_message_applied", {
		gameId = self.gameId,
		player = payload.p or "none",
		count = self:GetPlayerCount(),
	})
end

function HideSeek:OnStartSpotRequestMessage(message)
	local payload = message.payload or {}

	if payload.g ~= self.gameId or not self:IsMessageFromHost(message, payload.h or self.host) then
		WEP:Log("HideSeek", "start_spot_request_ignored", {
			sender = message.sender,
			gameId = payload.g or "none",
			reason = "game or host mismatch",
		}, "warn")
		return
	end

	if isBlank(payload.sk) or not isSelfName(payload.sk) then
		return
	end

	self.seeker = payload.sk
	self.hideSeconds = clamp(payload.hs, MIN_HIDE_SECONDS, MAX_HIDE_SECONDS, self.hideSeconds)
	self.seekSeconds = clamp(payload.ss, MIN_SEEK_SECONDS, MAX_SEEK_SECONDS, self.seekSeconds)
	self.starRevealUses = clamp(payload.ru, MIN_STAR_REVEAL_USES, MAX_STAR_REVEAL_USES, self.starRevealUses)
	self.startRadius = clamp(payload.ar, MIN_START_RADIUS, MAX_START_RADIUS, self.startRadius)

	if not self:CaptureStartSpot() then
		return
	end

	self:Broadcast(MSG_START_SPOT, self:AddStartSpotPayload({
		g = self.gameId,
		t = Timer.Now(),
	}, true))
	WEP:Print("Hide and Seek starting spot set.")
	self:RefreshWindow()
end

function HideSeek:OnStartSpotMessage(message)
	local payload = message.payload or {}

	if not self:IsHost() then
		return
	end

	if payload.g ~= self.gameId or not self:IsMessageFromSeeker(message) then
		WEP:Log("HideSeek", "start_spot_message_ignored", {
			sender = message.sender,
			gameId = payload.g or "none",
			reason = "game or seeker mismatch",
		}, "warn")
		return
	end

	if self.status ~= STATUS_LOBBY or not self.startSpotPending then
		WEP:Log("HideSeek", "start_spot_message_ignored", {
			sender = message.sender,
			gameId = payload.g or "none",
			status = self.status or "none",
			reason = "not waiting",
		}, "warn")
		return
	end

	self:ApplyStartSpotPayload(payload, true)
	if not self:HasStartSpot() then
		WEP:Log("HideSeek", "start_spot_message_ignored", {
			sender = message.sender,
			gameId = payload.g or "none",
			reason = "missing coordinates",
		}, "warn")
		WEP:Print("Hide and Seek start canceled: seeker did not send usable coordinates.")
		self.startSpotPending = false
		self:RefreshWindow()
		return
	end

	self:StartGameWithStartSpot(tonumber(payload.t) or Timer.Now())
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

function HideSeek:StartGameWithStartSpot(startedAt)
	if not self:HasStartSpot() then
		WEP:Log("HideSeek", "start_failed", {
			gameId = self.gameId or "none",
			error = "missing start spot",
		}, "error")
		WEP:Print("Could not start Hide and Seek: missing starting spot.")
		self:ShowMenu()
		return false
	end

	startedAt = tonumber(startedAt) or Timer.Now()
	self.startSpotPending = false
	self.nextSeeker = nil
	self:ClearFound()
	WEP:Log("HideSeek", "started", {
		gameId = self.gameId,
		seeker = self.seeker or "none",
		hideSeconds = self.hideSeconds,
		seekSeconds = self.seekSeconds,
		starRevealUses = self.starRevealUses,
		startRadius = self.startRadius,
		startMapId = self.startMapId,
	})
	self:BeginHiding(self.hideSeconds, self.seekSeconds, startedAt)
	self:BroadcastState()
	self:Broadcast(MSG_START, self:AddStartSpotPayload({
		g = self.gameId,
		sk = self.seeker,
		hs = self.hideSeconds,
		ss = self.seekSeconds,
		ru = self.starRevealUses,
		t = startedAt,
	}, true))

	if gameWindow then
		gameWindow:Hide()
	end

	return true
end

function HideSeek:RequestStartSpotFromSeeker(seeker)
	self.startSpotPending = true
	self.startSpotRequestToken = (self.startSpotRequestToken or 0) + 1
	local token = self.startSpotRequestToken

	local ok = self:Broadcast(MSG_START_SPOT_REQUEST, self:AddStartSpotPayload({
		g = self.gameId,
		h = self.host or Player.GetFullName(),
		sk = seeker,
		hs = self.hideSeconds,
		ss = self.seekSeconds,
		ru = self.starRevealUses,
	}, false))

	if not ok then
		self.startSpotPending = false
		self:RefreshWindow()
		return false
	end

	WEP:Print("Waiting for", seeker, "to set the Hide and Seek starting spot.")
	self:BroadcastState()
	self:RefreshWindow()

	Timer.After(START_SPOT_RESPONSE_TIMEOUT_SECONDS, function()
		if self.startSpotRequestToken == token and self.startSpotPending and self.status == STATUS_LOBBY then
			self.startSpotPending = false
			WEP:Log("HideSeek", "start_spot_request_timed_out", {
				gameId = self.gameId or "none",
				seeker = seeker or "none",
			}, "warn")
			WEP:Print("Hide and Seek start canceled: seeker did not send a starting spot.")
			self:RefreshWindow()
		end
	end)

	return true
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

	if self.startSpotPending then
		WEP:Print("Hide and Seek is waiting for the seeker to set the starting spot.")
		self:RefreshWindow()
		return
	end

	if not self:ReadWindowSettings() then
		self:ShowMenu()
		return
	end

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

	local seeker = self:GetSelectedSeeker() or self:PickRandomSeeker()
	if not seeker then
		WEP:Log("HideSeek", "start_failed", {
			gameId = self.gameId or "none",
			error = "could not choose seeker",
		}, "error")
		WEP:Print("Could not choose a seeker.")
		return
	end

	self.seeker = seeker
	self.nextSeeker = nil
	self:ClearFound()

	if self:IsSeeker() then
		if not self:CaptureStartSpot() then
			self:ShowMenu()
			return
		end

		self:StartGameWithStartSpot(Timer.Now())
		return
	end

	self:ClearStartSpot()
	self:RequestStartSpotFromSeeker(seeker)
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
	self.starRevealUses = clamp(payload.ru, MIN_STAR_REVEAL_USES, MAX_STAR_REVEAL_USES, self.starRevealUses)
	self.nextSeeker = nil
	self:ApplyStartSpotPayload(payload, true)
	if not self:HasStartSpot() then
		WEP:Log("HideSeek", "start_message_ignored", {
			sender = message.sender,
			gameId = payload.g or "none",
			reason = "missing start spot",
		}, "warn")
		WEP:Print("Hide and Seek start ignored: missing starting spot.")
		return
	end

	self:ClearFound()
	WEP:Log("HideSeek", "start_message_applied", {
		gameId = self.gameId,
		seeker = self.seeker or "none",
		starRevealUses = self.starRevealUses,
		startRadius = self.startRadius,
		startMapId = self.startMapId or "none",
	})
	self:BeginHiding(self.hideSeconds, self.seekSeconds, tonumber(payload.t) or Timer.Now())
end

function HideSeek:BeginHiding(hideSeconds, seekSeconds, startedAt)
	self.status = STATUS_HIDING
	self.seekSeconds = seekSeconds
	self.seekEndsAt = nil
	self.hideEndsAt = (tonumber(startedAt) or Timer.Now()) + hideSeconds
	self.resultReason = nil
	self:ResetStarRevealUses()
	self:CancelStarReveal()
	self:ClearAllRaidTargets()
	self.startLocationUnavailableWarned = false
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
		starRevealUses = self.starRevealUses,
		startRadius = self.startRadius,
		startMapId = self.startMapId or "none",
		remaining = remaining,
	})

	self:SetStartSpotWaypoint()

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
	self.seekerAtStartSpot = nil
	self.seekerSpotUpdatedAt = nil
	self.seekerAbsentSince = nil
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
		WEP:Print("Find a hider, target them, then return to the starting spot.")
	else
		WEP:Print("The seeker is hunting. Reach the starting spot while the seeker is away.")
	end

	Timer.After(self.seekSeconds, function()
		if self.timerToken == token and self.status == STATUS_SEEKING and self:IsHost() then
			self:FinishGame("time", true)
		end
	end)

	self:StartHomeMonitor()
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

	self:BlockSeekerTargetBindings()
	WEP:Log("HideSeek", "seeker_ui_hidden", {
		groups = #SEEKER_UI_GROUPS,
	})
end

function HideSeek:RestoreSeekerUI()
	self:RestoreSeekerTargetBindings()

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
	if not self:IsActiveHider(player) then
		return
	end

	self:TagPlayer(player.name, true)
end

function HideSeek:MarkTagged(playerName)
	local player = self:GetPlayer(playerName)
	if not self:IsActiveHider(player) then
		return nil
	end

	local wasPending = player.pendingFound == true
	player.pendingFound = true

	if not wasPending then
		WEP:Print(player.name, "was tagged. The seeker must return to the starting spot.")
		playSound("ui_select")
	end

	WEP:Log("HideSeek", "player_tagged", {
		gameId = self.gameId or "none",
		player = player.name,
	})
	self:RefreshWindow()
	return player
end

function HideSeek:TagPlayer(playerName, broadcast)
	local player = self:MarkTagged(playerName)
	if not player then
		return false
	end

	if broadcast then
		self:Broadcast(MSG_TAGGED, {
			g = self.gameId,
			p = player.name,
		})
	end

	if self:IsHost() then
		self:BroadcastState()
	end

	return true
end

function HideSeek:OnTaggedMessage(message)
	local payload = message.payload or {}

	if payload.g ~= self.gameId or self.status ~= STATUS_SEEKING or not self:IsMessageFromSeeker(message) then
		WEP:Log("HideSeek", "tagged_message_ignored", {
			sender = message.sender,
			gameId = payload.g or "none",
			reason = "state or seeker mismatch",
		}, "warn")
		return
	end

	WEP:Log("HideSeek", "tagged_message_received", {
		sender = message.sender,
		player = payload.p or "none",
		gameId = self.gameId,
	})
	if self:MarkTagged(payload.p) and self:IsHost() then
		self:BroadcastState()
	end
end

function HideSeek:MarkFound(playerName, foundBy, broadcast)
	local player = self:GetPlayer(playerName)
	if not self:IsActiveHider(player) then
		return false
	end

	player.found = true
	player.safe = false
	player.pendingFound = false
	self.nextSeeker = player.name
	WEP:Print(player.name, "was found by", foundBy or self.seeker or "the seeker")
	playSound("ui_select")
	WEP:Log("HideSeek", "player_found", {
		gameId = self.gameId or "none",
		player = player.name,
		foundBy = foundBy or self.seeker or "unknown",
		broadcast = broadcast == true,
		nextSeeker = self.nextSeeker,
	})

	if broadcast then
		self:Broadcast(MSG_FOUND, {
			g = self.gameId,
			p = player.name,
			by = foundBy or self.seeker or Player.GetFullName(),
			ns = self.nextSeeker,
		})
	end

	self:RefreshWindow()

	if self:IsHost() and self.status ~= STATUS_ENDED then
		self:FinishGame("found", true, player.name)
	end

	return true
end

function HideSeek:OnFoundMessage(message)
	local payload = message.payload or {}

	if payload.g ~= self.gameId or (not self:IsMessageFromHost(message) and not self:IsMessageFromSeeker(message)) then
		WEP:Log("HideSeek", "found_message_ignored", {
			sender = message.sender,
			gameId = payload.g or "none",
			reason = "game or sender mismatch",
		}, "warn")
		return
	end

	WEP:Log("HideSeek", "found_message_received", {
		sender = message.sender,
		player = payload.p or "none",
		gameId = self.gameId,
		nextSeeker = payload.ns or "none",
	})
	self:MarkFound(payload.p, payload.by or message.sender, false)

	if payload.p and isSelfName(payload.p) then
		WEP:Print("You were found.")
	end
end

function HideSeek:MarkSafe(playerName, broadcast)
	local player = self:GetPlayer(playerName)
	if not self:IsActiveHider(player) then
		return false
	end

	player.safe = true
	player.pendingFound = false
	WEP:Print(player.name, "reached the starting spot and is safe.")
	playSound("ui_select")
	WEP:Log("HideSeek", "player_safe", {
		gameId = self.gameId or "none",
		player = player.name,
		broadcast = broadcast == true,
	})

	if broadcast then
		self:BroadcastState()
	end

	self:RefreshWindow()

	if self:IsHost() and self.status ~= STATUS_ENDED and self:AllHidersSafe() then
		self:FinishGame("safe", true)
	end

	return true
end

function HideSeek:ProcessSafeRequest(playerName, senderName)
	if not self:IsHost() or self.status ~= STATUS_SEEKING then
		return false
	end

	if isBlank(playerName) or not namesMatch(playerName, senderName) then
		WEP:Log("HideSeek", "safe_request_ignored", {
			player = playerName or "none",
			sender = senderName or "none",
			reason = "sender mismatch",
		}, "warn")
		return false
	end

	local player = self:GetPlayer(playerName)
	if not self:IsActiveHider(player) then
		return false
	end

	if not self:IsSeekerAbsentForSafe() then
		WEP:Log("HideSeek", "safe_request_ignored", {
			gameId = self.gameId or "none",
			player = player.name,
			seekerAtStart = self.seekerAtStartSpot == true,
			seekerSpotUpdatedAt = self.seekerSpotUpdatedAt or "none",
			reason = "seeker not absent",
		}, "warn")
		return false
	end

	return self:MarkSafe(player.name, true)
end

function HideSeek:OnSafeMessage(message)
	local payload = message.payload or {}

	if not self:IsHost() then
		return
	end

	if payload.g ~= self.gameId then
		WEP:Log("HideSeek", "safe_message_ignored", {
			sender = message.sender,
			gameId = payload.g or "none",
			reason = "game mismatch",
		}, "warn")
		return
	end

	local playerName = payload.p or message.sender
	if not messageSentBy(message, playerName) then
		WEP:Log("HideSeek", "safe_message_ignored", {
			sender = message.sender,
			player = playerName or "none",
			reason = "sender mismatch",
		}, "warn")
		return
	end

	self:ProcessSafeRequest(playerName, message.sender)
end

function HideSeek:OnSeekerSpotMessage(message)
	local payload = message.payload or {}

	if payload.g ~= self.gameId or not self:IsMessageFromSeeker(message) then
		WEP:Log("HideSeek", "seeker_spot_message_ignored", {
			sender = message.sender,
			gameId = payload.g or "none",
			reason = "game or seeker mismatch",
		}, "warn")
		return
	end

	if self.status ~= STATUS_SEEKING then
		WEP:Log("HideSeek", "seeker_spot_message_ignored", {
			sender = message.sender,
			gameId = payload.g or "none",
			status = self.status or "none",
			reason = "not seeking",
		}, "warn")
		return
	end

	local atStart = tostring(payload.at or "") == "1"
	self:UpdateSeekerSpotState(atStart, tonumber(payload.t) or Timer.Now())

	if self:IsHost() and atStart then
		WEP:Log("HideSeek", "seeker_at_start", {
			gameId = self.gameId,
			seeker = self.seeker or "none",
		})
		self:ConfirmPendingFoundAtStart()
	end
end

function HideSeek:FinishGame(reason, broadcast, nextSeeker)
	if not self.gameId then
		WEP:Log("HideSeek", "finish_skipped", {
			reason = "no game id",
		}, "warn")
		return
	end

	self.status = STATUS_ENDED
	self.resultReason = reason or "ended"
	if not isBlank(nextSeeker) then
		self.nextSeeker = nextSeeker
	end
	self.timerToken = (self.timerToken or 0) + 1
	self:StopHomeMonitor()
	self:ClearStartSpotWaypoint()
	self:HideCountdown()
	ScreenOverlay.HideBlackout()
	self:RestoreSeekerUI()
	self:CancelStarReveal()
	self.hideEndsAt = nil
	self.seekEndsAt = nil
	WEP:Log("HideSeek", "finished", {
		gameId = self.gameId,
		reason = self.resultReason,
		broadcast = broadcast == true,
		nextSeeker = self.nextSeeker or "none",
	})

	if reason == "found" then
		WEP:Print("Hide and Seek ended: seeker wins.")
		if self.nextSeeker then
			WEP:Print("Next seeker:", self.nextSeeker)
		end
	elseif reason == "safe" then
		WEP:Print("Hide and Seek ended: hiders win.")
	elseif reason == "time" then
		WEP:Print("Hide and Seek ended: hiders win.")
	else
		WEP:Print("Hide and Seek ended.")
	end

	if broadcast then
		self:Broadcast(MSG_END, {
			g = self.gameId,
			r = reason or "ended",
			ns = self.nextSeeker or "",
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
		nextSeeker = payload.ns or "none",
	})
	self:FinishGame(payload.r or "ended", false, payload.ns)
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
	elseif self:AllHidersSafe() then
		self:FinishGame("safe", true)
	else
		self:BroadcastState()
	end
end

function HideSeek:ResetGame()
	local previousGameId = self.gameId
	self:StopHomeMonitor()
	self:HideCountdown()
	ScreenOverlay.HideBlackout()
	self:RestoreSeekerUI()
	self:CancelStarReveal()
	self.status = STATUS_IDLE
	self.gameId = nil
	self.host = nil
	self.seeker = nil
	self.seekEndsAt = nil
	self.hideEndsAt = nil
	self.resultReason = nil
	self.nextSeeker = nil
	self.starRevealUsesRemaining = 0
	self:ClearStartSpot()
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
	WEP:Print("Start:", self:GetStartSpotDetailText())
	WEP:Print("Star reveal:", self:GetStarRevealText())
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
		self:StopHomeMonitor()
		self:HideCountdown()
		ScreenOverlay.HideBlackout()
		self:RestoreSeekerUI()
		self:CancelStarReveal()
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
