-- Autoplayer API
-- Made with love
-- By Kawi

local settings = {
	Version = "2.14", -- autoplayer version

	Author = {
		DiscordServer = "https://discord.gg/4bexJD6WVT",
		Discord = "@its_kawi"
	},

	AutoPlay = false,
	CopyEnemyNotes = false, -- I find this stupid | When your lane has no arrows, it autoplays enemy's notes
	HitOffset = 0,

	SVEnabled = false,
	PressKeyMode = false,
	
	FrameworkConnected = false, -- read only

	Performance = {
		Notes = 2, -- 0 - 10. 0-8 decrease amount of notes that can be rendered, 9 hides opponent's side, 10 hides your's
		UI = 0, -- 0 - 3. 1 removes accuracy gauge, 2 removes indicators (sick, good, etc.), 3 hides the whole HUD 

		Disable3D = false
	},

	KPS = { -- limits your keys per second
		PerKey = 0, -- 0 = inf
		Global = 0, -- 0 = inf
	},

	HoldDuration = {
		Value = 0.05, -- in seconds
		Random = 0.05 -- range: -25% to 100% | in seconds
	},

	MoreStats = false, -- if true, stats will have autoplayer stats also, if string, it will act as its "true", but will contain that one string on top of the stats

	TimeLeft = 0,
	TimePassed = 0,
	SongRealDuration = 0,
	SongDuration = 0,

	ScrollSpeed = 0,

	Display = {
		Lanes = {
			Me = {
				TotalNotes = 0,
				NotesRendered = 0,
				NotesVisible = 0
			},
			Enemy = {
				TotalNotes = 0,
				NotesRendered = 0,
				NotesVisible = 0
			}
		},

		TotalNotes = 0,
		NotesRendered = 0,
		NotesVisible = 0,

		FPS = 0,
		KPS = 0,

		IsModChart = false,
		IsSV = false,

		Rate = 1,
		SongDifficulty = "",
		SongNameColor = Color3.new(1, 1, 1),
		SongName = "",
		TimeLeft = 0,
		SongDuration = 0,
		SongRealDuration = 0,
		TimePassed = 0,
	},

	Spray = false, -- aka Legit | makes ms splat when you hit notes, e.g. static 40 ms will turn into from 40 to -20 ms
	PerfectSick = 0, -- 0 to 2

	Chances = {
		Sick = 100,
		Good = 0,
		Ok = 0,
		Bad = 0,
		Miss = 0
	},

	Supported = { -- 3 = supported, 2 = kinda supported, 1 = poorly supported, 0 = not supported
		["SV"] = 2,
		["Mod Charts"] = 3,
		["Multi-Key"] = 3,
		["60 FPS+"] = 3,
		["Low FPS"] = 3,
		["Down & Up Scroll"] = 3,
		["Start Auto Play mid-song"] = 3,
		["Solara/Mobile"] = 3,
		["Keep Auto-Playing while buzy"] = 3
	}
}

local global = getfenv().getgenv and getfenv().getgenv() or _G
local key = "FFAutoPlayLib"

if global[key] then
	return global[key]
end

local GITHUB = "https://raw.githubusercontent.com/Its-Kawi/"
local util = (getfenv().getgenv or function() return _G end)().QKUtil or (function() local url = GITHUB .. "Utilities/refs/heads/main/Utility/Main.lua" local rf, IF = getfenv().readfile or getfenv().read_file, getfenv().isfile or getfenv().is_file return loadstring(rf and IF and IF("QUtil/Utility.lua") and rf("QUtil/Utility.lua") or getfenv().request and getfenv().request({ Url = url, Method = "GET" }).Body or game:HttpGet(url))() end)()

if global[key] then
	return global[key]
end

local event = util:Event()
local message = event.new()
local songStarted = event.new()
local songStopped = event.new()
local songStopped = event.new()
local noteAdded = event.new()
local noteRemoved = event.new()

settings.Message = message

settings.Events = {
	SongStarted = songStarted, -- (<CORE>)
	SongStopped = songStopped, -- (<CORE>)
	Message = message, -- (text, title)
	NoteAdded = noteAdded, -- (<NOTE>)
	NoteRemoved = noteRemoved -- (<NOTE>)
}

local plrs = game:GetService("Players")
local plr = plrs.LocalPlayer or plrs.PlayerAdded:Wait()
local pgui = plr:WaitForChild("PlayerGui")

local tick = tick
local defer = task.defer
local spawn = task.spawn
local delay = task.delay
local _wait = task.wait
local pcall = pcall
local max = math.max
local min = math.min
local error = error
local tonumber = tonumber
local insert = table.insert
local remove = table.remove
local find = table.find
local c3n = Color3.new
local random = math.random
local sort = table.sort
local abs = math.abs
local v2 = vector.create
local round = math.round
local clamp = math.clamp
local keypress = getfenv().keypress or getfenv().key_press
local keyrelease = getfenv().keyrelease or getfenv().key_release
local run_on_actor = getfenv().run_on_actor

local display = settings.Display

local function clone(a)
	local b = { }

	for i, v in a do
		b[i] = v
	end

	return b
end

local inf = 1 / 0

local lastOffset = 0
local function wait(t)
	t = max(tonumber(t) or 0, 0)
	local took = _wait(t)

	if t == 0 then
		lastOffset = took - t
	end

	return took
end

local globalScrollSpeedBuffer = { }
local globalScrollSpeed = 0

local songId = 0
local rate = 1
local timePassed = 0

spawn(function()
	local unpack = unpack or table.unpack
	local c3r, c3h = Color3.fromRGB, Color3.fromHex

	local function decodeTime(time)
		local split = time:split(":")
		if #split == 1 then return tonumber(time) end

		while #split < 4 do
			insert(split, 1, 0)
		end

		return (split[1] * 86400) + (split[2] * 3600) + (split[3] * 60) + split[4]
	end

	local topLabel = pgui:WaitForChild("GameGui"):WaitForChild("Screen"):WaitForChild("TopLabel"):WaitForChild("Label")
	topLabel.Changed:Connect(function()
		local text = topLabel.Text
		local splitted = text:split("\n")

		if #splitted == 3 then
			local l1, l3 = splitted[1], splitted[3]
			if l1:sub(-2, -1) == "x)" then
				local endBracket = -3
				while true do
					if l1:sub(endBracket, endBracket) == "(" then
						rate = tonumber(l1:sub(endBracket + 1, -3))
						display.Rate = rate
						break
					end

					endBracket -= 1
					if -endBracket > #l1 then
						display.Rate = 1
						break
					end
				end
			else
				display.Rate = 1
			end

			local difficultyStart = l1:find("</font> (", 0, true)
			if difficultyStart then
				local difficultyEnd = l1:find(")", difficultyStart, true)
				display.SongDifficulty = l1:sub(difficultyStart + 9, difficultyEnd - 1)
			end

			local colorStart = l1:find("><font color='", 0, true)
			if colorStart then
				local colorEnd = l1:find("'>", colorStart, true) + 1
				local color = l1:sub(colorStart + 14, colorEnd - 2):gsub("\n\r\f\t\s\0 ", ""):lower()

				if color:sub(1, 3) == "rgb" then
					display.SongNameColor = c3r(unpack(color:sub(5, -2):split(",")))
				elseif color:sub(1, 1) == "#" then
					display.SongNameColor = c3h(color:sub(2, -1))
				end
			end

			display.SongName = l1:sub((l1:find(")'>", 0, true)) + 3, (l1:find("</f", 0, true)) - 1)

			local s, r = pcall(decodeTime, l3:sub(1, -10))
			display.TimeLeft = s and r or 0
			settings.TimeLeft = display.TimeLeft
			display.SongDuration = max(display.TimeLeft, display["Song" .. "Duration"], 0) -- suspend studio warning
			display.SongRealDuration = round(display.SongDuration * display.Rate)
			settings.SongRealDuration = display.SongRealDuration

			timePassed = round((display.SongDuration - display.TimeLeft) * display.Rate)
			display.TimePassed = timePassed
			settings.TimePassed = display.TimePassed
		end
	end)
end)

local actions
if run_on_actor then
	spawn(function()
		local test = {
			[0] = false, -- COMMs READY
			[1] = false, -- SV Enabled
			[2] = false, -- Is SV
			[3] = 0, -- hitbox offset
			[4] = false, -- scroll speed changed?
		}
		
		spawn(run_on_actor, plr:WaitForChild("PlayerScripts"):WaitForChild("ClientActor"), [==[
local c = ...
local renv = getrenv and getrenv() or getfenv()
local wait = task.wait

local function loadFail(reason)
	return warn("FRAMEWORK NOT FOUND" .. (reason and ": " .. reason or ""))
end

if not renv then return loadFail("getrenv is missing in your executor environment") end

local _G = renv._G
local framework = _G.Client
while not framework do
	framework = _G.Client
	wait(0.01)
end

c[0] = true
repeat wait(0.01) until c[0] ~= true
	
print("FRAMEWORK COMMUNICATION IS READY")

local settings = framework.SettingsHandler.Settings
local oldSS = settings.ScrollSpeed

while wait(0.01) do
	local ss = settings.ScrollSpeed
	c[3] = settings.HitboxOffset
	c[4] = c[4] or ss ~= oldSS
	oldSS = ss

	local myField = framework.VSRG.GameHandler.Field
	if myField then
		c[1] = myField.SVCharts or false
		
		local game = myField.Game
		if game and game.Metadata then
			c[2] = game.Metadata.IsSV or false
		end
	else
		c[1] = false
		c[2] = false
	end
end
]==], test)

		repeat wait() until test[0]
		actions = test
		test[0] = false
		
		settings.FrameworkConnected = true
	end)
end

local inputs = { }
local tempConns = { }
local vsrgConnection, vsrgConn2

local scr = Enum.InputBindingType.Scriptable
local inpFire

local onInput; function onInput(v, overwrite)
	local input
	local laneNum = tonumber(v.Name:sub(5))
	local start = tick()

	while not input and vsrgConnection do
		for idx, val in v:GetChildren() do
			if val.Name:match("Gamepad") or tick() - start > 2 and val.Name:match("Keyboard") or tick() - start > 4 then
				input = val
				break
			end
		end
		
		if input then
			break
		end
		
		wait()
	end

	if not input then return end
	input.Type = scr
	
	if not overwrite then
		tempConns[#tempConns + 1] = input:GetPropertyChangedSignal("Type"):Connect(function()
			input.Type = scr
		end)
		
		local lastRefresh = 0
		tempConns[#tempConns + 1] = v.ChildAdded:Connect(function()
			local ct = tick()
			if ct - lastRefresh > 0.02 then
				lastRefresh = ct
				onInput(v, true)
			end
		end)
	end

	inputs[laneNum] = input
	inpFire = input.Fire
end

local function hookInputs(vsrgContext)
	inputs = { }

	vsrgConnection = vsrgContext:GetPropertyChangedSignal("Parent"):Connect(function()
		if not vsrgContext.Parent then
			for _, v in tempConns do
				if v.Connected then
					v:Disconnect()
				end
			end
			
			inputs = { }
			vsrgConnection:Disconnect()
			vsrgConn2:Disconnect()
			vsrgConnection = nil
		end
	end)

	for i, v in vsrgContext:GetChildren() do
		onInput(v)
	end

	vsrgConn2 = vsrgContext.ChildAdded:Connect(onInput)
end

local kbVals = { }
local kbs = { }
local function getUnrepeated(data)
	local n = #data
	local assignment = { }
	local used = { }

	local sortedIndices = { }
	for i = 1, n do sortedIndices[i] = i end

	sort(sortedIndices, function(a, b) return #data[a] < #data[b] end)

	local backtrack; backtrack = function(idx)
		if idx > n then return true end

		local setIdx = sortedIndices[idx]
		local candidates = { }

		for _, val in ipairs(data[setIdx]) do
			if not used[val] then
				insert(candidates, val)
			end
		end

		sort(candidates)

		for _, val in ipairs(candidates) do
			assignment[setIdx] = val
			used[val] = true

			if backtrack(idx + 1) then
				return true
			end

			used[val] = nil
			assignment[setIdx] = nil
		end

		return false
	end

	if backtrack(1) then
		local result = { }
		for i = 1, n do result[i] = assignment[i] end

		return result
	end

	return false
end

local _fireLane
function _fireLane(laneIndex, state)
	local inp = inputs[laneIndex]
	if not inp then return end

	local s, e = pcall(inpFire, inp, state)
	if not s then
		input.Type = scr
		_fireLane(laneIndex, state)
	end
end

local guiServ = game:GetService("GuiService")
local uis = game:GetService("UserInputService")
local escOpen, buzy = guiServ.MenuIsOpen, uis:GetFocusedTextBox() ~= nil
local onWindow = (getfenv().isrbxactive or getfenv().is_rbx_active or function() return true end)()

uis.WindowFocused:Connect(function()
	onWindow = true
end)

uis.WindowFocusReleased:Connect(function()
	onWindow = false
end)

guiServ.MenuClosed:Connect(function()
	escOpen = false
end)

guiServ.MenuOpened:Connect(function()
	escOpen = true
end)

uis.TextBoxFocused:Connect(function(tb)
	wait()
	buzy = true
end)

uis.TextBoxFocusReleased:Connect(function()
	buzy = false
end)

local keyEnums = util:Keys()
local _keyPressLane
function _keyPressLane(laneIndex, state)
	if escOpen or buzy or not onWindow then
		return _fireLane(laneIndex, state)
	end
	
	local kb = kbs[laneIndex]
	if not kb then return end

	kb = keyEnums[kb]
	
	if not kb then
		return _fireLane(laneIndex, state)
	end
	
	if state then
		keypress(kb)
	else
		keyrelease(kb)
	end
end

local mode = false
local function fireLane(...)
	if mode then
		_keyPressLane(...)
	else
		_fireLane(...)
	end
end

local kbsRefreshing = false
local ekc = Enum.KeyCode

local function refreshKbs()
	wait()
	if kbsRefreshing then return end
	
	kbsRefreshing = true
	kbs = getUnrepeated(kbVals)
	for i, v in kbs do
		kbs[i] = ekc:FromName(v)
	end
	
	wait()
	kbsRefreshing = false
end

local laneStates = { }
local laneHitIndexes = { }
local perLaneKPS = { }
local KPS = 0
local lastKeyHit = 0

local function appendKPS(lane)
	lastKeyHit = tick()

	KPS += 1
	perLaneKPS[lane] = (perLaneKPS[lane] or 0) + 1
	display.KPS = KPS

	wait(1)

	KPS -= 1
	perLaneKPS[lane] -= 1
	display.KPS = KPS
end

local function hitLane(laneIndex, duration)
	duration = duration or 0

	if laneStates[laneIndex] then
		fireLane(laneIndex, false)
		laneStates[laneIndex] = false
	end

	spawn(appendKPS, laneIndex)
	fireLane(laneIndex, true)
	laneStates[laneIndex] = true

	laneHitIndexes[laneIndex] = (laneHitIndexes[laneIndex] or -1) + 1
	local myIndex = laneHitIndexes[laneIndex]

	if duration > 0 then
		wait(duration)
	end

	if laneHitIndexes[laneIndex] == myIndex then
		fireLane(laneIndex, false)
		laneStates[laneIndex] = false
	end
end

local kpsBuffers = { }
local kpsK, kpsG = settings.KPS.PerKey, settings.KPS.Global
if kpsK == 0 then kpsK = inf end
if kpsG == 0 then kpsG = inf end

local function tryHitLane(laneIndex, duration, skipWait)
	local current = tick()
	local k = settings.KPS

	if (perLaneKPS[laneIndex] or 0) > round(kpsK / 2.5) or 1 / kpsK > current - (kpsBuffers[laneIndex] or 0) or KPS > kpsG then return false end
	kpsBuffers[laneIndex] = current

	if skipWait then
		spawn(hitLane, laneIndex, duration)
	else
		hitLane(laneIndex, duration)
	end

	return true
end

local function waitForChildError(object, childName, timeout)
	timeout = timeout or 30

	local ret = object:WaitForChild(childName, timeout)
	if not ret then
		error("Failed to find child \"" .. childName .. "\" in " .. object:GetFullName() .. " in " .. timeout .. " seconds", 0)
	end

	return ret
end

local function getAverage(t)
	local avg = 0
	local l = #t

	for i = 1, l do
		avg += t[i]
	end

	avg /= l
	return avg ~= avg and 0 or avg
end

local function append(table, value, size)
	local size = round(max(tonumber(size) or 0, 1))

	while #table >= size do
		remove(table, #table)
	end

	insert(table, 1, value)
	return getAverage(table)
end

local rng = random()

local badNoteAssets = { "rbxassetid://103483801062498", "rbxassetid://88530467220950", "rbxassetid://109130876544260", "rbxassetid://120222801097284", "rbxassetid://101951481332606" }
local black = c3n()
local ch = settings.Chances

local function rollChance()
	local total = 0
	for _, weight in ch do
		total += weight
	end

	local r = rng * total
	local sum = 0

	for k, weight in ch do
		sum += weight
		if r <= sum then
			return k
		end
	end

	return "Sick"
end

local useX = false
local function UDimToVector2(ud)
	return v2(useX and ud.X.Scale or 0, ud.Y.Scale, 0)
end

local function isDownS(data)
	local topOnes = 0
	local receptor = data.Receptor

	for laneIndex, note in data.Notes do
		if note.Note.Position.Y.Scale < receptor.Position.Y.Scale + 0.5 then
			topOnes += 1
		end
	end

	return topOnes / #data.Notes > 0.75
end

local function sortLane(data)
	local function sortF(a, b)
		local cond = a.Note.Position.Y.Scale < b.Note.Position.Y.Scale
		if data.IsDownScroll then
			cond = not cond
		end

		return cond
	end

	sort(data.Notes, sortF)
	sort(data.BadNotes, sortF)
end

local boolIdx = {
	[true] = "Me",
	[false] = "Enemy"
}

local total = 0
local sperf = settings.Performance
local notesperf = sperf.Notes
local renderQueue = {
	[true] = { }, -- mine
	[false] = { } -- enemy
}

local alreadyRendered = {
	[true] = 0,
	[false] = 0
}

local function calcRender(isMine)
	return round(notesperf <= 0 and inf or (notesperf >= 9 and not isMine or notesperf >= 10 and isMine) and 0 or (1000 / globalScrollSpeed) / min(notesperf, 8))
end

local dlanes = display.Lanes
local function flushRenderQueue(queue, isMine)
	local maxRendersAllowed = calcRender(isMine)
	local canRender = maxRendersAllowed - alreadyRendered[isMine]
	
	for i = min(canRender, #queue), 1, -1 do
		local note = remove(queue, i)
		note.Visible = true
			
		alreadyRendered[isMine] += 1
	end
	
	dlanes[boolIdx[isMine]].NotesVisible = alreadyRendered[isMine]
	display.NotesVisible = dlanes[boolIdx[true]].NotesVisible + dlanes[boolIdx[false]].NotesVisible
end

noteAdded:Connect(function(note)
	local isMine = note.IsMine
	local queue = renderQueue[isMine]
	local note = note.Note
	local maxRendersAllowed = calcRender(isMine)
	
	note.Visible = notesperf <= 0
	insert(queue, note)
	flushRenderQueue(queue, isMine)
end)

noteRemoved:Connect(function(note)
	local isMine = note.IsMine
	local queue = renderQueue[isMine]
	
	local found = find(queue, note.Note)
	if found then
		remove(queue, found)
	else
		alreadyRendered[isMine] -= 1
	end
	
	flushRenderQueue(queue, isMine)
end)

local dataIndex = {
	[true] = "My",
	[false] = "Enemy"
}

local offsets = {
	Sick = 0.05,
	Good = 0.1,
	Ok = 0.15,
	Bad = 0.2,
	Miss = 0.3
}

local offsetOffset = 0.01
local hitOffset0 = offsets.Sick
local hitOffset01 = hitOffset0 - offsetOffset
local hitOffset02 = offsetOffset * 2
local rendered = 0
local spr = settings.Spray

local function onNote(note, data, sharedData, isNew, isMine)
	local sprite = note:WaitForChild("LayeredSprite"):WaitForChild("1")
	local isBlack = sprite.ImageColor3 == black

	local n = dataIndex[isMine] .. "Notes"
	local n2 = dataIndex[isMine] .. "BlackNotes"

	sharedData.Notes += 1
	sharedData[n] += 1
	sharedData[n2] += isBlack and isMine and 1 or 0

	local isGood = (not isBlack or sharedData[n2] / sharedData[n] > 0.75) and not find(badNoteAssets, sprite.Image)
	local toInsert
	if isGood then
		toInsert = data.Notes
	else
		toInsert = data.BadNotes
	end

	local catName = boolIdx[isMine]
	local cat = dlanes[catName]
	local rolled = rollChance()

	local destroying = event.new()
	local noteData = {
		Note = note,
		Rolled = rolled,
		HitDistance = spr and (rolled == "Sick" and (rng * 0.075) - 0.025 - offsetOffset or max(offsets[rolled] - hitOffset0, 0) + hitOffset02 + (rng * hitOffset01)) or offsets[rolled] or hitOffset01,
		PSickAdjust = 0,
		IsBad = not isGood,
		IsNew = isNew,
		IsMine = isMine,
		Hit = false,
		Lane = data,
		LaneIndex = data.LaneIndex,
		Destroyed = false,
		Destroying = destroying,
		DisplayCategory = cat,
		CategoryName = catName
	}

	local m = isMine and 1 or 0

	total += 1
	cat.TotalNotes += 1
	cat.NotesRendered += 1
	display.TotalNotes += 1
	display.NotesRendered += 1
	rendered += 1

	defer(noteAdded.Fire, noteAdded, noteData)

	toInsert[#toInsert + 1] = noteData
	if isNew then
		local isDownScrollSpawn = note.Position.Y.Scale < data.Receptor.Position.Y.Scale + 0.5
		if isDownScrollSpawn ~= data.IsDownScroll then
			data.IsDownScroll = isDownScrollSpawn
			sortLane(data)
		end
	end

	while note.Parent do
		note:GetPropertyChangedSignal("Parent"):Wait()
	end

	cat.NotesRendered -= 1
	display.NotesRendered -= 1
	rendered -= m

	noteRemoved:Fire(noteData)
	destroying:Fire()
	noteData.Destroyed = true

	local found = find(toInsert, noteData)
	if found then
		remove(toInsert, found)
	end
end

local function labelAdded(laneNum, label, cons)
	local textL = label:WaitForChild("Text", 9e9)
	kbVals[laneNum] = kbVals[laneNum] or { }

	local myIdx = #kbVals[laneNum] + 1
	kbVals[laneNum][myIdx] = textL.Text

	cons[#cons + 1] = textL:GetPropertyChangedSignal("Text"):Connect(function()
		if textL.TextTransparency >= 0.95 then return end
		
		kbVals[laneNum][myIdx] = textL.Text
		refreshKbs()
	end)

	refreshKbs()
end

local function onLane(lane, data, sharedData, isMine)
	local laneNum = tonumber(lane.Name:sub(5))
	if not laneNum then return end

	data.LanesCount = max(data.LanesCount, laneNum)

	local Notes = { }
	local receptor = lane:WaitForChild("Receptor")

	local myData = {
		ScrollSpeed = 0,
		ScrollSpeedBuffer = { },
		LaneIndex = laneNum,
		Lane = lane,
		Notes = Notes,
		BadNotes = { },
		IsDownScroll = true,
		Receptor = receptor
	}

	data.Lanes[laneNum] = myData
	local notes = lane:WaitForChild("Notes")

	if not sharedData.Working then return end

	for i, v in notes:GetChildren() do
		spawn(onNote, v, myData, sharedData, false, isMine)
	end

	if #Notes > 0 then
		myData.IsDownScroll = isDownS(myData)
		sortLane(myData)
	end
	
	local cons = { }
	cons[#cons + 1] = notes.ChildAdded:Connect(function(v)
		onNote(v, myData, sharedData, true, isMine)
	end)
	
	local labels = lane:WaitForChild("Labels", 9e9)
	for i, v in labels:GetChildren() do
		spawn(labelAdded, laneNum, v, cons)
	end

	cons[#cons + 1] = labels.ChildAdded:Connect(function(v)
		spawn(labelAdded, laneNum, v, cons)
	end)
	
	delay(0.1, refreshKbs)

	sharedData.StoppedWorking:Wait()
	for i, v in cons do
		v:Disconnect()
	end
end

local function onField(field, myData, sharedData, isMine)
	local lanes = field:WaitForChild("Inner")
	if not sharedData.Working then return end

	for i, v in lanes:GetChildren() do
		spawn(onLane, v, myData, sharedData, isMine)
	end
end

local function getDistance(a, b)
	return (a - b).Magnitude
end

local function getClosest(toIterate)
	if not plr.Character then return end

	local c, d = nil, inf

	for _, v in toIterate:GetChildren() do
		local m = getDistance(v:GetPivot().Position, plr.Character:GetPivot().Position)
		if m < d then
			c, d = v, m
		end
	end

	return c, d
end

local function getMyStage()
	if workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("Stages") then
		return getClosest(workspace.Map.Stages)
	end
end

local function getMySide()
	local stage = getMyStage()
	if stage then
		local node = getClosest(stage.Nodes)
		if node then
			return node.Name:sub(1, node.Name:find("_") - 1)
		end
	end
end

local side = getMySide() or "Left"
local renderDelta = 0
local fps = 0
local estFps = 0
local fpsBuffer = { }

local rs = game:GetService("RunService")
local re = rs.RenderStepped

local ticks = 0
local lastPerf = notesperf

local alwaysSV = true
local modChart = false
local isSV = false
local doSV = false

local ho = settings.HitOffset
local psick = settings.PerfectSick
local hdv = settings.HoldDuration.Value
local hdr = settings.HoldDuration.Random
local ap = settings.AutoPlay

spawn(function()
	while true do
		local start = tick()
		re:Wait()
		renderDelta = tick() - start

		ticks += 1

		side = getMySide() or side
		fps = 1 / renderDelta

		estFps = append(fpsBuffer, fps, fps)
		settings.FPS = estFps

		local newChances = clone(settings.Chances)
		local onlySick = false

		for i, v in newChances do
			if v <= 0 then
				newChances[i] = nil
			elseif i ~= "Sick" then
				onlySick = false
			end
		end

		if onlySick then
			newChances.Sick = nil
		end
		
		mode = keypress and keyrelease and settings.PressKeyMode

		sve = settings.SVEnabled
		doSV = actions and actions[1] and actions[2] or not actions and (isSV or alwaysSV) and sve
		ch = newChances
		ho = actions and actions[3] / 1000 or settings.HitOffset
		spr = settings.Spray
		notesperf = settings.Performance.Notes
		psick = settings.PerfectSick
		hdv = settings.HoldDuration.Value
		hdr = settings.HoldDuration.Random
		ap = settings.AutoPlay
		rng = random()

		kpsK, kpsG = settings.KPS.PerKey, settings.KPS.Global
		if kpsK == 0 then kpsK = inf end
		if kpsG == 0 then kpsG = inf end
		
		if not settings.Playing and actions then
			actions[4] = false
		end
	end
end)

local function isBehind(data, x, y)
	local is = x.Y > y.Y
	if data.IsDownScroll then
		is = not is
	end

	return is
end

for i, v in offsets do
	offsets[i] = v - offsetOffset
end

local sickOffset  = offsets.Sick
local sickOffset2 = offsets.Sick / 2
local badOffset   = offsets.Bad
local missOffset  = offsets.Miss
local missOffset2 = offsets.Miss * 2
local SVD = 0

local function lerp(a, b, c)
	return (a + (b - a) * c)
end

local canHit; canHit = function(note, data, far)
	local x = UDimToVector2(data.Receptor.Position) + v2(useX and 0.5 or 0, 0.5, 0)
	local y = UDimToVector2(note.Note.Position)

	local dist = getDistance(x, y) / data.ScrollSpeed
	local behind = isBehind(data, x, y)

	dist -= ho / lerp(1, 1.08, abs(ho))
	
	if dist < 0 then
		dist = -dist
		behind = not behind
	end

	if note.IsBad then
		return dist, behind
	else
		if far then
			return dist <= missOffset2
		else
			local forceSick = false

			for i, v in data.BadNotes do
				local d, b = canHit(v, data)
				forceSick = forceSick or b and d <= missOffset and 1

				if b and d < missOffset or not b and d < dist then
					return false, behind, dist, false, false
				end
			end

			local rolled = not forceSick and note.Rolled or "FSick"
			local sick = rolled == "Sick" or rolled == "FSick"

			if doSV or modChart then
				if behind and sick then
					return true, true, dist, false, false
				end

				if (modChart or sick) and not doSV then
					return rolled ~= "Miss" and (sick and dist <= sickOffset2 or dist <= note.HitDistance / (doSV and 1.5 or 1)), false, dist, sick, forceSick or modChart and 0.25 or 0
				else
					return false, false, dist, false, false
				end
			else
				if behind then
					return dist <= badOffset, true, dist, dist <= sickOffset, false
				end

				return rolled ~= "Miss" and (rolled == "FSick" and dist <= sickOffset or sick and sve and SVD ~= 0 and dist <= note.HitDistance / ((SVD + 1.25) / 2) or (not sve or SVD == 0) and dist <= note.HitDistance), false, dist, sick, forceSick
			end
		end
	end
end

local longNoteIndex
local function calc(v, data)
	return abs(v.Size.Y.Scale / data.ScrollSpeed) + (doSV and 0.25 or 0.075)
end

local function raceEvents(events, timeout)
	timeout = timeout or 1

	local last = tick()
	local cons = { }
	local winner

	for i, v in events do
		cons[#cons + 1] = v:Once(function()
			winner = i

			for idx, val in cons do
				val:Disconnect()
			end
		end)
	end

	repeat wait() until winner or tick() - last > timeout

	winner = winner or 0
	for idx, val in cons do
		val:Disconnect()
	end

	return winner
end

local one = UDim2.fromScale(1, 1)
local playLane

local function hitNote(note, data, dist, sick, force)
	local Note = note.Note
	local s = force or psick
	local isBehind = Note.Position.Y.Scale < data.Receptor.Position.Y.Scale + 0.5
	if data.IsDownScroll then
		isBehind = not isBehind
	end

	if sick and s and s > 0 then
		local t = isBehind and (s <= 1 and 0 or (sickOffset - dist) * (s - 1) - (0.001 + (lastOffset * 2))) or (s <= 1 and (dist * s) + (lastOffset / 1.5) or (dist + (sickOffset * (s - 1)) - (0.001 + (lastOffset * 2))))
		if t > 0 then
			wait(t)
		end
	end

	if note.Hit then return end
	note.Hit = true

	local time = hdv
	if hdr > 0 then
		time = max(time + (((rng * 1.25) - 0.25) * hdr), 0)
	end

	local holdTime = 0
	local children = Note:GetChildren()
	if not longNoteIndex then
		for i, v in children do
			if v and v.Size ~= one then
				holdTime = calc(v, data)
				longNoteIndex = i
				break
			end
		end
	else
		local v = children[longNoteIndex]
		if v and v.Size ~= one then
			holdTime = calc(v, data)
		end
	end

	time += holdTime

	while true do
		if not Note.Parent then return end

		local s = tryHitLane(data.LaneIndex, time, holdTime == 0)
		if s then break end

		wait()
	end

	raceEvents({ Note:GetPropertyChangedSignal("Parent"), Note:GetPropertyChangedSignal("Position") }, 0)

	if note.Parent then
		local notes = data.Notes
		if not find(notes, note) then
			notes[#notes + 1] = note

			sortLane(data)
			playLane(data)
		end

		note.Hit = false
	end
end

function playLane(lane)
	local notes = lane.Notes
	local toRemove = { }
	for i = 1, #notes do
		local note = notes[i]
		local hit, far, dist, sick, force = canHit(note, lane)
		if hit then
			toRemove[#toRemove + 1] = i
			defer(hitNote, note, lane, dist, sick, force)
		else
			break
		end
	end

	for i = #toRemove, 1, -1 do
		remove(notes, toRemove[i])
	end
end

local finishes = 0
local fe = event.new()
local modChartDetectBuffer = 0
local function mcdf()
	local mySongId = songId
	modChartDetectBuffer += 1

	wait(30 / rate)

	if songId == mySongId then
		modChartDetectBuffer -= 1
	end
end

local function processLane(lane, sharedData, doAutoPlay)
	local note = lane.Notes[1]
	if not note then
		re:Wait()

		finishes += 1
		fe:Fire()

		return
	end

	local receptor = lane.Receptor

	local noteStart, receptorStart = UDimToVector2(note.Note.Position), UDimToVector2(receptor.Position)
	local start = tick()

	re:Wait()

	local took = tick() - start
	local receptorEnd = UDimToVector2(receptor.Position)
	local receptorTravel = receptorEnd - receptorStart
	if not modChart and receptorTravel.Magnitude > 0.001 then
		spawn(mcdf)
		if modChartDetectBuffer > estFps * 10 then
			modChart = true
			display.IsModChart = true
		end
	end

	if modChart then
		local isDown = isDownS(lane)
		if isDown ~= lane.IsDownScroll then
			lane.IsDownScroll = isDown
			noteStart, receptorStart = v2(-(noteStart.X - 0.5) + 0.5, -(noteStart.Y - 0.5) + 0.5, 0), v2(-receptorStart.X, -receptorStart.Y, 0)
			receptorTravel = receptorEnd - receptorStart

			sortLane(lane)
		end
	end

	local rawSpeed = getDistance(noteStart, UDimToVector2(note.Note.Position) - receptorTravel) / took
	lane.ScrollSpeed = append(lane.ScrollSpeedBuffer, rawSpeed, estFps / (doSV and 5 or 2))
	globalScrollSpeed = append(globalScrollSpeedBuffer, rawSpeed, inf)

	if ap and doAutoPlay then
		playLane(lane)
	end

	finishes += 1
	fe:Fire()
end

local function SVDTC(first)
	local mySongId = songId
	
	SVD += 1

	isSV = SVD >= 4
	display.IsSV = display.IsSV or isSV

	wait((first and 50 or 30) / rate)

	if songId == mySongId then
		SVD -= 1
		display.IsSV = isSV
	end
end

spawn(function()
	while true do
		repeat wait(0.1) until settings.Playing or actions

		local lastGlobal = globalScrollSpeed
		local first = true
		while wait(0.15) and re:Wait() and settings.Playing and not actions do
			local jump = globalScrollSpeed / lastGlobal
			lastGlobal = globalScrollSpeed
			globalScrollSpeedBuffer = { }

			if abs(1 - jump) > 0.1 / lerp(rate, 1, 0.67) and rendered / lastGlobal < 175 * rate then
				spawn(SVDTC, first)
				first = false
			end
		end
		
		if actions then
			break
		end
	end
end)

local function statsAdded(stats, cons)
	if stats:FindFirstChild("Title") then return end

	local row = stats:WaitForChild("Combo"):Clone()
	local rows = { }
	local totalRows = 0

	local function addRow(name, isFirst)
		local safeName = name:gsub(" ", "")
		local row = row:Clone()
		row.Name = safeName
		row.LayoutOrder = isFirst and -999 or 999 + totalRows
		row.Parent = stats

		totalRows += 1

		local label = row.Label
		label.Text = name .. ": null"

		local fn = function(_, value, prefix)
			row.Visible = true
			if typeof(value) == "string" then
				label.Text = value
			elseif tonumber(value) then
				label.Text = name .. ": " .. (prefix or "") .. value
			else
				row.Visible = false
			end
		end

		rows[safeName] = fn
		return fn
	end

	addRow("Title", true)
	addRow("Total Notes")
	addRow("Rendered")
	addRow("Autoplay KPS")
	addRow("FPS")

	cons[#cons + 1] = re:Connect(function()
		local hs = settings.MoreStats
		if hs then
			rows:Title(typeof(hs) == "string" and hs or false)
			rows:Rendered(display.NotesRendered == display.NotesVisible and display.NotesRendered or "Rendered: " .. display.NotesVisible .. " (" .. display.NotesRendered .. ")")
			rows:TotalNotes(total)
			rows:AutoplayKPS(KPS)
			rows:FPS("FPS: <font color=\"#" .. (estFps < 60 and c3n(1):Lerp(c3n(0, 1), estFps / 60) or estFps < 120 and c3n(0, 1):Lerp(c3n(1, 0, 1), (estFps - 60) / 60) or estFps < 240 and c3n(1, 0, 1):Lerp(c3n(0.33, 0, 1), (estFps - 120) / 120) or c3n(0.6, 0.2, 1)):ToHex() .. "\">" .. ("%.1f"):format(estFps) .. "</font>")
		else
			for i, v in rows do
				rows[i](nil, false)
			end
		end
	end)
end

local function set3d(enabled)
	rs:Set3dRenderingEnabled(enabled)
end

local gui = Instance.new("ScreenGui", pgui)
gui.Name = "Black"
gui.DisplayOrder = -999
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.ResetOnSpawn = false

local black = Instance.new("Frame", gui)
black.BackgroundColor3 = c3n()
black.Size = UDim2.fromScale(2, 2)
black.Position = UDim2.fromScale(0.5, 0.5)
black.AnchorPoint = Vector2.new(0.5, 0.5)
black.ZIndex = -999
black.Visible = false

local function resetState(sharedData)
	songId += 1

	modChartDetectBuffer = 0
	globalScrollSpeed = 0
	SVD = 0
	isSV = false
	modChart = false
	total = 0
	kbs = { }
	kbVals = { }

	for _, lane in display.Lanes do
		for i in lane do
			lane[i] = 0
		end
	end

	display.TotalNotes = 0
	display.NotesRendered = 0
	display.NotesVisible = 0
	display.IsModChart = false
	display.IsSV = false

	set3d(true)
	black.Visible = false
end

local can3d = pcall(set3d, true)
songStarted:Connect(function(sharedData)
	resetState(sharedData)
	settings.Playing = true

	local cons = { }
	local hud = sharedData.Window.Game:WaitForChild("HUD")
	if hud:FindFirstChild("Stats") then
		spawn(statsAdded, hud.Stats, cons)
	end

	cons[#cons + 1] = hud.ChildAdded:Connect(function(child)
		if child.Name == "Stats" then
			statsAdded(child, cons)
		end
	end)

	local working = true
	songStopped:Once(function()
		working = false
		for i, v in cons do
			v:Disconnect()
		end
	end)

	local indicators = { }
	for i, v in hud:GetChildren() do
		if v.Name == "Indicator" then
			indicators[#indicators + 1] = v
		end
	end

	cons[#cons + 1] = hud.ChildAdded:Connect(function(child)
		if child.Name == "Indicator" then
			indicators[#indicators + 1] = child
		end
	end)

	while wait(0.1) and working do
		local gauge = hud:FindFirstChild("AccuracyGauge")
		if gauge then
			if can3d then
				set3d(not sperf.Disable3D)
				black.Visible = sperf.Disable3D
			end

			hud.Visible = sperf.UI < 3
			hud.AccuracyGauge.Visible = sperf.UI < 1

			for i, v in indicators do
				v.Parent = sperf.UI < 2 and hud or nil
			end
		end
	end

	for i, v in indicators do
		v:Destroy()
	end

	set3d(true)
	black.Visible = false
end)

songStopped:Connect(function(a)
	settings.Playing = false
	a.Working = false

	resetState(a)
	settings.Core = nil
end)

local function onWindow(window)
	local fields = window.Game.Fields

	local sharedData = {
		Fields = {
			Left = {
				LanesCount = 0,
				Lanes = { },
			},
			Right = {
				LanesCount = 0,
				Lanes = { }
			},
		},

		MyBlackNotes = 0,
		EnemyBlackNotes = 0,
		MyNotes = 0,
		EnemyNotes = 0,

		Notes = 0,

		Working = true,
		StoppedWorking = event.new(),
		Window = window
	}

	songStarted:Fire(sharedData)
	sharedData.StoppedWorking:Once(function()
		songStopped:Fire(sharedData)
	end)

	for i, v in sharedData.Fields do
		local s, obj = pcall(waitForChildError, fields, i)
		if not s then
			sharedData.StoppedWorking:Fire()
			return
		else
			spawn(onField, obj, sharedData.Fields[i], sharedData, i == side)
		end
	end

	while window.Parent do
		local needsFlush = false
		if actions and actions[4] then
			actions[4] = false
			needsFlush = true
			
			for _, field in sharedData.Fields do
				for _, lane in field.Lanes do
					lane.ScrollSpeed = 0
					lane.ScrollSpeedBuffer = { }
					globalScrollSpeed = 0
					globalScrollSpeedBuffer = { }
				end
			end
		end
		
		local myField = sharedData.Fields[side]
		local oppositeField = sharedData.Fields[side == "Left" and "Right" or "Left"]

		local mineHasNotes = not settings.CopyEnemyNotes
		if not mineHasNotes then		
			for _, lane in myField.Lanes do
				for _, note in lane.Notes do
					if canHit(note, lane, true) then
						mineHasNotes = true
						break
					end
				end
				
				if mineHasNotes then
					break
				end
			end
		end

		local targetField = mineHasNotes and myField or oppositeField

		finishes = 0
		local need = 0

		for i, v in myField.Lanes do
			need += 1
			spawn(processLane, v, sharedData, myField == targetField)
		end

		for i, v in oppositeField.Lanes do
			need += 1
			spawn(processLane, v, sharedData, oppositeField == targetField)
		end

		while finishes ~= need do
			fe:Wait()
		end
		
		if needsFlush then
			for i, v in renderQueue do
				flushRenderQueue(v, i)
			end
		end
	end

	sharedData.StoppedWorking:Fire()
end

local function vf(ch)
	if ch.ClassName == "InputContext" then
		hookInputs(ch)
	elseif ch.Name == "Window" and ch:WaitForChild("Game", 1) and ch.Game:WaitForChild("Fields", 1) then
		onWindow(ch)
	end
end

pgui.ChildAdded:Connect(vf)
for i, v in pgui:GetChildren() do
	spawn(vf, v)
end

global[key] = settings
re:Wait()

return settings