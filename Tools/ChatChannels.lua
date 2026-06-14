local _, WEP = ...

WEP.Tools = WEP.Tools or {}

local ChatChannels = {}
WEP.Tools.ChatChannels = ChatChannels

WEP:Log("ChatChannels", "loaded")

function ChatChannels.NormalizeName(channelName)
	if not channelName then
		return nil
	end

	local normalized = tostring(channelName):match("^%d+%.%s*(.+)$") or tostring(channelName)
	return string.lower(normalized)
end

function ChatChannels.GetId(channelName)
	if not GetChannelName then
		return 0
	end

	local channelId = GetChannelName(channelName)
	if type(channelId) == "number" then
		return channelId
	end

	return 0
end

function ChatChannels.BuildLookup(channelNames)
	local lookup = {}

	for _, channelName in ipairs(channelNames) do
		lookup[ChatChannels.NormalizeName(channelName)] = true
	end

	return lookup
end

function ChatChannels.HideFromFrames(channelNames)
	if not ChatFrame_RemoveChannel then
		WEP:Log("ChatChannels", "hide_from_frames_unavailable", nil, "warn")
		return
	end

	local windowCount = NUM_CHAT_WINDOWS or 10
	local removed = 0

	for i = 1, windowCount do
		local chatFrame = _G["ChatFrame" .. i]

		if chatFrame then
			for _, channelName in ipairs(channelNames) do
				ChatFrame_RemoveChannel(chatFrame, channelName)
				removed = removed + 1
			end
		end
	end

	WEP:Log("ChatChannels", "hide_from_frames", {
		channels = #channelNames,
		removals = removed,
		windows = windowCount,
	})
end
