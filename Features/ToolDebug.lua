local _, WEP = ...

local ToolDebug = {}
WEP.ToolDebug = ToolDebug

local Timer = WEP.Tools.Timer
local Player = WEP.Tools.Player
local ChatChannels = WEP.Tools.ChatChannels
local ScreenOverlay = WEP.Tools.ScreenOverlay

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

function ToolDebug:Initialize()
	if self.initialized then
		return
	end

	self.initialized = true
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
end

function ToolDebug.PrintList()
	WEP:Print("Testable tools: player, timer, chat, overlay.")
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

WEP:RegisterModule("ToolDebug", ToolDebug)
