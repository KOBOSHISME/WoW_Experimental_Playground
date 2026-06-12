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

function Diagnostics:Initialize()
	if self.initialized then
		return
	end

	self.initialized = true

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

function Diagnostics.PrintHelp()
	WEP:Print("Commands:")
	WEP:Print("/wep comm status - Show communication status.")
	WEP:Print("/wep comm ping - Send a hidden discovery ping.")
	WEP:Print("/wep comm debug [on|off] - Toggle communication debug messages.")
end

function Diagnostics.PrintStatus()
	local status = WEP.Comm:GetStatus()

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

	WEP:Print("Comm debug:", formatOnOff(WEP.db.comm.debug))
end

function Diagnostics:SendPing()
	local ok, messageIdOrErr = WEP.Comm:Send("PING", {
		source = "slash",
	}, {
		transport = "CHANNEL",
	})

	if not ok then
		WEP:Print("PING failed:", messageIdOrErr)
		return
	end

	self.pendingPings[messageIdOrErr] = {
		sentAt = Timer.Now(),
		responses = 0,
	}

	WEP:Print("PING queued on hidden discovery channel.")

	Timer.After(5, function()
		local pendingPing = self.pendingPings[messageIdOrErr]

		if pendingPing then
			if pendingPing.responses == 0 then
				WEP:Print("No PONG responses received.")
			end

			self.pendingPings[messageIdOrErr] = nil
		end
	end)
end

function Diagnostics.OnPing(_, message)
	WEP:Debug("PING from", message.sender, "via", message.transport)

	local delay = 0.2 + (math.random() * 0.8)

	Timer.After(delay, function()
		WEP.Comm:Send("PONG", {
			replyTo = message.id,
		}, {
			transport = "CHANNEL",
		})
	end)
end

function Diagnostics:OnPong(message)
	local payload = message.payload
	local replyTo = type(payload) == "table" and payload.replyTo or nil

	if not replyTo or not self.pendingPings[replyTo] then
		WEP:Debug("Unmatched PONG from", message.sender)
		return
	end

	local pendingPing = self.pendingPings[replyTo]
	pendingPing.responses = pendingPing.responses + 1

	WEP:Print("PONG from", message.sender, "via", message.transport)
end

WEP:RegisterModule("Diagnostics", Diagnostics)
