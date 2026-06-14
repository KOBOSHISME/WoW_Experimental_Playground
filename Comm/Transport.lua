local _, WEP = ...

local Comm = {
	handlers = {},
	sendQueue = {},
	seenMessages = {},
	channelNames = {},
	channelLookup = {},
	joinedChannels = {},
	stats = {
		sent = 0,
		received = 0,
		dropped = 0,
		duplicates = 0,
	},
}

WEP.Comm = Comm

WEP:Log("Comm", "loaded")

local ADDON_PREFIX = "WEPXP"
local DISCOVERY_FALLBACK_CHANNEL = "wepcomm"
local MAX_QUEUE_SIZE = 50
local SEND_INTERVAL_SECONDS = 0.35
local SEEN_MESSAGE_TTL_SECONDS = 300
local CHANNEL_RETRY_LIMIT = 2
local OLD_DISCOVERY_CHANNEL_PATTERN = "^wep%x%x%x%x%x%x%x%x$"

local VALID_ADDON_DISTRIBUTIONS = {
	PARTY = true,
	RAID = true,
	GUILD = true,
	WHISPER = true,
}

local Timer = WEP.Tools.Timer
local Player = WEP.Tools.Player
local ChatChannels = WEP.Tools.ChatChannels
local Hash = WEP.Utils.Hash

local function getDateParts()
	if C_DateAndTime and C_DateAndTime.GetCurrentCalendarTime then
		local currentTime = C_DateAndTime.GetCurrentCalendarTime()
		if currentTime and currentTime.year and currentTime.month and currentTime.monthDay then
			return currentTime.year, currentTime.month, currentTime.monthDay
		end
	end

	if date then
		local localDate = date("*t")
		if localDate then
			return localDate.year, localDate.month, localDate.day
		end
	end

	return 1970, 1, 1
end

function Comm:Initialize()
	if self.initialized then
		return
	end

	self.initialized = true
	WEP:Log("Comm", "initialize", {
		enabled = WEP.db.comm.enabled,
		discoveryChannel = WEP.db.comm.discoveryChannel,
		addonMessages = WEP.db.comm.addonMessages,
	})
	self.frame = CreateFrame("Frame")
	self.frame:SetScript("OnEvent", function(_, event, ...)
		self:OnEvent(event, ...)
	end)

	self.channelNames = self:GenerateDiscoveryChannels()
	self.channelLookup = ChatChannels.BuildLookup(self.channelNames)

	if WEP.db.comm.enabled then
		self.frame:RegisterEvent("PLAYER_ENTERING_WORLD")

		if WEP.db.comm.discoveryChannel then
			self.frame:RegisterEvent("CHAT_MSG_CHANNEL")
			self:JoinDiscoveryChannels()
		end

		if WEP.db.comm.addonMessages then
			self.frame:RegisterEvent("CHAT_MSG_ADDON")
			self:RegisterAddonPrefix()
		end
	end
end

function Comm.GenerateDiscoveryChannels()
	local realmToken = Player.GetRealmToken()
	local year, month, day = getDateParts()
	local dateKeys = {
		string.format("%04d-%02d-%02d", year, month, day),
		string.format("%02d-%02d-%04d", day, month, year),
		string.format("%02d-%02d-%04d", month, day, year),
	}

	local channels = {}
	local seenChannels = {}

	local function addChannel(channelName)
		if not seenChannels[channelName] then
			channels[#channels + 1] = channelName
			seenChannels[channelName] = true
		end
	end

	for _, dateKey in ipairs(dateKeys) do
		addChannel("wep" .. Hash.Hex8(realmToken .. "|" .. dateKey))
	end

	addChannel(DISCOVERY_FALLBACK_CHANNEL)

	return channels
end

function Comm:RegisterAddonPrefix()
	if not WEP.db.comm.addonMessages then
		self.addonPrefixRegistered = false
		WEP:Log("Comm", "addon_prefix_skipped", {
			reason = "addon messages disabled",
		})
		return
	end

	if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
		self.addonPrefixRegistered = C_ChatInfo.RegisterAddonMessagePrefix(ADDON_PREFIX) ~= false
	elseif RegisterAddonMessagePrefix then
		self.addonPrefixRegistered = RegisterAddonMessagePrefix(ADDON_PREFIX) ~= false
	else
		self.addonPrefixRegistered = false
		self.lastError = "addon message API unavailable"
	end

	WEP:Log("Comm", "addon_prefix_registered", {
		prefix = ADDON_PREFIX,
		registered = self.addonPrefixRegistered == true,
		error = self.lastError or "none",
	}, self.addonPrefixRegistered and "info" or "warn")
end

function Comm:GetGroupDistribution()
	if IsInRaid and IsInRaid() then
		return "RAID"
	end

	if IsInGroup and IsInGroup() then
		return "PARTY"
	end

	if GetNumGroupMembers then
		local count = GetNumGroupMembers()

		if count and count > 0 then
			return "PARTY"
		end
	end

	return nil
end

function Comm:GetDefaultBroadcastOptions()
	local commDb = WEP.db and WEP.db.comm
	local distribution = self:GetGroupDistribution()

	if distribution and commDb and commDb.addonMessages and self.addonPrefixRegistered then
		return {
			transport = "ADDON",
			distribution = distribution,
		}
	end

	return {
		transport = "CHANNEL",
	}
end

function Comm:CleanupOldDiscoveryChannels()
	if not GetChannelName or not LeaveChannelByName then
		return
	end

	local validChannels = self.channelLookup or {}
	local maxChannels = MAX_WOW_CHAT_CHANNELS or 20

	for i = 1, maxChannels do
		local _, channelName = GetChannelName(i)
		local normalizedChannelName = ChatChannels.NormalizeName(channelName)

		if normalizedChannelName
			and normalizedChannelName:match(OLD_DISCOVERY_CHANNEL_PATTERN)
			and not validChannels[normalizedChannelName]
		then
			LeaveChannelByName(channelName)
		end
	end
end

function Comm:RefreshJoinedChannels()
	self.joinedChannels = {}
	self.activeChannel = nil

	for _, channelName in ipairs(self.channelNames) do
		local channelId = ChatChannels.GetId(channelName)

		if channelId > 0 then
			self.joinedChannels[channelName] = channelId

			if not self.activeChannel then
				self.activeChannel = channelName
			end
		end
	end
end

function Comm:HideDiscoveryChannels()
	ChatChannels.HideFromFrames(self.channelNames)
end

function Comm:JoinDiscoveryChannels()
	if not WEP.db.comm.enabled or not WEP.db.comm.discoveryChannel then
		WEP:Log("Comm", "join_discovery_skipped", {
			enabled = WEP.db.comm.enabled,
			discoveryChannel = WEP.db.comm.discoveryChannel,
		}, "warn")
		return
	end

	if not JoinChannelByName then
		self.lastError = "channel API unavailable"
		WEP:Log("Comm", "join_discovery_failed", {
			error = self.lastError,
		}, "error")
		return
	end

	self.channelNames = self:GenerateDiscoveryChannels()
	self.channelLookup = ChatChannels.BuildLookup(self.channelNames)

	self:CleanupOldDiscoveryChannels()

	for _, channelName in ipairs(self.channelNames) do
		if ChatChannels.GetId(channelName) == 0 then
			JoinChannelByName(channelName)
		end
	end

	WEP:Log("Comm", "join_discovery_requested", {
		channels = #self.channelNames,
	})

	Timer.After(1, function()
		self:RefreshJoinedChannels()
		self:HideDiscoveryChannels()

		if not self.activeChannel then
			self.lastError = "no discovery channel joined"
		end

		WEP:Log("Comm", "join_discovery_checked", {
			activeChannel = self.activeChannel or "none",
			error = self.lastError or "none",
		}, self.activeChannel and "info" or "warn")
	end)
end

function Comm:IsDiscoveryChannel(channelName)
	local normalizedChannelName = ChatChannels.NormalizeName(channelName)
	return normalizedChannelName and self.channelLookup[normalizedChannelName] == true
end

function Comm:RegisterHandler(messageType, callback)
	if type(messageType) ~= "string" or messageType == "" then
		return false, "message type is required"
	end

	if type(callback) ~= "function" then
		return false, "callback must be a function"
	end

	self.handlers[messageType] = self.handlers[messageType] or {}
	self.handlers[messageType][#self.handlers[messageType] + 1] = callback
	WEP:Log("Comm", "handler_registered", {
		type = messageType,
		count = #self.handlers[messageType],
	})

	return true
end

function Comm:MakeMessageId()
	self.messageCounter = (self.messageCounter or 0) + 1
	return Player.GetFullName() .. ":" .. Timer.Now() .. ":" .. self.messageCounter
end

function Comm:Send(messageType, payload, options)
	options = options or {}

	if not WEP.db.comm.enabled then
		WEP:Log("Comm", "send_failed", {
			type = messageType,
			error = "communication is disabled",
		}, "warn")
		return false, "communication is disabled"
	end

	local distribution = options.distribution and string.upper(options.distribution) or nil
	local transport = options.transport and string.upper(options.transport) or nil

	if not transport then
		transport = distribution and "ADDON" or "CHANNEL"
	end

	if transport ~= "CHANNEL" and transport ~= "ADDON" then
		WEP:Log("Comm", "send_failed", {
			type = messageType,
			transport = transport or "none",
			error = "unsupported transport",
		}, "error")
		return false, "unsupported transport"
	end

	if transport == "CHANNEL" and not WEP.db.comm.discoveryChannel then
		WEP:Log("Comm", "send_failed", {
			type = messageType,
			transport = transport,
			error = "discovery channel is disabled",
		}, "warn")
		return false, "discovery channel is disabled"
	end

	if transport == "ADDON" then
		if not WEP.db.comm.addonMessages then
			WEP:Log("Comm", "send_failed", {
				type = messageType,
				transport = transport,
				error = "addon messages are disabled",
			}, "warn")
			return false, "addon messages are disabled"
		end

		if not VALID_ADDON_DISTRIBUTIONS[distribution or ""] then
			WEP:Log("Comm", "send_failed", {
				type = messageType,
				distribution = distribution or "none",
				error = "unsupported addon distribution",
			}, "error")
			return false, "unsupported addon distribution"
		end

		if distribution == "WHISPER" and (not options.target or options.target == "") then
			WEP:Log("Comm", "send_failed", {
				type = messageType,
				distribution = distribution,
				error = "whisper target is required",
			}, "error")
			return false, "whisper target is required"
		end
	end

	local messageId = self:MakeMessageId()
	local wireText, encodeErr = WEP.Protocol:Encode(messageType, payload, messageId, Player.GetFullName(), Timer.Now())

	if not wireText then
		WEP:Log("Comm", "send_failed", {
			type = messageType,
			messageId = messageId,
			error = encodeErr,
		}, "error")
		return false, encodeErr
	end

	if #self.sendQueue >= MAX_QUEUE_SIZE then
		self.stats.dropped = self.stats.dropped + 1
		WEP:Log("Comm", "send_failed", {
			type = messageType,
			messageId = messageId,
			error = "outgoing queue is full",
		}, "error")
		return false, "outgoing queue is full"
	end

	self.sendQueue[#self.sendQueue + 1] = {
		wireText = wireText,
		transport = transport,
		distribution = distribution,
		target = options.target,
		attempts = 0,
	}

	self:ScheduleQueue()
	WEP:Log("Comm", "send_queued", {
		type = messageType,
		messageId = messageId,
		transport = transport,
		queueSize = #self.sendQueue,
	})
	return true, messageId
end

function Comm:ScheduleQueue()
	if self.queueTimerActive then
		return
	end

	self.queueTimerActive = true

	Timer.After(SEND_INTERVAL_SECONDS, function()
		self.queueTimerActive = false
		self:ProcessQueue()
	end)
end

function Comm:ProcessQueue()
	if #self.sendQueue == 0 then
		return
	end

	local item = table.remove(self.sendQueue, 1)
	local ok, err

	if item.transport == "ADDON" then
		ok, err = self:SendAddonWire(item)
	else
		ok, err = self:SendDiscoveryWire(item)
	end

	if not ok then
		item.attempts = item.attempts + 1
		self.lastError = err

		if err == "no discovery channel joined" and item.attempts <= CHANNEL_RETRY_LIMIT then
			table.insert(self.sendQueue, 1, item)
		else
			self.stats.dropped = self.stats.dropped + 1
			WEP:Debug("Dropped outgoing message:", err)
			WEP:Log("Comm", "send_dropped", {
				transport = item.transport,
				error = err,
				attempts = item.attempts,
			}, "error")
		end
	end

	if #self.sendQueue > 0 then
		self:ScheduleQueue()
	end
end

function Comm:SendDiscoveryWire(item)
	if not WEP.db.comm.discoveryChannel then
		return false, "discovery channel is disabled"
	end

	if not SendChatMessage then
		return false, "chat message API unavailable"
	end

	self:RefreshJoinedChannels()

	local sentToAnyChannel = false

	for _, channelName in ipairs(self.channelNames) do
		local channelId = self.joinedChannels[channelName] or ChatChannels.GetId(channelName)

		if channelId > 0 then
			local ok, err = pcall(SendChatMessage, item.wireText, "CHANNEL", nil, channelId)

			if ok then
				sentToAnyChannel = true
			else
				self.lastError = err
			end
		end
	end

	if not sentToAnyChannel then
		self:JoinDiscoveryChannels()
		WEP:Log("Comm", "discovery_send_failed", {
			error = "no discovery channel joined",
		}, "warn")
		return false, "no discovery channel joined"
	end

	self.stats.sent = self.stats.sent + 1
	WEP:Log("Comm", "discovery_sent", {
		channels = #self.channelNames,
	})
	return true
end

function Comm:SendAddonWire(item)
	if not WEP.db.comm.addonMessages then
		return false, "addon messages are disabled"
	end

	if not self.addonPrefixRegistered then
		return false, "addon message prefix is not registered"
	end

	local distribution = item.distribution
	if not VALID_ADDON_DISTRIBUTIONS[distribution or ""] then
		return false, "unsupported addon distribution"
	end

	if distribution == "WHISPER" and (not item.target or item.target == "") then
		return false, "whisper target is required"
	end

	local sendAddonMessage = C_ChatInfo and C_ChatInfo.SendAddonMessage or SendAddonMessage

	if not sendAddonMessage then
		return false, "addon message API unavailable"
	end

	local ok, err = pcall(sendAddonMessage, ADDON_PREFIX, item.wireText, distribution, item.target)

	if not ok then
		WEP:Log("Comm", "addon_send_failed", {
			distribution = distribution,
			target = item.target or "none",
			error = err,
		}, "error")
		return false, err
	end

	self.stats.sent = self.stats.sent + 1
	WEP:Log("Comm", "addon_sent", {
		distribution = distribution,
		target = item.target or "none",
	})
	return true
end

function Comm:PruneSeenMessages()
	local cutoff = Timer.Now() - SEEN_MESSAGE_TTL_SECONDS

	for messageId, seenAt in pairs(self.seenMessages) do
		if seenAt < cutoff then
			self.seenMessages[messageId] = nil
		end
	end
end

function Comm:IsDuplicate(messageId)
	self:PruneSeenMessages()

	if self.seenMessages[messageId] then
		self.stats.duplicates = self.stats.duplicates + 1
		return true
	end

	self.seenMessages[messageId] = Timer.Now()
	return false
end

function Comm:HandleIncoming(wireText, apiSender, transport, channelName)
	if not WEP.db.comm.enabled then
		return
	end

	local message, decodeErr = WEP.Protocol:Decode(wireText)

	if not message then
		WEP:Debug("Ignored incoming message:", decodeErr)
		WEP:Log("Comm", "incoming_ignored", {
			transport = transport,
			sender = apiSender or "none",
			error = decodeErr,
		}, "warn")
		return
	end

	if WEP:IsSelf(apiSender) or WEP:IsSelf(message.sender) then
		WEP:Log("Comm", "incoming_ignored", {
			type = message.type,
			sender = apiSender or message.sender,
			reason = "self",
		})
		return
	end

	if self:IsDuplicate(message.id) then
		WEP:Log("Comm", "incoming_duplicate", {
			type = message.type,
			id = message.id,
			sender = message.sender,
		}, "warn")
		return
	end

	message.claimedSender = message.sender
	if apiSender and apiSender ~= "" then
		message.sender = apiSender
	end
	message.transport = transport
	message.channel = channelName
	message.receivedAt = Timer.Now()

	self.stats.received = self.stats.received + 1
	WEP:Log("Comm", "incoming_received", {
		type = message.type,
		id = message.id,
		sender = message.sender,
		transport = transport,
	})
	self:Dispatch(message)
end

function Comm:Dispatch(message)
	local handlers = self.handlers[message.type]

	if not handlers then
		WEP:Debug("No handler for message type:", message.type)
		WEP:Log("Comm", "dispatch_no_handler", {
			type = message.type,
			sender = message.sender,
		}, "warn")
		return
	end

	for _, callback in ipairs(handlers) do
		local ok, err = pcall(callback, message)

		if not ok then
			WEP:Log("Comm", "dispatch_failed", {
				type = message.type,
				error = err,
			}, "error")
			WEP:Print("Comm handler failed:", message.type, err)
		end
	end
end

function Comm:OnEvent(event, ...)
	if event == "PLAYER_ENTERING_WORLD" then
		Timer.After(2, function()
			self:JoinDiscoveryChannels()
		end)
		return
	end

	if event == "CHAT_MSG_CHANNEL" then
		local messageText, sender, _, channelName, _, _, _, _, channelBaseName = ...
		local discoveryChannelName = channelBaseName or channelName

		if self:IsDiscoveryChannel(discoveryChannelName) then
			self:HandleIncoming(messageText, sender, "CHANNEL", discoveryChannelName)
		end

		return
	end

	if event == "CHAT_MSG_ADDON" then
		local prefix, messageText, distribution, sender = ...

		if prefix == ADDON_PREFIX then
			self:HandleIncoming(messageText, sender, distribution or "ADDON", nil)
		end
	end
end

function Comm:GetStatus()
	if #self.channelNames == 0 then
		self.channelNames = self:GenerateDiscoveryChannels()
		self.channelLookup = ChatChannels.BuildLookup(self.channelNames)
	end

	self:RefreshJoinedChannels()

	local channels = {}

	for _, channelName in ipairs(self.channelNames) do
		local channelId = self.joinedChannels[channelName]

		channels[#channels + 1] = {
			name = channelName,
			id = channelId,
			joined = channelId ~= nil,
		}
	end

	return {
		enabled = WEP.db.comm.enabled,
		debug = WEP.db.comm.debug,
		discoveryChannel = WEP.db.comm.discoveryChannel,
		addonMessages = WEP.db.comm.addonMessages,
		addonPrefix = ADDON_PREFIX,
		addonPrefixRegistered = self.addonPrefixRegistered == true,
		activeChannel = self.activeChannel,
		channels = channels,
		queueSize = #self.sendQueue,
		queueLimit = MAX_QUEUE_SIZE,
		lastError = self.lastError,
		stats = self.stats,
	}
end

WEP:RegisterModule("Comm", Comm)
