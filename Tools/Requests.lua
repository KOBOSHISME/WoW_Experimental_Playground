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

local REQUEST_MESSAGE_TYPE = "REQ"
local RESPONSE_MESSAGE_TYPE = "REQ_RES"
local BROADCAST_TARGET = "*"
local DATA_PREFIX = "data:"

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
				WEP:Print("Request handler failed:", requestType, err)
			end
		end
	end

	if wildcardCallbacks and wildcardCallbacks ~= callbacks then
		for _, callback in ipairs(wildcardCallbacks) do
			local ok, err = pcall(callback, event)
			if not ok then
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
		return false, "request type is required"
	end

	if type(callback) ~= "function" then
		return false, "callback must be a function"
	end

	Requests.requestHandlers[requestType] = Requests.requestHandlers[requestType] or {}
	Requests.requestHandlers[requestType][#Requests.requestHandlers[requestType] + 1] = callback

	return true
end

function Requests.RegisterResponseHandler(requestType, callback)
	if isBlank(requestType) then
		return false, "request type is required"
	end

	if type(callback) ~= "function" then
		return false, "callback must be a function"
	end

	Requests.responseHandlers[requestType] = Requests.responseHandlers[requestType] or {}
	Requests.responseHandlers[requestType][#Requests.responseHandlers[requestType] + 1] = callback

	return true
end

function Requests.Send(target, requestType, data, options)
	if isBlank(target) then
		return false, "target is required"
	end

	if isBlank(requestType) then
		return false, "request type is required"
	end

	local copiedData, dataErr = copyFlatData(data)
	if not copiedData then
		return false, dataErr
	end

	local requestId = Requests.MakeRequestId()
	local payload = {
		rid = requestId,
		rtype = requestType,
		target = target,
	}

	addDataToPayload(payload, copiedData)

	local ok, messageIdOrErr = WEP.Comm:Send(REQUEST_MESSAGE_TYPE, payload, {
		transport = "CHANNEL",
	})

	if not ok then
		return false, messageIdOrErr
	end

	Requests.pendingOutgoing[requestId] = {
		id = requestId,
		type = requestType,
		target = target,
		data = copiedData,
		sentAt = Timer.Now(),
		messageId = messageIdOrErr,
		options = options or {},
	}
	Requests.stats.sent = Requests.stats.sent + 1

	return true, requestId
end

function Requests.Respond(requestId, target, status, data)
	if isBlank(requestId) then
		return false, "request id is required"
	end

	if isBlank(target) then
		return false, "target is required"
	end

	if isBlank(status) then
		return false, "status is required"
	end

	local copiedData, dataErr = copyFlatData(data)
	if not copiedData then
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

	local ok, messageIdOrErr = WEP.Comm:Send(RESPONSE_MESSAGE_TYPE, payload, {
		transport = "CHANNEL",
	})

	if not ok then
		return false, messageIdOrErr
	end

	Requests.stats.responsesSent = Requests.stats.responsesSent + 1
	return true, messageIdOrErr
end

function Requests:OnRequestMessage(message)
	local payload = message.payload
	local requestId = type(payload) == "table" and payload.rid or nil
	local requestType = type(payload) == "table" and payload.rtype or nil
	local target = type(payload) == "table" and payload.target or nil

	if isBlank(requestId) or isBlank(requestType) or not targetMatches(target) then
		self.stats.ignored = self.stats.ignored + 1
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
	}

	self.receivedRequests[requestId] = request
	self.stats.received = self.stats.received + 1

	dispatch(self.requestHandlers, requestType, request)
end

function Requests:OnResponseMessage(message)
	local payload = message.payload
	local requestId = type(payload) == "table" and payload.rid or nil
	local target = type(payload) == "table" and payload.target or nil
	local status = type(payload) == "table" and payload.status or nil

	if isBlank(requestId) or isBlank(status) or not targetMatches(target) then
		self.stats.ignored = self.stats.ignored + 1
		return
	end

	local pendingRequest = self.pendingOutgoing[requestId]
	local requestType = (pendingRequest and pendingRequest.type) or payload.rtype or ""
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

	dispatch(self.responseHandlers, requestType, response)

	if pendingRequest and pendingRequest.target ~= BROADCAST_TARGET then
		self.pendingOutgoing[requestId] = nil
	end
end

function Requests.GetStatus()
	return {
		pendingOutgoingCount = countEntries(Requests.pendingOutgoing),
		receivedRequestCount = countEntries(Requests.receivedRequests),
		pendingOutgoing = Requests.pendingOutgoing,
		receivedRequests = Requests.receivedRequests,
		stats = Requests.stats,
	}
end

WEP:RegisterModule("Requests", Requests)
