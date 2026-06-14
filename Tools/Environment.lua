local _, WEP = ...

WEP.Tools = WEP.Tools or {}

local Environment = {}
WEP.Tools.Environment = Environment

WEP:Log("Environment", "loaded")

local DEFAULT_NAMEPLATE_LIMIT = 40
local DEFAULT_BOSS_LIMIT = 5
local DEFAULT_PARTY_LIMIT = 4
local DEFAULT_RAID_LIMIT = 40

local POWER_TYPE_NAMES = {
	[0] = "mana",
	[1] = "rage",
	[2] = "focus",
	[3] = "energy",
	[6] = "runic_power",
}

local function safeCall(fn, ...)
	if type(fn) ~= "function" then
		return nil
	end

	local ok, first, second, third, fourth, fifth, sixth, seventh, eighth, ninth, tenth = pcall(fn, ...)
	if not ok then
		return nil
	end

	return first, second, third, fourth, fifth, sixth, seventh, eighth, ninth, tenth
end

local function round(value, decimals)
	if type(value) ~= "number" then
		return nil
	end

	local scale = 10 ^ (decimals or 0)
	return math.floor((value * scale) + 0.5) / scale
end

local function getLimit(value, defaultValue)
	value = tonumber(value) or defaultValue

	if value < 0 then
		return 0
	end

	return math.floor(value)
end

local function addUniqueToken(tokens, seenTokens, unitToken)
	if type(unitToken) ~= "string" or unitToken == "" or seenTokens[unitToken] then
		return
	end

	tokens[#tokens + 1] = unitToken
	seenTokens[unitToken] = true
end

local function getGuidInfo(guid)
	if type(guid) ~= "string" or guid == "" then
		return nil
	end

	local parts = {}
	for part in guid:gmatch("[^-]+") do
		parts[#parts + 1] = part
	end

	return {
		raw = guid,
		type = parts[1],
		id = tonumber(parts[6]),
	}
end

local function getMapPosition(mapId)
	if not mapId or not C_Map or not C_Map.GetPlayerMapPosition then
		return nil, nil
	end

	local position = safeCall(C_Map.GetPlayerMapPosition, mapId, "player")
	if not position then
		return nil, nil
	end

	local x, y
	if position.GetXY then
		x, y = position:GetXY()
	elseif position.x and position.y then
		x, y = position.x, position.y
	end

	if type(x) ~= "number" or type(y) ~= "number" then
		return nil, nil
	end

	return round(x * 100, 2), round(y * 100, 2)
end

local function getReaction(unit)
	local reaction = safeCall(UnitReaction, unit, "player")

	if not reaction then
		return nil
	end

	if reaction <= 3 then
		return reaction, "hostile"
	end

	if reaction == 4 then
		return reaction, "neutral"
	end

	return reaction, "friendly"
end

local function getPower(unit)
	local powerTypeId, powerTypeToken = safeCall(UnitPowerType, unit)
	local power = safeCall(UnitPower, unit, powerTypeId)
	local powerMax = safeCall(UnitPowerMax, unit, powerTypeId)

	return {
		typeId = powerTypeId,
		type = powerTypeToken or POWER_TYPE_NAMES[powerTypeId],
		current = power,
		max = powerMax,
		percent = powerMax and powerMax > 0 and round((power or 0) / powerMax * 100, 1) or nil,
	}
end

function Environment.GetLocation()
	local mapId = C_Map and C_Map.GetBestMapForUnit and safeCall(C_Map.GetBestMapForUnit, "player") or nil
	local x, y = getMapPosition(mapId)
	local inInstance, instanceType = safeCall(IsInInstance)
	local instanceName, instanceKind, difficultyId, difficultyName, maxPlayers, dynamicDifficulty, isDynamic, instanceMapId, groupSize =
		safeCall(GetInstanceInfo)
	local pvpType, isSubZonePvP, factionName = safeCall(GetZonePVPInfo)

	return {
		zone = safeCall(GetZoneText),
		realZone = safeCall(GetRealZoneText),
		subZone = safeCall(GetSubZoneText),
		minimapZone = safeCall(GetMinimapZoneText),
		mapId = mapId,
		x = x,
		y = y,
		instance = {
			inInstance = inInstance == true,
			type = instanceType or instanceKind,
			name = instanceName,
			difficultyId = difficultyId,
			difficultyName = difficultyName,
			maxPlayers = maxPlayers,
			dynamicDifficulty = dynamicDifficulty,
			isDynamic = isDynamic,
			mapId = instanceMapId,
			groupSize = groupSize,
		},
		pvp = {
			type = pvpType,
			isSubZonePvP = isSubZonePvP,
			factionName = factionName,
		},
		flags = {
			resting = safeCall(IsResting) == true,
			indoors = safeCall(IsIndoors) == true,
			outdoors = safeCall(IsOutdoors) == true,
			swimming = safeCall(IsSwimming) == true,
			flying = safeCall(IsFlying) == true,
			mounted = safeCall(IsMounted) == true,
			falling = safeCall(IsFalling) == true,
		},
	}
end

function Environment.GetUnit(unit)
	if type(unit) ~= "string" or unit == "" or not UnitExists or not UnitExists(unit) then
		return nil
	end

	local name, realm = safeCall(UnitName, unit)
	local guid = safeCall(UnitGUID, unit)
	local guidInfo = getGuidInfo(guid)
	local reaction, reactionLabel = getReaction(unit)
	local health = safeCall(UnitHealth, unit)
	local healthMax = safeCall(UnitHealthMax, unit)
	local className, classFile = safeCall(UnitClass, unit)
	local raceName, raceFile = safeCall(UnitRace, unit)
	local targetName = UnitExists and UnitExists(unit .. "target") and safeCall(UnitName, unit .. "target") or nil

	return {
		unit = unit,
		name = name,
		realm = realm,
		guid = guid,
		guidType = guidInfo and guidInfo.type or nil,
		npcId = guidInfo and guidInfo.id or nil,
		level = safeCall(UnitLevel, unit),
		classification = safeCall(UnitClassification, unit),
		creatureType = safeCall(UnitCreatureType, unit),
		creatureFamily = safeCall(UnitCreatureFamily, unit),
		reaction = reaction,
		reactionLabel = reactionLabel,
		className = className,
		classFile = classFile,
		raceName = raceName,
		raceFile = raceFile,
		factionGroup = safeCall(UnitFactionGroup, unit),
		isPlayer = safeCall(UnitIsPlayer, unit) == true,
		isPlayerControlled = safeCall(UnitPlayerControlled, unit) == true,
		isFriend = safeCall(UnitIsFriend, "player", unit) == true,
		isEnemy = safeCall(UnitIsEnemy, "player", unit) == true,
		canAttack = safeCall(UnitCanAttack, "player", unit) == true,
		canAssist = safeCall(UnitCanAssist, "player", unit) == true,
		isDeadOrGhost = safeCall(UnitIsDeadOrGhost, unit) == true,
		isTapped = safeCall(UnitIsTapDenied, unit) == true,
		inCombat = safeCall(UnitAffectingCombat, unit) == true,
		health = {
			current = health,
			max = healthMax,
			percent = healthMax and healthMax > 0 and round((health or 0) / healthMax * 100, 1) or nil,
		},
		power = getPower(unit),
		targetName = targetName,
	}
end

function Environment.GetNameplateTokens(limit)
	local tokens = {}
	local seenTokens = {}
	limit = getLimit(limit, DEFAULT_NAMEPLATE_LIMIT)

	if C_NamePlate and C_NamePlate.GetNamePlates then
		local nameplates = safeCall(C_NamePlate.GetNamePlates)
		if type(nameplates) == "table" then
			for _, nameplate in ipairs(nameplates) do
				addUniqueToken(tokens, seenTokens, nameplate.namePlateUnitToken)

				if nameplate.UnitFrame then
					addUniqueToken(tokens, seenTokens, nameplate.UnitFrame.unit)
				end
			end
		end
	end

	for index = 1, limit do
		addUniqueToken(tokens, seenTokens, "nameplate" .. index)
	end

	return tokens
end

function Environment.GetUnitTokens(options)
	options = options or {}

	local tokens = {}
	local seenTokens = {}

	addUniqueToken(tokens, seenTokens, "player")
	addUniqueToken(tokens, seenTokens, "target")
	addUniqueToken(tokens, seenTokens, "mouseover")
	addUniqueToken(tokens, seenTokens, "focus")
	addUniqueToken(tokens, seenTokens, "pet")

	for index = 1, getLimit(options.bossLimit, DEFAULT_BOSS_LIMIT) do
		addUniqueToken(tokens, seenTokens, "boss" .. index)
	end

	for index = 1, getLimit(options.partyLimit, DEFAULT_PARTY_LIMIT) do
		addUniqueToken(tokens, seenTokens, "party" .. index)
		addUniqueToken(tokens, seenTokens, "partypet" .. index)
	end

	for index = 1, getLimit(options.raidLimit, DEFAULT_RAID_LIMIT) do
		addUniqueToken(tokens, seenTokens, "raid" .. index)
		addUniqueToken(tokens, seenTokens, "raidpet" .. index)
	end

	if options.includeNameplates ~= false then
		for _, token in ipairs(Environment.GetNameplateTokens(options.nameplateLimit)) do
			addUniqueToken(tokens, seenTokens, token)
		end
	end

	return tokens
end

function Environment.GetUnits(options)
	local units = {}
	local seenGuids = {}

	for _, unitToken in ipairs(Environment.GetUnitTokens(options)) do
		local unit = Environment.GetUnit(unitToken)

		if unit then
			local dedupeKey = unit.guid or unit.name or unit.unit
			if not seenGuids[dedupeKey] then
				units[#units + 1] = unit
				seenGuids[dedupeKey] = true
			end
		end
	end

	return units
end

function Environment.GetSnapshot(options)
	local snapshot = {
		capturedAt = WEP.Tools.Timer.Now(),
		location = Environment.GetLocation(),
		player = Environment.GetUnit("player"),
		target = Environment.GetUnit("target"),
		mouseover = Environment.GetUnit("mouseover"),
		focus = Environment.GetUnit("focus"),
		units = Environment.GetUnits(options),
	}

	WEP:Log("Environment", "snapshot_captured", {
		mapId = snapshot.location and snapshot.location.mapId or "none",
		unitCount = #snapshot.units,
		hasTarget = snapshot.target ~= nil,
	})

	return snapshot
end

function Environment.GetStatus(options)
	local snapshot = Environment.GetSnapshot(options)
	WEP:Log("Environment", "status_captured", {
		unitCount = #snapshot.units,
		hasTarget = snapshot.target ~= nil,
		hasMouseover = snapshot.mouseover ~= nil,
		hasFocus = snapshot.focus ~= nil,
	})

	return {
		location = snapshot.location,
		unitCount = #snapshot.units,
		hasTarget = snapshot.target ~= nil,
		hasMouseover = snapshot.mouseover ~= nil,
		hasFocus = snapshot.focus ~= nil,
	}
end
