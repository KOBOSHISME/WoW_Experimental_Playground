local _, WEP = ...

WEP.Tools = WEP.Tools or {}

local UIVisibility = {
	groupStates = {},
	frameStates = {},
	pendingOps = {},
	allHidden = false,
}

WEP.Tools.UIVisibility = UIVisibility

local HIDDEN_PARENT_NAME = "WEPUIVisibilityHiddenParent"

local hiddenParent
local combatWatcher

local GROUP_ORDER = {
	"actionbars",
	"unitframes",
	"minimap",
	"questtracker",
	"chat",
	"bags",
	"micromenu",
	"buffs",
	"casting",
	"mirrorbars",
}

local GROUP_ALIASES = {
	actionbar = "actionbars",
	actionbars = "actionbars",
	bag = "bags",
	bags = "bags",
	buff = "buffs",
	buffs = "buffs",
	cast = "casting",
	casting = "casting",
	chat = "chat",
	chats = "chat",
	micro = "micromenu",
	micromenu = "micromenu",
	minimap = "minimap",
	mirror = "mirrorbars",
	mirrorbar = "mirrorbars",
	mirrorbars = "mirrorbars",
	quest = "questtracker",
	questtracker = "questtracker",
	tracker = "questtracker",
	unit = "unitframes",
	unitframe = "unitframes",
	unitframes = "unitframes",
}

local GROUPS = {
	actionbars = {
		"ActionButton1",
		"ActionButton2",
		"ActionButton3",
		"ActionButton4",
		"ActionButton5",
		"ActionButton6",
		"ActionButton7",
		"ActionButton8",
		"ActionButton9",
		"ActionButton10",
		"ActionButton11",
		"ActionButton12",
		"BonusActionButton1",
		"BonusActionButton2",
		"BonusActionButton3",
		"BonusActionButton4",
		"BonusActionButton5",
		"BonusActionButton6",
		"BonusActionButton7",
		"BonusActionButton8",
		"BonusActionButton9",
		"BonusActionButton10",
		"BonusActionButton11",
		"BonusActionButton12",
		"MultiBarBottomLeft",
		"MultiBarBottomRight",
		"MultiBarLeft",
		"MultiBarRight",
		"MultiBar5",
		"MultiBar6",
		"MultiBar7",
		"PetActionBar",
		"PetActionBarFrame",
		"PossessBarFrame",
		"ShapeshiftBarFrame",
		"StanceBar",
		"StanceBarFrame",
		"OverrideActionBar",
		"ExtraActionBarFrame",
		"ZoneAbilityFrame",
		"MainMenuBarVehicleLeaveButton",
		"MainStatusTrackingBarContainer",
	},
	unitframes = {
		"PlayerFrame",
		"PetFrame",
		"TargetFrame",
		"TargetFrameToT",
		"FocusFrame",
		"FocusFrameToT",
		"PartyFrame",
		"PartyMemberFrame1",
		"PartyMemberFrame2",
		"PartyMemberFrame3",
		"PartyMemberFrame4",
		"CompactPartyFrame",
		"CompactRaidFrameManager",
		"CompactRaidFrameContainer",
		"Boss1TargetFrame",
		"Boss2TargetFrame",
		"Boss3TargetFrame",
		"Boss4TargetFrame",
		"Boss5TargetFrame",
		"ArenaEnemyFrame1",
		"ArenaEnemyFrame2",
		"ArenaEnemyFrame3",
		"ArenaEnemyFrame4",
		"ArenaEnemyFrame5",
	},
	minimap = {
		"MinimapCluster",
		"Minimap",
		"MiniMapTracking",
		"MiniMapMailFrame",
		"GameTimeFrame",
		"MinimapZoneTextButton",
		"MinimapBackdrop",
		"MinimapBorder",
		"MinimapBorderTop",
		"MinimapZoomIn",
		"MinimapZoomOut",
	},
	questtracker = {
		"ObjectiveTrackerFrame",
		"QuestWatchFrame",
		"WatchFrame",
		"QuestTimerFrame",
		"ScenarioObjectiveTracker",
	},
	chat = {
		"ChatFrame1",
		"ChatFrame2",
		"ChatFrame3",
		"ChatFrame4",
		"ChatFrame5",
		"ChatFrame6",
		"ChatFrame7",
		"ChatFrame8",
		"ChatFrame9",
		"ChatFrame10",
		"GeneralDockManager",
		"ChatFrameMenuButton",
		"QuickJoinToastButton",
	},
	bags = {
		"MainMenuBarBackpackButton",
		"CharacterBag0Slot",
		"CharacterBag1Slot",
		"CharacterBag2Slot",
		"CharacterBag3Slot",
		"KeyRingButton",
	},
	micromenu = {
		"CharacterMicroButton",
		"SpellbookMicroButton",
		"TalentMicroButton",
		"AchievementMicroButton",
		"QuestLogMicroButton",
		"GuildMicroButton",
		"LFDMicroButton",
		"CollectionsMicroButton",
		"EJMicroButton",
		"StoreMicroButton",
		"MainMenuMicroButton",
		"HelpMicroButton",
	},
	buffs = {
		"BuffFrame",
		"DebuffFrame",
		"TemporaryEnchantFrame",
		"ConsolidatedBuffs",
		"PlayerBuffTimerManager",
	},
	casting = {
		"CastingBarFrame",
		"PlayerCastingBarFrame",
		"TargetFrameSpellBar",
		"FocusFrameSpellBar",
		"PetCastingBarFrame",
		"EnemyCastingBar",
	},
	mirrorbars = {
		"MirrorTimer1",
		"MirrorTimer2",
		"MirrorTimer3",
		"MirrorTimerContainer",
	},
}

local function safeCall(fn, ...)
	if type(fn) ~= "function" then
		return nil
	end

	local ok, first, second, third, fourth, fifth = pcall(fn, ...)
	if not ok then
		return nil
	end

	return first, second, third, fourth, fifth
end

local function isInCombat()
	if InCombatLockdown and InCombatLockdown() then
		return true
	end

	if UnitAffectingCombat and UnitAffectingCombat("player") then
		return true
	end

	return false
end

local function ensureHiddenParent()
	if hiddenParent then
		return hiddenParent
	end

	if not CreateFrame or not UIParent then
		return nil
	end

	hiddenParent = _G and _G[HIDDEN_PARENT_NAME] or nil

	if not hiddenParent then
		hiddenParent = CreateFrame("Frame", HIDDEN_PARENT_NAME, UIParent)
	end

	if hiddenParent.Hide then
		hiddenParent:Hide()
	end

	if hiddenParent.SetAlpha then
		hiddenParent:SetAlpha(0)
	end

	if hiddenParent.EnableMouse then
		hiddenParent:EnableMouse(false)
	end

	if hiddenParent.EnableMouseWheel then
		hiddenParent:EnableMouseWheel(false)
	end

	if hiddenParent.SetIgnoreParentScale then
		hiddenParent:SetIgnoreParentScale(true)
	end

	if hiddenParent.SetIgnoreParentAlpha then
		hiddenParent:SetIgnoreParentAlpha(true)
	end

	return hiddenParent
end

local function ensureCombatWatcher()
	if combatWatcher or not CreateFrame then
		return
	end

	combatWatcher = CreateFrame("Frame")
	combatWatcher:RegisterEvent("PLAYER_REGEN_ENABLED")
	combatWatcher:SetScript("OnEvent", function()
		if not isInCombat() then
			UIVisibility.ProcessQueue()
		end
	end)
end

local function queueOrRun(callback)
	if isInCombat() then
		UIVisibility.pendingOps[#UIVisibility.pendingOps + 1] = callback
		ensureCombatWatcher()
		return true, "queued"
	end

	return callback()
end

local function normalizeGroup(group)
	if type(group) ~= "string" then
		return nil
	end

	local key = string.lower(group):gsub("[%s_-]+", "")
	return GROUP_ALIASES[key]
end

local function snapshotPoints(frame)
	local points = {}
	local count = safeCall(frame.GetNumPoints, frame) or 0

	for index = 1, count do
		local point, relativeTo, relativePoint, xOffset, yOffset = safeCall(frame.GetPoint, frame, index)
		points[#points + 1] = {
			point = point,
			relativeTo = relativeTo,
			relativePoint = relativePoint,
			xOffset = xOffset,
			yOffset = yOffset,
		}
	end

	return points
end

local function restorePoints(frame, points)
	if not points or not frame.ClearAllPoints or not frame.SetPoint then
		return
	end

	safeCall(frame.ClearAllPoints, frame)

	for _, point in ipairs(points) do
		if point.point then
			safeCall(frame.SetPoint, frame, point.point, point.relativeTo, point.relativePoint, point.xOffset, point.yOffset)
		end
	end
end

local function getFrameState(frame)
	local state = UIVisibility.frameStates[frame]

	if state then
		return state
	end

	state = {
		parent = safeCall(frame.GetParent, frame),
		points = snapshotPoints(frame),
		wasShown = safeCall(frame.IsShown, frame) == true,
		mouseEnabled = safeCall(frame.IsMouseEnabled, frame),
		mouseWheelEnabled = safeCall(frame.IsMouseWheelEnabled, frame),
		hiddenBy = {},
		hiddenByCount = 0,
	}

	UIVisibility.frameStates[frame] = state

	return state
end

local function applyHide(frame)
	local parent = ensureHiddenParent()
	if not parent then
		return false, "hidden parent is unavailable"
	end

	if frame.SetParent then
		safeCall(frame.SetParent, frame, parent)
	end

	if frame.Hide then
		safeCall(frame.Hide, frame)
	end

	if frame.EnableMouse then
		safeCall(frame.EnableMouse, frame, false)
	end

	if frame.EnableMouseWheel then
		safeCall(frame.EnableMouseWheel, frame, false)
	end

	return true
end

local function applyRestore(frame, state)
	if state.parent and frame.SetParent then
		safeCall(frame.SetParent, frame, state.parent)
	end

	restorePoints(frame, state.points)

	if state.mouseEnabled ~= nil and frame.EnableMouse then
		safeCall(frame.EnableMouse, frame, state.mouseEnabled == true)
	end

	if state.mouseWheelEnabled ~= nil and frame.EnableMouseWheel then
		safeCall(frame.EnableMouseWheel, frame, state.mouseWheelEnabled == true)
	end

	if state.wasShown then
		if frame.Show then
			safeCall(frame.Show, frame)
		end
	elseif frame.Hide then
		safeCall(frame.Hide, frame)
	end
end

local function resolveGroupFrames(groupName)
	local frames = {}
	local seenFrames = {}

	for _, frameName in ipairs(GROUPS[groupName] or {}) do
		local frame = _G and _G[frameName] or nil

		if frame and not seenFrames[frame] then
			frames[#frames + 1] = frame
			seenFrames[frame] = true
		end
	end

	return frames
end

local function markFrameForGroup(frame, groupName, framesToHide)
	local state = getFrameState(frame)

	if state.hiddenBy[groupName] then
		return
	end

	state.hiddenBy[groupName] = true
	state.hiddenByCount = state.hiddenByCount + 1

	if state.hiddenByCount == 1 then
		framesToHide[#framesToHide + 1] = frame
	end
end

local function restoreFrameForGroup(frame, groupName)
	local state = UIVisibility.frameStates[frame]

	if not state or not state.hiddenBy[groupName] then
		return
	end

	state.hiddenBy[groupName] = nil
	state.hiddenByCount = state.hiddenByCount - 1

	if state.hiddenByCount <= 0 then
		applyRestore(frame, state)
		UIVisibility.frameStates[frame] = nil
	end
end

local function hideGroup(groupName)
	local groupState = UIVisibility.groupStates[groupName]

	if groupState and groupState.hidden then
		return true, "applied", groupName
	end

	local frames = resolveGroupFrames(groupName)
	local framesToHide = {}

	if #frames > 0 and not ensureHiddenParent() then
		return false, "hidden parent is unavailable"
	end

	for _, frame in ipairs(frames) do
		markFrameForGroup(frame, groupName, framesToHide)
	end

	for _, frame in ipairs(framesToHide) do
		local ok, err = applyHide(frame)
		if not ok then
			return false, err
		end
	end

	UIVisibility.groupStates[groupName] = {
		hidden = true,
		frames = frames,
	}

	return true, "applied", groupName
end

local function showGroup(groupName)
	local groupState = UIVisibility.groupStates[groupName]

	if not groupState or not groupState.hidden then
		return true, "applied", groupName
	end

	for _, frame in ipairs(groupState.frames or {}) do
		restoreFrameForGroup(frame, groupName)
	end

	UIVisibility.groupStates[groupName] = nil

	return true, "applied", groupName
end

function UIVisibility.ProcessQueue()
	if isInCombat() then
		return
	end

	local pending = UIVisibility.pendingOps
	UIVisibility.pendingOps = {}

	for _, callback in ipairs(pending) do
		callback()
	end
end

function UIVisibility.GetGroupNames()
	local names = {}

	for _, groupName in ipairs(GROUP_ORDER) do
		names[#names + 1] = groupName
	end

	return names
end

function UIVisibility.NormalizeGroup(group)
	return normalizeGroup(group)
end

function UIVisibility.HideAll()
	return queueOrRun(function()
		if not UIParent or not UIParent.Hide then
			return false, "UIParent is unavailable"
		end

		local ok, err = pcall(UIParent.Hide, UIParent)
		if not ok then
			return false, err
		end

		UIVisibility.allHidden = true

		return true, "applied"
	end)
end

function UIVisibility.ShowAll()
	return queueOrRun(function()
		if not UIParent or not UIParent.Show then
			return false, "UIParent is unavailable"
		end

		local ok, err = pcall(UIParent.Show, UIParent)
		if not ok then
			return false, err
		end

		UIVisibility.allHidden = false

		return true, "applied"
	end)
end

function UIVisibility.ToggleAll()
	local uiParentHidden = UIVisibility.GetStatus().allHidden

	if uiParentHidden then
		return UIVisibility.ShowAll()
	end

	return UIVisibility.HideAll()
end

function UIVisibility.Hide(group)
	local groupName = normalizeGroup(group)

	if not groupName then
		return false, "unknown UI group: " .. tostring(group)
	end

	return queueOrRun(function()
		return hideGroup(groupName)
	end)
end

function UIVisibility.Show(group)
	local groupName = normalizeGroup(group)

	if not groupName then
		return false, "unknown UI group: " .. tostring(group)
	end

	return queueOrRun(function()
		return showGroup(groupName)
	end)
end

function UIVisibility.Toggle(group)
	local groupName = normalizeGroup(group)

	if not groupName then
		return false, "unknown UI group: " .. tostring(group)
	end

	if UIVisibility.groupStates[groupName] and UIVisibility.groupStates[groupName].hidden then
		return UIVisibility.Show(groupName)
	end

	return UIVisibility.Hide(groupName)
end

function UIVisibility.ShowEverythingManaged()
	return queueOrRun(function()
		for _, groupName in ipairs(GROUP_ORDER) do
			showGroup(groupName)
		end

		return true, "applied"
	end)
end

function UIVisibility.GetStatus()
	local groups = {}
	local groupStates = {}
	local allHidden = UIVisibility.allHidden

	if UIParent and UIParent.IsShown then
		allHidden = safeCall(UIParent.IsShown, UIParent) ~= true
	end

	for _, groupName in ipairs(GROUP_ORDER) do
		local frameCount = #resolveGroupFrames(groupName)
		local hidden = UIVisibility.groupStates[groupName] and UIVisibility.groupStates[groupName].hidden == true or false

		groups[#groups + 1] = {
			name = groupName,
			hidden = hidden,
			frameCount = frameCount,
		}

		groupStates[groupName] = hidden
	end

	return {
		allHidden = allHidden == true,
		trackedAllHidden = UIVisibility.allHidden == true,
		groups = groups,
		groupStates = groupStates,
		pendingCount = #UIVisibility.pendingOps,
	}
end
