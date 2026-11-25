-- Load WindUI Library
local WindUI = loadstring(game:HttpGet("https://github.com/Footagesus/WindUI/releases/latest/download/main.lua"))()

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")
local Lighting = game:GetService("Lighting")

local LocalPlayer = Players.LocalPlayer
local Mouse = LocalPlayer:GetMouse()
local Camera = workspace.CurrentCamera

local Config = {
    FOVVisible = false, FOVRadius = 300, AimLockEnabled = false, AimTargetMode = "Head",
    BulletCurveEnabled = false, SilentAimEnabled = false, SilentAimCurve = 0.85,
    RapidFireEnabled = false, RapidFireDelay = 0.1, WallbangEnabled = false, DeviceMode = "Mobile",
    BoxESP = false, HealthBarESP = false,
    InfiniteStamina = false, InfiniteJump = false, SpeedEnabled = false, WalkSpeedValue = 28,
    SpinEnabled = false, SpinDegPerSec = 360,
    VehicleSpeedEnabled = false, VehicleSpeedMultiplier = 1.65, AntiDriftEnabled = false, LockVehicleEnabled = false,
    SmoothAimAssist = false, SmoothnessValue = 0.18, LegitSprint = false, LegitSprintSpeed = 22, AutoRecoverHealth = false,
    SaveScriptEnabled = false, DontSaveScript = true
}

local State = {
    LockedTarget = nil, LockedPart = nil, LockedAimPos = nil,
    SilentTarget = nil, SilentPart = nil, SilentAimPos = nil,
    LockedSeat = nil, LockedRoot = nil, LockedModel = nil, LockedGroundCFrame = nil,
    SavedCameraType = nil, RapidFireLoopRunning = false
}

local FOVCircle = Drawing.new("Circle")
FOVCircle.Thickness, FOVCircle.NumSides, FOVCircle.Radius, FOVCircle.Filled, FOVCircle.Visible = 1.5, 36, Config.FOVRadius, false, false
FOVCircle.Color = Color3.fromRGB(168, 85, 247)

local function GetCam() return workspace.CurrentCamera or Camera end
local function GetRefScreenPos(cam)
    if Config.DeviceMode == "PC" and Mouse then return Vector2.new(Mouse.X, Mouse.Y + 36) end
    return Vector2.new(cam.ViewportSize.X * 0.5, cam.ViewportSize.Y * 0.5)
end
local function GetAimPartFromChar(char)
    if not char then return nil end
    if Config.AimTargetMode == "Body" then
        return char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso") or char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Head")
    end
    return char:FindFirstChild("Head") or char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso")
end
local function GetAimWorldPos(char, part)
    if not char or not part or not part.Parent then return nil end
    if Config.AimTargetMode == "Head" then
        local head = char:FindFirstChild("Head")
        if head and head:IsA("BasePart") then return head.Position + Vector3.new(0, 0.2, 0) end
    end
    return part.Position
end
local function IsProtectedTarget(char) return not char or char:FindFirstChildOfClass("ForceField") ~= nil end
local function IsValidTarget(plr)
    if not plr or plr == LocalPlayer then return false, nil, nil end
    local char = plr.Character
    if not char or IsProtectedTarget(char) then return false, nil, nil end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health <= 0 then return false, nil, nil end
    local part = GetAimPartFromChar(char)
    if not part then return false, nil, nil end
    local pos = GetAimWorldPos(char, part)
    if not pos then return false, nil, nil end
    return true, part, pos
end
local function IsPosInsideFOV(cam, worldPos, refPos, radius)
    if not cam or not worldPos then return false, math.huge end
    local sp, onScreen = cam:WorldToViewportPoint(worldPos)
    if not onScreen or sp.Z <= 0 then return false, math.huge end
    local d = (Vector2.new(sp.X, sp.Y) - refPos).Magnitude
    return d <= radius, d
end
local function HasLockActive() return Config.FOVVisible or Config.AimLockEnabled end
local function ClearAimState(cam)
    State.LockedTarget, State.LockedPart, State.LockedAimPos = nil, nil, nil
    if cam and State.SavedCameraType and cam.CameraType == Enum.CameraType.Scriptable then
        cam.CameraType, State.SavedCameraType = State.SavedCameraType, nil
    end
end
local function UpdateSingleTargetLock(cam, refPos)
    if not HasLockActive() then ClearAimState(cam); return nil, nil end
    local cPlr, cPart, cPos, cDist = nil, nil, nil, Config.FOVRadius
    for _, plr in ipairs(Players:GetPlayers()) do
        local ok, p, pos = IsValidTarget(plr)
        if ok and p and pos then
            local ins, d = IsPosInsideFOV(cam, pos, refPos, Config.FOVRadius)
            if ins and d < cDist then cDist, cPlr, cPart, cPos = d, plr, p, pos end
        end
    end
    if State.LockedTarget then
        local ok, p, pos = IsValidTarget(State.LockedTarget)
        if ok and p and pos then
            local ins, d = IsPosInsideFOV(cam, pos, refPos, Config.FOVRadius)
            if ins then
                if cPlr and cPlr ~= State.LockedTarget and (cDist + 30) < d then
                    State.LockedTarget, State.LockedPart, State.LockedAimPos = cPlr, cPart, cPos
                    return cPart, cPos
                end
                State.LockedPart, State.LockedAimPos = p, pos
                return p, pos
            end
        end
        State.LockedTarget, State.LockedPart, State.LockedAimPos = nil, nil, nil
    end
    State.LockedTarget, State.LockedPart, State.LockedAimPos = cPlr, cPart, cPos
    return cPart, cPos
end
local SilentAim = {}
local lastSilentScan = 0
function SilentAim.Clear() State.SilentTarget, State.SilentPart, State.SilentAimPos = nil, nil, nil end
function SilentAim.Update(cam, refPos)
    if not Config.SilentAimEnabled then SilentAim.Clear(); return nil, nil end
    local now = os.clock()
    if (now - lastSilentScan) < 0.08 then return State.SilentPart, State.SilentAimPos end
    lastSilentScan = now
    local bPlr, bPart, bPos, bDist = nil, nil, nil, Config.FOVRadius
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer then
            local ok, p, pos = IsValidTarget(plr)
            if ok and p and pos then
                local ins, d = IsPosInsideFOV(cam, pos, refPos, Config.FOVRadius)
                if ins and d < bDist then bDist, bPlr, bPart, bPos = d, plr, p, pos end
            end
        end
    end
    State.SilentTarget, State.SilentPart, State.SilentAimPos = bPlr, bPart, bPos
    return bPart, bPos
end

local function ApplyCameraAimLock(cam, lockedPart, aimPos)
    if not Config.AimLockEnabled or not lockedPart or not lockedPart.Parent or not aimPos then
        if State.SavedCameraType and cam.CameraType == Enum.CameraType.Scriptable then
            cam.CameraType, State.SavedCameraType = State.SavedCameraType, nil
        end
        return
    end
    if not State.SavedCameraType then State.SavedCameraType = cam.CameraType end
    if cam.CameraType ~= Enum.CameraType.Scriptable then cam.CameraType = Enum.CameraType.Scriptable end
    cam.CFrame = cam.CFrame:Lerp(CFrame.lookAt(cam.CFrame.Position, aimPos), 0.98)
end
local function ApplyGameplayAssist(cam, refPos)
    if not Config.SmoothAimAssist or Config.AimLockEnabled then return end
    local bestPos, bestDist = nil, Config.FOVRadius
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer then
            local valid, _, aimPos = IsValidTarget(plr)
            if valid and aimPos then
                local inside, dist = IsPosInsideFOV(cam, aimPos, refPos, Config.FOVRadius)
                if inside and dist < bestDist then bestDist, bestPos = dist, aimPos end
            end
        end
    end
    if bestPos then
        local alpha = math.clamp(tonumber(Config.SmoothnessValue) or 0.18, 0.05, 0.45)
        cam.CFrame = cam.CFrame:Lerp(CFrame.lookAt(cam.CFrame.Position, bestPos), alpha)
    end
end
local function ApplyCharacterSpin(dt)
    if not Config.SpinEnabled then return end
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if hrp and hum and hum.Health > 0 then
        local deg = math.clamp(tonumber(Config.SpinDegPerSec) or 360, 30, 10000)
        hrp.CFrame = hrp.CFrame * CFrame.Angles(0, math.rad(deg * dt), 0)
    end
end
local function TriggerEquippedWeapon()
    local tool = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Tool")
    if tool then pcall(function() tool:Activate() end) end
end
local function StartRapidFireLoop()
    if State.RapidFireLoopRunning then return end
    State.RapidFireLoopRunning = true
    task.spawn(function()
        while Config.RapidFireEnabled do
            TriggerEquippedWeapon()
            task.wait(math.max(tonumber(Config.RapidFireDelay) or 0.1, 0.1))
        end
        State.RapidFireLoopRunning = false
    end)
end
local function GetCurrentVehicleParts()
    local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
    local seat = hum and hum.SeatPart
    if not seat or not seat:IsA("BasePart") then return nil, nil, nil end
    local model = seat:FindFirstAncestorOfClass("Model")
    local root = seat
    if model then
        if model.PrimaryPart and model.PrimaryPart:IsA("BasePart") then root = model.PrimaryPart
        else
            local body = model:FindFirstChild("Body") or model:FindFirstChild("Chassis") or model:FindFirstChild("HumanoidRootPart")
            if body and body:IsA("BasePart") then root = body end
        end
    end
    return seat, root, model
end
local function GetGroundSnappedCFrame(root, model)
    if not root or not root.Parent then return nil end
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    local ignoreList = {}
    if LocalPlayer.Character then table.insert(ignoreList, LocalPlayer.Character) end
    if model then table.insert(ignoreList, model) end
    params.FilterDescendantsInstances = ignoreList
    local lowestY = root.Position.Y - (root.Size.Y * 0.5)
    if model then
        for _, desc in ipairs(model:GetDescendants()) do
            if desc:IsA("BasePart") then
                local b = desc.Position.Y - (desc.Size.Y * 0.5)
                if b < lowestY then lowestY = b end
            end
        end
    end
    local res = workspace:Raycast(Vector3.new(root.Position.X, lowestY + 1.5, root.Position.Z), Vector3.new(0, -25, 0), params)
    return res and (root.CFrame + Vector3.new(0, res.Position.Y - lowestY, 0)) or root.CFrame
end
local function ClearVehicleLockState() State.LockedSeat, State.LockedRoot, State.LockedModel, State.LockedGroundCFrame = nil, nil, nil, nil end
local function UpdateVehiclePhysics()
    local seat, root, model = GetCurrentVehicleParts()
    if not (Config.VehicleSpeedEnabled or Config.AntiDriftEnabled or Config.LockVehicleEnabled) or not seat or not root then
        ClearVehicleLockState(); return
    end
    if Config.LockVehicleEnabled then
        if State.LockedModel ~= model or not State.LockedGroundCFrame then
            State.LockedSeat, State.LockedRoot, State.LockedModel = seat, root, model
            State.LockedGroundCFrame = GetGroundSnappedCFrame(root, model)
        end
        if seat:IsA("VehicleSeat") then seat.Throttle, seat.Steer = 0, 0 end
        root.AssemblyLinearVelocity, root.AssemblyAngularVelocity, root.CFrame = Vector3.zero, Vector3.zero, State.LockedGroundCFrame
        return
    end
    ClearVehicleLockState()
    local vel = root.AssemblyLinearVelocity
    local throttling = seat:IsA("VehicleSeat") and ((math.abs(seat.Throttle) > 0.05) or (math.abs(seat.Steer) > 0.05))
    if Config.AntiDriftEnabled then
        local r = root.CFrame.RightVector
        vel = vel - (r * (vel:Dot(r) * 0.85))
        local a = root.AssemblyAngularVelocity
        root.AssemblyAngularVelocity = Vector3.new(a.X * 0.6, a.Y * 0.7, a.Z * 0.6)
    end
    if Config.VehicleSpeedEnabled then
        local h = Vector3.new(vel.X, 0, vel.Z)
        if not throttling and h.Magnitude < 2.5 then vel = Vector3.new(0, vel.Y, 0)
        elseif throttling and h.Magnitude > 0.5 then
            local b = h * Config.VehicleSpeedMultiplier
            if b.Magnitude > 165 then b = b.Unit * 165 end
            vel = Vector3.new(b.X, vel.Y, b.Z)
        end
    end
    root.AssemblyLinearVelocity = vel
end

local Window = WindUI:CreateWindow({
    Title = "BDHub Reload", Icon = "fish", Author = "BDHub Reload", Folder = "BDHubReload",
    Size = UDim2.fromOffset(580, 460), MinSize = Vector2.new(560, 350), MaxSize = Vector2.new(850, 560),
    ToggleKey = Enum.KeyCode.LeftShift, Transparent = true, Theme = "Dark", Resizable = true,
    SideBarWidth = 200, BackgroundImageTransparency = 0.42, HideSearchBar = true, ScrollBarEnabled = false,
    User = { Enabled = false, Anonymous = true, Callback = function() end }
})

task.spawn(function()
    pcall(function()
        task.wait(0.25)
        local function styleFish(root)
            for _, obj in ipairs(root:GetDescendants()) do
                if obj:IsA("ImageLabel") or obj:IsA("ImageButton") then
                    local hasTitle, p = false, obj.Parent
                    for _ = 1, 5 do
                        if not p then break end
                        for _, ch in ipairs(p:GetChildren()) do
                            if ch:IsA("TextLabel") and ch.Text == "BDHub Reload" then hasTitle = true; break end
                        end
                        if hasTitle then break end
                        p = p.Parent
                    end
                    if hasTitle and obj.AbsolutePosition.Y < 260 then
                        obj.ImageColor3 = Color3.fromRGB(0, 255, 100)
                        local w = obj.Size.X.Offset > 0 and obj.Size.X.Offset or 22
                        local h = obj.Size.Y.Offset > 0 and obj.Size.Y.Offset or 22
                        obj.Size = UDim2.fromOffset(math.floor(w * 1.25), math.floor(h * 1.25))
                        return
                    end
                end
            end
        end
        styleFish(game:GetService("CoreGui"))
        if LocalPlayer:FindFirstChild("PlayerGui") then styleFish(LocalPlayer.PlayerGui) end
    end)
end)
local AimbotTab = Window:Tab({ Title = "Aimbot", Icon = "crosshair" })
AimbotTab:Section({ Title = "FOV, Lock, Silent Aim & Rapid Fire" })
AimbotTab:Toggle({ Title = "Show FOV Circle", Default = false, Callback = function(v) Config.FOVVisible = v; FOVCircle.Visible = v; if not HasLockActive() then ClearAimState(GetCam()) end end })
AimbotTab:Slider({ Title = "FOV Radius", Step = 5, Value = { Min = 30, Max = 1000, Default = 300 }, Callback = function(v) Config.FOVRadius = v; FOVCircle.Radius = v end })
AimbotTab:Toggle({ Title = "Camera Lock (Aimbot)", Default = false, Callback = function(v) Config.AimLockEnabled = v; if not v then ClearAimState(GetCam()) end end })
AimbotTab:Dropdown({ Title = "Aim Target Mode", Values = { "Head", "Body" }, Value = "Head", Callback = function(opt)
    local c = type(opt) == "table" and opt[1] or opt
    if c == "Head" or c == "Body" then
        Config.AimTargetMode = c
        if State.LockedTarget and State.LockedTarget.Character then
            local part = GetAimPartFromChar(State.LockedTarget.Character)
            State.LockedPart, State.LockedAimPos = part, GetAimWorldPos(State.LockedTarget.Character, part)
        end
    end
end })
AimbotTab:Toggle({ Title = "Silent Aim", Default = false, Callback = function(v) Config.SilentAimEnabled = v; if not v then SilentAim.Clear() end end })
AimbotTab:Slider({ Title = "Silent Aim Curve Strength", Step = 0.05, Value = { Min = 0.1, Max = 1.0, Default = 0.85 }, Callback = function(v) Config.SilentAimCurve = math.clamp(tonumber(v) or 0.85, 0.05, 1.0) end })
AimbotTab:Toggle({ Title = "Bullet Curve (Locked Target)", Default = false, Callback = function(v) Config.BulletCurveEnabled = v end })
AimbotTab:Toggle({ Title = "Rapid Fire", Default = false, Callback = function(v) Config.RapidFireEnabled = v; if v then StartRapidFireLoop() end end })
AimbotTab:Slider({ Title = "Rapid Fire Delay (0.1 = Fast)", Step = 0.05, Value = { Min = 0.1, Max = 1.0, Default = 0.1 }, Callback = function(v) Config.RapidFireDelay = math.max(tonumber(v) or 0.1, 0.1) end })
AimbotTab:Toggle({ Title = "Wallbang / Pierce", Default = false, Callback = function(v) Config.WallbangEnabled = v end })
AimbotTab:Dropdown({ Title = "Device Mode", Values = { "Mobile", "PC" }, Value = "Mobile", Callback = function(opt) local c = type(opt) == "table" and opt[1] or opt; if c then Config.DeviceMode = c end end })

local VisualsTab = Window:Tab({ Title = "Visuals", Icon = "eye" })
VisualsTab:Section({ Title = "Box & Health Bar ESP" })
VisualsTab:Toggle({ Title = "Box ESP", Default = false, Callback = function(v) Config.BoxESP = v end })
VisualsTab:Toggle({ Title = "Health Bar ESP", Default = false, Callback = function(v) Config.HealthBarESP = v end })

local PlayerTab = Window:Tab({ Title = "Player", Icon = "user" })
PlayerTab:Section({ Title = "Movement & Spin Controls" })
PlayerTab:Toggle({ Title = "Infinite Stamina", Default = false, Callback = function(v) Config.InfiniteStamina = v end })
PlayerTab:Toggle({ Title = "Infinite Jump", Default = false, Callback = function(v) Config.InfiniteJump = v end })
PlayerTab:Toggle({ Title = "Fast Run", Default = false, Callback = function(v)
    Config.SpeedEnabled = v
    local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
    if hum and not v and not Config.LegitSprint then hum.WalkSpeed = 16 end
end })
PlayerTab:Slider({ Title = "Run Speed", Step = 1, Value = { Min = 16, Max = 100, Default = 28 }, Callback = function(v) Config.WalkSpeedValue = v end })
PlayerTab:Toggle({ Title = "Spin Character", Default = false, Callback = function(v) Config.SpinEnabled = v end })
PlayerTab:Slider({ Title = "Spin Degrees (Max 10,000°)", Step = 50, Value = { Min = 30, Max = 10000, Default = 360 }, Callback = function(v) Config.SpinDegPerSec = math.clamp(tonumber(v) or 360, 30, 10000) end })

local VehicleTab = Window:Tab({ Title = "Vehicle", Icon = "car" })
VehicleTab:Section({ Title = "Speed, Anti-Drift & Lock" })
VehicleTab:Toggle({ Title = "Vehicle Speed (Boost on Throttle)", Default = false, Callback = function(v) Config.VehicleSpeedEnabled = v end })
VehicleTab:Slider({ Title = "Vehicle Speed Multiplier", Step = 0.05, Value = { Min = 1.0, Max = 2.5, Default = 1.65 }, Callback = function(v) Config.VehicleSpeedMultiplier = v end })
VehicleTab:Toggle({ Title = "Anti-Drift / Stabilizer", Default = false, Callback = function(v) Config.AntiDriftEnabled = v end })
VehicleTab:Toggle({ Title = "Lock Vehicle (On Ground)", Default = false, Callback = function(v) Config.LockVehicleEnabled = v; if not v then ClearVehicleLockState() end end })

local GameplayTab = Window:Tab({ Title = "Gameplay", Icon = "gamepad" })
GameplayTab:Section({ Title = "Legit Playstyle Assist" })
GameplayTab:Toggle({ Title = "Smooth Aim Assist (Legit)", Default = false, Callback = function(v) Config.SmoothAimAssist = v end })
GameplayTab:Slider({ Title = "Aim Assist Smoothness", Step = 0.02, Value = { Min = 0.05, Max = 0.50, Default = 0.18 }, Callback = function(v) Config.SmoothnessValue = tonumber(v) or 0.18 end })
GameplayTab:Toggle({ Title = "Legit Sprint Pace", Default = false, Callback = function(v)
    Config.LegitSprint = v
    local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
    if hum and not v and not Config.SpeedEnabled then hum.WalkSpeed = 16 end
end })
GameplayTab:Slider({ Title = "Legit Sprint Speed", Step = 1, Value = { Min = 16, Max = 36, Default = 22 }, Callback = function(v) Config.LegitSprintSpeed = tonumber(v) or 22 end })
GameplayTab:Toggle({ Title = "Auto Recover / Stamina Guard", Default = false, Callback = function(v) Config.AutoRecoverHealth = v end })

local SettingsTab = Window:Tab({ Title = "Settings", Icon = "settings" })
SettingsTab:Section({ Title = "Script & Server" })
SettingsTab:Button({ Title = "Save Script", Callback = function()
    Config.SaveScriptEnabled, Config.DontSaveScript = true, false
    pcall(function() WindUI:Notify({ Title = "BDHub Reload", Content = "Save Script enabled.", Duration = 3 }) end)
end })
SettingsTab:Button({ Title = "FPS Booster", Callback = function()
    pcall(function()
        Lighting.GlobalShadows, Lighting.FogEnd = false, 9e9
        for _, obj in ipairs(workspace:GetDescendants()) do
            if obj:IsA("BasePart") then obj.Material, obj.Reflectance = Enum.Material.SmoothPlastic, 0
            elseif obj:IsA("Decal") or obj:IsA("Texture") then obj.Transparency = 1
            elseif obj:IsA("ParticleEmitter") or obj:IsA("Trail") then obj.Enabled = false end
        end
    end)
    pcall(function() WindUI:Notify({ Title = "BDHub Reload", Content = "FPS Booster applied.", Duration = 3 }) end)
end })
SettingsTab:Button({ Title = "Don't Save Script", Callback = function()
    Config.SaveScriptEnabled, Config.DontSaveScript = false, true
    pcall(function() WindUI:Notify({ Title = "BDHub Reload", Content = "Don't Save Script active.", Duration = 3 }) end)
end })
SettingsTab:Button({ Title = "Server Hop", Callback = function()
    local ok, res = pcall(function() return HttpService:JSONDecode(game:HttpGet("https://games.roblox.com/v1/games/" .. game.PlaceId .. "/servers/Public?sortOrder=Asc&limit=100")) end)
    if ok and res and res.data then
        for _, srv in ipairs(res.data) do
            if srv.id ~= game.JobId and srv.playing < srv.maxPlayers then
                TeleportService:TeleportToPlaceInstance(game.PlaceId, srv.id, LocalPlayer); break
            end
        end
    end
end })

local ESPObjects = {}
local hasDrawing = pcall(function() return Drawing and Drawing.new end)
local function RemovePlayerESP(plr)
    local d = ESPObjects[plr]
    if d then for _, o in pairs(d) do pcall(function() if o and o.Remove then o:Remove() end end) end; ESPObjects[plr] = nil end
end
UserInputService.JumpRequest:Connect(function()
    if not Config.InfiniteJump then return end
    local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
    if hum then hum:ChangeState(Enum.HumanoidStateType.Jumping) end
end)
Players.PlayerRemoving:Connect(RemovePlayerESP)

local function EnsurePlayerESP(plr)
    if not hasDrawing then return nil end
    if not ESPObjects[plr] then
        local box = Drawing.new("Square"); box.Thickness, box.Filled, box.Visible = 1.5, false, false
        local hpBg = Drawing.new("Line"); hpBg.Thickness, hpBg.Color, hpBg.Visible = 3, Color3.fromRGB(0, 0, 0), false
        local hpFill = Drawing.new("Line"); hpFill.Thickness, hpFill.Visible = 1.5, false
        ESPObjects[plr] = { Box = box, HPBg = hpBg, HPFill = hpFill }
    end
    return ESPObjects[plr]
end

local function UpdateESP(cam)
    if not (hasDrawing and (Config.BoxESP or Config.HealthBarESP)) then
        for plr in pairs(ESPObjects) do RemovePlayerESP(plr) end
        return
    end
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer and plr.Character then
            local char = plr.Character
            local hrp = char:FindFirstChild("HumanoidRootPart")
            local hum = char:FindFirstChildOfClass("Humanoid")
            if hrp and hum and hum.Health > 0 then
                local d = EnsurePlayerESP(plr)
                local rootPos, onScreen = cam:WorldToViewportPoint(hrp.Position)
                if onScreen and rootPos.Z > 0 then
                    local tanH = math.tan(math.rad(cam.FieldOfView * 0.5))
                    local sc = 1000 / math.max(rootPos.Z * tanH * 2, 0.01)
                    local w = math.clamp(math.floor(4 * sc), 8, 220)
                    local h = math.clamp(math.floor(5.5 * sc), 12, 280)
                    local pos = Vector2.new(rootPos.X - w * 0.5, rootPos.Y - h * 0.5)
                    d.Box.Visible = Config.BoxESP
                    if Config.BoxESP then
                        d.Box.Color = (State.LockedTarget == plr) and Color3.fromRGB(255, 0, 0) or Color3.fromRGB(255, 255, 255)
                        d.Box.Size, d.Box.Position = Vector2.new(w, h), pos
                    end
                    d.HPBg.Visible, d.HPFill.Visible = Config.HealthBarESP, Config.HealthBarESP
                    if Config.HealthBarESP then
                        local pct = math.clamp(hum.Health / math.max(hum.MaxHealth, 1), 0, 1)
                        d.HPBg.From, d.HPBg.To = Vector2.new(pos.X - 6, pos.Y + h), Vector2.new(pos.X - 6, pos.Y)
                        d.HPFill.From, d.HPFill.To = Vector2.new(pos.X - 6, pos.Y + h), Vector2.new(pos.X - 6, pos.Y + (h - (h * pct)))
                        d.HPFill.Color = Color3.fromRGB(0, 255, 90)
                    end
                else
                    for _, o in pairs(d) do o.Visible = false end
                end
            else RemovePlayerESP(plr) end
        else RemovePlayerESP(plr) end
    end
end

local lastSilentTick = 0
RunService.RenderStepped:Connect(function(dt)
    local cam = GetCam()
    if not cam then return end
    local refPos = GetRefScreenPos(cam)
    FOVCircle.Position, FOVCircle.Radius, FOVCircle.Visible = refPos, Config.FOVRadius, Config.FOVVisible
    local lockedPart, aimPos = UpdateSingleTargetLock(cam, refPos)
    local now = os.clock()
    if (now - lastSilentTick) >= 0.1 then lastSilentTick = now; SilentAim.Update(cam, refPos) end
    ApplyCameraAimLock(cam, lockedPart, aimPos)
    ApplyGameplayAssist(cam, refPos)
    ApplyCharacterSpin(dt)
    local char = LocalPlayer.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if hum then
        if Config.SpeedEnabled then hum.WalkSpeed = Config.WalkSpeedValue
        elseif Config.LegitSprint and hum.MoveDirection.Magnitude > 0.05 then hum.WalkSpeed = Config.LegitSprintSpeed end
        if (Config.InfiniteStamina or Config.AutoRecoverHealth) and char:GetAttribute("Stamina") ~= nil then char:SetAttribute("Stamina", 100) end
        if Config.AutoRecoverHealth and hum.Health > 0 and hum.Health < hum.MaxHealth then
            pcall(function() hum.Health = math.min(hum.MaxHealth, hum.Health + (8 * dt)) end)
        end
    end
    UpdateVehiclePhysics()
    UpdateESP(cam)
end)
