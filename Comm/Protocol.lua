local _, WEP = ...

local Protocol = {}
WEP.Protocol = Protocol

Protocol.WIRE_PREFIX = "WEP1"
Protocol.FIELD_SEPARATOR = "~"
Protocol.LEGACY_FIELD_SEPARATOR = "|"
Protocol.VERSION = 1
Protocol.MAX_WIRE_BYTES = 240
Protocol.MAX_MESSAGE_TYPE_BYTES = 32

local function escapeValue(value)
	if value == nil then
		value = ""
	end

	value = tostring(value)
	value = value:gsub("%%", "%%25")
	value = value:gsub("~", "%%7E")
	value = value:gsub("|", "%%7C")
	value = value:gsub(";", "%%3B")
	value = value:gsub("=", "%%3D")
	return value
end

local function unescapeValue(value)
	if value == nil then
		value = ""
	end

	value = tostring(value)
	value = value:gsub("%%3D", "=")
	value = value:gsub("%%3B", ";")
	value = value:gsub("%%7C", "|")
	value = value:gsub("%%7E", "~")
	value = value:gsub("%%25", "%%")
	return value
end

local function isScalar(value)
	local valueType = type(value)
	return valueType == "string" or valueType == "number" or valueType == "boolean"
end

local function isValidMessageType(messageType)
	return type(messageType) == "string"
		and #messageType > 0
		and #messageType <= Protocol.MAX_MESSAGE_TYPE_BYTES
		and messageType:match("^[A-Za-z0-9_:%-]+$") ~= nil
end

local function encodePayload(payload)
	local payloadType = type(payload)

	if payload == nil then
		return "s:"
	end

	if isScalar(payload) then
		return "s:" .. escapeValue(payload)
	end

	if payloadType ~= "table" then
		return nil, "payload must be a string or scalar key/value table"
	end

	local entries = {}

	for key, value in pairs(payload) do
		if not isScalar(key) or not isScalar(value) then
			return nil, "payload table only supports scalar keys and values"
		end

		entries[#entries + 1] = {
			key = key,
			sortKey = tostring(key),
			value = value,
		}
	end

	table.sort(entries, function(left, right)
		return left.sortKey < right.sortKey
	end)

	local encoded = {}

	for _, entry in ipairs(entries) do
		encoded[#encoded + 1] = escapeValue(entry.key) .. "=" .. escapeValue(entry.value)
	end

	return "kv:" .. table.concat(encoded, ";")
end

local function decodePayload(payloadText)
	if type(payloadText) ~= "string" or #payloadText < 2 then
		return nil, "missing payload"
	end

	local payloadType = payloadText:sub(1, 2)
	local body = payloadText:sub(3)

	if payloadType == "s:" then
		return unescapeValue(body)
	end

	if payloadType ~= "kv" or body:sub(1, 1) ~= ":" then
		return nil, "unsupported payload type"
	end

	body = body:sub(2)

	local payload = {}
	local startIndex = 1

	if body == "" then
		return payload
	end

	while startIndex <= #body do
		local separatorIndex = body:find(";", startIndex, true)
		local pairText = separatorIndex and body:sub(startIndex, separatorIndex - 1) or body:sub(startIndex)
		local equalsIndex = pairText:find("=", 1, true)

		if not equalsIndex then
			return nil, "malformed key/value payload"
		end

		local key = unescapeValue(pairText:sub(1, equalsIndex - 1))
		local value = unescapeValue(pairText:sub(equalsIndex + 1))

		if key == "" then
			return nil, "empty payload key"
		end

		payload[key] = value

		if not separatorIndex then
			break
		end

		startIndex = separatorIndex + 1
	end

	return payload
end

local function splitWireMessage(text, separator)
	local fields = {}
	local startIndex = 1

	for i = 1, 6 do
		local separatorIndex = text:find(separator, startIndex, true)
		if not separatorIndex then
			return nil
		end

		fields[i] = text:sub(startIndex, separatorIndex - 1)
		startIndex = separatorIndex + 1
	end

	fields[7] = text:sub(startIndex)
	return fields
end

function Protocol:Encode(messageType, payload, messageId, sender, timestamp)
	if not isValidMessageType(messageType) then
		return nil, "invalid message type"
	end

	if type(messageId) ~= "string" or messageId == "" then
		return nil, "missing message id"
	end

	if type(sender) ~= "string" or sender == "" then
		return nil, "missing sender"
	end

	local payloadText, payloadErr = encodePayload(payload)
	if not payloadText then
		return nil, payloadErr
	end

	local fields = {
		self.WIRE_PREFIX,
		tostring(self.VERSION),
		messageType,
		escapeValue(messageId),
		escapeValue(sender),
		tostring(timestamp or 0),
		payloadText,
	}

	local wireText = table.concat(fields, self.FIELD_SEPARATOR)

	if #wireText > self.MAX_WIRE_BYTES then
		return nil, "message exceeds " .. self.MAX_WIRE_BYTES .. " bytes"
	end

	return wireText
end

function Protocol:Decode(text)
	if type(text) ~= "string" then
		return nil, "message is not text"
	end

	if #text == 0 or #text > self.MAX_WIRE_BYTES then
		return nil, "message size is invalid"
	end

	if text:sub(1, #self.WIRE_PREFIX) ~= self.WIRE_PREFIX then
		return nil, "not a WEP message"
	end

	local separator = text:sub(#self.WIRE_PREFIX + 1, #self.WIRE_PREFIX + 1)
	if separator ~= self.FIELD_SEPARATOR and separator ~= self.LEGACY_FIELD_SEPARATOR then
		return nil, "invalid field separator"
	end

	local fields = splitWireMessage(text, separator)
	if not fields then
		return nil, "malformed wire message"
	end

	if fields[1] ~= self.WIRE_PREFIX then
		return nil, "invalid wire prefix"
	end

	local version = tonumber(fields[2])
	if version ~= self.VERSION then
		return nil, "unsupported wire version"
	end

	local messageType = fields[3]
	if not isValidMessageType(messageType) then
		return nil, "invalid message type"
	end

	local messageId = unescapeValue(fields[4])
	local sender = unescapeValue(fields[5])
	local timestamp = tonumber(fields[6]) or 0
	local payload, payloadErr = decodePayload(fields[7])

	if messageId == "" then
		return nil, "missing message id"
	end

	if sender == "" then
		return nil, "missing sender"
	end

	if payload == nil then
		return nil, payloadErr
	end

	return {
		version = version,
		type = messageType,
		id = messageId,
		sender = sender,
		timestamp = timestamp,
		payload = payload,
	}
end
