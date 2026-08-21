if not LPH_NO_VIRTUALIZE then
    LPH_NO_VIRTUALIZE = function(f, ...)
        assert(type(f) == "function" and #{...} == 0, "LPH_NO_VIRTUALIZE only accepts a single function as an argument.")
        return f
    end
end

--[[
    Bypass :shush:
]]

pcall(LPH_NO_VIRTUALIZE(function()
    local bypassed = false

    local kKickNames = {
        "Kick",
        "kick"
    }

    local kProtectedProperties = {
        Enabled = true,
        Disabled = false
    }

    local kSlotMap = {
        [69]  = 2,
        [138] = 3,
        [207] = 4,
        [276] = 5,
        [345] = 6,
        [414] = 7,
    }

    local kFilledSub = {
        1,
        2,
        3,
        4,
        5
    }

    local Players = cloneref(game:GetService("Players"))
    local ReplicatedFirst = cloneref(game:GetService("ReplicatedFirst"))
    local ReplicatedStorage = cloneref(game:GetService("ReplicatedStorage"))
    local ScriptContext = cloneref(game:GetService("ScriptContext"))

    local LocalPlayer = Players.LocalPlayer

    local ac_script = ReplicatedFirst:WaitForChild("LocalScript3")
    local ac_event = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("RemoteEvent")

    local last = nil
    local first_seen = false
    local hijack_ready = false
    local client_id
    local expected_interval = 0.6
    local min_interval = 0.25
    local ema_alpha = 0.5
    local samples = 0
    local hidden_fn = {}
    local max_stack_depth = 128
    if not setstackhidden then
        local function ValidTraceback(s)
            local dotPos = string.find(s, "%.")
            local colonPos = string.find(s, ":")

            if not dotPos then
                return false
            end

            if not colonPos then
                return true
            end

            return dotPos < colonPos
        end

        local function TracebackLines(str, lvl)
            local pos = lvl
            return function()
                if not pos then
                    return nil
                end
                local p1, p2 = string.find(str, "\r?\n", pos)
                local line
                if p1 then
                    line = str:sub(pos, p1 - 1)
                    pos = p2 + 1
                else
                    line = str:sub(pos)
                    pos = nil
                end
                return line
            end
        end

        local old_dbg_traceback;
        old_dbg_traceback = hookfunction(getrenv().debug.traceback, function(...)
            if checkcaller() or not (pcall(old_dbg_traceback, ...)) then
                return old_dbg_traceback(...)
            end

            local StartingString, StackLevel = ...
            local Traceback = old_dbg_traceback(...)
            local NewTraceback = {}

            if typeof(StartingString) == "string" or typeof(StartingString) == "number" then
                table.insert(NewTraceback, tostring(StartingString))
            end

            if typeof(StackLevel) ~= "number" or not tonumber(StackLevel) then
                StackLevel = 1
            else
                StackLevel = math.floor(tonumber(StackLevel))
            end

            for Line in TracebackLines(Traceback, StackLevel) do
                if not ValidTraceback(Line) then
                    continue
                end

                table.insert(NewTraceback, Line)
            end

            return table.concat(NewTraceback, "\n") .. "\n"
        end)

        local old_dbg_info;
        old_dbg_info = hookfunction(getrenv().debug.info, function(...)
            local ToInspect, LevelOrInfo, _ThreadInfo = ...

            if
                checkcaller()
                or typeof(ToInspect) == "function"
                or typeof(ToInspect) == "thread"
                or not pcall(function(LevelOrInfo)
                    old_dbg_info(function() end, LevelOrInfo)
                end, LevelOrInfo)
            then
                return old_dbg_info(...)
            end

            ToInspect = math.floor(ToInspect)

            local ReconstructedConstructedStack = {}
            for Level = 2, max_stack_depth do
                local Function, Source, Line, Name, NumberOfArgs, Varargs = old_dbg_info(Level, "fslna")

                if not Function or not Source or not Line or not Name then
                    break
                end

                if isexecutorclosure(Function) and not hidden_fn[Function] then
                    continue
                end

                table.insert(ReconstructedConstructedStack, {
                    f = Function,
                    s = Source,
                    l = Line,
                    n = Name,
                    a = { NumberOfArgs, Varargs },
                })
            end

            local InfoLevel = ReconstructedConstructedStack[ToInspect + 1]

            if not InfoLevel then
                return old_dbg_info(3e4, LevelOrInfo)
            end

            local ReturnResult = {}
            for idx, info in string.split(LevelOrInfo, "") do
                local Value = InfoLevel[info]

                if typeof(Value) == "table" then
                    for _, v in Value do
                        table.insert(ReturnResult, v)
                    end

                    continue
                end

                table.insert(ReturnResult, Value)
            end

            return table.unpack(ReturnResult, 1, #ReturnResult)
        end)

        local old_getfenv;
        old_getfenv = hookfunction(getrenv().getfenv, function(...)
            if checkcaller() then
                return old_getfenv(...)
            end

            local ToInspect: (...any) -> (...any) | number = ...

            local Success, ResultingEnv = pcall(function()
                if typeof(ToInspect) == "number" and ToInspect >= 0 then
                    return old_getfenv(ToInspect + 3)
                end

                return old_getfenv(ToInspect)
            end)

            if not Success then
                if typeof(ToInspect) == "number" and ToInspect >= 0 then
                    return old_getfenv(ToInspect + 3)
                end

                return old_getfenv(ToInspect)
            end

            if ToInspect == nil or typeof(ToInspect) == "function" then
                return ResultingEnv
            end

            ToInspect = math.floor(ToInspect)

            local ReconstructedConstructedStack = {}
            for Level = 1, max_stack_depth do
                local StackInfoSuccess, Data = pcall(function()
                    return {
                        Environement = old_getfenv(Level + 3),
                        Function = old_dbg_info(Level + 3, "f"),
                    }
                end)

                if not StackInfoSuccess or not Data then
                    break
                end

                local Environement = Data.Environement
                local Function = Data.Function

                if typeof(Environement["getgenv"]) == "function" and isexecutorclosure(Environement["getgenv"]) then
                    if shared.Hooking.IncludeInStackFunctions[Function] then
                        Environement = setmetatable(ResultingEnv, {
                            __index = getrenv()
                        })
                    else
                        continue
                    end
                end

                table.insert(ReconstructedConstructedStack, Environement)
            end

            local InfoLevel = ReconstructedConstructedStack[ToInspect + 1]

            if not InfoLevel then
                return old_getfenv(3e4)
            end

            return InfoLevel
        end)
    end

    setstackhidden = setstackhidden or function(fn_or_level, hidden)
        assert(typeof(hidden) == "boolean", "hidden must be boolean")

        local ok, fn = pcall(function()
            if typeof(fn_or_level) == "number" then
                return debug.info(fn_or_level + 2, "f")
            end
            return fn_or_level
        end)

        assert(ok and fn, "invalid argument #1 to 'setstackhidden'")
        hidden_fn[fn] = not hidden
    end

    local TrustedFunctions = setmetatable({}, {
        __mode = "k"
    })

    local function TrustFunction(fn)
        if type(fn) == "function" then
            TrustedFunctions[fn] = true
        end

        return fn
    end

    local function IsTrustedFunction(fn)
        return TrustedFunctions[fn] == true
    end

    local SafeHook = function(hookfn, ...)
        local args = {...}
        local func, inst, metamethod, detour

        if hookfn == hookmetamethod then
            inst = args[1]
            metamethod = args[2]
            detour = args[3]
        else
            func = args[1]
            detour = args[2]
        end

        local original_func

        if hookfn == hookfunction and iscclosure(func) then
            detour = newcclosure(detour)
        end

        if not iscclosure(detour) then
            detour = newcclosure(detour)
        end

        setstackhidden(detour, true)

        local ok, _ = pcall(function()
            TrustFunction(detour)
                    
            if hookfn == hookmetamethod then
                original_func = hookfn(inst, metamethod, detour)
            else
                original_func = hookfn(func, detour)
            end
        end)

        if not ok then
            LocalPlayer:Kick("[AethSec]: Bypass failed! n1")
        end

        return original_func
    end

    local SafeCall = function(func, ...)
        if checkcaller() then
            return func(...)
        end

        local old = getthreadidentity()
        if old ~= 2 then
            setthreadidentity(2)
        end

        local result = {func(...)}

        if old ~= 2 then
            setthreadidentity(old)
        end

        return table.unpack(result)
    end

    local monitor_conn = ScriptContext.Error:Connect(TrustFunction(function(message, stack, _)
        message = tostring(message)
        stack = tostring(stack)
        if stack:find("PlayerScripts.Controllers.MiscellaneousController") and message:find("attempt to index number with number") then
            LocalPlayer:Kick("[AethSec]: Bypass failed! n2")
        end
    end))

    local oldindex; oldindex = SafeHook(hookmetamethod, ac_script, "__index", function(t, k)
        local is_caller = not bypassed and checkcaller()
        if t == ac_script and not is_caller and kProtectedProperties[k] ~= nil then
            return kProtectedProperties[k]
        end
        if checkcaller() then
            return oldindex(t, k)
        end
        return SafeCall(oldindex, t, k)
    end)

    local oldnewindex; oldnewindex = SafeHook(hookmetamethod, ac_script, "__newindex", function(t, k, v)
        local is_caller = not bypassed and checkcaller()
        if t == ac_script and not is_caller and kProtectedProperties[k] ~= nil then
            kProtectedProperties[k] = v
            if k == "Enabled" then
                kProtectedProperties["Disabled"] = not v
            end

            if k == "Disabled" then
                kProtectedProperties["Enabled"] = not v
            end
            return
        end
        if checkcaller() then
            return oldnewindex(t, k, v)
        end
        return SafeCall(oldnewindex, t, k, v)
    end)

    client_id = ""
    last = tick()

    local oldfireserver; oldfireserver = SafeHook(hookfunction, ac_event.FireServer, function(self, ...)
        local now = tick()
        local args = {...}

        if not first_seen then
            first_seen = true
            local first_arg = args[1]

            if type(first_arg) == "table" and #first_arg >= 1 and (type(first_arg[1]) == "string" or type(first_arg[1]) == "number") then
                client_id = tostring(first_arg[1])
            else
                client_id = client_id or ""
            end

            last = tick()
            samples = 1
            hijack_ready = true

            local res = SafeCall(oldfireserver, self, ...)
            return res
        end

        local interval = now - (last or now)

        if interval > 0 then
            if samples == 0 then
                expected_interval = interval
            else
                expected_interval = ema_alpha * interval + (1 - ema_alpha) * expected_interval
            end

            samples = samples + 1

            if expected_interval < min_interval then
                expected_interval = min_interval
            end
        end

        local res = SafeCall(oldfireserver, self, ...)
        last = tick()

        return res
    end)

    local BuildSubTable = function()
        local num_empty = math.random(1, 5)
        local empty_map = {}
        local empty_slots = {7}
        empty_map[7] = true

        while #empty_slots < num_empty do
            local slot = math.random(1, 6)
            if not empty_map[slot] then
                empty_map[slot] = true
                table.insert(empty_slots, slot)
            end
        end

        table.sort(empty_slots)

        local result = {}
        for i = 1, 7 do
            if empty_map[i] then
                result[i] = {}
            else
                result[i] = kFilledSub
            end
        end

        return result, empty_slots
    end

    local ApplyTransforms = function(t, mask, empty_slots)
        local payload = t[1]
        local outer_index = #payload
        local inner_index = empty_slots[math.random(1, #empty_slots)]
        local derived
        local outer_val = payload[outer_index]

        if type(outer_val) == "table" and type(inner_index) == "number" then
            derived = outer_val[inner_index]
        else
            for i = outer_index, 1, -1 do
                if type(payload[i]) ~= "table" then
                    continue
                end

                local candidate = payload[i]

                if type(inner_index) == "number" and candidate[inner_index] ~= nil then
                    derived = candidate[inner_index]
                    break
                else
                    derived = candidate
                    break
                end
            end

            if derived == nil then
                derived = {}
            end
        end

        local written = {}
        local kSlotMapRef = kSlotMap

        for _, value in ipairs(mask) do
            local slot = kSlotMapRef[value]
            if slot and not written[slot] then
                t[slot] = derived
                written[slot] = true
            end
        end

        return t
    end

    local BuildPayload = function(challenge, mask)
        local sub_table, empty_slots = BuildSubTable()
        local total_idx = math.random(1, 8)
        local payload = {client_id, buffer.tostring(challenge)}
        local extra_strings = math.random(0, 2)

        for _ = 1, extra_strings do
            payload[#payload + 1] = ""
        end

        while #payload < (total_idx - 1) do
            payload[#payload + 1] = math.random(5, 100000)
        end

        payload[#payload + 1] = sub_table

        local t = {
            payload,
            {},
            nil,
            nil,
            nil,
            nil,
            nil
        }
        return ApplyTransforms(t, mask, empty_slots)
    end

    task.spawn(function()
        getfenv().script = ac_script
        while not hijack_ready do
            task.wait()
        end

        ac_script.Enabled = false

        ac_event.OnClientEvent:Connect(function(...)
            last = tick()

            local remote = Instance.new("RemoteEvent", nil)
            remote:FireServer()

            local t = {...}
            local challenge = t[1]
            local index = t[2]
            local mask = t[3]

            if typeof(challenge) ~= "buffer" or type(index) ~= "number" or type(mask) ~= "table" then
                LocalPlayer:Kick("[AethSec]: Bypass failed! n3")
            end

            local payload = BuildPayload(challenge, mask)
            task.defer(function()
                local since_last = tick() - (last or 0)
                local desired_wait = expected_interval - since_last
                
                if desired_wait > 0 then
                    task.wait(desired_wait)
                end
                ac_event:FireServer(table.unpack(payload, 1, 5))
                last = tick()
                remote:Destroy()
            end)
        end)
            
        bypassed = true
        monitor_conn:Disconnect()
    end)

    for _, name in ipairs(kKickNames) do
        local func = LocalPlayer[name]
        if type(func) ~= "function" then return end
            
        local oldfunc; oldfunc = SafeHook(hookfunction, func, function(self, ...)
            if self == LocalPlayer and not checkcaller() then
                return nil
            end
            return oldfunc(self, ...)
        end)
    end

    for _, conn in ipairs(getconnections(ScriptContext.Error)) do
        if not conn.Function then continue end
        if IsTrustedFunction(conn.Function) then continue end
        SafeHook(hookfunction, conn.Function, function(...)
            return nil
        end)
    end

    SafeHook(hookfunction, ScriptContext.Error.Connect, function(...)
        return nil
    end)

    while not bypassed do
        task.wait(0.5)
    end
    task.wait(1)
end))


    local repo = 'https://raw.githubusercontent.com/xiaoxi9008/FREE_5473372ed4de255c1f59c5d676ddd1cb/refs/heads/main/'
local Library = loadstring(game:HttpGet(repo .. 'Library-XIAOXI.lua'))()
local Options = Library.Options
local Toggles = Library.Toggles
Library.ShowToggleFrameInKeybinds = true
Library.ShowCustomCursor = true
Library.NotifySide = "Right"

local function patchTab(tab)
    if not tab.AddLeftGroupbox then
        function tab:AddLeftGroupbox(title)
            local groupbox = self:AddGroupbox(title)
            groupbox.Side = "Left"
            return groupbox
        end
    end
    if not tab.AddRightGroupbox then
        function tab:AddRightGroupbox(title)
            local groupbox = self:AddGroupbox(title)
            groupbox.Side = "Right"
            return groupbox
        end
    end
    return tab
end

local Window = Library:CreateWindow({
    Title = 'XIAOXI SCRIPT',
    Footer = "竞争对手V2.0.1",
    Center = true,
    AutoShow = true,
    Resizable = true,
    ShowCustomCursor = true,
    NotifySide = "Right",
    TabPadding = 8,
    MenuFadeTime = 0
})

local originalAddTab = Window.AddTab
Window.AddTab = function(self, name)
    local tab = originalAddTab(self, name)
    return patchTab(tab)
end

local Tabs = {}
Tabs.Main = Window:AddTab('主要')
Tabs.Combat = Window:AddTab('射击')
Tabs.Visuals = Window:AddTab('视觉')
Tabs.Spoof = Window:AddTab('伪装')
Tabs["UI Settings"] = Window:AddTab('UI 调试')

local TeamCheckEnabled = false
local WallCheckEnabled = true
local ESPEnabled = false
local vu88 = {}
local vu85 = false
local SilentActive = false
local RageActive = false

local function IsTargetTeamValid(player)
    if not TeamCheckEnabled then return true end
    if not player then return false end
    local Players = game:GetService("Players")
    local lp = Players.LocalPlayer
    local myTeam = lp:GetAttribute("TeamID")
    local theirTeam = player:GetAttribute("TeamID")
    if myTeam and theirTeam and myTeam == theirTeam then return false end
    return true
end

local function checkWallBetween(fromPos, toPos, targetCharacter)
    if not WallCheckEnabled then return true end
    if not fromPos or not toPos or not targetCharacter then return false end
    local direction = (toPos - fromPos).Unit
    local distance = (toPos - fromPos).Magnitude
    if distance < 0.01 then return true end
    local Players = game:GetService("Players")
    local lp = Players.LocalPlayer
    local raycastParams = RaycastParams.new()
    raycastParams.FilterDescendantsInstances = {}
    if lp.Character then table.insert(raycastParams.FilterDescendantsInstances, lp.Character) end
    table.insert(raycastParams.FilterDescendantsInstances, targetCharacter)
    raycastParams.FilterType = Enum.RaycastFilterType.Blacklist
    raycastParams.IgnoreWater = true
    local result = workspace:Raycast(fromPos, direction * distance, raycastParams)
    if not result then return true end
    if result.Instance:IsDescendantOf(targetCharacter) then return true end
    return false
end

local function toggleTableAttribute(attribute, value)
    for _, gcVal in pairs(getgc(true)) do
        if type(gcVal) == "table" and rawget(gcVal, attribute) then
            gcVal[attribute] = value
        end
    end
end

local SkinUnlockerGroup = Tabs.Main:AddLeftGroupbox("美化类")

local SkinUnlockerToggle = SkinUnlockerGroup:AddToggle("全皮美化", {
    Text = "皮肤解锁",
    Description = "解锁所有皮肤/挂件/饰品",
    Default = false,
    Callback = function(Value)
        if Value then
            task.wait(4)

            -- Unlock All Skins / Wraps / Charms.
            local _plrs    = game:GetService("Players")
            local _rs      = game:GetService("ReplicatedStorage")
            local _http    = game:GetService("HttpService")
            local _run     = game:GetService("RunService")
            local _ws      = game:GetService("Workspace")
            local _lp      = _plrs.LocalPlayer
            local _pscripts = _lp.PlayerScripts
            local _ctrl    = _pscripts.Controllers
            local _mods    = _rs:WaitForChild("Modules", 10)

            local _enumLib = require(_mods:WaitForChild("EnumLibrary", 10))
            if _enumLib then pcall(function() _enumLib:WaitForEnumBuilder() end) end

            local _cosLib  = require(_mods:WaitForChild("CosmeticLibrary", 10))
            local _itmLib  = require(_mods:WaitForChild("ItemLibrary", 10))
            local _datCtrl = require(_ctrl:WaitForChild("PlayerDataController", 10))

            local _eq, _favs = {}, {}
            local _buildingWep, _viewProf = nil, nil
            local _lastWep = nil
            local _fakeInv = {}

            local function _mkCosmetic(nm, ctype, opts)
                local _base = _cosLib.Cosmetics[nm]
                if not _base then return nil end
                local _d = {}
                for k, v in pairs(_base) do _d[k] = v end
                _d.Name = nm
                _d.Type = _d.Type or ctype
                _d.Seed = _d.Seed or math.random(1, 1000000)
                if _enumLib then
                    local _s, _eid = pcall(_enumLib.ToEnum, _enumLib, nm)
                    if _s and _eid then
                        _d.Enum = _eid
                        _d.ObjectID = _d.ObjectID or _eid
                    end
                end
                if opts then
                    if opts.inverted ~= nil then _d.Inverted = opts.inverted end
                    if opts.favoritesOnly ~= nil then _d.OnlyUseFavorites = opts.favoritesOnly end
                end
                return _d
            end

            local _cfgFile = "rivals_unlocker_config.json"
            local _saveLock = false

            local function _stripForSave()
                local _out = {}
                for wn, cos in pairs(_eq) do
                    _out[wn] = {}
                    for ct, cd in pairs(cos) do
                        if cd and cd.Name then
                            _out[wn][ct] = {
                                Name = cd.Name,
                                Inverted = cd.Inverted,
                                OnlyUseFavorites = cd.OnlyUseFavorites
                            }
                        end
                    end
                end
                return { equipped = _out, favorites = _favs }
            end

            local function _loadCfg()
                if not isfile or not readfile then return end
                local _ok1, _ex = pcall(isfile, _cfgFile)
                if not _ok1 or not _ex then return end
                local _ok2, _raw = pcall(readfile, _cfgFile)
                if not _ok2 or not _raw or _raw == "" then return end
                local _ok3, _dec = pcall(_http.JSONDecode, _http, _raw)
                if not _ok3 or not _dec then return end
                if _dec.favorites then
                    _favs = _dec.favorites
                end
                if _dec.equipped then
                    _eq = {}
                    local _cnt = 0
                    for wn, cos in pairs(_dec.equipped) do
                        _eq[wn] = {}
                        for ct, sd in pairs(cos) do
                            if sd and sd.Name then
                                if _cosLib.Cosmetics[sd.Name] then
                                    local _cloned = _mkCosmetic(sd.Name, ct, {
                                        inverted = sd.Inverted,
                                        favoritesOnly = sd.OnlyUseFavorites
                                    })
                                    if _cloned then
                                        _eq[wn][ct] = _cloned
                                        _cnt += 1
                                    end
                                end
                            end
                        end
                        if not next(_eq[wn]) then _eq[wn] = nil end
                    end
                end
            end

            local function _saveCfg()
                if not writefile or _saveLock then return end
                _saveLock = true
                task.spawn(function()
                    task.wait(1)
                    local _payload = _stripForSave()
                    local _ok, _enc = pcall(_http.JSONEncode, _http, _payload)
                    if _ok then
                        pcall(writefile, _cfgFile, _enc)
                    end
                    _saveLock = false
                end)
            end

            _loadCfg()

            local _cosTypes = {"Skin","Wrap","Charm","Dance","Emote"}
            local function _isCosType(cosObj)
                if not cosObj then return false end
                for _, t in ipairs(_cosTypes) do
                    if cosObj.Type == t then return true end
                end
                return false
            end

            _cosLib.OwnsCosmeticNormally = function(self, inv, nm, wep)
                local c = _cosLib.Cosmetics[nm]
                if c and c.Type == "Skin" then return true end
                return false
            end
            _cosLib.OwnsCosmeticUniversally = function(self, inv, nm, wep)
                local c = _cosLib.Cosmetics[nm]
                if c and c.Type == "Skin" then return true end
                return false
            end
            _cosLib.OwnsCosmeticForWeapon = function(self, inv, nm, wep)
                local c = _cosLib.Cosmetics[nm]
                if c and c.Type == "Skin" then return true end
                return false
            end

            local _origOwns = _cosLib.OwnsCosmetic
            _cosLib.OwnsCosmetic = function(self, inv, nm, wep)
                if nm:find("MISSING_") or nm == "Bubble Gun" then
                    return _origOwns(self, inv, nm, wep)
                end
                local c = _cosLib.Cosmetics[nm]
                if c and _isCosType(c) then return true end
                return _origOwns(self, inv, nm, wep)
            end

            local _origGet = _datCtrl.Get
            _datCtrl.Get = function(self, key)
                local _val = _origGet(self, key)
                if key == "CosmeticInventory" then
                    local _prx = {}
                    if _val then
                        for k, v in pairs(_val) do
                            local c = _cosLib.Cosmetics[k]
                            if c and _isCosType(c) then _prx[k] = v end
                        end
                    end
                    return setmetatable(_prx, {
                        __index = function(t, k)
                            local c = _cosLib.Cosmetics[k]
                            if c and _isCosType(c) then return true end
                            return nil
                        end
                    })
                end
                if key == "FavoritedCosmetics" then
                    local _res = _val and table.clone(_val) or {}
                    for wep, fv in pairs(_favs) do
                        _res[wep] = _res[wep] or {}
                        for nm, isFav in pairs(fv) do
                            local c = _cosLib.Cosmetics[nm]
                            if c and _isCosType(c) then
                                _res[wep][nm] = isFav
                            end
                        end
                    end
                    return _res
                end
                return _val
            end

            local _origGetWep = _datCtrl.GetWeaponData
            _datCtrl.GetWeaponData = function(self, wn)
                local _d = _origGetWep(self, wn)
                if not _d then return nil end
                local _m = {}
                for k, v in pairs(_d) do _m[k] = v end
                _m.Name = wn
                if _eq[wn] then
                    for ct, cd in pairs(_eq[wn]) do
                        _m[ct] = cd
                    end
                end
                return _m
            end

            local _fightCtrl
            pcall(function()
                _fightCtrl = require(_ctrl:WaitForChild("FighterController", 10))
            end)

            if hookmetamethod then
                local _remotes   = _rs:FindFirstChild("Remotes")
                local _dataRem   = _remotes and _remotes:FindFirstChild("Data")
                local _equipRem  = _dataRem and _dataRem:FindFirstChild("EquipCosmetic")
                local _favRem    = _dataRem and _dataRem:FindFirstChild("FavoriteCosmetic")
                local _repRem    = _remotes and _remotes:FindFirstChild("Replication")
                local _fightRem  = _repRem and _repRem:FindFirstChild("Fighter")
                local _useItmRem = _fightRem and _fightRem:FindFirstChild("UseItem")

                if _equipRem then
                    local _onc
                    _onc = hookmetamethod(game, "__namecall", function(self, ...)
                        if getnamecallmethod() ~= "FireServer" then
                            return _onc(self, ...)
                        end
                        local _a = {...}

                        if _useItmRem and self == _useItmRem then
                            local _oid = _a[1]
                            if _fightCtrl then
                                pcall(function()
                                    local _f = _fightCtrl:GetFighter(_lp)
                                    if _f and _f.Items then
                                        for _, itm in pairs(_f.Items) do
                                            if itm:Get("ObjectID") == _oid then
                                                _lastWep = itm.Name
                                                break
                                            end
                                        end
                                    end
                                end)
                            end
                        end

                        if self == _equipRem then
                            local _wn   = _a[1]
                            local _ct   = _a[2]
                            local _cn   = _a[3]
                            local _opts = _a[4] or {}
                            if _cn and _cn ~= "None" and _cn ~= "" then
                                local _inv = _datCtrl:Get("CosmeticInventory")
                                if _inv and rawget(_inv, _cn) then
                                    return _onc(self, ...)
                                end
                            end
                            _eq[_wn] = _eq[_wn] or {}
                            if not _cn or _cn == "None" or _cn == "" then
                                _eq[_wn][_ct] = nil
                                if not next(_eq[_wn]) then _eq[_wn] = nil end
                            else
                                local _cloned = _mkCosmetic(_cn, _ct, {
                                    inverted = _opts.IsInverted,
                                    favoritesOnly = _opts.OnlyUseFavorites
                                })
                                if _cloned then _eq[_wn][_ct] = _cloned end
                            end
                            task.defer(function()
                                pcall(function() _datCtrl.CurrentData:Replicate("WeaponInventory") end)
                            end)
                            _saveCfg()
                            return
                        end

                        if self == _favRem then
                            local _cos = _cosLib.Cosmetics[_a[2]]
                            if _cos then
                                _favs[_a[1]] = _favs[_a[1]] or {}
                                _favs[_a[1]][_a[2]] = _a[3] or nil
                                task.spawn(function()
                                    pcall(function() _datCtrl.CurrentData:Replicate("FavoritedCosmetics") end)
                                end)
                                _saveCfg()
                            end
                            return
                        end

                        return _onc(self, ...)
                    end)
                end
            end

            local _cliItem
            pcall(function()
                _cliItem = require(_lp.PlayerScripts.Modules.ClientReplicatedClasses.ClientFighter.ClientItem)
            end)

            if _cliItem and _cliItem._CreateViewModel then
                local _origCVM = _cliItem._CreateViewModel
                _cliItem._CreateViewModel = function(self, vmRef)
                    local _wn  = self.Name
                    local _wp  = self.ClientFighter and self.ClientFighter.Player
                    _buildingWep = (_wp == _lp) and _wn or nil
                    if _wp == _lp and _eq[_wn] then
                        local _dk = self:ToEnum("Data")
                        if vmRef[_dk] then
                            if _eq[_wn].Skin then
                                vmRef[_dk][self:ToEnum("Skin")] = _eq[_wn].Skin
                                vmRef[_dk][self:ToEnum("Name")] = _eq[_wn].Skin.Name
                            end
                            if _eq[_wn].Charm then vmRef[_dk][self:ToEnum("Charm")] = _eq[_wn].Charm end
                            if _eq[_wn].Wrap  then vmRef[_dk][self:ToEnum("Wrap")]  = _eq[_wn].Wrap  end
                        elseif vmRef.Data then
                            if _eq[_wn].Skin  then vmRef.Data.Skin  = _eq[_wn].Skin; vmRef.Data.Name = _eq[_wn].Skin.Name end
                            if _eq[_wn].Charm then vmRef.Data.Charm = _eq[_wn].Charm end
                            if _eq[_wn].Wrap  then vmRef.Data.Wrap  = _eq[_wn].Wrap  end
                        end
                    end
                    local _r = _origCVM(self, vmRef)
                    _buildingWep = nil
                    return _r
                end
            end

            local _vmMod = _lp.PlayerScripts.Modules.ClientReplicatedClasses.ClientFighter.ClientItem:FindFirstChild("ClientViewModel")
            if _vmMod then
                local _CVM = require(_vmMod)
                local _origNew = _CVM.new
                _CVM.new = function(repData, cliItm)
                    local _wp  = cliItm.ClientFighter and cliItm.ClientFighter.Player
                    local _wn  = _buildingWep or cliItm.Name
                    if _wp == _lp and _eq[_wn] then
                        local _RC  = require(_rs.Modules.ReplicatedClass)
                        local _dk  = _RC:ToEnum("Data")
                        repData[_dk] = repData[_dk] or {}
                        local _cos = _eq[_wn]
                        if _cos.Skin  then repData[_dk][_RC:ToEnum("Skin")]  = _cos.Skin  end
                        if _cos.Charm then repData[_dk][_RC:ToEnum("Charm")] = _cos.Charm end
                        if _cos.Wrap  then repData[_dk][_RC:ToEnum("Wrap")]  = _cos.Wrap  end
                    end
                    return _origNew(repData, cliItm)
                end
            end
        end
    end
})


local SilentGroup = Tabs.Combat:AddLeftGroupbox("静默瞄准")

local function RunSilentAim()
    pcall(function()
        local __linni001 = setmetatable({}, {
            __index = function(__linni002, __linni003)
                local __linni004, __linni005 = pcall(function()
                    return game:GetService(__linni003)
                end)
                if __linni005 then
                    return cloneref(__linni005)
                end
                return nil
            end
        })
        local __linni006 = getgenv()
        if __linni006.__linni007 then
            __linni006.__linni007:Shutdown()
        end
        local __linni008 = __linni001.Players
        local __linni009 = __linni001.RunService
        local __linni010 = __linni001.ReplicatedStorage
        local __linni011 = __linni001.Workspace
        local __linni012 = __linni001.UserInputService
        local __linni013 = __linni008.LocalPlayer
        local __linni014 = __linni011.CurrentCamera
        local __linni015 = __linni013.PlayerScripts
        local __linni016 = require(__linni015.Modules.ItemTypes.Gun)
        local __linni017 = require(__linni010.Modules.Utility)
        local __linni018 = setmetatable({}, {
            __index = function(_, __linni019)
                local __linni020 = __linni013.Character
                if not __linni020 then return nil end
                if __linni019 == "__root" then
                    return __linni020:FindFirstChild("HumanoidRootPart")
                elseif __linni019 == "__head" then
                    return __linni020:FindFirstChild("Head")
                end
                return nil
            end
        })
        __linni006.__linni007 = {}
        do
            local __linni021 = __linni006.__linni007
            function __linni021:__init()
                self.__active = true
                self.__target = nil
                self.__desync = false
                self.__conn1 = nil
                self.__conn2 = nil
                self.__task1 = nil
                self.__oldfunc = nil
                self:__setup()
            end
            function __linni021:__setup()
                self.__conn1 = __linni009.Heartbeat:Connect(function()
                    if not self.__active then return end
                    self.__target = self:__find()
                end)
                local __linni022 = __linni016.StartShooting
                self.__oldfunc = __linni022
                __linni016.StartShooting = function(__linni023, ...)
                    local __linni024 = {__linni022(__linni023, ...)}
                    if not __linni023.ClientFighter or not __linni023.ClientFighter.IsLocalPlayer then
                        return unpack(__linni024)
                    end
                    local __linni025 = __linni024[3]
                    if not __linni025 or typeof(__linni025) ~= "table" then
                        return unpack(__linni024)
                    end
                    __linni024[4] = true
                    local __linni026 = self.__target
                    if not self.__active or not __linni026 or not __linni026.Character then
                        return unpack(__linni024)
                    end
                    if not TeamCheckEnabled or IsTargetTeamValid(__linni026) then
                        if WallCheckEnabled then
                            local camPos = __linni014.CFrame.Position
                            local targetHead = __linni026.Character:FindFirstChild("Head")
                            if targetHead and not checkWallBetween(camPos, targetHead.Position, __linni026.Character) then
                                return unpack(__linni024)
                            end
                        end
                        if not self.__desync or self.__curr ~= __linni026 then
                            self:__desync_start(__linni026)
                            task.wait(0.1)
                        end
                        if self.__task1 then
                            task.cancel(self.__task1)
                            self.__task1 = nil
                        end
                        local __linni027 = __linni026.Character:FindFirstChild("Head")
                        if not __linni027 then return unpack(__linni024) end
                        local __linni028 = __linni027.Position
                        local __linni029 = __linni027.CFrame
                        local __linni030 = __linni028 - Vector3.new(0, 5, 0)
                        local __linni031 = CFrame.lookAt(__linni030, __linni028)
                        local __linni032 = __linni029:ToObjectSpace(CFrame.new(__linni028 + Vector3.new(math.random(), math.random(), math.random())))
                        __linni025[utf8.char(0)] = __linni017:EncodeCFrame(CFrame.new(__linni030, __linni028) * CFrame.Angles(__linni031:ToOrientation()))
                        __linni025[utf8.char(1)] = __linni017:EncodeCFrame(CFrame.new(__linni028) * CFrame.Angles(__linni031:ToOrientation()))
                        __linni025[utf8.char(2)] = __linni027
                        __linni025[utf8.char(3)] = __linni017:EncodeCFrame(__linni032)
                        self.__task1 = task.delay(0.15, function()
                            self:__desync_stop()
                        end)
                    end
                    return unpack(__linni024)
                end
            end
            function __linni021:__find()
                local __linni033 = nil
                local __linni034 = math.huge
                local __linni035 = __linni012:GetMouseLocation()
                for _, __linni036 in next, __linni008:GetPlayers() do
                    if __linni036 == __linni013 then continue end
                    if TeamCheckEnabled and __linni036:GetAttribute("TeamID") == __linni013:GetAttribute("TeamID") then continue end
                    local __linni037 = __linni036.Character
                    if not __linni037 then continue end
                    local __linni038 = __linni037:FindFirstChild("HumanoidRootPart")
                    local __linni039 = __linni037:FindFirstChild("Head")
                    local __linni040 = __linni037:FindFirstChildWhichIsA("Humanoid")
                    if not (__linni038 and __linni039 and __linni040 and __linni040.Health > 0) then continue end
                    if WallCheckEnabled then
                        local camPos = __linni014.CFrame.Position
                        if not checkWallBetween(camPos, __linni038.Position, __linni037) then continue end
                    end
                    local __linni041, __linni042 = __linni014:WorldToViewportPoint(__linni038.Position)
                    if not __linni042 then continue end
                    local __linni043 = Vector2.new(__linni041.X, __linni041.Y)
                    local __linni044 = (__linni035 - __linni043).Magnitude
                    if __linni044 < __linni034 then
                        __linni034 = __linni044
                        __linni033 = __linni036
                    end
                end
                return __linni033
            end
            function __linni021:__desync_start(__linni045)
                if self.__conn2 then self.__conn2:Disconnect() end
                self.__desync = true
                self.__curr = __linni045
                self.__conn2 = __linni009.Heartbeat:Connect(function()
                    if not self.__desync then return end
                    local __linni046 = __linni018.__root
                    if not __linni046 then return end
                    local __linni047 = __linni045.Character and __linni045.Character:FindFirstChild("HumanoidRootPart")
                    if not __linni047 then 
                        self:__desync_stop()
                        return 
                    end
                    local __linni048 = __linni046.CFrame
                    local __linni049 = __linni046.Velocity
                    local __linni050 = __linni046.RotVelocity
                    __linni046.CFrame = __linni047.CFrame * CFrame.new(0, -5, 0)
                    __linni009:BindToRenderStep("__restore", 101, function()
                        __linni046.CFrame = __linni048
                        __linni046.Velocity = __linni049
                        __linni046.RotVelocity = __linni050
                        __linni009:UnbindFromRenderStep("__restore")
                    end)
                end)
            end
            function __linni021:__desync_stop()
                self.__desync = false
                self.__curr = nil
                if self.__conn2 then
                    self.__conn2:Disconnect()
                    self.__conn2 = nil
                end
            end
            function __linni021:Shutdown()
                self.__active = false
                if self.__conn1 then self.__conn1:Disconnect() end
                if self.__conn2 then self.__conn2:Disconnect() end
                if self.__task1 then task.cancel(self.__task1) end
                if self.__oldfunc then
                    __linni016.StartShooting = self.__oldfunc
                end
            end
            __linni021:__init()
        end
    end)
    Library:Notify("静默瞄准已启用", 3)
end

local function StopSilentAim()
    pcall(function()
        if getgenv().__linni007 and getgenv().__linni007.Shutdown then
            getgenv().__linni007:Shutdown()
            getgenv().__linni007 = nil
        end
    end)
    Library:Notify("静默瞄准已禁用", 3)
end

SilentGroup:AddToggle("SilentAim", {
    Text = "启用静默瞄准",
    Default = false,
    Callback = function(Value)
        if Value then
            RunSilentAim()
            SilentActive = true
        else
            StopSilentAim()
            SilentActive = false
        end
    end
})

SilentGroup:AddToggle("SilentWallCheck", {
    Text = "墙壁检测",
    Default = true,
    Callback = function(Value)
        WallCheckEnabled = Value
    end
})

SilentGroup:AddSlider("AimFOV", {
    Text = "瞄准范围 (FOV)",
    Default = 360,
    Min = 0,
    Max = 100000,
    Rounding = 0,
    Callback = function(Value)
        getgenv().AimFOV = Value
    end
})

SilentGroup:AddSlider("AimSmoothness", {
    Text = "瞄准平滑度",
    Default = 0,
    Min = 0,
    Max = 100,
    Rounding = 0,
    Callback = function(Value)
        getgenv().AimSmoothness = Value
    end
})

SilentGroup:AddLabel("关闭墙壁检测之后将会穿墙打人")

local RageGroup = Tabs.Combat:AddRightGroupbox("愤怒机器人")
local RageConnections = {}

local function RunRage()
    pcall(function()
        local plr = game:GetService("Players").LocalPlayer
        local rs = game:GetService("ReplicatedStorage")
        local evt = rs.Remotes.Replication.Fighter.UseItem
        local cev = rs.Remotes.Replication.Fighter.UpdateCameraRotation
        local cam = workspace.CurrentCamera
        local rns = game:GetService("RunService")
        local ws = game:GetService("Workspace")
        local lf, IL, Ut, itm, trg, aur
        
        pcall(function() IL = require(rs.Modules.ItemLibrary) end)
        pcall(function() Ut = require(rs.Modules.Utility) end)
        
        for _, v in pairs(getgc(true)) do
            if type(v) == "table" and rawget(v, "LocalFighter") then lf = v.LocalFighter break end
        end
        
        if IL and IL.Items then
            for _, d in pairs(IL.Items) do
                if type(d) == "table" then
                    if d.ShootSpread then d.ShootSpread = 0 end
                    if d.ShootRecoil then d.ShootRecoil = 0 end
                    if d.RaycastPierceCount then d.RaycastPierceCount = 99 end
                end
            end
        end
        
        local function enc(p, l)
            local cf = CFrame.lookAt(p, l)
            local rx, ry, rz = cf:ToOrientation()
            return {["\x00"]=p.X,["\x01"]=p.Y,["\x02"]=p.Z,["\x03"]=rx,["\x04"]=ry,["\x05"]=rz}
        end
        
        local function gtg()
            local ch = plr.Character
            if not ch or not ch:FindFirstChild("HumanoidRootPart") then return end
            local mp, nt, nd = ch.HumanoidRootPart.Position, nil, 9999
            for _, p in pairs(game:GetService("Players"):GetPlayers()) do
                if p ~= plr and p.Character then
                    if TeamCheckEnabled then
                        local myTeam = plr:GetAttribute("TeamID")
                        local theirTeam = p:GetAttribute("TeamID")
                        if myTeam and theirTeam and myTeam == theirTeam then continue end
                    end
                    local hr, hm = p.Character:FindFirstChild("HumanoidRootPart"), p.Character:FindFirstChild("Humanoid")
                    if hr and hm and hm.Health > 0 then
                        if WallCheckEnabled then
                            local camPos = cam.CFrame.Position
                            if not checkWallBetween(camPos, hr.Position, p.Character) then continue end
                        end
                        local ds = (hr.Position - mp).Magnitude
                        if ds < nd then nd, nt = ds, p.Character end
                    end
                end
            end
            return nt
        end
        
        local function createTrail(pos, targetPosition)
            if not getgenv().ShowBulletTrails then return end
            local distance = (pos - targetPosition).Magnitude
            local mainBeam = Instance.new("Part")
            mainBeam.Name = "BulletTrail_Main"
            mainBeam.Material = Enum.Material.Neon
            mainBeam.BrickColor = BrickColor.new("Black")
            mainBeam.Anchored = true
            mainBeam.CanCollide = false
            mainBeam.Transparency = 0.3
            mainBeam.Size = Vector3.new(0.15, 0.15, distance)
            mainBeam.CFrame = CFrame.lookAt(pos, targetPosition) * CFrame.new(0, 0, -distance/2)
            mainBeam.Parent = workspace
            task.spawn(function()
                for i = 1, 10 do
                    if mainBeam and mainBeam.Parent then
                        mainBeam.Transparency = 0.3 + (i * 0.07)
                        task.wait(0.05)
                    end
                end
                if mainBeam and mainBeam.Parent then
                    mainBeam:Destroy()
                end
            end)
            return mainBeam
        end
        
        local rageTask = task.spawn(function()
            while RageActive do
                local itm
                if lf and lf.Items then
                    for _, v in pairs(lf.Items) do
                        if v.IsEquipped and v.Info and v.Info.MaxAmmo then itm = v break end
                    end
                end
                local tg = gtg()
                if itm and tg then
                    local hd, hr = tg:FindFirstChild("Head"), plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
                    if hr and hd then
                        local cd = (IL and IL.Items and IL.Items[itm.Info.Name] and IL.Items[itm.Info.Name].ShootCooldown) or 0.15
                        local hp, mp = hd.Position, hr.Position + Vector3.new(0, 1.5, 0)
                        local dr = (hp - mp).Unit
                        
                        if Ut then pcall(function() 
                            local function dtr(d)
                                return Vector2.new(math.asin(math.clamp(d.Y, -0.99, 0.99)), math.atan2(-d.X, -d.Z))
                            end
                            cev:FireServer(Ut:EncodeCameraRotation(dtr(dr)), nil) 
                        end) end
                        task.wait(0.015)
                        local oid
                        pcall(function() oid = itm:Get("ObjectID") end)
                        if oid then
                            evt:FireServer(oid, "\x1A", {["\x01"]={["\x00"]=enc(hp,mp),["\x01"]=enc(mp,hp),["\x02"]=hd,["\x03"]={["\x00"]=dr.X,["\x01"]=dr.Y,["\x02"]=dr.Z,["\x03"]=-dr.X,["\x04"]=-dr.Y,["\x05"]=-dr.Z}},["\x02"]=true,["\x03"]=true}, nil)
                            createTrail(mp, hp)
                        end
                        task.wait(cd + 0.02)
                    else task.wait(0.1) end
                else task.wait(0.1) end
            end
        end)
        table.insert(RageConnections, rageTask)
    end)
    Library:Notify("Ragerobot已启用", 3)
end

local function StopRage()
    RageActive = false
    for _, conn in ipairs(RageConnections) do
        pcall(task.cancel, conn)
    end
    RageConnections = {}
    Library:Notify("Rage模式已禁用", 3)
end

RageGroup:AddToggle("RageMode", {
    Text = "启用RageRobot",
    Default = false,
    Callback = function(Value)
        if Value then
            RageActive = true
            RunRage()
        else
            StopRage()
        end
    end
})

RageGroup:AddToggle("RageWallCheck", {
    Text = "墙壁检测",
    Default = true,
    Callback = function(Value)
        WallCheckEnabled = Value
    end
})

RageGroup:AddToggle("ShowBulletTrails", {
    Text = "显示子弹轨迹",
    Default = true,
    Callback = function(Value)
        getgenv().ShowBulletTrails = Value
    end
})

RageGroup:AddSlider("MaxTrails", {
    Text = "最大轨迹数量",
    Default = 50,
    Min = 10,
    Max = 200,
    Rounding = 0,
    Callback = function(Value)
        getgenv().MAX_TRAILS = Value
    end
})

local NoCooldownGroup = Tabs.Combat:AddLeftGroupbox("武器修改")

NoCooldownGroup:AddLabel("谨慎开启开启之后就不能关闭了")

NoCooldownGroup:AddToggle("NoShootCooldown", {
    Text = "无射击冷却",
    Default = false,
    Callback = function(Value)
        if Value then
            toggleTableAttribute("ShootCooldown", 0)
            toggleTableAttribute("ShootCooldown", 0.01)
        else
            toggleTableAttribute("ShootCooldown", nil)
        end
    end
})

NoCooldownGroup:AddToggle("NoShootSpread", {
    Text = "无散射",
    Default = false,
    Callback = function(Value)
        if Value then
            toggleTableAttribute("ShootSpread", 0)
        else
            toggleTableAttribute("ShootSpread", nil)
        end
    end
})

NoCooldownGroup:AddToggle("NoShootRecoil", {
    Text = "无后坐力",
    Default = false,
    Callback = function(Value)
        if Value then
            toggleTableAttribute("ShootRecoil", 0)
        else
            toggleTableAttribute("ShootRecoil", nil)
        end
    end
})

NoCooldownGroup:AddToggle("NoAttackCooldown", {
    Text = "无攻击冷却",
    Default = false,
    Callback = function(Value)
        if Value then
            toggleTableAttribute("AttackCooldown", 0)
        else
            toggleTableAttribute("AttackCooldown", nil)
        end
    end
})

NoCooldownGroup:AddToggle("NoDeflectCooldown", {
    Text = "无格挡冷却",
    Default = false,
    Callback = function(Value)
        if Value then
            toggleTableAttribute("DeflectCooldown", 0)
        else
            toggleTableAttribute("DeflectCooldown", nil)
        end
    end
})

NoCooldownGroup:AddToggle("NoDashCooldown", {
    Text = "无冲刺冷却",
    Default = false,
    Callback = function(Value)
        if Value then
            toggleTableAttribute("DashCooldown", 0)
        else
            toggleTableAttribute("DashCooldown", nil)
        end
    end
})

NoCooldownGroup:AddToggle("NoGenericCooldown", {
    Text = "无通用冷却",
    Default = false,
    Callback = function(Value)
        if Value then
            toggleTableAttribute("Cooldown", 0)
        else
            toggleTableAttribute("Cooldown", nil)
        end
    end
})

NoCooldownGroup:AddToggle("NoSpinCooldown", {
    Text = "无旋转冷却",
    Default = false,
    Callback = function(Value)
        if Value then
            toggleTableAttribute("SpinCooldown", 0)
        else
            toggleTableAttribute("SpinCooldown", nil)
        end
    end
})

NoCooldownGroup:AddToggle("NoBuildCooldown", {
    Text = "无建筑冷却",
    Default = false,
    Callback = function(Value)
        if Value then
            toggleTableAttribute("BuildCooldown", 0)
        else
            toggleTableAttribute("BuildCooldown", nil)
        end
    end
})

local TeamCheckGroup = Tabs.Combat:AddRightGroupbox("队伍检测")

TeamCheckGroup:AddToggle("TeamCheckEnabled", {
    Text = "启用队伍检测",
    Default = false,
    Callback = function(Value)
        TeamCheckEnabled = Value
    end
})

TeamCheckGroup:AddLabel("开启后将不会攻击队友")

local ESPGroup = Tabs.Visuals:AddLeftGroupbox("ESP")

local function vu153()
    if ESPEnabled then return end
    ESPEnabled = true
    vu85 = true
    
    local Players = game:GetService("Players")
    local lp = Players.LocalPlayer
    local Camera = workspace.CurrentCamera
    local RunService = game:GetService("RunService")
    local CoreGui = game:GetService("CoreGui")
    
    local ScreenGui = Instance.new("ScreenGui")
    ScreenGui.Name = "ESPHolder"
    ScreenGui.Parent = CoreGui
    
    local function CreatePlayerESP(plr)
        if vu88[plr] then return end
        if plr == lp then return end
        
        local Name = Instance.new("TextLabel")
        Name.Parent = ScreenGui
        Name.Position = UDim2.new(0.5, 0, 0, -11)
        Name.Size = UDim2.new(0, 100, 0, 20)
        Name.AnchorPoint = Vector2.new(0.5, 0.5)
        Name.BackgroundTransparency = 1
        Name.TextColor3 = Color3.fromRGB(255, 255, 255)
        Name.Font = Enum.Font.Code
        Name.TextSize = 11
        Name.TextStrokeTransparency = 0
        Name.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
        Name.RichText = true
        
        local Distance = Instance.new("TextLabel")
        Distance.Parent = ScreenGui
        Distance.Position = UDim2.new(0.5, 0, 0, 11)
        Distance.Size = UDim2.new(0, 100, 0, 20)
        Distance.AnchorPoint = Vector2.new(0.5, 0.5)
        Distance.BackgroundTransparency = 1
        Distance.TextColor3 = Color3.fromRGB(255, 255, 255)
        Distance.Font = Enum.Font.Code
        Distance.TextSize = 11
        Distance.TextStrokeTransparency = 0
        Distance.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
        Distance.RichText = true
        
        local Box = Instance.new("Frame")
        Box.Parent = ScreenGui
        Box.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
        Box.BackgroundTransparency = 0.75
        Box.BorderSizePixel = 0
        
        local Outline = Instance.new("UIStroke")
        Outline.Parent = Box
        Outline.Enabled = true
        Outline.Transparency = 0
        Outline.Color = Color3.fromRGB(255, 255, 255)
        Outline.LineJoinMode = Enum.LineJoinMode.Miter
        
        local Healthbar = Instance.new("Frame")
        Healthbar.Parent = ScreenGui
        Healthbar.BackgroundColor3 = Color3.fromRGB(0, 255, 0)
        Healthbar.BackgroundTransparency = 0
        
        local BehindHealthbar = Instance.new("Frame")
        BehindHealthbar.Parent = ScreenGui
        BehindHealthbar.ZIndex = -1
        BehindHealthbar.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
        BehindHealthbar.BackgroundTransparency = 0
        
        local HealthText = Instance.new("TextLabel")
        HealthText.Parent = ScreenGui
        HealthText.Position = UDim2.new(0.5, 0, 0, 31)
        HealthText.Size = UDim2.new(0, 100, 0, 20)
        HealthText.AnchorPoint = Vector2.new(0.5, 0.5)
        HealthText.BackgroundTransparency = 1
        HealthText.TextColor3 = Color3.fromRGB(0, 255, 0)
        HealthText.Font = Enum.Font.Code
        HealthText.TextSize = 11
        HealthText.TextStrokeTransparency = 0
        HealthText.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
        
        local function HideESP()
            Box.Visible = false
            Name.Visible = false
            Distance.Visible = false
            Healthbar.Visible = false
            BehindHealthbar.Visible = false
            HealthText.Visible = false
        end
        
        local connection = RunService.RenderStepped:Connect(function()
            if not ESPEnabled then HideESP() return end
            if plr.Character and plr.Character:FindFirstChild("HumanoidRootPart") then
                local HRP = plr.Character.HumanoidRootPart
                local Humanoid = plr.Character:FindFirstChild("Humanoid")
                if not Humanoid then return end
                
                if TeamCheckEnabled and not IsTargetTeamValid(plr) then
                    HideESP()
                    return
                end
                
                local Pos, OnScreen = Camera:WorldToScreenPoint(HRP.Position)
                local Dist = (Camera.CFrame.Position - HRP.Position).Magnitude / 3.5714285714
                
                if OnScreen and Dist <= 200 then
                    local Size = HRP.Size.Y
                    local scaleFactor = (Size * Camera.ViewportSize.Y) / (Pos.Z * 2)
                    local w, h = 3 * scaleFactor, 4.5 * scaleFactor
                    
                    Box.Position = UDim2.new(0, Pos.X - w / 2, 0, Pos.Y - h / 2)
                    Box.Size = UDim2.new(0, w, 0, h)
                    Box.Visible = true
                    
                    Name.Position = UDim2.new(0, Pos.X, 0, Pos.Y - h / 2 - 9)
                    Name.Text = string.format('%s', plr.Name)
                    Name.Visible = true
                    
                    Distance.Position = UDim2.new(0, Pos.X, 0, Pos.Y + h / 2 + 7)
                    Distance.Text = string.format("%d meters", math.floor(Dist))
                    Distance.Visible = true
                    
                    local health = Humanoid.Health / Humanoid.MaxHealth
                    Healthbar.Position = UDim2.new(0, Pos.X - w / 2 - 6, 0, Pos.Y - h / 2 + h * (1 - health))
                    Healthbar.Size = UDim2.new(0, 2.5, 0, h * health)
                    Healthbar.Visible = true
                    
                    BehindHealthbar.Position = UDim2.new(0, Pos.X - w / 2 - 6, 0, Pos.Y - h / 2)
                    BehindHealthbar.Size = UDim2.new(0, 2.5, 0, h)
                    BehindHealthbar.Visible = true
                    
                    local healthPercentage = math.floor(Humanoid.Health / Humanoid.MaxHealth * 100)
                    HealthText.Position = UDim2.new(0, Pos.X - w / 2 - 6, 0, Pos.Y - h / 2 + h * (1 - healthPercentage / 100) + 3)
                    HealthText.Text = tostring(healthPercentage)
                    HealthText.Visible = Humanoid.Health < Humanoid.MaxHealth
                else
                    HideESP()
                end
            else
                HideESP()
            end
        end)
        
        vu88[plr] = {connection, Name, Distance, Box, Healthbar, BehindHealthbar, HealthText}
    end
    
    for _, v in pairs(Players:GetPlayers()) do
        if v ~= lp then CreatePlayerESP(v) end
    end
    
    Players.PlayerAdded:Connect(function(v)
        if v ~= lp then CreatePlayerESP(v) end
    end)
    
    Players.PlayerRemoving:Connect(function(v)
        if vu88[v] then
            for _, item in ipairs(vu88[v]) do
                if type(item) == "function" then
                    pcall(item.Disconnect, item)
                elseif type(item) == "table" then
                    pcall(item.Disconnect, item)
                elseif type(item) == "Instance" then
                    pcall(item.Destroy, item)
                end
            end
            vu88[v] = nil
        end
    end)
    
    Library:Notify("ESP已启用", 3)
end

local function vu158()
    ESPEnabled = false
    for _, items in pairs(vu88) do
        if type(items) == "table" then
            for _, item in ipairs(items) do
                if type(item) == "function" then
                    pcall(item.Disconnect, item)
                elseif type(item) == "table" then
                    pcall(item.Disconnect, item)
                elseif type(item) == "Instance" then
                    pcall(item.Destroy, item)
                end
            end
        end
    end
    vu88 = {}
    for _, v in ipairs(game:GetService("CoreGui"):GetChildren()) do
        if v.Name == "ESPHolder" then v:Destroy() end
    end
    Library:Notify("ESP已禁用", 3)
end

ESPGroup:AddToggle("ESPEnabled", {
    Text = "启用ESP",
    Default = false,
    Callback = function(Value)
        if Value then
            vu153()
        else
            vu158()
        end
    end
})

ESPGroup:AddToggle("ESPTeamCheck", {
    Text = "ESP队伍检测",
    Default = false,
    Callback = function(Value)
        TeamCheckEnabled = Value
        if ESPEnabled then
            vu158()
            task.wait(0.1)
            vu153()
        end
    end
})

local DeviceGroup = Tabs.Visuals:AddRightGroupbox("设备欺骗")
local DeviceType = "MouseKeyboard"

DeviceGroup:AddDropdown("DeviceType", {
    Text = "选择伪装设备类型",
    Values = {"电脑", "手机", "手柄", "VR"},
    Default = "电脑",  
    Callback = function(Value)
        local deviceMap = {
            ["电脑"] = "MouseKeyboard",
            ["手机"] = "Touch",
            ["手柄"] = "Gamepad",
            ["VR"] = "VR"
        }
        DeviceType = deviceMap[Value] 
    end
})

DeviceGroup:AddToggle("EnableDeviceSpoof", {
    Text = "启用设备欺骗",
    Default = false,
    Callback = function(Value)
        if Value then
            pcall(function()
                local ReplicatedStorage = game:GetService('ReplicatedStorage')
                ReplicatedStorage.Remotes.Replication.Fighter.SetControls:FireServer(DeviceType)
                Library:Notify("设备欺骗为: " .. DeviceType, 3)
            end)
        end
    end
})

DeviceGroup:AddButton("应用设备欺骗", function()
    pcall(function()
        local ReplicatedStorage = game:GetService('ReplicatedStorage')
        ReplicatedStorage.Remotes.Replication.Fighter.SetControls:FireServer(DeviceType)
        Library:Notify("设备已欺骗为: " .. DeviceType, 3)
    end)
end)

local SpoofGroup = Tabs.Spoof:AddLeftGroupbox("伪装配置")

local function RunAvatarSpoof(username)
    if not username or username == "" then
        Library:Notify("请输入用户名", 3)
        return
    end
    
    pcall(function()
        local Players = game:GetService("Players")
        local LocalPlayer = Players.LocalPlayer
        
        local function apply_avatar(uname)
            task.spawn(function()
                local char = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
                local hum = char:WaitForChild("Humanoid", 10)
                if not hum then return end

                local targetPlayer = nil
                for _, p in ipairs(Players:GetPlayers()) do
                    if p.Name:lower() == uname:lower() then
                        targetPlayer = p
                        break
                    end
                end

                local desc
                if targetPlayer and targetPlayer.Character then
                    local targetHum = targetPlayer.Character:FindFirstChildOfClass("Humanoid")
                    if targetHum then
                        desc = targetHum:GetAppliedDescription()
                    end
                end

                if not desc then
                    local ok, userId = pcall(Players.GetUserIdFromNameAsync, Players, uname)
                    if not ok then 
                        Library:Notify("用户不存在: " .. uname, 3)
                        return 
                    end

                    local ok2, d = pcall(Players.GetHumanoidDescriptionFromUserId, Players, userId)
                    if not ok2 then 
                        Library:Notify("获取装扮失败", 3)
                        return 
                    end
                    desc = d
                end

                for _, c in ipairs(char:GetChildren()) do
                    if c:IsA("Accessory") or c:IsA("Hat") or c:IsA("BodyColors")
                    or c:IsA("CharacterMesh") or c:IsA("Shirt") or c:IsA("Pants")
                    or c:IsA("ShirtGraphic") then
                        c:Destroy()
                    end
                end

                pcall(function()
                    if hum.ApplyDescriptionClientServer then
                        hum:ApplyDescriptionClientServer(desc)
                    else
                        hum:ApplyDescription(desc)
                    end
                end)

                local bc = char:FindFirstChildOfClass("BodyColors") or Instance.new("BodyColors")
                bc.Parent = char
                bc.HeadColor3 = desc.HeadColor
                bc.TorsoColor3 = desc.TorsoColor
                bc.LeftArmColor3 = desc.LeftArmColor
                bc.RightArmColor3 = desc.RightArmColor
                bc.LeftLegColor3 = desc.LeftLegColor
                bc.RightLegColor3 = desc.RightLegColor
                
                Library:Notify("装扮已应用: " .. uname, 3)
            end)
        end
        
        apply_avatar(username)
    end)
end

local SpoofUsername = ""
SpoofGroup:AddInput("SpoofUsername", {
    Text = "目标用户名",
    Default = "",
    Placeholder = "输入要伪装的用户名",
    Callback = function(Value)
        SpoofUsername = Value
    end
})

SpoofGroup:AddToggle("EnableAvatarSpoof", {
    Text = "启用装扮伪装",
    Default = false,
    Callback = function(Value)
        if Value and SpoofUsername and SpoofUsername ~= "" then
            RunAvatarSpoof(SpoofUsername)
            getgenv().AvatarSpoofActive = true
            getgenv().SpoofTarget = SpoofUsername
        else
            getgenv().AvatarSpoofActive = false
            Library:Notify("装扮伪装已禁用", 3)
        end
    end
})

SpoofGroup:AddButton("应用装扮伪装", function()
    if SpoofUsername and SpoofUsername ~= "" then
        RunAvatarSpoof(SpoofUsername)
    else
        Library:Notify("请输入目标用户名", 3)
    end
end)

SpoofGroup:AddDivider()

SpoofGroup:AddLabel("用户数据伪装")

local SpoofConfig = {
    victim = "3414748161",
    level = "492",
    streak = "762",
    elo = "90000",
    keys = "4270",
    premium = false,
    verified = false,
    platform = "DESKTOP"
}

SpoofGroup:AddInput("VictimID", {
    Text = "受害者用户ID",
    Default = "3414748161",
    Placeholder = "输入用户ID",
    Numeric = true,
    Callback = function(Value)
        SpoofConfig.victim = Value
    end
})

SpoofGroup:AddInput("Level", {
    Text = "等级",
    Default = "492",
    Placeholder = "输入等级",
    Numeric = true,
    Callback = function(Value)
        SpoofConfig.level = Value
    end
})

SpoofGroup:AddInput("Streak", {
    Text = "连胜",
    Default = "762",
    Placeholder = "输入连胜数",
    Numeric = true,
    Callback = function(Value)
        SpoofConfig.streak = Value
    end
})

SpoofGroup:AddInput("ELO", {
    Text = "ELO评分",
    Default = "90000",
    Placeholder = "输入ELO",
    Numeric = true,
    Callback = function(Value)
        SpoofConfig.elo = Value
    end
})

SpoofGroup:AddInput("Keys", {
    Text = "Keys数量",
    Default = "4270",
    Placeholder = "输入Keys数量",
    Numeric = true,
    Callback = function(Value)
        SpoofConfig.keys = Value
    end
})

SpoofGroup:AddToggle("Premium", {
    Text = "Premium会员",
    Default = false,
    Callback = function(Value)
        SpoofConfig.premium = Value
    end
})

SpoofGroup:AddToggle("Verified", {
    Text = "已验证徽章",
    Default = false,
    Callback = function(Value)
        SpoofConfig.verified = Value
    end
})

SpoofGroup:AddDropdown("Platform", {
    Text = "平台图标",
    Values = {"DESKTOP", "MOBILE", "CONSOLE", "VR"},
    Default = "DESKTOP",
    Callback = function(Value)
        SpoofConfig.platform = Value
    end
})

local function RunDataSpoof()
    pcall(function()
        local cfg = SpoofConfig
        local victim = cfg.victim
        local helper = ""
        local level = cfg.level
        local streak = cfg.streak
        local elo = cfg.elo
        local keys = cfg.keys
        local premium = cfg.premium
        local verified = cfg.verified
        local platform = tostring(cfg.platform):upper()
        
        repeat task.wait() until game:IsLoaded()
        local Players = game:GetService("Players")
        local friend = helper ~= "" and Players:WaitForChild(helper) or Players.LocalPlayer
        
        local UserData = game:HttpGet("https://users.roblox.com/v1/users/" .. tostring(victim), true)
        local decodedData = game:GetService("HttpService"):JSONDecode(UserData)
        friend.Name = decodedData.name
        friend.UserId = decodedData.id
        friend.CharacterAppearanceId = decodedData.id
        friend.DisplayName = decodedData.displayName
        
        repeat task.wait() until friend.Character
        friend.Character:WaitForChild("Humanoid")
        friend.Character.Name = decodedData.name
        friend.Character.Humanoid.DisplayName = decodedData.displayName
        Players:WaitForChild(decodedData.name):SetAttribute("Level", tonumber(level))
        Players:WaitForChild(decodedData.name):SetAttribute("StatisticDuelsWinStreak", tonumber(streak))
        local ls = Players:WaitForChild(decodedData.name):WaitForChild("leaderstats")
        if ls and ls:FindFirstChild("Level") then ls.Level.Value = tonumber(level) end
        if ls and ls:FindFirstChild("Win Streak") then ls["Win Streak"].Value = tonumber(streak) end
        if tonumber(elo) > 0 then
            Players:WaitForChild(decodedData.name):SetAttribute("DisplayELO", tonumber(elo))
        end
        
        local function Char()
            local plr = Players:FindFirstChild(decodedData.name)
            if not plr or not plr.Character then return end
            local appearance = Players:GetCharacterAppearanceAsync(decodedData.id)
            for i,v in pairs(plr.Character:GetChildren()) do
                if v:IsA("Accessory") or v:IsA("Shirt") or v:IsA("Pants") or v:IsA("BodyColors") then
                    v:Destroy()
                end
            end
            for i,v in pairs(appearance:GetChildren()) do
                if v:IsA("Shirt") or v:IsA("Pants") or v:IsA("BodyColors") then
                    v.Parent = plr.Character
                elseif v:IsA("Accessory") then
                    plr.Character.Humanoid:AddAccessory(v)
                end
            end
            if appearance:FindFirstChild("face") then
                local head = plr.Character:FindFirstChild("Head")
                if head and head:FindFirstChild("face") then head.face:Destroy() end
                appearance.face.Parent = head
            end
        end
        Char()
        Players:FindFirstChild(decodedData.name).CharacterAdded:Connect(function()
            Char()
        end)
        
        local spoofedPlayer = Players:FindFirstChild(decodedData.name) or friend
        local oldNamecall
        oldNamecall = hookmetamethod(game, "__index", function(self, key)
            if self == spoofedPlayer then
                if key == "MembershipType" and premium then
                    return Enum.MembershipType.Premium
                end
                if key == "HasVerifiedBadge" and verified then
                    return true
                end
            end
            return oldNamecall(self, key)
        end)
        
        local imagetable = {
            ["DESKTOP"] = "rbxassetid://17136633356",
            ["MOBILE"] = "rbxassetid://17136633510",
            ["CONSOLE"] = "rbxassetid://17136633629",
            ["VR"] = "rbxassetid://17136765745"
        }
        
        game:GetService("RunService").RenderStepped:Connect(function()
            pcall(function()
                local plrName = decodedData.name
                local ctrl = Players:FindFirstChild(plrName) and Players[plrName].Character and Players[plrName].Character:FindFirstChild("HumanoidRootPart") and Players[plrName].Character.HumanoidRootPart:FindFirstChild("Nametag") and Players[plrName].Character.HumanoidRootPart.Nametag:FindFirstChild("Frame") and Players[plrName].Character.HumanoidRootPart.Nametag.Frame:FindFirstChild("Player") and Players[plrName].Character.HumanoidRootPart.Nametag.Frame.Player:FindFirstChild("Controls")
                if ctrl then
                    ctrl.Image = imagetable[platform]
                end
                
                local container = Players.LocalPlayer:FindFirstChild("PlayerGui") and Players.LocalPlayer.PlayerGui:FindFirstChild("MainGui") and Players.LocalPlayer.PlayerGui.MainGui:FindFirstChild("MainFrame") and Players.LocalPlayer.PlayerGui.MainGui.MainFrame:FindFirstChild("Lobby") and Players.LocalPlayer.PlayerGui.MainGui.MainFrame.Lobby:FindFirstChild("Currency") and Players.LocalPlayer.PlayerGui.MainGui.MainFrame.Lobby.Currency:FindFirstChild("Container")
                if container then
                    for _, v in ipairs(container:GetDescendants()) do
                        if v.Name == "Icon" and keys and v.Image == "rbxassetid://17860673529" then
                            local title = v.Parent and v.Parent.Parent and v.Parent.Parent:FindFirstChild("Title")
                            if title then title.Text = keys end
                        end
                    end
                end
            end)
        end)
    end)
    Library:Notify("数据伪装已启用 - ID: " .. SpoofConfig.victim, 3)
end

SpoofGroup:AddToggle("EnableDataSpoof", {
    Text = "启用数据伪装",
    Default = false,
    Callback = function(Value)
        if Value then
            RunDataSpoof()
        else
            Library:Notify("数据伪装已禁用，请重新加入游戏", 3)
        end
    end
})

SpoofGroup:AddButton("应用数据伪装", function()
    RunDataSpoof()
end)

local MenuGroup = Tabs["UI Settings"]:AddLeftGroupbox("Debug")

MenuGroup:AddToggle("KeybindMenuOpen", {
    Default = Library.KeybindFrame.Visible,
    Text = "shortcut menu",
    Callback = function(value)
        Library.KeybindFrame.Visible = value
    end,
})

MenuGroup:AddToggle("ShowCustomCursor", {
    Text = "custom cursors",
    Default = true,
    Callback = function(Value)
        Library.ShowCustomCursor = Value
    end,
})

MenuGroup:AddDropdown("NotificationSide", {
    Values = { "Left", "Right" },
    Default = "Right",
    Text = "informer location",
    Callback = function(Value)
        Library:SetNotifySide(Value)
    end,
})

MenuGroup:AddDropdown("DPIDropdown", {
    Values = { "25%", "50%", "75%", "100%", "125%", "150%", "175%", "200%" },
    Default = "100%",
    Text = "UI Size",
    Callback = function(Value)
        Value = Value:gsub("%%", "")
        local DPI = tonumber(Value)
        Library:SetDPIScale(DPI)
    end,
})

MenuGroup:AddDivider()
MenuGroup:AddLabel("Menu bind")
    :AddKeyPicker("MenuKeybind", {
        Default = "R",
        NoUI = true,
        Text = "Menu keybind"
    })

MenuGroup:AddButton("Destroy UI", function()
    Library:Unload()
end)

ThemeManager:SetLibrary(Library)
SaveManager:SetLibrary(Library)
SaveManager:IgnoreThemeSettings()
SaveManager:SetIgnoreIndexes({ "MenuKeybind" })
ThemeManager:SetFolder("MyScriptHub")
SaveManager:SetFolder("MyScriptHub/specific-game")
SaveManager:SetSubFolder("specific-place")
SaveManager:BuildConfigSection(Tabs["UI Settings"])
ThemeManager:ApplyToTab(Tabs["UI Settings"])
SaveManager:LoadAutoloadConfig() 