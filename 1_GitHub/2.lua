local GameplayData = require("GameLua.GameCore.Data.GameplayData")

-- ============================================================
-- ICE RED HUD BOX + ICE PAPA SKELETON HUD + ORIGINAL ENEMY MAP MARKER
-- Based on the 90 Hz BRPlayerCharacterBase supplied by the user.
-- Skeleton: bone aliases and 12 connections adopted from the user's
-- larger ICE PAPA HUD file. No aimbot, friend UID, graphics,
-- health bars, tracer lines, names, or counter features are imported.
-- Box and skeleton each reproject on the shared 90-Hz HUD loop.
-- Bone reads are separately throttled to limit expensive mesh calls.
-- ============================================================
_G.Mod_WallHighlight = (_G.Mod_WallHighlight ~= false)
_G.Mod_BonesESP = (_G.Mod_BonesESP ~= false)  -- bones on by default; independent of red boxes

local ICE_SecurityUtils = require("GameLua.Mod.BaseMod.Common.Security.SecurityCommonUtils")
local ICE_Ticker = require("common.time_ticker")
local ICE_InGameMarkTools = require("GameLua.Mod.BaseMod.Common.InGameMarkTools")

-- Auto enemy map location marker (template feature)
_G.Mod_AutoEnemyMapMark = (_G.Mod_AutoEnemyMapMark ~= false)

local function ICE_IsValid(obj)
    return obj ~= nil and slua and slua.isValid and slua.isValid(obj)
end

local function ICE_GetPlayerKey(pawn)
    if not ICE_IsValid(pawn) then return nil end
    local key = nil
    pcall(function()
        if pawn.GetPlayerKey then key = pawn:GetPlayerKey() end
    end)
    if not key or key == 0 then key = pawn.PlayerKey end
    if (not key or key == 0) and pawn.PlayerState then
        key = pawn.PlayerState.PlayerKey
    end
    if key == 0 then return nil end
    return key
end

local function ICE_GetTeamID(pawn)
    if not ICE_IsValid(pawn) then return nil end
    local team = pawn.TeamID
    if team == nil and pawn.PlayerState then
        team = pawn.PlayerState.TeamID
    end
    return team
end

local function ICE_GetLocalPawn()
    local pc = nil
    pcall(function()
        if GameplayData.GetPlayerController then
            pc = GameplayData.GetPlayerController()
        end
    end)

    if not ICE_IsValid(pc) and slua_GameFrontendHUD then
        pcall(function() pc = slua_GameFrontendHUD:GetPlayerController() end)
    end
    if not ICE_IsValid(pc) then return nil end

    local pawn = nil
    pcall(function()
        if pc.GetPlayerCharacterSafety then
            pawn = pc:GetPlayerCharacterSafety()
        elseif pc.GetCurPawn then
            pawn = pc:GetCurPawn()
        elseif pc.GetPawn then
            pawn = pc:GetPawn()
        end
    end)
    return ICE_IsValid(pawn) and pawn or nil
end

local function ICE_IsAlive(pawn)
    if not ICE_IsValid(pawn) then return false end
    local alive = nil

    if pawn.HealthStatus ~= nil and ICE_SecurityUtils and ICE_SecurityUtils.IsHealthStatusAlive then
        pcall(function()
            alive = ICE_SecurityUtils.IsHealthStatusAlive(pawn.HealthStatus)
        end)
    end

    if alive == nil and pawn.IsAlive then
        pcall(function() alive = pawn:IsAlive() end)
    end

    return alive == true
end

-- ============================================================
-- AUTO ENEMY MAP MARKER
-- Ported from the old compact BR template, but moved into the
-- same single global loop used by the stable 4.6 ESP.
-- ============================================================
local ICE_EnemyMarks = {}
local ICE_LastEnemyMarkUpdate = 0

local function ICE_HideEnemyMark(key)
    if not key then return end
    local mark = ICE_EnemyMarks[key]
    if mark and ICE_InGameMarkTools then
        pcall(function() ICE_InGameMarkTools.HideMapMark(mark) end)
    end
    ICE_EnemyMarks[key] = nil
end

local function ICE_GetPawnMarkPosition(pawn)
    if not ICE_IsValid(pawn) then return nil end

    local pos = nil

    pcall(function()
        if pawn.GetHeadLocation then
            pos = pawn:GetHeadLocation(false)
        end
    end)

    if not pos then
        pcall(function()
            if pawn.GetFuzzyPosition then
                pos = pawn:GetFuzzyPosition(FVector(0, 0, 0))
            end
        end)
    end

    if not pos then
        pcall(function()
            if pawn.K2_GetActorLocation then
                pos = pawn:K2_GetActorLocation()
            elseif pawn.GetActorLocation then
                pos = pawn:GetActorLocation()
            end
        end)
    end

    return pos
end

local function ICE_UpdateEnemyMapMarks(myPawn, allPawns)
    if not Client then return end
    if not _G.Mod_AutoEnemyMapMark then
        for key in pairs(ICE_EnemyMarks) do ICE_HideEnemyMark(key) end
        return
    end
    if not ICE_InGameMarkTools or not ICE_IsValid(myPawn) or not allPawns then return end

    local now = os.clock()
    if now - ICE_LastEnemyMarkUpdate < 1.0 then return end
    ICE_LastEnemyMarkUpdate = now

    local myKey = ICE_GetPlayerKey(myPawn)
    local myTeam = ICE_GetTeamID(myPawn)
    local seen = {}

    for _, pawn in pairs(allPawns) do
        if ICE_IsValid(pawn) then
            local key = ICE_GetPlayerKey(pawn)

            if key then
                seen[key] = true

                local isMe = (pawn == myPawn) or (myKey ~= nil and key == myKey)
                local team = ICE_GetTeamID(pawn)
                local isTeammate = (myTeam ~= nil and team ~= nil and team == myTeam)

                if (not isMe) and (not isTeammate) and ICE_IsAlive(pawn) then
                    local pos = ICE_GetPawnMarkPosition(pawn)
                    if pos then
                        ICE_HideEnemyMark(key)
                        local newMark = nil
                        pcall(function()
                            newMark = ICE_InGameMarkTools.ClientAddMapMark(
                                1003, pos, 0, "", 4, nil
                            )
                        end)
                        if newMark then
                            ICE_EnemyMarks[key] = newMark
                        end
                    end
                else
                    ICE_HideEnemyMark(key)
                end
            end
        end
    end

    for key, _ in pairs(ICE_EnemyMarks) do
        if not seen[key] then
            ICE_HideEnemyMark(key)
        end
    end
end

-- Reuse the existing blue-box toggle name, now controlling HUD boxes only.
_G.ICE_HUD_BOX_CONFIG = _G.ICE_HUD_BOX_CONFIG or {}
local ICE_HUD_DEFAULTS = {
    MaxRangeMeters = 400.0,
    MaxRendered = 8,  -- limit active red HUD boxes to reduce UMG load
    ScanInterval = 0.35,
    UpdateInterval = 1.0 / 90.0,   -- request 90 Hz HUD updates
    TransformInterval = 0.50,
    BodySampleInterval = 1.0 / 60.0,  -- sample body at 60 Hz to limit capsule calls
    BodySmoothingSeconds = 0.022, -- 22 ms position smoothing
    ProjectionGraceSeconds = 0.10,
    UnusedWidgetKeepSeconds = 2.0,
    SkeletonNearSampleInterval = 1.0 / 60.0, -- near bones sampled at 60 Hz
    SkeletonFarSampleInterval = 1.0 / 30.0,  -- far bones sampled at 30 Hz
    SkeletonFarMeters = 130.0,
    SkeletonSmoothingSeconds = 0.022,
    SkeletonMissingHoldSeconds = 0.18,
    SkeletonLineThickness = 1.25
}
for k, value in pairs(ICE_HUD_DEFAULTS) do
    if _G.ICE_HUD_BOX_CONFIG[k] == nil then
        _G.ICE_HUD_BOX_CONFIG[k] = value
    end
end
-- Upgrade only the old stock values on a live reload; keep custom settings.
if _G.ICE_HUD_BOX_CONFIG.UpdateInterval == 0.033 then
    _G.ICE_HUD_BOX_CONFIG.UpdateInterval = 0.025
end
-- iPhone high-refresh 90-Hz PRESET (overrides prior 144-Hz test settings on reload).
-- Timers can run no faster than the actual game/engine tick.
_G.ICE_HUD_BOX_CONFIG.UpdateInterval = 1.0 / 90.0
_G.ICE_HUD_BOX_CONFIG.BodySampleInterval = 1.0 / 60.0
_G.ICE_HUD_BOX_CONFIG.MaxRendered = 8
_G.ICE_HUD_BOX_CONFIG.BodySmoothingSeconds = 0.022
local g_icepapa_ShotESP = {
    Canvas=nil, Boxes={}, Skeletons={}, BodyByKey={}, ScreenByKey={},
    BoneNameByKey={}, SkeletonSamplesByKey={}, SkeletonSmoothByKey={},
    CreateRetryUntil={}, Enemies={}, LastWorld=nil,
    FrameNow=0, LastScanClock=-999, LastTransformClock=-999,
    CanvasScaleX=1.0, CanvasScaleY=1.0,
    CanvasOffsetX=0.0, CanvasOffsetY=0.0,
    CanvasLocalWidth=nil, CanvasLocalHeight=nil,
    LastCanvasSizeClock=-999
}
local V2 = _G.FVector2D
if not V2 then pcall(function() V2 = import("Vector2D") end) end
local LinearColor = _G.FLinearColor
if not LinearColor then pcall(function() LinearColor = import("LinearColor") end) end
local SlateBlueprintLibrary = nil
pcall(function() SlateBlueprintLibrary = import("SlateBlueprintLibrary") end)
local WidgetLayoutLibrary = nil
pcall(function() WidgetLayoutLibrary = import("WidgetLayoutLibrary") end)
local SlateColor = nil
pcall(function() SlateColor = import("SlateColor") or import("/Script/SlateCore.SlateColor") end)
local GameplayStaticsESP = nil
pcall(function() GameplayStaticsESP = import("GameplayStatics") end)

-- g_icepapa_ESPV2 made by ICE PAPA
local function g_icepapa_ESPV2(x, y)
    if V2 then return V2(x, y) end
    return {X = x, Y = y}
end

-- ESP color made by ICE PAPA
local function g_icepapa_ESPColor(r, g, b, a)
    if LinearColor then return LinearColor(r, g, b, a or 1.0) end
    return {R=r, G=g, B=b, A=a or 1.0}
end
local ESP_RED = g_icepapa_ESPColor(1.0, 0.0, 0.0, 1.0)
local ESP_BONES_RED = g_icepapa_ESPColor(1.0, 0.0, 0.0, 1.0)
-- ESP object validation made by ICE PAPA
local function g_icepapa_ESPValid(obj)
    if not obj then return false end
    local ok, valid = pcall(function() return slua.isValid(obj) end)
    return ok and valid == true
end

-- ESP timing made by ICE PAPA
local function g_icepapa_ESPNow()
    local t = nil
    pcall(function()
        local w = (slua and slua.getWorld and slua.getWorld()) or nil
        if GameplayStaticsESP and w and GameplayStaticsESP.GetRealTimeSeconds then
            t = GameplayStaticsESP.GetRealTimeSeconds(w)
        end
    end)
    if tonumber(t) then return tonumber(t) end
    pcall(function() if os and os.clock then t = os.clock() end end)
    return tonumber(t) or 0.0
end

-- ESP world access made by ICE PAPA
local function g_icepapa_ESPWorld()
    local w = nil
    pcall(function() if slua and slua.getWorld then w = slua.getWorld() end end)
    return w
end

-- ESP player controller made by ICE PAPA
local function g_icepapa_ESPGetController()
    local pc = nil
    pcall(function()
        local GDP = require("GameLua.GameCore.Data.GameplayData")
        if GDP and GDP.GetPlayerController then pc = GDP.GetPlayerController() end
    end)
    if not g_icepapa_ESPValid(pc) then
        pcall(function()
            if slua_GameFrontendHUD then pc = slua_GameFrontendHUD:GetPlayerController() end
        end)
    end
    return g_icepapa_ESPValid(pc) and pc or nil
end
-- ESP character vertical bounds made by ICE PAPA
local function g_icepapa_ESPGetCharacterVerticalBounds(character)
    if not g_icepapa_ESPValid(character) then return nil, nil end

    local center, halfHeight = nil, nil
    local capsule = nil

    pcall(function()
        if character.GetCapsuleComponent then
            capsule = character:GetCapsuleComponent()
        elseif character.CapsuleComponent then
            capsule = character.CapsuleComponent
        end
    end)

    if capsule and g_icepapa_ESPValid(capsule) then
        pcall(function()
            if capsule.K2_GetComponentLocation then
                center = capsule:K2_GetComponentLocation()
            elseif capsule.GetComponentLocation then
                center = capsule:GetComponentLocation()
            end

            if capsule.GetScaledCapsuleHalfHeight then
                halfHeight = capsule:GetScaledCapsuleHalfHeight()
            elseif capsule.GetUnscaledCapsuleHalfHeight then
                halfHeight = capsule:GetUnscaledCapsuleHalfHeight()
            elseif capsule.CapsuleHalfHeight then
                halfHeight = capsule.CapsuleHalfHeight
            end
        end)
    end

    if not center then
        pcall(function()
            if character.K2_GetActorLocation then
                center = character:K2_GetActorLocation()
            end
        end)
    end

    if not center then
        pcall(function()
            if Game and Game.GetActorLocation then
                center = Game:GetActorLocation(character)
            end
        end)
    end

    if not center then return nil, nil end

    if not halfHeight or halfHeight < 10 or halfHeight > 200 then
        halfHeight = 85
        pcall(function()
            if character.bIsCrouched then halfHeight = 60 end
            if character.IsProne and character:IsProne() then halfHeight = 25 end
        end)
    end

    return center, halfHeight
end

-- ESP head and feet position made by ICE PAPA
local function g_icepapa_ESPGetCharacterBoxLocs(character)
    local center, halfHeight = g_icepapa_ESPGetCharacterVerticalBounds(character)
    if not center or not halfHeight then return nil, nil end

    local headLoc = {
        X = center.X,
        Y = center.Y,
        Z = center.Z + halfHeight
    }

    local feetLoc = {
        X = center.X,
        Y = center.Y,
        Z = center.Z - halfHeight
    }

    return headLoc, feetLoc
end

-- Sample expensive capsule data separately from camera updates.
-- World-space interpolation doesn't introduce camera-follow lag on rotation.
local function g_icepapa_ESPSmoothBodyLocs(key,character,now)
    local state=g_icepapa_ShotESP
    local entry=state.BodyByKey[key]
    if not entry then
        entry={LastSample=-999.0,LastFrame=now,Head=nil,Feet=nil}
        state.BodyByKey[key]=entry
    end
    local cfg=_G.ICE_HUD_BOX_CONFIG
    if not entry.Head or (now-entry.LastSample)>=(tonumber(cfg.BodySampleInterval) or 0.045) then
        local head,feet=g_icepapa_ESPGetCharacterBoxLocs(character)
        if head and feet then
            entry.Head,entry.Feet=head,feet
            entry.LastSample=now
        end
    end
    if not entry.Head or not entry.Feet then return nil,nil end
    local dt=math.max(0.0,math.min(0.10,now-(entry.LastFrame or now)))
    entry.LastFrame=now
    local tau=math.max(0.008,tonumber(cfg.BodySmoothingSeconds) or 0.032)
    local alpha=1.0-math.exp(-dt/tau)
    local function lerpWorld(previous,target)
        if not previous then return {X=target.X,Y=target.Y,Z=target.Z} end
        local dx,dy,dz=target.X-previous.X,target.Y-previous.Y,target.Z-previous.Z
        if dx*dx+dy*dy+dz*dz>400*400 then
            previous.X,previous.Y,previous.Z=target.X,target.Y,target.Z
        else
            previous.X=previous.X+dx*alpha
            previous.Y=previous.Y+dy*alpha
            previous.Z=previous.Z+dz*alpha
        end
        return previous
    end
    entry.SmoothHead=lerpWorld(entry.SmoothHead,entry.Head)
    entry.SmoothFeet=lerpWorld(entry.SmoothFeet,entry.Feet)
    return entry.SmoothHead,entry.SmoothFeet
end
local function g_icepapa_ESPDestroyWidgetData(data)
    if not data then return end
    local widget = data.Widget or data.Container
    if g_icepapa_ESPValid(widget) then
        pcall(function() widget:RemoveFromParent() end)
        -- Unreal owns UObject lifetime; removing it from the panel is enough.
        -- ConditionalBeginDestroy on a still-referenced UMG widget is unsafe.
    end
end

local function g_icepapa_ESPResetWidgets()
    for _, group in pairs(g_icepapa_ShotESP.Boxes) do
        for _, data in ipairs(group) do
            g_icepapa_ESPDestroyWidgetData(data)
        end
    end
    for _, group in pairs(g_icepapa_ShotESP.Skeletons) do
        for _, data in ipairs(group) do
            g_icepapa_ESPDestroyWidgetData(data)
        end
    end
    g_icepapa_ShotESP.Boxes = {}
    g_icepapa_ShotESP.Skeletons = {}
    g_icepapa_ShotESP.BoneNameByKey = {}
    g_icepapa_ShotESP.SkeletonSamplesByKey = {}
    g_icepapa_ShotESP.SkeletonSmoothByKey = {}
    g_icepapa_ShotESP.BodyByKey = {}
    g_icepapa_ShotESP.ScreenByKey = {}
    g_icepapa_ShotESP.CreateRetryUntil = {}
    g_icepapa_ShotESP.Enemies = {}
    g_icepapa_ShotESP.Canvas = nil
    g_icepapa_ShotESP.CanvasLocalWidth = nil
    g_icepapa_ShotESP.CanvasLocalHeight = nil
    g_icepapa_ShotESP.LastCanvasSizeClock = -999
    g_icepapa_ShotESP.HadCanvasCalibration = false
end
-- ESP HUD canvas made by ICE PAPA
local function g_icepapa_ESPGetCanvas()
    if g_icepapa_ESPValid(g_icepapa_ShotESP.Canvas) then return g_icepapa_ShotESP.Canvas end
    local root = nil
    pcall(function()
        local InGameUITools = require("GameLua.Mod.BaseMod.Common.UI.InGameUITools")
        if InGameUITools and InGameUITools.GetMainControlBaseUI then root = InGameUITools.GetMainControlBaseUI() end
    end)
    if not g_icepapa_ESPValid(root) then return nil end
    local canvas = nil
    pcall(function()
        if g_icepapa_ESPValid(root.CanvasPanel_0) then canvas = root.CanvasPanel_0
        elseif g_icepapa_ESPValid(root.CanvasPanel_42) then canvas = root.CanvasPanel_42 end
    end)
    if g_icepapa_ESPValid(canvas) then
        -- HUD may be recreated on respawn without the world pointer changing.
        if g_icepapa_ShotESP.Canvas ~= nil and
           g_icepapa_ShotESP.Canvas ~= canvas then
            g_icepapa_ESPResetWidgets()
            g_icepapa_ShotESP.LastScanClock = -999.0
            g_icepapa_ShotESP.LastTransformClock = -999.0
        end
        g_icepapa_ShotESP.Canvas = canvas
        return canvas
    end
    return nil
end

-- ESP viewport size made by ICE PAPA
local function g_icepapa_ESPViewport(pc)
    local w, h = 1920.0, 1080.0
    pcall(function()
        if pc and pc.GetViewportSize then
            local v = g_icepapa_ESPV2(0,0)
            pc:GetViewportSize(v)
            if v and tonumber(v.X) and v.X > 200 then w, h = v.X, v.Y end
        end
    end)
    return w, h
end

-- ESP HUD canvas made by ICE PAPA
local function g_icepapa_ESPGetCanvasLocalSize()
    local canvas = g_icepapa_ESPGetCanvas()
    if not g_icepapa_ESPValid(canvas) then return nil, nil end

    local cw, ch = nil, nil
    pcall(function()
        local geo = canvas:GetCachedGeometry()
        if not geo then return end

        local size = nil
        if geo.GetLocalSize then
            size = geo:GetLocalSize()
        elseif SlateBlueprintLibrary and SlateBlueprintLibrary.GetLocalSize then
            size = SlateBlueprintLibrary.GetLocalSize(geo)
        end

        if size and tonumber(size.X) and tonumber(size.Y) and size.X > 1 and size.Y > 1 then
            cw, ch = tonumber(size.X), tonumber(size.Y)
        end
    end)

    return cw, ch
end

-- Avoid repeated Slate geometry calls on every ESP frame.
local function g_icepapa_ESPGetCachedCanvasSize(pc, now)
    local state = g_icepapa_ShotESP
    if not state.CanvasLocalWidth or now - state.LastCanvasSizeClock >= 0.50 then
        local w, h = g_icepapa_ESPGetCanvasLocalSize()
        if not w or not h then w, h = g_icepapa_ESPViewport(pc) end
        state.CanvasLocalWidth, state.CanvasLocalHeight = w, h
        state.LastCanvasSizeClock = now
    end
    return state.CanvasLocalWidth, state.CanvasLocalHeight
end

-- ESP canvas transform made by ICE PAPA
local function g_icepapa_ESPUpdateCanvasTransform(pc)
    local canvas = g_icepapa_ESPGetCanvas()
    if not g_icepapa_ESPValid(canvas) then return false end

    local calibrated = false

    pcall(function()
        if SlateBlueprintLibrary and SlateBlueprintLibrary.AbsoluteToLocal then
            local geo = canvas:GetCachedGeometry()
            if geo then
                local p0 = SlateBlueprintLibrary.AbsoluteToLocal(
                    geo,
                    g_icepapa_ESPV2(0, 0)
                )
                local p1 = SlateBlueprintLibrary.AbsoluteToLocal(
                    geo,
                    g_icepapa_ESPV2(100, 100)
                )

                if p0 and p1
                    and tonumber(p0.X) and tonumber(p0.Y)
                    and tonumber(p1.X) and tonumber(p1.Y)
                    and p1.X ~= p0.X and p1.Y ~= p0.Y then

                    g_icepapa_ShotESP.CanvasScaleX = (p1.X - p0.X) / 100.0
                    g_icepapa_ShotESP.CanvasScaleY = (p1.Y - p0.Y) / 100.0
                    g_icepapa_ShotESP.CanvasOffsetX = p0.X
                    g_icepapa_ShotESP.CanvasOffsetY = p0.Y
                    calibrated = true
                    g_icepapa_ShotESP.HadCanvasCalibration = true
                end
            end
        end
    end)

    -- Geometry can temporarily be unavailable during layout; retain the
    -- last good transform instead of jumping to a fallback scale.
    if not calibrated and not g_icepapa_ShotESP.HadCanvasCalibration then
        local scale = 1.0
        pcall(function()
            if WidgetLayoutLibrary and WidgetLayoutLibrary.GetViewportScale then
                local s = WidgetLayoutLibrary.GetViewportScale(pc)
                if tonumber(s) and s > 0 then
                    scale = s
                end
            end
        end)

        g_icepapa_ShotESP.CanvasScaleX = 1.0 / scale
        g_icepapa_ShotESP.CanvasScaleY = 1.0 / scale
        g_icepapa_ShotESP.CanvasOffsetX = 0.0
        g_icepapa_ShotESP.CanvasOffsetY = 0.0
    end

    return true
end

-- ESP world to HUD projection made by ICE PAPA
local function g_icepapa_ESPProject(pc, worldLoc)
    if not pc or not worldLoc then return nil end

    local pix = g_icepapa_ESPV2(0, 0)
    local ok = false

    pcall(function()
        local res = pc:ProjectWorldLocationToScreen(worldLoc, pix, true)
        if res == false or res == 0 then
            ok = false
        else
            local x,y = pix and tonumber(pix.X),pix and tonumber(pix.Y)
            local coordsValid = x and y and x == x and y == y
                and math.abs(x) < 100000 and math.abs(y) < 100000
            ok = (res == true or res == 1 or res == nil) and coordsValid
                and (res == true or res == 1 or x ~= 0 or y ~= 0)
        end
    end)

    if not ok then return nil end

    local sx = g_icepapa_ShotESP.CanvasScaleX or 1.0
    local sy = g_icepapa_ShotESP.CanvasScaleY or 1.0
    local ox = g_icepapa_ShotESP.CanvasOffsetX or 0.0
    local oy = g_icepapa_ShotESP.CanvasOffsetY or 0.0

    return g_icepapa_ESPV2(
        pix.X * sx + ox,
        pix.Y * sy + oy
    )
end
local function g_icepapa_ESPCreateLine(color)
    local canvas = g_icepapa_ESPGetCanvas()
    if not g_icepapa_ESPValid(canvas) then return nil end
    local border = nil
    pcall(function() border = CGame:NewObjectFromPath("/Script/UMG.Border", canvas) end)
    if not g_icepapa_ESPValid(border) then return nil end
    pcall(function()
        border:SetBrushColor(color)
        border:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
        border:SetRenderTransformPivot(g_icepapa_ESPV2(0.0, 0.0))
    end)
    local slot = nil
    pcall(function() slot = canvas:AddChildToCanvas(border) end)
    if not slot then g_icepapa_ESPDestroyWidgetData({Widget=border}) return nil end
    pcall(function() slot:SetAutoSize(false) slot:SetZOrder(30) end)
    return {Widget=border, Slot=slot, Visible=true}
end

-- Screen-aligned rectangles have only horizontal and vertical edges.
-- Changing UMG render angles every tick caused unnecessary layout/render work.
local function ICE_HUD_SnapHalf(v)
    return math.floor(v*2 + 0.5)*0.5
end
local function g_icepapa_ESPDrawEdge(data, x, y, width, height)
    if not data or not g_icepapa_ESPValid(data.Widget) or not data.Slot then return false end
    if width < 1 or height < 0.5 then
        if data.Visible ~= false then
            pcall(function() data.Widget:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed) end)
            data.Visible = false
        end
        return false
    end

    -- Subpixel snapping suppresses edge shimmer as positions change.
    x,y,width,height = ICE_HUD_SnapHalf(x),ICE_HUD_SnapHalf(y),
        ICE_HUD_SnapHalf(width),ICE_HUD_SnapHalf(height)
    if not data.LastX or data.LastX ~= x or data.LastY ~= y
        or data.LastW ~= width or data.LastH ~= height then
        local ok = pcall(function()
            data.Slot:SetPosition(g_icepapa_ESPV2(x, y))
            data.Slot:SetSize(g_icepapa_ESPV2(width, height))
        end)
        if not ok then return false end
        data.LastX,data.LastY,data.LastW,data.LastH = x,y,width,height
    end
    if data.Visible ~= true then
        pcall(function() data.Widget:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible) end)
        data.Visible = true
    end
    return true
end

-- ESP widget hide made by ICE PAPA
local function g_icepapa_ESPHide(data)
    if data and data.Visible ~= false and g_icepapa_ESPValid(data.Widget) then
        pcall(function() data.Widget:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed) end)
        data.Visible = false
    end
end

local function g_icepapa_ESPDestroyGroup(group)
    if not group then return end
    for _, data in ipairs(group) do g_icepapa_ESPDestroyWidgetData(data) end
end

local function g_icepapa_ESPLineGroup(registry, key, count, color)
    local state = g_icepapa_ShotESP
    local now = state.FrameNow or 0
    local group = registry[key]
    local valid = group and #group == count
    if valid and (not group.LastValidated or now - group.LastValidated > 1.0) then
        for _, data in ipairs(group) do
            if not data or not g_icepapa_ESPValid(data.Widget) then valid = false break end
        end
        if valid then group.LastValidated = now end
    end
    if valid then return group end

    if now < (state.CreateRetryUntil[key] or -1) then return nil end
    g_icepapa_ESPDestroyGroup(group)
    group = {}
    for i=1,count do
        local data = g_icepapa_ESPCreateLine(color)
        if not data then
            g_icepapa_ESPDestroyGroup(group)
            registry[key] = nil
            state.CreateRetryUntil[key] = now + 0.75
            return nil
        end
        group[i] = data
    end
    group.LastValidated = now
    group.LastActiveClock = now
    state.CreateRetryUntil[key] = nil
    registry[key] = group
    return group
end

local function g_icepapa_ESPHideGroup(group)
    if not group then return end
    for _, data in ipairs(group) do g_icepapa_ESPHide(data) end
end

local function g_icepapa_ESPUpdateBox(key, head, feet, enabled)
    local group = g_icepapa_ShotESP.Boxes[key]
    if not enabled or not head or not feet then
        g_icepapa_ESPHideGroup(group)
        return
    end
    local h = math.abs(feet.Y-head.Y)
    if h < 5 then g_icepapa_ESPHideGroup(group) return end
    local half = math.max(7.0, h*0.22)
    local top = math.min(head.Y,feet.Y)
    local bottom = math.max(head.Y,feet.Y)
    local left,right = head.X-half,head.X+half
    local thick = 1.5
    group = g_icepapa_ESPLineGroup(g_icepapa_ShotESP.Boxes,key,4,ESP_RED)
    if not group then return end
    group.LastActiveClock = g_icepapa_ShotESP.FrameNow
    g_icepapa_ESPDrawEdge(group[1],left,top,right-left,thick)
    g_icepapa_ESPDrawEdge(group[2],right-thick,top,thick,bottom-top)
    g_icepapa_ESPDrawEdge(group[3],left,bottom-thick,right-left,thick)
    g_icepapa_ESPDrawEdge(group[4],left,top,thick,bottom-top)
end


-- ============================================================
-- ICE PAPA BONES HUD: 12-segment red skeleton
-- Derived from the attached 180 KB source, without its unrelated UI.
-- World-space bone sampling + fresh camera projection at every 90 Hz HUD tick.
-- ============================================================
local ICE_BONES_NAMES = {
    head={"Head","head","head_01"},
    neck={"neck_01","Neck","neck"},
    pelvis={"pelvis","Pelvis"},
    ls={"upperarm_l","UpperArm_L","clavicle_l"},
    le={"lowerarm_l","LowerArm_L"},
    lw={"hand_l","Hand_L"},
    rs={"upperarm_r","UpperArm_R","clavicle_r"},
    re={"lowerarm_r","LowerArm_R"},
    rw={"hand_r","Hand_R"},
    lk={"calf_l","Calf_L","knee_l"},
    la={"foot_l","Foot_L"},
    rk={"calf_r","Calf_R","knee_r"},
    ra={"foot_r","Foot_R"}
}
local ICE_BONES_LINKS = {
    {"head","neck"}, {"neck","ls"}, {"ls","le"}, {"le","lw"},
    {"neck","rs"}, {"rs","re"}, {"re","rw"}, {"neck","pelvis"},
    {"pelvis","lk"}, {"lk","la"}, {"pelvis","rk"}, {"rk","ra"}
}

local function ICE_BonesGetWorld(mesh, playerKey, joint, names)
    local aliasByKey=g_icepapa_ShotESP.BoneNameByKey
    local aliases=aliasByKey[playerKey]
    if not aliases then aliases={} aliasByKey[playerKey]=aliases end
    local function getLocation(name)
        local ok,loc=pcall(function()
            local p=nil
            if mesh.GetSocketLocation then p=mesh:GetSocketLocation(name) end
            if not p and mesh.GetBoneLocation then p=mesh:GetBoneLocation(name) end
            return p
        end)
        if not ok or not loc then return nil end
        local x,y,z=tonumber(loc.X),tonumber(loc.Y),tonumber(loc.Z)
        if not x or not y or not z or x~=x or y~=y or z~=z then return nil end
        if math.abs(x)>100000000 or math.abs(y)>100000000 or math.abs(z)>100000000 then return nil end
        return {X=x,Y=y,Z=z}
    end
    local selected=aliases[joint]
    local pos=selected and getLocation(selected) or nil
    if not pos then
        aliases[joint]=nil
        for _,name in ipairs(names) do
            local exists=true
            if mesh.DoesSocketExist then
                local ok,res=pcall(mesh.DoesSocketExist,mesh,name)
                if ok and res==false then exists=false end
            end
            if exists then
                pos=getLocation(name)
                if pos then aliases[joint]=name break end
            end
        end
    end
    return pos
end

local function ICE_BonesSmooth(previous,target,alpha)
    if not previous then return {X=target.X,Y=target.Y,Z=target.Z} end
    local dx,dy,dz=target.X-previous.X,target.Y-previous.Y,target.Z-previous.Z
    if dx*dx+dy*dy+dz*dz>350*350 then
        return {X=target.X,Y=target.Y,Z=target.Z}
    end
    previous.X=previous.X+dx*alpha
    previous.Y=previous.Y+dy*alpha
    previous.Z=previous.Z+dz*alpha
    return previous
end

-- Angle helper works in older Lua builds where math.atan(y,x) is unsupported.
local function ICE_BonesAtan2(y,x)
    if math.atan2 then return math.atan2(y,x) end
    if x>0 then return math.atan(y/x) end
    if x<0 then return math.atan(y/x)+(y>=0 and math.pi or -math.pi) end
    if y>0 then return math.pi*0.5 end
    if y<0 then return -math.pi*0.5 end
    return 0.0
end

local function ICE_BonesDrawSegment(data,x1,y1,x2,y2,thickness)
    if not data or not g_icepapa_ESPValid(data.Widget) or not data.Slot then return false end
    local dx,dy=x2-x1,y2-y1
    local length=math.sqrt(dx*dx+dy*dy)
    if length<1.0 then g_icepapa_ESPHide(data) return false end
    local changed=not data.LastX or math.abs(data.LastX-x1)>=0.20
        or math.abs(data.LastY-y1)>=0.20 or math.abs(data.LastDX-dx)>=0.20
        or math.abs(data.LastDY-dy)>=0.20 or data.LastThickness~=thickness
    if changed then
        local angle=ICE_BonesAtan2(dy,dx)*180.0/math.pi
        local ok=pcall(function()
            data.Slot:SetPosition(g_icepapa_ESPV2(x1,y1))
            data.Slot:SetSize(g_icepapa_ESPV2(length,thickness))
            data.Widget:SetRenderAngle(angle)
        end)
        if not ok then return false end
        data.LastX,data.LastY,data.LastDX,data.LastDY=x1,y1,dx,dy
        data.LastThickness=thickness
    end
    if data.Visible~=true then
        pcall(function() data.Widget:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible) end)
        data.Visible=true
    end
    return true
end

local function ICE_BonesUpdate(key,character,pc,enabled,distance,now)
    local state=g_icepapa_ShotESP
    local group=state.Skeletons[key]
    if not enabled then
        g_icepapa_ESPHideGroup(group)
        state.SkeletonSamplesByKey[key]=nil
        state.SkeletonSmoothByKey[key]=nil
        return
    end
    local cfg=_G.ICE_HUD_BOX_CONFIG
    local far=(tonumber(distance) or 0)>(tonumber(cfg.SkeletonFarMeters) or 130)
    local interval=far and (tonumber(cfg.SkeletonFarSampleInterval) or (1.0/30.0))
        or (tonumber(cfg.SkeletonNearSampleInterval) or (1.0/60.0))
    local hold=tonumber(cfg.SkeletonMissingHoldSeconds) or 0.18
    local snapshot=state.SkeletonSamplesByKey[key]
    if not snapshot then
        snapshot={World={},Seen={},LastSample=-999}
        state.SkeletonSamplesByKey[key]=snapshot
    end
    local smooth=state.SkeletonSmoothByKey[key]
    if not smooth then
        smooth={World={},LastFrame=now}
        state.SkeletonSmoothByKey[key]=smooth
    end
    if now-snapshot.LastSample>=math.max(0.008,interval) then
        local mesh=nil
        pcall(function() mesh=character.Mesh or (character.GetMesh and character:GetMesh()) end)
        if g_icepapa_ESPValid(mesh) then
            local root=nil
            pcall(function()
                if character.K2_GetActorLocation then root=character:K2_GetActorLocation()
                elseif Game and Game.GetActorLocation then root=Game:GetActorLocation(character) end
            end)
            local rx=root and tonumber(root.X)
            local ry=root and tonumber(root.Y)
            local rz=root and tonumber(root.Z)
            for joint,names in pairs(ICE_BONES_NAMES) do
                local point=ICE_BonesGetWorld(mesh,key,joint,names)
                if point and rx and ry and rz then
                    local dx,dy,dz=point.X-rx,point.Y-ry,point.Z-rz
                    if dx*dx+dy*dy+dz*dz>550*550 then point=nil end
                end
                if point then
                    snapshot.World[joint]=point
                    snapshot.Seen[joint]=now
                elseif now-(snapshot.Seen[joint] or -999)>hold then
                    snapshot.World[joint]=nil
                    snapshot.Seen[joint]=nil
                end
            end
        end
        snapshot.LastSample=now
    end
    local dt=math.max(0,math.min(0.10,now-(smooth.LastFrame or now)))
    smooth.LastFrame=now
    local tau=math.max(0.008,tonumber(cfg.SkeletonSmoothingSeconds) or 0.022)
    local alpha=1.0-math.exp(-dt/tau)
    if not group then alpha=1.0 end
    local projected={}
    for joint in pairs(ICE_BONES_NAMES) do
        local point=snapshot.World[joint]
        if point and now-(snapshot.Seen[joint] or -999)<=hold then
            smooth.World[joint]=ICE_BonesSmooth(smooth.World[joint],point,alpha)
            -- Project every HUD frame, not only on the 60/30 Hz mesh sample.
            projected[joint]=g_icepapa_ESPProject(pc,smooth.World[joint])
        else
            smooth.World[joint]=nil
        end
    end
    group=g_icepapa_ESPLineGroup(state.Skeletons,key,#ICE_BONES_LINKS,ESP_BONES_RED)
    if not group then return end
    if not group.BonesPivotConfigured then
        -- Pivot at the left-edge center so each rotated segment joins bones cleanly.
        for _,data in ipairs(group) do
            pcall(function() data.Widget:SetRenderTransformPivot(g_icepapa_ESPV2(0.0,0.5)) end)
        end
        group.BonesPivotConfigured=true
    end
    group.LastActiveClock=now
    for i,link in ipairs(ICE_BONES_LINKS) do
        local a,b=projected[link[1]],projected[link[2]]
        if a and b then
            ICE_BonesDrawSegment(group[i],a.X,a.Y,b.X,b.Y,
                tonumber(cfg.SkeletonLineThickness) or 1.25)
        else
            g_icepapa_ESPHide(group[i])
        end
    end
end

-- Only real player pawns are used, as in the original blue-box file.
-- The 400m range and 8-actor limit follow the attached 90 Hz HUD.
local ICE_HUD_JustCleanedReplay = false
local ICE_HUD_LastPawns = nil

local function ICE_HUD_Scan()
    local me = ICE_GetLocalPawn()
    if not ICE_IsValid(me) then
        g_icepapa_ShotESP.Enemies = {}
        ICE_HUD_LastPawns = nil
        return
    end
    local pawns = nil
    pcall(function() pawns = Game:GetAllPlayerPawns() end)
    if not pawns then return end
    ICE_HUD_LastPawns = pawns

    -- One-shot cleanup of replay frames left by the previous blue box.
    -- Never call Replay_CreateEnemyFrameUI again.
    if not ICE_HUD_JustCleanedReplay then
        for _, pawn in pairs(pawns) do
            if ICE_IsValid(pawn) and pawn.Replay_SetVisiableOfFrameUI then
                pcall(function() pawn:Replay_SetVisiableOfFrameUI(false) end)
            end
        end
        ICE_HUD_JustCleanedReplay = true
    end

    -- The marker is independent from the new HUD box toggle.
    ICE_UpdateEnemyMapMarks(me, pawns)

    if not _G.Mod_WallHighlight and not _G.Mod_BonesESP then
        g_icepapa_ShotESP.Enemies = {}
        return
    end
    local myKey = ICE_GetPlayerKey(me)
    local myTeam = ICE_GetTeamID(me)
    local myPos = nil
    pcall(function() myPos = me:K2_GetActorLocation() end)
    local enemies = {}
    for _, pawn in pairs(pawns) do
        if ICE_IsValid(pawn) and ICE_IsAlive(pawn) then
            local key = ICE_GetPlayerKey(pawn)
            local team = ICE_GetTeamID(pawn)
            if key and pawn ~= me and (not myKey or key ~= myKey)
                and (myTeam == nil or team == nil or tostring(team) ~= tostring(myTeam)) then
                local pos = nil
                pcall(function() pos = pawn:K2_GetActorLocation() end)
                if pos and myPos then
                    local dx,dy,dz = pos.X-myPos.X, pos.Y-myPos.Y, pos.Z-myPos.Z
                    local dist = math.sqrt(dx*dx+dy*dy+dz*dz) / 100
                    if dist <= (tonumber(_G.ICE_HUD_BOX_CONFIG.MaxRangeMeters) or 400) then
                        enemies[#enemies+1] = {Character=pawn,Key=tostring(key),Distance=dist}
                    end
                end
            end
        end
    end
    table.sort(enemies, function(x,y) return x.Distance < y.Distance end)
    g_icepapa_ShotESP.Enemies = enemies
    local active={}
    local max = math.max(1, math.floor(tonumber(_G.ICE_HUD_BOX_CONFIG.MaxRendered) or 8))
    for i=1,math.min(#enemies,max) do active[enemies[i].Key]=true end
    -- Hide immediately, but reuse line widgets briefly when the nearest-
    -- player ranking changes. Destroy/recreate on each scan visibly flashed.
    local now=g_icepapa_ShotESP.FrameNow or 0
    local keep=math.max(0.5,tonumber(_G.ICE_HUD_BOX_CONFIG.UnusedWidgetKeepSeconds) or 2.0)
    for key, group in pairs(g_icepapa_ShotESP.Boxes) do
        if active[key] then
            group.LastActiveClock=now
        else
            g_icepapa_ESPHideGroup(group)
            if now - (group.LastActiveClock or now) >= keep then
                g_icepapa_ESPDestroyGroup(group)
                g_icepapa_ShotESP.Boxes[key]=nil
                g_icepapa_ShotESP.BodyByKey[key]=nil
                g_icepapa_ShotESP.ScreenByKey[key]=nil
            end
        end
    end
    -- Keep skeleton segment widgets around for a short time when rankings shift.
    for key, group in pairs(g_icepapa_ShotESP.Skeletons) do
        if active[key] and _G.Mod_BonesESP then
            group.LastActiveClock=now
        else
            g_icepapa_ESPHideGroup(group)
            if now-(group.LastActiveClock or now)>=keep then
                g_icepapa_ESPDestroyGroup(group)
                g_icepapa_ShotESP.Skeletons[key]=nil
                g_icepapa_ShotESP.BoneNameByKey[key]=nil
                g_icepapa_ShotESP.SkeletonSamplesByKey[key]=nil
                g_icepapa_ShotESP.SkeletonSmoothByKey[key]=nil
            end
        end
    end
    for key in pairs(g_icepapa_ShotESP.CreateRetryUntil) do
        if not active[key] then g_icepapa_ShotESP.CreateRetryUntil[key]=nil end
    end
    -- Clean up locations for actors whose box was never created.
    for key, entry in pairs(g_icepapa_ShotESP.BodyByKey) do
        if not active[key] and not g_icepapa_ShotESP.Boxes[key]
            and now - (entry.LastFrame or now) >= keep then
            g_icepapa_ShotESP.BodyByKey[key]=nil
            g_icepapa_ShotESP.ScreenByKey[key]=nil
        end
    end
end

local function ICE_HUD_Draw()
    if not Client then return end
    local state = g_icepapa_ShotESP
    local world = g_icepapa_ESPWorld()
    if world ~= state.LastWorld then
        g_icepapa_ESPResetWidgets()
        state.LastWorld = world
        state.LastScanClock = -999
        state.LastTransformClock = -999
        ICE_HUD_JustCleanedReplay = false
    end
    local now = g_icepapa_ESPNow()
    state.FrameNow = now
    if now - state.LastScanClock >= (tonumber(_G.ICE_HUD_BOX_CONFIG.ScanInterval) or 0.35) then
        -- The map marker is updated by Scan regardless of the HUD toggle.
        -- Calling the marker updater on every HUD frame was wasted work.
        ICE_HUD_Scan()
        state.LastScanClock = now
    end

    if not _G.Mod_WallHighlight and not _G.Mod_BonesESP then
        if next(state.Boxes) or next(state.Skeletons) then
            g_icepapa_ESPResetWidgets()
        end
        return
    end
    if not g_icepapa_ESPGetCanvas() then return end
    local pc = g_icepapa_ESPGetController()
    if not pc then return end
    if now - state.LastTransformClock >= (tonumber(_G.ICE_HUD_BOX_CONFIG.TransformInterval) or 0.50) then
        g_icepapa_ESPUpdateCanvasTransform(pc)
        state.LastTransformClock = now
    end
    local max = math.max(1, math.floor(tonumber(_G.ICE_HUD_BOX_CONFIG.MaxRendered) or 8))
    for i, item in ipairs(state.Enemies) do
        if i>max then break end
        local pawn,key=item.Character,item.Key
        if ICE_IsValid(pawn) and ICE_IsAlive(pawn) then
            local head,feet=g_icepapa_ESPSmoothBodyLocs(key,pawn,now)
            local headScreen=head and g_icepapa_ESPProject(pc,head) or nil
            local feetScreen=feet and g_icepapa_ESPProject(pc,feet) or nil
            local old=state.ScreenByKey[key]
            if headScreen and feetScreen then
                if not old then
                    old={}
                    state.ScreenByKey[key]=old
                end
                old.Head,old.Feet,old.Clock=headScreen,feetScreen,now
            elseif old and now-(old.Clock or 0) <=
                (tonumber(_G.ICE_HUD_BOX_CONFIG.ProjectionGraceSeconds) or 0.10) then
                -- Ignore a single failed screen projection; don't blink off.
                headScreen,feetScreen=old.Head,old.Feet
            else
                state.ScreenByKey[key]=nil
            end
            g_icepapa_ESPUpdateBox(key,headScreen,feetScreen,_G.Mod_WallHighlight)
            -- Shared 90-Hz HUD ticker: separate 60/30-Hz joint sampling avoids
            -- repeated 12-bone native mesh reads on every paint update.
            ICE_BonesUpdate(key,pawn,pc,_G.Mod_BonesESP,item.Distance,now)
        else
            g_icepapa_ESPHideGroup(state.Boxes[key])
            g_icepapa_ESPHideGroup(state.Skeletons[key])
        end
    end
end

-- Invalidate the former blue replay-frame loop on a hot reload.
_G.ICE_BLUE_BOX_LOOP_TOKEN = (_G.ICE_BLUE_BOX_LOOP_TOKEN or 0) + 1
-- Prevent multiple HUD loops from accumulating on reload.
_G.ICE_HUD_ONLY_LOOP_TOKEN = (_G.ICE_HUD_ONLY_LOOP_TOKEN or 0) + 1
local ICE_HUD_LoopToken = _G.ICE_HUD_ONLY_LOOP_TOKEN
local function ICE_HUD_Tick()
    if ICE_HUD_LoopToken ~= _G.ICE_HUD_ONLY_LOOP_TOKEN then
        g_icepapa_ESPResetWidgets()
        return
    end
    pcall(ICE_HUD_Draw)
    if ICE_Ticker and ICE_Ticker.AddTimerOnce then
        ICE_Ticker.AddTimerOnce(tonumber(_G.ICE_HUD_BOX_CONFIG.UpdateInterval) or (1.0 / 90.0), ICE_HUD_Tick)
    end
end
if Client and ICE_Ticker and ICE_Ticker.AddTimerOnce then
    ICE_Ticker.AddTimerOnce(0.35, ICE_HUD_Tick)
end


