local _, WEP = ...

local ToolDebug = {}
WEP.ToolDebug = ToolDebug

local Timer = WEP.Tools.Timer
local Player = WEP.Tools.Player
local ChatChannels = WEP.Tools.ChatChannels
local ScreenOverlay = WEP.Tools.ScreenOverlay
local UIVisibility = WEP.Tools.UIVisibility
local Requests = WEP.Tools.Requests
local Environment = WEP.Tools.Environment

local function joinArgs(args, startIndex)
	local values = {}

	for index = startIndex, #args do
		values[#values + 1] = args[index]
	end

	return table.concat(values, " ")
end

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

local function parseKeyValueArgs(args, startIndex)
	local data = {}

	for index = startIndex, #args do
		local arg = args[index]
		local equalsIndex = arg:find("=", 1, true)

		if not equalsIndex or equalsIndex == 1 then
			return nil, "expected key=value at argument " .. index
		end

		local key = arg:sub(1, equalsIndex - 1)
		local value = arg:sub(equalsIndex + 1)

		data[key] = value
	end

	return data
end

local function formatData(data)
	local parts = {}

	for key, value in pairs(data or {}) do
		parts[#parts + 1] = tostring(key) .. "=" .. tostring(value)
	end

	table.sort(parts)

	if #parts == 0 then
		return "none"
	end

	return table.concat(parts, ", ")
end

local function formatOptional(value)
	if value == nil or value == "" then
		return "none"
	end

	return tostring(value)
end

local function formatUnitSummary(unit)
	local healthPercent = unit.health and unit.health.percent and (unit.health.percent .. "%") or "unknown"
	local level = unit.level and tostring(unit.level) or "unknown"
	local reaction = unit.reactionLabel or "unknown"
	local npcId = unit.npcId and (" npc:" .. unit.npcId) or ""

	return unit.unit
		.. " "
		.. (unit.name or "Unknown")
		.. " level:"
		.. level
		.. " "
		.. reaction
		.. " hp:"
		.. healthPercent
		.. npcId
end

function ToolDebug:Initialize()
	if self.initialized then
		return
	end

	self.initialized = true

	if Requests then
		Requests.RegisterRequestHandler("debug", function(request)
			WEP:Print(
				"Debug request:",
				request.id,
				"type:",
				request.type,
				"from:",
				request.sender,
				"data:",
				formatData(request.data)
			)
		end)

		Requests.RegisterResponseHandler("debug", function(response)
			WEP:Print(
				"Debug response:",
				response.id,
				"status:",
				response.status,
				"from:",
				response.sender,
				"data:",
				formatData(response.data)
			)
		end)
	end
end

function ToolDebug:HandleSlash(args)
	local toolName = args[2]

	if not toolName or toolName == "help" then
		self:PrintHelp()
		return
	end

	if toolName == "list" then
		self:PrintList()
		return
	end

	if toolName == "player" then
		self:PrintPlayer()
		return
	end

	if toolName == "timer" then
		self:HandleTimer(args)
		return
	end

	if toolName == "chat" or toolName == "chatchannels" then
		self:HandleChatChannels(args)
		return
	end

	if toolName == "overlay" or toolName == "screen" or toolName == "screenoverlay" then
		self:HandleScreenOverlay(args)
		return
	end

	if toolName == "ui" or toolName == "visibility" then
		self:HandleUIVisibility(args)
		return
	end

	if toolName == "environment" or toolName == "env" then
		self:HandleEnvironment(args)
		return
	end

	if toolName == "request" or toolName == "requests" then
		self:HandleRequests(args)
		return
	end

	WEP:Print("Unknown tool:", toolName)
	self:PrintList()
end

function ToolDebug.PrintHelp()
	WEP:Print("Tool debug commands:")
	WEP:Print("/wep tools list - List testable tools.")
	WEP:Print("/wep tools player - Print player tool values.")
	WEP:Print("/wep tools timer now - Print Timer.Now().")
	WEP:Print("/wep tools timer after [seconds] - Schedule a timer callback.")
	WEP:Print("/wep tools chat normalize <channel> - Normalize a chat channel name.")
	WEP:Print("/wep tools chat getid <channel> - Print a chat channel id.")
	WEP:Print("/wep tools overlay blackout <0-100> - Set blackout percentage.")
	WEP:Print("/wep tools overlay hide - Hide the blackout overlay.")
	WEP:Print("/wep tools overlay status - Print the current blackout percentage.")
	WEP:Print("/wep tools ui hide|show|toggle all - Control full UI visibility.")
	WEP:Print("/wep tools ui hide|show|toggle <group> - Control a UI group.")
	WEP:Print("/wep tools ui show managed - Restore all managed UI groups.")
	WEP:Print("/wep tools ui groups|status - Inspect UI visibility state.")
	WEP:Print("/wep tools environment status - Print environment summary.")
	WEP:Print("/wep tools environment location - Print location details.")
	WEP:Print("/wep tools environment unit [unit] - Print one unit, default target.")
	WEP:Print("/wep tools environment units [limit] - Print visible/addressable units.")
	WEP:Print("/wep tools request send <target|*> <type> [key=value ...] - Send a request.")
	WEP:Print("/wep tools request respond <id> <target> <status> [key=value ...] - Send a response.")
	WEP:Print("/wep tools request status - Print request tool state.")
end

function ToolDebug.PrintList()
	WEP:Print("Testable tools: player, timer, chat, overlay, ui, environment, request.")
end

function ToolDebug.PrintPlayer()
	WEP:Print("Player short:", Player.GetShortName())
	WEP:Print("Player full:", Player.GetFullName())
	WEP:Print("Player realm:", Player.GetRealmToken())
end

function ToolDebug:HandleTimer(args)
	local action = args[3] or "now"

	if action == "now" then
		WEP:Print("Timer.Now:", Timer.Now())
		return
	end

	if action == "after" then
		local delay = clamp(args[4], 0, 60)
		WEP:Print("Timer scheduled:", delay, "seconds.")

		Timer.After(delay, function()
			WEP:Print("Timer fired after", delay, "seconds.")
		end)
		return
	end

	WEP:Print("Usage: /wep tools timer now|after [seconds]")
end

function ToolDebug:HandleChatChannels(args)
	local action = args[3]
	local channelName = joinArgs(args, 4)

	if not action or channelName == "" then
		WEP:Print("Usage: /wep tools chat normalize|getid <channel>")
		return
	end

	if action == "normalize" then
		WEP:Print("Normalized channel:", ChatChannels.NormalizeName(channelName) or "nil")
		return
	end

	if action == "getid" then
		WEP:Print("Channel id:", ChatChannels.GetId(channelName))
		return
	end

	WEP:Print("Usage: /wep tools chat normalize|getid <channel>")
end

function ToolDebug:HandleScreenOverlay(args)
	local action = args[3] or "status"

	if action == "blackout" then
		local percentage = clamp(args[4], 0, 100)
		local ok = ScreenOverlay.SetBlackoutPercentage(percentage)

		if ok then
			WEP:Print("Blackout percentage:", ScreenOverlay.GetBlackoutPercentage())
		else
			WEP:Print("Blackout overlay unavailable.")
		end

		return
	end

	if action == "hide" then
		ScreenOverlay.HideBlackout()
		WEP:Print("Blackout overlay hidden.")
		return
	end

	if action == "status" then
		WEP:Print("Blackout percentage:", ScreenOverlay.GetBlackoutPercentage())
		return
	end

	WEP:Print("Usage: /wep tools overlay blackout <0-100>|hide|status")
end

function ToolDebug:HandleUIVisibility(args)
	if not UIVisibility then
		WEP:Print("UI visibility tool unavailable.")
		return
	end

	local action = args[3] or "status"
	local target = args[4]

	if action == "hide" then
		if target == "all" then
			local ok, state = UIVisibility.HideAll()
			self:PrintUIVisibilityResult(ok, state, "all")
			return
		end

		if target then
			local ok, state, groupName = UIVisibility.Hide(target)
			self:PrintUIVisibilityResult(ok, state, groupName or target)
			return
		end
	end

	if action == "show" then
		if target == "all" then
			local ok, state = UIVisibility.ShowAll()
			self:PrintUIVisibilityResult(ok, state, "all")
			return
		end

		if target == "managed" then
			local ok, state = UIVisibility.ShowEverythingManaged()
			self:PrintUIVisibilityResult(ok, state, "managed")
			return
		end

		if target then
			local ok, state, groupName = UIVisibility.Show(target)
			self:PrintUIVisibilityResult(ok, state, groupName or target)
			return
		end
	end

	if action == "toggle" then
		if target == "all" then
			local ok, state = UIVisibility.ToggleAll()
			self:PrintUIVisibilityResult(ok, state, "all")
			return
		end

		if target then
			local ok, state, groupName = UIVisibility.Toggle(target)
			self:PrintUIVisibilityResult(ok, state, groupName or target)
			return
		end
	end

	if action == "groups" then
		self:PrintUIVisibilityGroups()
		return
	end

	if action == "status" then
		self:PrintUIVisibilityStatus()
		return
	end

	WEP:Print("Usage: /wep tools ui hide|show|toggle all|<group>")
	WEP:Print("Usage: /wep tools ui show managed")
	WEP:Print("Usage: /wep tools ui groups|status")
end

function ToolDebug:PrintUIVisibilityResult(ok, state, target)
	if not ok then
		WEP:Print("UI visibility failed:", state)
		return
	end

	if state == "queued" then
		WEP:Print("UI visibility queued until combat ends:", formatOptional(target))
		return
	end

	WEP:Print("UI visibility applied:", formatOptional(target))
end

function ToolDebug.PrintUIVisibilityGroups()
	WEP:Print("UI visibility groups:", table.concat(UIVisibility.GetGroupNames(), ", "))
end

function ToolDebug.PrintUIVisibilityStatus()
	local status = UIVisibility.GetStatus()

	WEP:Print(
		"Full UI:",
		status.allHidden and "hidden" or "shown",
		"tracked:",
		status.trackedAllHidden and "hidden" or "shown",
		"pending:",
		status.pendingCount
	)

	for _, group in ipairs(status.groups) do
		WEP:Print(
			"UI group:",
			group.name,
			group.hidden and "hidden" or "shown",
			"frames:",
			group.frameCount
		)
	end
end

function ToolDebug:HandleEnvironment(args)
	if not Environment then
		WEP:Print("Environment tool unavailable.")
		return
	end

	local action = args[3] or "status"

	if action == "status" then
		local status = Environment.GetStatus()
		local location = status.location

		WEP:Print(
			"Environment:",
			formatOptional(location.zone),
			"subzone:",
			formatOptional(location.subZone),
			"map:",
			formatOptional(location.mapId),
			"coords:",
			formatOptional(location.x),
			formatOptional(location.y)
		)
		WEP:Print(
			"Units:",
			status.unitCount,
			"target:",
			status.hasTarget and "yes" or "no",
			"mouseover:",
			status.hasMouseover and "yes" or "no",
			"focus:",
			status.hasFocus and "yes" or "no"
		)
		return
	end

	if action == "location" then
		self:PrintEnvironmentLocation()
		return
	end

	if action == "unit" then
		self:PrintEnvironmentUnit(args[4] or "target")
		return
	end

	if action == "units" then
		self:PrintEnvironmentUnits(math.floor(clamp(args[4], 1, 20)))
		return
	end

	WEP:Print("Usage: /wep tools environment status|location|unit [unit]|units [limit]")
end

function ToolDebug.PrintEnvironmentLocation()
	local location = Environment.GetLocation()
	local instance = location.instance
	local flags = location.flags

	WEP:Print(
		"Location:",
		formatOptional(location.zone),
		"subzone:",
		formatOptional(location.subZone),
		"real:",
		formatOptional(location.realZone)
	)
	WEP:Print(
		"Map:",
		formatOptional(location.mapId),
		"coords:",
		formatOptional(location.x),
		formatOptional(location.y),
		"pvp:",
		formatOptional(location.pvp.type)
	)
	WEP:Print(
		"Instance:",
		instance.inInstance and "yes" or "no",
		formatOptional(instance.name),
		formatOptional(instance.type),
		"difficulty:",
		formatOptional(instance.difficultyName)
	)
	WEP:Print(
		"Flags:",
		"resting=" .. tostring(flags.resting),
		"indoors=" .. tostring(flags.indoors),
		"outdoors=" .. tostring(flags.outdoors),
		"swimming=" .. tostring(flags.swimming),
		"mounted=" .. tostring(flags.mounted)
	)
end

function ToolDebug.PrintEnvironmentUnit(unitToken)
	local unit = Environment.GetUnit(unitToken)

	if not unit then
		WEP:Print("No unit found for token:", unitToken)
		return
	end

	WEP:Print(formatUnitSummary(unit))
	WEP:Print(
		"Unit details:",
		"guidType:",
		formatOptional(unit.guidType),
		"creature:",
		formatOptional(unit.creatureType),
		"classification:",
		formatOptional(unit.classification)
	)
	WEP:Print(
		"Unit flags:",
		"player=" .. tostring(unit.isPlayer),
		"enemy=" .. tostring(unit.isEnemy),
		"friend=" .. tostring(unit.isFriend),
		"combat=" .. tostring(unit.inCombat),
		"target=" .. formatOptional(unit.targetName)
	)
end

function ToolDebug.PrintEnvironmentUnits(limit)
	local units = Environment.GetUnits()

	WEP:Print("Environment units:", #units, "showing:", math.min(#units, limit))

	for index = 1, math.min(#units, limit) do
		WEP:Print(formatUnitSummary(units[index]))
	end

	if #units > limit then
		WEP:Print("Additional units omitted:", #units - limit)
	end
end

function ToolDebug:HandleRequests(args)
	if not Requests then
		WEP:Print("Request tool unavailable.")
		return
	end

	local action = args[3] or "status"

	if action == "send" then
		local target = args[4]
		local requestType = args[5]

		if not target or not requestType then
			WEP:Print("Usage: /wep tools request send <target|*> <type> [key=value ...]")
			return
		end

		local data, dataErr = parseKeyValueArgs(args, 6)
		if not data then
			WEP:Print("Request data error:", dataErr)
			return
		end

		local ok, requestIdOrErr = Requests.Send(target, requestType, data)
		if not ok then
			WEP:Print("Request send failed:", requestIdOrErr)
			return
		end

		WEP:Print("Request sent:", requestIdOrErr, "type:", requestType, "target:", target)
		return
	end

	if action == "respond" then
		local requestId = args[4]
		local target = args[5]
		local status = args[6]

		if not requestId or not target or not status then
			WEP:Print("Usage: /wep tools request respond <id> <target> <status> [key=value ...]")
			return
		end

		local data, dataErr = parseKeyValueArgs(args, 7)
		if not data then
			WEP:Print("Response data error:", dataErr)
			return
		end

		local ok, messageIdOrErr = Requests.Respond(requestId, target, status, data)
		if not ok then
			WEP:Print("Request response failed:", messageIdOrErr)
			return
		end

		WEP:Print("Request response sent:", messageIdOrErr, "for:", requestId, "status:", status)
		return
	end

	if action == "status" then
		self:PrintRequestStatus()
		return
	end

	WEP:Print("Usage: /wep tools request send|respond|status")
end

function ToolDebug.PrintRequestStatus()
	local status = Requests.GetStatus()

	WEP:Print(
		"Requests sent:",
		status.stats.sent,
		"received:",
		status.stats.received,
		"responses sent:",
		status.stats.responsesSent,
		"responses received:",
		status.stats.responsesReceived,
		"ignored:",
		status.stats.ignored
	)
	WEP:Print("Pending outgoing:", status.pendingOutgoingCount, "received requests:", status.receivedRequestCount)

	for requestId, request in pairs(status.pendingOutgoing) do
		WEP:Print("Pending:", requestId, "type:", request.type, "target:", request.target)
	end

	for requestId, request in pairs(status.receivedRequests) do
		WEP:Print("Received:", requestId, "type:", request.type, "from:", request.sender)
	end
end

WEP:RegisterModule("ToolDebug", ToolDebug)
