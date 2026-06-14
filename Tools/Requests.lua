local _, WEP = ...

WEP.Tools = WEP.Tools or {}

local Requests = {
	requestHandlers = {},
	responseHandlers = {},
	pendingOutgoing = {},
	receivedRequests = {},
	stats = {
		sent = 0,
		received = 0,
		responsesSent = 0,
		responsesReceived = 0,
		ignored = 0,
	},
}

WEP.Tools.Requests = Requests

local Timer = WEP.Tools.Timer
local Player = WEP.Tools.Player

WEP:Log("Requests", "loaded")

local REQUEST_MESSAGE_TYPE = "REQ"
local RESPONSE_MESSAGE_TYPE = "REQ_RES"
local BROADCAST_TARGET = "*"
local DATA_PREFIX = "data:"
local REQUEST_TTL_SECONDS = 300
local RECEIVED_REQUEST_TTL_SECONDS = 600

local ADDON_DISTRIBUTIONS = {
	PARTY = true,
	RAID = true,
	GUILD = true,
	WHISPER = true,
}

local RESERVED_PAYLOAD_KEYS = {
	rid = true,
	rtype = true,
	target = true,
	status = true,
}

local function isScalar(value)
	local valueType = type(value)
	return valueType == "string" or valueType == "number" or valueType == "boolean"
end

local function normalizeName(value)
	return string.lower(Player.NormalizeName(value))
end

local function isBlank(value)
	return type(value) ~= "string" or value == ""
end

local function namesMatch(left, right)
	if isBlank(left) or isBlank(right) then
		return false
	end

	local normalizedLeft = normalizeName(left)
	local normalizedRight = normalizeName(right)

	if normalizedLeft == normalizedRight then
		return true
	end

	local leftShort = normalizedLeft:match("^([^-]+)") or normalizedLeft
	local rightShort = normalizedRight:match("^([^-]+)") or normalizedRight

	if leftShort ~= rightShort then
		return false
	end

	return not normalizedLeft:find("-", 1, true) or not normalizedRight:find("-", 1, true)
end

local function countEntries(values)
	local count = 0

	for _ in pairs(values) do
		count = count + 1
	end

	return count
end

local function copyFlatData(data)
	local copied = {}

	if data == nil then
		return copied
	end

	if type(data) ~= "table" then
		return nil, "data must be a flat key/value table"
	end

	for key, value in pairs(data) do
		if not isScalar(key) or not isScalar(value) then
			return nil, "data must only contain scalar keys and values"
		end

		local keyText = tostring(key)
		if keyText == "" then
			return nil, "data keys cannot be empty"
		end

		if RESERVED_PAYLOAD_KEYS[keyText] then
			return nil, "data key is reserved: " .. keyText
		end

		copied[keyText] = value
	end

	return copied
end

local function addDataToPayload(payload, data)
	for key, value in pairs(data) do
		payload[DATA_PREFIX .. key] = value
	end
end

local function extractData(payload)
	local data = {}

	for key, value in pairs(payload or {}) do
		if type(key) == "string" and key:sub(1, #DATA_PREFIX) == DATA_PREFIX then
			local dataKey = key:sub(#DATA_PREFIX + 1)
			if dataKey ~= "" then
				data[dataKey] = value
			end
		end
	end

	return data
end

local function copyOptions(options)
	local copied = {}

	if type(options) == "table" then
		for key, value in pairs(options) do
			copied[key] = value
		end
	end

	return copied
end

local function getExpirySeconds(options, defaultValue)
	if type(options) ~= "table" then
		return defaultValue
	end

	local seconds = tonumber(options.ttl or options.timeout or options.expiresIn)
	if not seconds or seconds <= 0 then
		return defaultValue
	end

	return seconds
end

local function pruneExpiredRequests(now)
	now = now or Timer.Now()

	for requestId, request in pairs(Requests.pendingOutgoing) do
		if request.expiresAt and request.expiresAt <= now then
			Requests.pendingOutgoing[requestId] = nil
		end
	end

	for requestId, request in pairs(Requests.receivedRequests) do
		if request.expiresAt and request.expiresAt <= now then
			Requests.receivedRequests[requestId] = nil
		end
	end
end

local function targetMatches(target)
	if target == BROADCAST_TARGET then
		return true
	end

	if isBlank(target) then
		return false
	end

	if WEP:IsSelf(target) then
		return true
	end

	local normalizedTarget = normalizeName(target)
	return normalizedTarget == normalizeName(Player.GetShortName()) or normalizedTarget == normalizeName(Player.GetFullName())
end

local function dispatch(handlersByType, requestType, event)
	local callbacks = handlersByType[requestType]
	local wildcardCallbacks = handlersByType[BROADCAST_TARGET]

	if callbacks then
		for _, callback in ipairs(callbacks) do
			local ok, err = pcall(callback, event)
			if not ok then
				WEP:Log("Requests", "handler_failed", {
					type = requestType,
					error = err,
				}, "error")
				WEP:Print("Request handler failed:", requestType, err)
			end
		end
	end

	if wildcardCallbacks and wildcardCallbacks ~= callbacks then
		for _, callback in ipairs(wildcardCallbacks) do
			local ok, err = pcall(callback, event)
			if not ok then
				WEP:Log("Requests", "handler_failed", {
					type = requestType,
					error = err,
				}, "error")
				WEP:Print("Request handler failed:", requestType, err)
			end
		end
	end
end

function Requests:Initialize()
	if self.initialized then
		return
	end

	self.initialized = true
	WEP:Log("Requests", "initialize")

	WEP.Comm:RegisterHandler(REQUEST_MESSAGE_TYPE, function(message)
		self:OnRequestMessage(message)
	end)

	WEP.Comm:RegisterHandler(RESPONSE_MESSAGE_TYPE, function(message)
		self:OnResponseMessage(message)
	end)
end

function Requests.MakeRequestId()
	Requests.requestCounter = (Requests.requestCounter or 0) + 1
	return tostring(Timer.Now()) .. "." .. Requests.requestCounter
end

function Requests.RegisterRequestHandler(requestType, callback)
	if isBlank(requestType) then
		WEP:Log("Requests", "request_handler_register_failed", {
			error = "request type is required",
		}, "error")
		return false, "request type is required"
	end

	if type(callback) ~= "function" then
		WEP:Log("Requests", "request_handler_register_failed", {
			type = requestType,
			error = "callback must be a function",
		}, "error")
		return false, "callback must be a function"
	end

	Requests.requestHandlers[requestType] = Requests.requestHandlers[requestType] or {}
	Requests.requestHandlers[requestType][#Requests.requestHandlers[requestType] + 1] = callback
	WEP:Log("Requests", "request_handler_registered", {
		type = requestType,
		count = #Requests.requestHandlers[requestType],
	})

	return true
end

function Requests.RegisterResponseHandler(requestType, callback)
	if isBlank(requestType) then
		WEP:Log("Requests", "response_handler_register_failed", {
			error = "request type is required",
		}, "error")
		return false, "request type is required"
	end

	if type(callback) ~= "function" then
		WEP:Log("Requests", "response_handler_register_failed", {
			type = requestType,
			error = "callback must be a function",
		}, "error")
		return false, "callback must be a function"
	end

	Requests.responseHandlers[requestType] = Requests.responseHandlers[requestType] or {}
	Requests.responseHandlers[requestType][#Requests.responseHandlers[requestType] + 1] = callback
	WEP:Log("Requests", "response_handler_registered", {
		type = requestType,
		count = #Requests.responseHandlers[requestType],
	})

	return true
end

function Requests.Send(target, requestType, data, options)
	pruneExpiredRequests()
	WEP:Log("Requests", "send_requested", {
		target = target or "none",
		type = requestType or "none",
	})

	if isBlank(target) then
		WEP:Log("Requests", "send_failed", {
			error = "target is required",
		}, "error")
		return false, "target is required"
	end

	if isBlank(requestType) then
		WEP:Log("Requests", "send_failed", {
			target = target,
			error = "request type is required",
		}, "error")
		return false, "request type is required"
	end

	local copiedData, dataErr = copyFlatData(data)
	if not copiedData then
		WEP:Log("Requests", "send_failed", {
			target = target,
			type = requestType,
			error = dataErr,
		}, "error")
		return false, dataErr
	end

	local requestId = Requests.MakeRequestId()
	local payload = {
		rid = requestId,
		rtype = requestType,
		target = target,
	}

	addDataToPayload(payload, copiedData)

	local sendOptions = copyOptions(options)

	if sendOptions.distribution then
		sendOptions.distribution = string.upper(tostring(sendOptions.distribution))
	end

	if not sendOptions.transport and not sendOptions.distribution and WEP.Comm.GetDefaultBroadcastOptions then
		sendOptions = WEP.Comm:GetDefaultBroadcastOptions()
	end

	sendOptions.transport = sendOptions.transport
		and string.upper(tostring(sendOptions.transport))
		or (sendOptions.distribution and "ADDON" or "CHANNEL")

	if sendOptions.transport == "ADDON"
		and sendOptions.distribution == "WHISPER"
		and isBlank(sendOptions.target)
	then
		sendOptions.target = target
	end

	local ok, messageIdOrErr = WEP.Comm:Send(REQUEST_MESSAGE_TYPE, payload, sendOptions)

	if not ok then
		WEP:Log("Requests", "send_failed", {
			target = target,
			type = requestType,
			requestId = requestId,
			error = messageIdOrErr,
		}, "error")
		return false, messageIdOrErr
	end

	local now = Timer.Now()
	Requests.pendingOutgoing[requestId] = {
		id = requestId,
		type = requestType,
		target = target,
		data = copiedData,
		sentAt = now,
		expiresAt = now + getExpirySeconds(sendOptions, REQUEST_TTL_SECONDS),
		messageId = messageIdOrErr,
		options = sendOptions,
	}
	Requests.stats.sent = Requests.stats.sent + 1
	WEP:Log("Requests", "sent", {
		target = target,
		type = requestType,
		requestId = requestId,
		messageId = messageIdOrErr,
		transport = sendOptions.transport,
	})

	return true, requestId
end

function Requests.Respond(requestId, target, status, data)
	pruneExpiredRequests()
	WEP:Log("Requests", "respond_requested", {
		requestId = requestId or "none",
		target = target or "none",
		status = status or "none",
	})

	if isBlank(requestId) then
		WEP:Log("Requests", "respond_failed", {
			error = "request id is required",
		}, "error")
		return false, "request id is required"
	end

	if isBlank(target) then
		WEP:Log("Requests", "respond_failed", {
			requestId = requestId,
			error = "target is required",
		}, "error")
		return false, "target is required"
	end

	if isBlank(status) then
		WEP:Log("Requests", "respond_failed", {
			requestId = requestId,
			target = target,
			error = "status is required",
		}, "error")
		return false, "status is required"
	end

	local copiedData, dataErr = copyFlatData(data)
	if not copiedData then
		WEP:Log("Requests", "respond_failed", {
			requestId = requestId,
			target = target,
			error = dataErr,
		}, "error")
		return false, dataErr
	end

	local receivedRequest = Requests.receivedRequests[requestId]
	local payload = {
		rid = requestId,
		rtype = receivedRequest and receivedRequest.type or "",
		target = target,
		status = status,
	}

	addDataToPayload(payload, copiedData)

	local sendOptions = {
		transport = "CHANNEL",
	}

	if receivedRequest and receivedRequest.transport and receivedRequest.transport ~= "CHANNEL" then
		local distribution = string.upper(receivedRequest.transport)

		if ADDON_DISTRIBUTIONS[distribution] then
			sendOptions.transport = "ADDON"
			sendOptions.distribution = distribution

			if distribution == "WHISPER" then
				sendOptions.target = target
			end
		end
	end

	local ok, messageIdOrErr = WEP.Comm:Send(RESPONSE_MESSAGE_TYPE, payload, sendOptions)

	if not ok then
		WEP:Log("Requests", "respond_failed", {
			requestId = requestId,
			target = target,
			status = status,
			error = messageIdOrErr,
		}, "error")
		return false, messageIdOrErr
	end

	Requests.stats.responsesSent = Requests.stats.responsesSent + 1
	WEP:Log("Requests", "responded", {
		requestId = requestId,
		target = target,
		status = status,
		messageId = messageIdOrErr,
		transport = sendOptions.transport,
	})
	return true, messageIdOrErr
end

function Requests:OnRequestMessage(message)
	pruneExpiredRequests()

	local payload = message.payload
	local requestId = type(payload) == "table" and payload.rid or nil
	local requestType = type(payload) == "table" and payload.rtype or nil
	local target = type(payload) == "table" and payload.target or nil

	if isBlank(requestId) or isBlank(requestType) or not targetMatches(target) then
		self.stats.ignored = self.stats.ignored + 1
		WEP:Log("Requests", "incoming_request_ignored", {
			requestId = requestId or "none",
			type = requestType or "none",
			target = target or "none",
			sender = message.sender,
		}, "warn")
		return
	end

	local request = {
		id = requestId,
		type = requestType,
		sender = message.sender,
		target = target,
		data = extractData(payload),
		receivedAt = message.receivedAt or Timer.Now(),
		transport = message.transport,
		expiresAt = Timer.Now() + RECEIVED_REQUEST_TTL_SECONDS,
	}

	self.receivedRequests[requestId] = request
	self.stats.received = self.stats.received + 1
	WEP:Log("Requests", "incoming_request_received", {
		requestId = requestId,
		type = requestType,
		sender = message.sender,
		target = target,
		transport = message.transport,
	})

	dispatch(self.requestHandlers, requestType, request)
end

function Requests:OnResponseMessage(message)
	pruneExpiredRequests()

	local payload = message.payload
	local requestId = type(payload) == "table" and payload.rid or nil
	local target = type(payload) == "table" and payload.target or nil
	local status = type(payload) == "table" and payload.status or nil

	if isBlank(requestId) or isBlank(status) or not targetMatches(target) then
		self.stats.ignored = self.stats.ignored + 1
		WEP:Log("Requests", "incoming_response_ignored", {
			requestId = requestId or "none",
			status = status or "none",
			target = target or "none",
			sender = message.sender,
		}, "warn")
		return
	end

	local pendingRequest = self.pendingOutgoing[requestId]
	if not pendingRequest then
		self.stats.ignored = self.stats.ignored + 1
		WEP:Log("Requests", "incoming_response_ignored", {
			requestId = requestId,
			status = status,
			target = target,
			sender = message.sender,
			reason = "no pending request",
		}, "warn")
		return
	end

	if pendingRequest.target ~= BROADCAST_TARGET and not namesMatch(message.sender, pendingRequest.target) then
		self.stats.ignored = self.stats.ignored + 1
		WEP:Log("Requests", "incoming_response_ignored", {
			requestId = requestId,
			status = status,
			target = target,
			sender = message.sender,
			reason = "sender mismatch",
		}, "warn")
		return
	end

	local requestType = pendingRequest.type
	local response = {
		id = requestId,
		type = requestType,
		sender = message.sender,
		target = target,
		status = status,
		data = extractData(payload),
		receivedAt = message.receivedAt or Timer.Now(),
		transport = message.transport,
		request = pendingRequest,
	}

	self.stats.responsesReceived = self.stats.responsesReceived + 1
	WEP:Log("Requests", "incoming_response_received", {
		requestId = requestId,
		type = requestType,
		status = status,
		sender = message.sender,
		transport = message.transport,
	})

	dispatch(self.responseHandlers, requestType, response)

	if pendingRequest and pendingRequest.target ~= BROADCAST_TARGET then
		self.pendingOutgoing[requestId] = nil
	end
end

function Requests.GetStatus()
	pruneExpiredRequests()

	return {
		pendingOutgoingCount = countEntries(Requests.pendingOutgoing),
		receivedRequestCount = countEntries(Requests.receivedRequests),
		pendingOutgoing = Requests.pendingOutgoing,
		receivedRequests = Requests.receivedRequests,
		stats = Requests.stats,
	}
end

WEP:RegisterModule("Requests", Requests)
