local _, WEP = ...

WEP.Tools = WEP.Tools or {}

local Timer = {}
WEP.Tools.Timer = Timer

WEP:Log("Timer", "loaded")

function Timer.Now()
	if GetServerTime then
		return GetServerTime()
	end

	if time then
		return time()
	end

	return 0
end

function Timer.After(delay, callback)
	if C_Timer and C_Timer.After then
		C_Timer.After(delay, callback)
	else
		WEP:Log("Timer", "after_immediate_fallback", {
			delay = delay,
		}, "warn")
		callback()
	end
end
