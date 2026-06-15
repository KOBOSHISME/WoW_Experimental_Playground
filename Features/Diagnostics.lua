local _, WEP = ...

local Diagnostics = {
	pendingPings = {},
}

WEP.Diagnostics = Diagnostics

local Timer = WEP.Tools.Timer
local Text = WEP.Utils.Text

local function splitCommand(input)
	local args = {}

	for word in Text.Trim(input):gmatch("%S+") do
		args[#args + 1] = string.lower(word)
	end

	return args
end

local function formatOnOff(value)
	return value and "on" or "off"
end

WEP:Log("Diagnostics", "loaded")

function Diagnostics:Initialize()
	if self.initialized then
		return
	end

	self.initialized = true
	WEP:Log("Diagnostics", "initialize")

	WEP.Comm:RegisterHandler("PING", function(message)
		self:OnPing(message)
	end)

	WEP.Comm:RegisterHandler("PONG", function(message)
		self:OnPong(message)
	end)

	SLASH_WOWEXPERIMENTALPLAYGROUND1 = "/wep"
	SlashCmdList.WOWEXPERIMENTALPLAYGROUND = function(input)
		self:HandleSlash(input)
	end
end

function Diagnostics:HandleSlash(input)
	local args = splitCommand(input)
	WEP:Log("Diagnostics", "slash", {
		input = input or "",
	})

	if not args[1] then
		self:ShowDefaultUI()
		return
	end

	if args[1] == "help" then
		self:PrintHelp()
		return
	end

	if args[1] == "logs" or args[1] == "log" then
		self:HandleLogs(args)
		return
	end

	if args[1] == "tools" or args[1] == "tool" then
		if WEP.ToolDebug and WEP.ToolDebug.HandleSlash then
			WEP.ToolDebug:HandleSlash(args)
		else
			WEP:Print("Tool debug feature is unavailable.")
		end

		return
	end

	if args[1] == "hide" or args[1] == "hideseek" or args[1] == "hideandseek" then
		if WEP.HideSeek and WEP.HideSeek.HandleSlash then
			WEP.HideSeek:HandleSlash(args)
		else
			WEP:Print("Hide and Seek feature is unavailable.")
		end

		return
	end

	if args[1] == "interfere" or args[1] == "interference" or args[1] == "prank" then
		if WEP.PartyInterference and WEP.PartyInterference.HandleSlash then
			WEP.PartyInterference:HandleSlash(args)
		else
			WEP:Print("Party Interference feature is unavailable.")
		end

		return
	end

	if args[1] == "sounds" or args[1] == "soundevents" then
		if WEP.SoundEvents and WEP.SoundEvents.HandleSlash then
			WEP.SoundEvents:HandleSlash(args)
		else
			WEP:Print("Sound Events feature is unavailable.")
		end

		return
	end

	if args[1] == "debug" and (args[2] == "tools" or args[2] == "tool") then
		local toolArgs = {
			"tools",
		}

		for index = 3, #args do
			toolArgs[#toolArgs + 1] = args[index]
		end

		if WEP.ToolDebug and WEP.ToolDebug.HandleSlash then
			WEP.ToolDebug:HandleSlash(toolArgs)
		else
			WEP:Print("Tool debug feature is unavailable.")
		end

		return
	end

	if args[1] == "comm" then
		if args[2] == "status" then
			self:PrintStatus()
			return
		end

		if args[2] == "ping" then
			self:SendPing()
			return
		end

		if args[2] == "debug" then
			self:ToggleDebug(args[3])
			return
		end
	end

	self:PrintHelp()
end

function Diagnostics:ShowDefaultUI()
	WEP:Log("Diagnostics", "show_default_ui")

	if WEP.FeaturePanel and WEP.FeaturePanel.ShowWindow then
		WEP.FeaturePanel:ShowWindow()
	else
		self:PrintHelp()
	end
end

function Diagnostics.PrintHelp()
	WEP:Print("Commands:")
	WEP:Print("/wep - Open the feature panel.")
	WEP:Print("/wep logs [limit] - Show recent WEP logs.")
	WEP:Print("/wep logs clear - Clear saved WEP logs.")
	WEP:Print("/wep logs echo on|off - Print new log entries to chat.")
	WEP:Print("/wep comm status - Show communication status.")
	WEP:Print("/wep comm ping - Send a hidden discovery ping.")
	WEP:Print("/wep comm debug [on|off] - Toggle communication debug messages.")
	WEP:Print("/wep hide - Open Hide and Seek.")
	WEP:Print("/wep interfere - Open Party Interference.")
	WEP:Print("/wep sounds - Open Sound Events.")
	WEP:Print("/wep tools help - Show tool debug commands.")
end

function Diagnostics:HandleLogs(args)
	local action = args[2]

	if action == "clear" then
		local count = WEP:ClearLogs()
		WEP:Print("Cleared WEP logs:", count)
		return
	end

	if action == "echo" then
		WEP.db.log = WEP.db.log or {}

		if args[3] == "on" then
			WEP.db.log.echo = true
		elseif args[3] == "off" then
			WEP.db.log.echo = false
		else
			WEP.db.log.echo = not WEP.db.log.echo
		end

		WEP:Log("Diagnostics", "log_echo_toggled", {
			enabled = WEP.db.log.echo == true,
		})
		WEP:Print("Log echo:", formatOnOff(WEP.db.log.echo == true))
		return
	end

	local limit = tonumber(action) or 10
	if limit < 1 then
		limit = 1
	end

	local logs = WEP:GetLogs(limit)
	WEP:Print("Recent WEP logs:", #logs)

	for _, entry in ipairs(logs) do
		WEP:Print(WEP:FormatLogEntry(entry))
	end
end

function Diagnostics.PrintStatus()
	local status = WEP.Comm:GetStatus()
	WEP:Log("Diagnostics", "comm_status", {
		activeChannel = status.activeChannel or "none",
		enabled = status.enabled,
		queueSize = status.queueSize,
	})

	WEP:Print("Comm enabled:", formatOnOff(status.enabled), "debug:", formatOnOff(status.debug))
	WEP:Print("Discovery channel:", formatOnOff(status.discoveryChannel), "active:", status.activeChannel or "none")
	WEP:Print(
		"Addon messages:",
		formatOnOff(status.addonMessages),
		"prefix",
		status.addonPrefix,
		status.addonPrefixRegistered and "registered" or "not registered"
	)
	WEP:Print(
		"Queue:",
		status.queueSize .. "/" .. status.queueLimit,
		"sent:",
		status.stats.sent,
		"received:",
		status.stats.received,
		"duplicates:",
		status.stats.duplicates,
		"dropped:",
		status.stats.dropped
	)

	for _, channel in ipairs(status.channels) do
		local channelState = channel.joined and ("joined #" .. channel.id) or "not joined"
		WEP:Print("Channel", channel.name .. ":", channelState)
	end

	if status.lastError then
		WEP:Print("Last comm warning:", status.lastError)
	end
end

function Diagnostics.ToggleDebug(_, value)
	if value == "on" then
		WEP.db.comm.debug = true
	elseif value == "off" then
		WEP.db.comm.debug = false
	else
		WEP.db.comm.debug = not WEP.db.comm.debug
	end

	WEP:Log("Diagnostics", "comm_debug_toggled", {
		enabled = WEP.db.comm.debug,
	})
	WEP:Print("Comm debug:", formatOnOff(WEP.db.comm.debug))
end

function Diagnostics:SendPing()
	WEP:Log("Diagnostics", "ping_send_start")

	local ok, messageIdOrErr = WEP.Comm:Send("PING", {
		source = "slash",
	}, WEP.Comm:GetDefaultBroadcastOptions())

	if not ok then
		WEP:Log("Diagnostics", "ping_send_failed", {
			error = messageIdOrErr,
		}, "error")
		WEP:Print("PING failed:", messageIdOrErr)
		return
	end

	self.pendingPings[messageIdOrErr] = {
		sentAt = Timer.Now(),
		responses = 0,
	}

	WEP:Print("PING queued.")
	WEP:Log("Diagnostics", "ping_queued", {
		messageId = messageIdOrErr,
	})

	Timer.After(5, function()
		local pendingPing = self.pendingPings[messageIdOrErr]

		if pendingPing then
			if pendingPing.responses == 0 then
				WEP:Log("Diagnostics", "ping_no_responses", {
					messageId = messageIdOrErr,
				}, "warn")
				WEP:Print("No PONG responses received.")
			end

			self.pendingPings[messageIdOrErr] = nil
		end
	end)
end

function Diagnostics.OnPing(_, message)
	WEP:Debug("PING from", message.sender, "via", message.transport)
	WEP:Log("Diagnostics", "ping_received", {
		sender = message.sender,
		transport = message.transport,
	})

	local delay = 0.2 + (math.random() * 0.8)

	Timer.After(delay, function()
		WEP.Comm:Send("PONG", {
			replyTo = message.id,
		}, WEP.Comm:GetDefaultBroadcastOptions())
	end)
end

function Diagnostics:OnPong(message)
	local payload = message.payload
	local replyTo = type(payload) == "table" and payload.replyTo or nil

	if not replyTo or not self.pendingPings[replyTo] then
		WEP:Debug("Unmatched PONG from", message.sender)
		WEP:Log("Diagnostics", "pong_unmatched", {
			sender = message.sender,
			replyTo = replyTo or "none",
		}, "warn")
		return
	end

	local pendingPing = self.pendingPings[replyTo]
	pendingPing.responses = pendingPing.responses + 1

	WEP:Log("Diagnostics", "pong_received", {
		sender = message.sender,
		replyTo = replyTo,
		responses = pendingPing.responses,
	})
	WEP:Print("PONG from", message.sender, "via", message.transport)
end

WEP:RegisterModule("Diagnostics", Diagnostics)
