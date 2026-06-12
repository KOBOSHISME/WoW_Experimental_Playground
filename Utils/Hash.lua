local _, WEP = ...

WEP.Utils = WEP.Utils or {}

local Hash = {}
WEP.Utils.Hash = Hash

local HASH_MODULO = 4294967296

function Hash.Hex8(text)
	text = tostring(text or "")

	local hash = 5381

	for i = 1, #text do
		hash = ((hash * 33) + text:byte(i)) % HASH_MODULO
	end

	return string.format("%08x", hash)
end
