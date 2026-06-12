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

local ADDON_PREFIX = "WEPXP"
local DISCOVERY_FALLBACK_CHANNEL = "wepcomm"
local MAX_QUEUE_SIZE = 50
local SEND_INTERVAL_SECONDS = 0.35
local SEEN_MESSAGE_TTL_SECONDS = 300
local CHANNEL_RETRY_LIMIT = 2
local HASH_MODULO = 4294967296
local OLD_DISCOVERY_CHANNEL_PATTERN = "^wep%x%x%x%x%x%x%x%x$"

local VALID_ADDON_DISTRIBUTIONS = {
	PARTY = true,
	RAID = true,
	GUILD = true,
	WHISPER = true,
}

local function now()
	if GetServerTime then
		return GetServerTime()
	end

	if time then
		return time()
	end

	return 0
end

local function after(delay, callback)
	if C_Timer and C_Timer.After then
		C_Timer.After(delay, callback)
	else
		callback()
	end
end

local function normalizeRealmName(realmName)
	if not realmName or realmName == "" then
		return "UnknownRealm"
	end

	return (tostring(realmName):gsub("%s+", ""))
end

local function getRealmToken()
	if GetNormalizedRealmName then
		local normalizedRealmName = GetNormalizedRealmName()
		if normalizedRealmName and normalizedRealmName ~= "" then
			return normalizeRealmName(normalizedRealmName)
		end
	end

	if GetRealmName then
		return normalizeRealmName(GetRealmName())
	end

	return "UnknownRealm"
end

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

local function hashText(text)
	local hash = 5381

	for i = 1, #text do
		hash = ((hash * 33) + text:byte(i)) % HASH_MODULO
	end

	return string.format("%08x", hash)
end

local function normalizeChannelName(channelName)
	if not channelName then
		return nil
	end

	local normalized = tostring(channelName):match("^%d+%.%s*(.+)$") or tostring(channelName)
	return string.lower(normalized)
end

local function getChannelId(channelName)
	if not GetChannelName then
		return 0
	end

	local channelId = GetChannelName(channelName)
	if type(channelId) == "number" then
		return channelId
	end

	return 0
end

local function buildChannelLookup(channelNames)
	local lookup = {}

	for _, channelName in ipairs(channelNames) do
		lookup[normalizeChannelName(channelName)] = true
	end

	return lookup
end

function Comm:Initialize()
	if self.initialized then
		return
	end

	self.initialized = true
	self.frame = CreateFrame("Frame")
	self.frame:SetScript("OnEvent", function(_, event, ...)
		self:OnEvent(event, ...)
	end)

	self.channelNames = self:GenerateDiscoveryChannels()
	self.channelLookup = buildChannelLookup(self.channelNames)

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
	local realmToken = getRealmToken()
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
		addChannel("wep" .. hashText(realmToken .. "|" .. dateKey))
	end

	addChannel(DISCOVERY_FALLBACK_CHANNEL)

	return channels
end

function Comm:RegisterAddonPrefix()
	if not WEP.db.comm.addonMessages then
		self.addonPrefixRegistered = false
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
end

function Comm:CleanupOldDiscoveryChannels()
	if not GetChannelName or not LeaveChannelByName then
		return
	end

	local validChannels = self.channelLookup or {}
	local maxChannels = MAX_WOW_CHAT_CHANNELS or 20

	for i = 1, maxChannels do
		local _, channelName = GetChannelName(i)
		local normalizedChannelName = normalizeChannelName(channelName)

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
		local channelId = getChannelId(channelName)

		if channelId > 0 then
			self.joinedChannels[channelName] = channelId

			if not self.activeChannel then
				self.activeChannel = channelName
			end
		end
	end
end

function Comm:HideDiscoveryChannels()
	if not ChatFrame_RemoveChannel then
		return
	end

	local windowCount = NUM_CHAT_WINDOWS or 10

	for i = 1, windowCount do
		local chatFrame = _G["ChatFrame" .. i]

		if chatFrame then
			for _, channelName in ipairs(self.channelNames) do
				ChatFrame_RemoveChannel(chatFrame, channelName)
			end
		end
	end
end

function Comm:JoinDiscoveryChannels()
	if not WEP.db.comm.enabled or not WEP.db.comm.discoveryChannel then
		return
	end

	if not JoinChannelByName then
		self.lastError = "channel API unavailable"
		return
	end

	self.channelNames = self:GenerateDiscoveryChannels()
	self.channelLookup = buildChannelLookup(self.channelNames)

	self:CleanupOldDiscoveryChannels()

	for _, channelName in ipairs(self.channelNames) do
		if getChannelId(channelName) == 0 then
			JoinChannelByName(channelName)
		end
	end

	after(1, function()
		self:RefreshJoinedChannels()
		self:HideDiscoveryChannels()

		if not self.activeChannel then
			self.lastError = "no discovery channel joined"
		end
	end)
end

function Comm:IsDiscoveryChannel(channelName)
	local normalizedChannelName = normalizeChannelName(channelName)
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

	return true
end

function Comm:MakeMessageId()
	self.messageCounter = (self.messageCounter or 0) + 1
	return WEP:GetPlayerFullName() .. ":" .. now() .. ":" .. self.messageCounter
end

function Comm:Send(messageType, payload, options)
	options = options or {}

	if not WEP.db.comm.enabled then
		return false, "communication is disabled"
	end

	local distribution = options.distribution and string.upper(options.distribution) or nil
	local transport = options.transport and string.upper(options.transport) or nil

	if not transport then
		transport = distribution and "ADDON" or "CHANNEL"
	end

	if transport ~= "CHANNEL" and transport ~= "ADDON" then
		return false, "unsupported transport"
	end

	if transport == "CHANNEL" and not WEP.db.comm.discoveryChannel then
		return false, "discovery channel is disabled"
	end

	if transport == "ADDON" then
		if not WEP.db.comm.addonMessages then
			return false, "addon messages are disabled"
		end

		if not VALID_ADDON_DISTRIBUTIONS[distribution or ""] then
			return false, "unsupported addon distribution"
		end

		if distribution == "WHISPER" and (not options.target or options.target == "") then
			return false, "whisper target is required"
		end
	end

	local messageId = self:MakeMessageId()
	local wireText, encodeErr = WEP.Protocol:Encode(messageType, payload, messageId, WEP:GetPlayerFullName(), now())

	if not wireText then
		return false, encodeErr
	end

	if #self.sendQueue >= MAX_QUEUE_SIZE then
		self.stats.dropped = self.stats.dropped + 1
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
	return true, messageId
end

function Comm:ScheduleQueue()
	if self.queueTimerActive then
		return
	end

	self.queueTimerActive = true

	after(SEND_INTERVAL_SECONDS, function()
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
		local channelId = self.joinedChannels[channelName] or getChannelId(channelName)

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
		return false, "no discovery channel joined"
	end

	self.stats.sent = self.stats.sent + 1
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
		return false, err
	end

	self.stats.sent = self.stats.sent + 1
	return true
end

function Comm:PruneSeenMessages()
	local cutoff = now() - SEEN_MESSAGE_TTL_SECONDS

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

	self.seenMessages[messageId] = now()
	return false
end

function Comm:HandleIncoming(wireText, apiSender, transport, channelName)
	if not WEP.db.comm.enabled then
		return
	end

	local message, decodeErr = WEP.Protocol:Decode(wireText)

	if not message then
		WEP:Debug("Ignored incoming message:", decodeErr)
		return
	end

	if WEP:IsSelf(apiSender) or WEP:IsSelf(message.sender) then
		return
	end

	if self:IsDuplicate(message.id) then
		return
	end

	message.claimedSender = message.sender
	if apiSender and apiSender ~= "" then
		message.sender = apiSender
	end
	message.transport = transport
	message.channel = channelName
	message.receivedAt = now()

	self.stats.received = self.stats.received + 1
	self:Dispatch(message)
end

function Comm:Dispatch(message)
	local handlers = self.handlers[message.type]

	if not handlers then
		WEP:Debug("No handler for message type:", message.type)
		return
	end

	for _, callback in ipairs(handlers) do
		local ok, err = pcall(callback, message)

		if not ok then
			WEP:Print("Comm handler failed:", message.type, err)
		end
	end
end

function Comm:OnEvent(event, ...)
	if event == "PLAYER_ENTERING_WORLD" then
		after(2, function()
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
		self.channelLookup = buildChannelLookup(self.channelNames)
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
