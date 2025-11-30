-- Urban Autofarm UI (Optimized, single LocalScript)
-- Paste into StarterPlayer -> StarterPlayerScripts (LocalScript)

-- Services
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

-- Config / tuning
local EVAL_RADIUS = 100000
local HIGHLIGHT_THROTTLE = 0.25      -- seconds between highlight updates
local AUTOFARM_RECHECK = 0.01        -- small yield inside autofarm loop
local WALK_DEFAULT = 16
local WS_MIN, WS_MAX, WS_STEP = 16, 100, 1

-- How many studs above the target to hover (change this to x(number), etc)
local VERTICAL_OFFSET = 10
local BACK_OFFSET = 0

-- UI palette (urban / neon)
local PAL = {
    bg = Color3.fromRGB(18,18,20),
    panel = Color3.fromRGB(28,28,30),
    accent = Color3.fromRGB(255,95,75),
    text = Color3.fromRGB(230,230,230),
    neonG = Color3.fromRGB(57,255,20),
    brightG = Color3.fromRGB(0,150,0),
    brightR = Color3.fromRGB(200,30,30),
    neonR = Color3.fromRGB(255,0,0)
}

-- State
local npcList = {}            -- array of models currently known (ref)
local npcByModel = {}         -- model -> true (fast remove)
local selectedNames = {}      -- name -> true/false (from lister)  <-- shared between NPC and Player lists
local highlights = {}         -- model -> Highlight instance
local highlightColor = {}     -- model -> Color3
local autoEnabled = false
local delayValue = 1
local wsEnabled = true

-- Helpers
local function new(class, props)
    local o = Instance.new(class)
    if props then for k,v in pairs(props) do o[k] = v end end
    return o
end
local function clamp(v,a,b) return math.clamp(v,a,b) end
local function roundTo(v, step) step = step or 1; return math.floor(v/step + 0.5)*step end
local function horizontalDistance(a,b)
    return (Vector3.new(a.X,0,a.Z) - Vector3.new(b.X,0,b.Z)).Magnitude
end

-- Clean previous GUI if exists (avoid duplicates during development)
local existing = PlayerGui:FindFirstChild("UrbanAutofarmUI")
if existing then existing:Destroy() end

-- Root ScreenGui
local Screen = new("ScreenGui", { Name = "UrbanAutofarmUI", Parent = PlayerGui, ResetOnSpawn = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling })

-- Main panel (compact urban)
local Main = new("Frame", {
    Parent = Screen, Name = "Main",
    Size = UDim2.new(0,420,0,360),
    Position = UDim2.new(0.02,0,0.08,0),
    BackgroundColor3 = PAL.bg, BorderSizePixel = 0, Active = true
})
new("UICorner", { Parent = Main, CornerRadius = UDim.new(0,10) })
local TopAccent = new("Frame", { Parent = Main, Size = UDim2.new(1,0,0,4), Position = UDim2.new(0,0,0,0), BackgroundColor3 = PAL.accent, BorderSizePixel = 0 })

-- Title / drag area
local Title = new("Frame", { Parent = Main, Size = UDim2.new(1,0,0,36), BackgroundTransparency = 1 })
new("TextLabel", { Parent = Title, Text = "URBAN MENU", Position = UDim2.new(0,12,0,0), Size = UDim2.new(1,-24,1,0), BackgroundTransparency = 1, Font = Enum.Font.GothamBold, TextSize = 16, TextColor3 = PAL.text, TextXAlignment = Enum.TextXAlignment.Left })
local DragArea = new("Frame", { Parent = Title, Size = UDim2.new(1,0,1,0), BackgroundTransparency = 1, Active = true })

-- Drag logic (simple & safe)
do
    local dragging, dragInput, dragStart, startPos
    DragArea.InputBegan:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
            dragStart = inp.Position
            startPos = Main.Position
            inp.Changed:Connect(function()
                if inp.UserInputState == Enum.UserInputState.End then dragging = false end
            end)
        end
    end)
    DragArea.InputChanged:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseMovement then dragInput = inp end
    end)
    UserInputService.InputChanged:Connect(function(inp)
        if dragging and inp == dragInput then
            local delta = inp.Position - dragStart
            Main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
        end
    end)
end

-- Tabs
local TabRow = new("Frame", { Parent = Main, Position = UDim2.new(0,10,0,44), Size = UDim2.new(1,-20,0,34), BackgroundTransparency = 1 })
local function MakeTab(text, x)
    local b = new("TextButton", { Parent = TabRow, Size = UDim2.new(0,128,1,0), Position = UDim2.new(x,0,0,0), Text = text, Font = Enum.Font.GothamBold, TextSize = 14, TextColor3 = PAL.text, BackgroundColor3 = PAL.panel, AutoButtonColor = true })
    new("UICorner", { Parent = b, CornerRadius = UDim.new(0,8) })
    return b
end
local BtnHome = MakeTab("Home", 0)
local BtnUtils = MakeTab("Utils", 0.33)
local BtnMods  = MakeTab("Mods", 0.66)

local Content = new("Frame", { Parent = Main, Position = UDim2.new(0,10,0,86), Size = UDim2.new(1,-20,1,-96), BackgroundTransparency = 1 })
local FrameHome = new("Frame", { Parent = Content, Size = UDim2.new(1,1,1,0), BackgroundTransparency = 1 })
local FrameUtils = new("Frame", { Parent = Content, Size = FrameHome.Size, BackgroundTransparency = 1, Visible = false })
local FrameMods  = new("Frame", { Parent = Content, Size = FrameHome.Size, BackgroundTransparency = 1, Visible = false })

local function Switch(tab)
    FrameHome.Visible = false; FrameUtils.Visible = false; FrameMods.Visible = false
    tab.Visible = true
    BtnHome.BackgroundColor3 = (tab==FrameHome) and PAL.accent or PAL.panel
    BtnUtils.BackgroundColor3 = (tab==FrameUtils) and PAL.accent or PAL.panel
    BtnMods.BackgroundColor3  = (tab==FrameMods) and PAL.accent or PAL.panel
end
BtnHome.MouseButton1Click:Connect(function() Switch(FrameHome) end)
BtnUtils.MouseButton1Click:Connect(function() Switch(FrameUtils) end)
BtnMods.MouseButton1Click:Connect(function() Switch(FrameMods) end)
Switch(FrameHome)

-- Small label helper
local function label(parent, text, pos)
    local l = new("TextLabel", { Parent = parent, Text = text, Position = pos or UDim2.new(0,0,0,0), Size = UDim2.new(0,300,0,20), BackgroundTransparency = 1, Font = Enum.Font.GothamBold, TextSize = 13, TextColor3 = PAL.text, TextXAlignment = Enum.TextXAlignment.Left })
    return l
end

-- Slider builder (robust)
local function Slider(parent, labelText, min, max, step, default)
    local root = new("Frame", { Parent = parent, Size = UDim2.new(1,0,0,50), BackgroundTransparency = 1 })
    label(root, labelText, UDim2.new(0,6,0,2))
    local valueLabel = new("TextLabel", { Parent = root, Position = UDim2.new(1,-80,0,2), Size = UDim2.new(0,74,0,18), BackgroundTransparency = 1, Text = tostring(default), Font = Enum.Font.GothamBold, TextSize = 13, TextColor3 = PAL.text })
    local bar = new("Frame", { Parent = root, Position = UDim2.new(0,6,0,26), Size = UDim2.new(1,-12,0,12), BackgroundColor3 = Color3.fromRGB(36,36,36), Active = true })
    new("UICorner", { Parent = bar, CornerRadius = UDim.new(0,6) })
    local fill = new("Frame", { Parent = bar, Size = UDim2.new(0,0,1,0), BackgroundColor3 = PAL.accent })
    local knob = new("Frame", { Parent = bar, Size = UDim2.new(0,14,1,0), BackgroundColor3 = PAL.accent, AnchorPoint = Vector2.new(0.5,0.5) })
    new("UICorner", { Parent = knob, CornerRadius = UDim.new(0,8) })
    knob.Position = UDim2.new(0, -7, 0.5, 0)

    local val = default
    local function set(v)
        v = math.clamp(v, min, max)
        v = roundTo(v, step)
        val = v
        valueLabel.Text = tostring(v)
        local pct = (v - min) / math.max(1, (max - min))
        fill.Size = UDim2.new(pct, 0, 1, 0)
        knob.Position = UDim2.new(pct, 0, 0.5, 0)
    end
    set(default)

    local dragging = false
    bar.InputBegan:Connect(function(i) if i.UserInputType == Enum.UserInputType.MouseButton1 then dragging = true set( ( (i.Position.X - bar.AbsolutePosition.X) / bar.AbsoluteSize.X ) * (max-min) + min ) end end)
    bar.InputEnded:Connect(function(i) if i.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end end)
    UserInputService.InputChanged:Connect(function(i) if dragging and i.UserInputType == Enum.UserInputType.MouseMovement then set( ( (i.Position.X - bar.AbsolutePosition.X) / bar.AbsoluteSize.X ) * (max-min) + min ) end end)

    return { Frame = root, GetValue = function() return val end, SetValue = set }
end

-- ---------- Home UI ----------
label(FrameHome, "Walkspeed", UDim2.new(0,6,0,0))
local wsSlider = Slider(FrameHome, "Walkspeed", WS_MIN, WS_MAX, WS_STEP, WALK_DEFAULT)
wsSlider.Frame.Position = UDim2.new(0,6,0,24)

local wsToggle = new("TextButton", { Parent = FrameHome, Position = UDim2.new(0,6,0,80), Size = UDim2.new(0,180,0,28), Text = "Enable Walkspeed: ON", Font = Enum.Font.GothamBold, TextSize = 13, BackgroundColor3 = PAL.panel, TextColor3 = PAL.text, AutoButtonColor = true })
new("UICorner", { Parent = wsToggle, CornerRadius = UDim.new(0,8) })
wsToggle.MouseButton1Click:Connect(function()
    wsEnabled = not wsEnabled
    wsToggle.Text = "Enable Walkspeed: " .. (wsEnabled and "ON" or "OFF")
    if not wsEnabled then
        local ch = LocalPlayer.Character
        if ch then pcall(function() ch:FindFirstChildOfClass("Humanoid").WalkSpeed = WALK_DEFAULT end) end
    else
        local ch = LocalPlayer.Character
        if ch then pcall(function() ch:FindFirstChildOfClass("Humanoid").WalkSpeed = wsSlider.GetValue() end) end
    end
end)

-- Evaluate button + lister
local evalBtn = new("TextButton", { Parent = FrameHome, Position = UDim2.new(0,200,0,80), Size = UDim2.new(0,180,0,28), Text = "Evaluate", Font = Enum.Font.GothamBold, TextSize = 13, BackgroundColor3 = PAL.panel, TextColor3 = PAL.text, AutoButtonColor = true })
new("UICorner", { Parent = evalBtn, CornerRadius = UDim.new(0,8) })

label(FrameHome, "List of NPCs", UDim2.new(0,6,0,116))
local lister = new("ScrollingFrame", { Parent = FrameHome, Position = UDim2.new(0,6,0,140), Size = UDim2.new(0,200,1,-156), CanvasSize = UDim2.new(0,0,0,0), ScrollBarThickness = 6, BackgroundColor3 = Color3.fromRGB(22,22,22) })
new("UICorner", { Parent = lister, CornerRadius = UDim.new(0,8) })
local listLayout = new("UIListLayout", { Parent = lister, Padding = UDim.new(0,6) })
listLayout.SortOrder = Enum.SortOrder.LayoutOrder

-- Player list UI (placed directly to the right of NPC list)
label(FrameHome, "Players", UDim2.new(0,212,0,116))
local playerList = new("ScrollingFrame", {
    Parent = FrameHome,
    Position = UDim2.new(0,212,0,140),
    Size = UDim2.new(0,200,1,-156),
    CanvasSize = UDim2.new(0,0,0,0),
    ScrollBarThickness = 6,
    BackgroundColor3 = Color3.fromRGB(22,22,22)
})
new("UICorner", { Parent = playerList, CornerRadius = UDim.new(0,8) })
local playerLayout = new("UIListLayout", {
    Parent = playerList,
    Padding = UDim.new(0,6),
    SortOrder = Enum.SortOrder.LayoutOrder
})

-- Evaluate function (manual)
local function clearNpcList()
    for _,m in ipairs(npcList) do npcByModel[m] = nil end
    npcList = {}
end

local function addNpcModel(model)
    if not model or not model:IsA("Model") then return end
    if npcByModel[model] then return end
    -- valid model: humanoid + hrp + not a player character
    if model:FindFirstChildOfClass("Humanoid") and (model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart) and not Players:GetPlayerFromCharacter(model) then
        table.insert(npcList, model)
        npcByModel[model] = true
    end
end

local function removeNpcModel(model)
    if not model then return end
    if not npcByModel[model] then return end
    npcByModel[model] = nil
    for i = #npcList,1,-1 do
        if npcList[i] == model then table.remove(npcList,i) end
    end
    -- cleanup highlight if present
    if highlights[model] then
        pcall(function() highlights[model]:Destroy() end)
        highlights[model] = nil
        highlightColor[model] = nil
    end
end

local function Evaluate()
    -- rebuild npcList
    clearNpcList()
    local rootPos = (LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") and LocalPlayer.Character.HumanoidRootPart.Position) or (workspace.CurrentCamera and workspace.CurrentCamera.CFrame.Position) or Vector3.new()
    local seenNames = {}
    for _,obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("Model") then
            if obj:FindFirstChildOfClass("Humanoid") and (obj:FindFirstChild("HumanoidRootPart") or obj.PrimaryPart) and not Players:GetPlayerFromCharacter(obj) then
                local hrp = obj:FindFirstChild("HumanoidRootPart") or obj.PrimaryPart
                if hrp and horizontalDistance(rootPos, hrp.Position) <= EVAL_RADIUS then
                    addNpcModel(obj)
                    seenNames[obj.Name] = true
                end
            end
        end
    end

    -- rebuild UI list once (manual)
    for _,c in ipairs(lister:GetChildren()) do if not (c:IsA("UIListLayout")) then c:Destroy() end end
    local order = {}
    for name,_ in pairs(seenNames) do table.insert(order, name) end
    table.sort(order)
    for i,name in ipairs(order) do
        local btn = new("TextButton", { Parent = lister, Size = UDim2.new(1,-8,0,28), LayoutOrder = i, Text = name, Font = Enum.Font.Gotham, TextSize = 13, BackgroundColor3 = (selectedNames[name] and PAL.accent) or Color3.fromRGB(36,36,36), TextColor3 = PAL.text, AutoButtonColor = true })
        new("UICorner", { Parent = btn, CornerRadius = UDim.new(0,6) })
        btn.MouseButton1Click:Connect(function()
            selectedNames[name] = not selectedNames[name]
            btn.BackgroundColor3 = selectedNames[name] and PAL.accent or Color3.fromRGB(36,36,36)
            -- if selecting and there's an existing model(s) with that name, create highlights immediately
            if selectedNames[name] then
                -- try to create highlights for matching npc models
                for _,m in ipairs(npcList) do
                    if m and m.Name == name and not highlights[m] then
                        pcall(function()
                            local h = Instance.new("Highlight")
                            h.Name = "AF_High"
                            h.Parent = workspace
                            h.Adornee = m
                            h.FillTransparency = 0.35
                            h.OutlineTransparency = 1
                            h.FillColor = PAL.neonG
                            highlights[m] = h
                            highlightColor[m] = h.FillColor
                        end)
                    end
                end
                -- try players' characters as well
                for _,plr in ipairs(Players:GetPlayers()) do
                    if plr.Name == name and plr.Character and not highlights[plr.Character] then
                        local m = plr.Character
                        local hrp = m:FindFirstChild("HumanoidRootPart") or m.PrimaryPart
                        if hrp and m:FindFirstChildOfClass("Humanoid") then
                            pcall(function()
                                local h = Instance.new("Highlight")
                                h.Name = "AF_High"
                                h.Parent = workspace
                                h.Adornee = m
                                h.FillTransparency = 0.35
                                h.OutlineTransparency = 1
                                h.FillColor = PAL.neonG
                                highlights[m] = h
                                highlightColor[m] = h.FillColor
                            end)
                        end
                    end
                end
            else
                -- if unselecting, remove highlights of that name
                for model,h in pairs(highlights) do
                    if model and model.Name == name then
                        pcall(function() if h and h.Parent then h:Destroy() end end)
                        highlights[model] = nil; highlightColor[model] = nil
                    end
                end
            end
        end)
    end
    lister.CanvasSize = UDim2.new(0,0,0, listLayout.AbsoluteContentSize.Y)
end

-- populate playerList with interactive buttons and hook join/leave
local function refreshPlayerList()
    for _,c in ipairs(playerList:GetChildren()) do if not (c:IsA("UIListLayout")) then c:Destroy() end end
    local order = {}
    for _,plr in ipairs(Players:GetPlayers()) do table.insert(order, plr.Name) end
    table.sort(order)
    for i,name in ipairs(order) do
        local btn = new("TextButton", { Parent = playerList, Size = UDim2.new(1,-8,0,28), LayoutOrder = i, Text = name, Font = Enum.Font.Gotham, TextSize = 13, BackgroundColor3 = (selectedNames[name] and PAL.accent) or Color3.fromRGB(36,36,36), TextColor3 = PAL.text, AutoButtonColor = true })
        new("UICorner", { Parent = btn, CornerRadius = UDim.new(0,6) })
        btn.MouseButton1Click:Connect(function()
            selectedNames[name] = not selectedNames[name]
            btn.BackgroundColor3 = selectedNames[name] and PAL.accent or Color3.fromRGB(36,36,36)
            if not selectedNames[name] then
                -- remove highlights that match name (players or NPCs)
                for model,h in pairs(highlights) do
                    if model and model.Name == name then
                        pcall(function() if h and h.Parent then h:Destroy() end end)
                        highlights[model] = nil; highlightColor[model] = nil
                    end
                end
            else
                -- create highlight immediately for player's current character if present
                for _,plr in ipairs(Players:GetPlayers()) do
                    if plr.Name == name and plr.Character and not highlights[plr.Character] then
                        local m = plr.Character
                        local hrp = m:FindFirstChild("HumanoidRootPart") or m.PrimaryPart
                        if hrp and m:FindFirstChildOfClass("Humanoid") then
                            pcall(function()
                                local h = Instance.new("Highlight")
                                h.Name = "AF_High"
                                h.Parent = workspace
                                h.Adornee = m
                                h.FillTransparency = 0.35
                                h.OutlineTransparency = 1
                                h.FillColor = PAL.neonG
                                highlights[m] = h
                                highlightColor[m] = h.FillColor
                            end)
                        end
                    end
                end
            end
        end)
    end
    playerList.CanvasSize = UDim2.new(0,0,0, playerLayout.AbsoluteContentSize.Y)
end

Players.PlayerAdded:Connect(function()
    -- refresh list when players join
    refreshPlayerList()
end)
Players.PlayerRemoving:Connect(function(plr)
    -- cleanup highlights for removing player's character
    if plr and plr.Character then
        local m = plr.Character
        if highlights[m] then
            pcall(function() highlights[m]:Destroy() end)
            highlights[m] = nil; highlightColor[m] = nil
        end
    end
    refreshPlayerList()
end)

evalBtn.MouseButton1Click:Connect(Evaluate)
Evaluate() -- initial populate
refreshPlayerList()

-- React to world changes: add/remove models to npcList when relevant
workspace.DescendantAdded:Connect(function(desc)
    -- only consider Models or descendants inside a model
    local model = desc:IsA("Model") and desc or desc:FindFirstAncestorWhichIsA("Model")
    if not model then return end
    -- add if valid (but keep Evaluate as source of names)
    task.spawn(function()
        -- wait briefly for model parts to initialize
        for i=1,12 do
            if model:FindFirstChildOfClass("Humanoid") and (model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart) and not Players:GetPlayerFromCharacter(model) then
                addNpcModel(model)
                -- if this name is currently selected, create highlight immediately (so new spawns get highlighted)
                if selectedNames[model.Name] then
                    if not highlights[model] then
                        local h = Instance.new("Highlight")
                        h.Name = "AF_High"
                        h.Parent = workspace
                        h.Adornee = model
                        h.FillTransparency = 0.35
                        h.OutlineTransparency = 1
                        h.FillColor = PAL.neonG
                        highlights[model] = h
                        highlightColor[model] = h.FillColor
                    end
                end
                break
            end
            task.wait(0.05)
        end
    end)
end)

workspace.DescendantRemoving:Connect(function(desc)
    local model = desc:IsA("Model") and desc or desc:FindFirstAncestorWhichIsA("Model")
    if model then
        removeNpcModel(model)
    end
end)

-- Also hook player characters spawning to create highlights if selected
Players.PlayerAdded:Connect(function(plr)
    plr.CharacterAdded:Connect(function(ch)
        if selectedNames[plr.Name] then
            -- create highlight for their character
            if not highlights[ch] then
                local ok, err = pcall(function()
                    local h = Instance.new("Highlight")
                    h.Name = "AF_High"
                    h.Parent = workspace
                    h.Adornee = ch
                    h.FillTransparency = 0.35
                    h.OutlineTransparency = 1
                    h.FillColor = PAL.neonG
                    highlights[ch] = h
                    highlightColor[ch] = h.FillColor
                end)
            end
        end
    end)
end)

-- Throttled highlight updater (efficient) - now considers both NPCs and selected players' characters
task.spawn(function()
    while true do
        task.wait(HIGHLIGHT_THROTTLE)

        if not next(selectedNames) then
            -- quick cleanup of highlights for vanished models
            for m,h in pairs(highlights) do
                if not m or not m.Parent or not m:FindFirstChildOfClass("Humanoid") or (not selectedNames[m.Name]) then
                    pcall(function() if h and h.Parent then h:Destroy() end end)
                    highlights[m] = nil; highlightColor[m] = nil
                end
            end
            continue
        end

        local camPos = workspace.CurrentCamera and workspace.CurrentCamera.CFrame.Position or (LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") and LocalPlayer.Character.HumanoidRootPart.Position) or Vector3.new()

        -- iterate npcList only (keeps iteration small) and create/update highlights for selected names
        local active = {}

        for _,model in ipairs(npcList) do
            if model and model.Parent and selectedNames[model.Name] then
                local hum = model:FindFirstChildOfClass("Humanoid")
                local hrp = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
                if hum and hrp and hrp:IsA("BasePart") then
                    -- ensure highlight exists
                    if not highlights[model] then
                        local h = Instance.new("Highlight")
                        h.Name = "AF_High"
                        h.Parent = workspace
                        h.Adornee = model
                        h.FillTransparency = 0.35
                        h.OutlineTransparency = 1
                        h.FillColor = PAL.neonG
                        highlights[model] = h
                        highlightColor[model] = h.FillColor
                    end
                    table.insert(active, { m = model, pos = hrp.Position })
                end
            end
        end

        -- also include selected players (their characters) in active list
        for _,plr in ipairs(Players:GetPlayers()) do
            if selectedNames[plr.Name] and plr.Character and plr.Character.Parent then
                local model = plr.Character
                local hum = model:FindFirstChildOfClass("Humanoid")
                local hrp = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
                if hum and hrp and hrp:IsA("BasePart") and hum.Health > 0 then
                    if not highlights[model] then
                        local h = Instance.new("Highlight")
                        h.Name = "AF_High"
                        h.Parent = workspace
                        h.Adornee = model
                        h.FillTransparency = 0.35
                        h.OutlineTransparency = 1
                        h.FillColor = PAL.neonG
                        highlights[model] = h
                        highlightColor[model] = h.FillColor
                    end
                    table.insert(active, { m = model, pos = hrp.Position })
                end
            end
        end

        -- remove highlights of models that are no longer valid or not selected
        for m,h in pairs(highlights) do
            if (not m or not m.Parent or not m:FindFirstChildOfClass("Humanoid") or not selectedNames[m.Name]) then
                pcall(function() if h and h.Parent then h:Destroy() end end)
                highlights[m] = nil; highlightColor[m] = nil
            end
        end

        if #active == 0 then
            -- nothing to color
        else
            -- sort active by distance to camera (closest -> farthest)
            table.sort(active, function(a,b) return horizontalDistance(camPos, a.pos) < horizontalDistance(camPos, b.pos) end)
            local n = #active
            for i,entry in ipairs(active) do
                local m = entry.m
                local t = (i - 1) / math.max(1, n - 1)
                local targetColor
                if t <= 0.33 then
                    local lt = t / 0.33
                    targetColor = PAL.neonG:Lerp(PAL.brightG, lt)
                elseif t <= 0.66 then
                    local lt = (t - 0.33) / 0.33
                    targetColor = PAL.brightG:Lerp(PAL.brightR, lt)
                else
                    local lt = (t - 0.66) / 0.34
                    targetColor = PAL.brightR:Lerp(PAL.neonR, lt)
                end
                local h = highlights[m]
                if h then
                    local cur = highlightColor[m] or h.FillColor
                    local newC = cur:Lerp(targetColor, 0.5) -- moderate smoothing per throttle tick
                    highlightColor[m] = newC
                    pcall(function() h.FillColor = newC end)
                    h.FillTransparency = math.clamp(0.12 + t * 0.6, 0, 0.9)
                end
            end
        end
    end
end)

-- Find closest selected NPC or Player (from npcList and selected players) - efficient
local function findClosestSelected()
    local ch = LocalPlayer.Character
    if not ch or not ch:FindFirstChild("HumanoidRootPart") then return nil end
    local rootPos = ch.HumanoidRootPart.Position
    local bestModel, bestD = nil, math.huge

    -- check NPCs
    for _,m in ipairs(npcList) do
        if m and m.Parent and selectedNames[m.Name] then
            local hum = m:FindFirstChildOfClass("Humanoid")
            local hrp = m:FindFirstChild("HumanoidRootPart") or m.PrimaryPart
            if hum and hrp and hum.Health > 0 then
                local d = horizontalDistance(rootPos, hrp.Position)
                if d < bestD then bestD = d; bestModel = { model = m, hrp = hrp, hum = hum } end
            end
        end
    end

    -- check selected players' characters
    for _,plr in ipairs(Players:GetPlayers()) do
        if selectedNames[plr.Name] and plr.Character and plr.Character.Parent then
            local m = plr.Character
            local hum = m:FindFirstChildOfClass("Humanoid")
            local hrp = m:FindFirstChild("HumanoidRootPart") or m.PrimaryPart
            if hum and hrp and hum.Health > 0 then
                local d = horizontalDistance(rootPos, hrp.Position)
                if d < bestD then bestD = d; bestModel = { model = m, hrp = hrp, hum = hum } end
            end
        end
    end

    return bestModel
end

-- AutoFarm loop (smooth lerp movement but safe)
task.spawn(function()
    while true do
        if autoEnabled then
            local target = findClosestSelected()
            if target then
                local ch = LocalPlayer.Character
                if not ch or not ch:FindFirstChild("HumanoidRootPart") then task.wait(0.2); continue end
                local myhrp = ch.HumanoidRootPart
                local startTime = tick()
                local delayVal = tonumber(delayValue)

                -- move toward target smoothly until delay elapsed or target dead/removed
                while autoEnabled and target and target.model and target.model.Parent and target.hum and target.hum.Health > 0 do
                    local tgtHRP = target.hrp
                    if not tgtHRP or not tgtHRP:IsA("BasePart") then break end

                    -- Build desired hover position: above the target and slightly behind to avoid collisions
                    local backOffset = -tgtHRP.CFrame.LookVector * BACK_OFFSET   -- 1.5 studs behind
                    local upOffset = Vector3.new(0, VERTICAL_OFFSET, 0)   -- vertical offset (studs above)
                    local desiredPos = tgtHRP.Position + upOffset + backOffset

                    local myPos = myhrp.Position
                    local dist = (desiredPos - myPos).Magnitude
                    local dt = RunService.Heartbeat:Wait()

                    -- compute lerp factor relative to dt and distance; tuned for smoothness
                    local speedFactor = 100 + (dist / 10000) -- increases if far
                    local alpha = math.clamp(dt * speedFactor, 0.1, 1)
                    local newPos = myPos:Lerp(desiredPos, alpha)

                    -- Try to reduce physics interference (helps keep you above the target)
                    pcall(function()
                        if myhrp.AssemblyLinearVelocity then
                            myhrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
                        end
                        myhrp.Velocity = Vector3.new(0,0,0)
                    end)

                    -- Face the target's true position (not the offset) so your body looks at them
                    pcall(function()
                        myhrp.CFrame = CFrame.new(newPos, tgtHRP.Position)
                    end)

                    -- stop moving to re-evaluate when delay elapsed (if delay > 0)
                    if delayVal > 0 and (tick() - startTime) >= delayVal then break end

                    -- re-evaluate target each loop if delay==0 for responsiveness
                    if delayVal == 0 then
                        target = findClosestSelected()
                        if not target then break end
                    end

                    -- safety small yield
                    task.wait(AUTOFARM_RECHECK)
                end
            else
                task.wait(0.5)
            end
        else
            task.wait(0.5)
        end
    end
end)

-- Mods UI: AutoFarm button + delay slider + warning modal
local AutoBtn = new("TextButton", { Parent = FrameMods, Position = UDim2.new(0,6,0,6), Size = UDim2.new(0,160,0,32), Text = "AUTO FARM: OFF", Font = Enum.Font.GothamBold, TextSize = 14, BackgroundColor3 = PAL.panel, TextColor3 = PAL.text })
new("UICorner", { Parent = AutoBtn, CornerRadius = UDim.new(0,8) })
AutoBtn.MouseButton1Click:Connect(function()
    autoEnabled = not autoEnabled
    AutoBtn.Text = "AUTO FARM: " .. (autoEnabled and "ON" or "OFF")
end)

label(FrameMods, "Delay Amount", UDim2.new(0,6,0,50))
local delaySlider = Slider(FrameMods, "Delay (s)", 0, 5, 0.1, 1)
delaySlider.Frame.Position = UDim2.new(0,6,0,78)

-- modal logic: only show after drag end + hold; only once per crossing under threshold
local modalActive = false
local wasUnder = false
local lastDelay = delaySlider.GetValue()

-- we need a small wrapper to detect DragEnd -> here we approximate by monitoring value changes periodically
-- simpler: poll the slider value when user stops dragging (we detect dragging via InputChanged)
local sliderDragging = false
do
    -- detect dragging via UserInputService - bar is the parent frame; rely on changed flag
    delaySlider.Frame.InputBegan:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1 then sliderDragging = true end
    end)
    delaySlider.Frame.InputEnded:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1 then
            sliderDragging = false
            -- after release, wait hold period then check
            task.delay(0.3, function()
                local cur = tonumber(delaySlider.GetValue()) or lastDelay
                if cur < 0.2 and not wasUnder and not modalActive then
                    modalActive = true
                    -- build modal
                    local M = new("Frame", { Parent = Screen, Size = UDim2.new(1,0,1,0), BackgroundColor3 = Color3.fromRGB(0,0,0), BackgroundTransparency = 0.6, ZIndex = 999 })
                    local box = new("Frame", { Parent = M, Size = UDim2.new(0,340,0,150), Position = UDim2.new(0.5,-170,0.5,-75), BackgroundColor3 = PAL.panel })
                    new("UICorner", { Parent = box, CornerRadius = UDim.new(0,10) })
                    new("TextLabel", { Parent = box, Position = UDim2.new(0,8,0,8), Size = UDim2.new(1,-16,0,80), BackgroundTransparency = 1, Text = "This is extremely Blatant. Are you sure?\nDelay: ".. tostring(cur), Font = Enum.Font.GothamBold, TextSize = 14, TextWrapped = true, TextColor3 = PAL.text})
                    local yes = new("TextButton", { Parent = box, Position = UDim2.new(0.06,0,0,96), Size = UDim2.new(0,140,0,36), Text = "Yes", BackgroundColor3 = PAL.accent, Font = Enum.Font.GothamBold, TextColor3 = PAL.text })
                    local no  = new("TextButton", { Parent = box, Position = UDim2.new(0.56,0,0,96), Size = UDim2.new(0,140,0,36), Text = "No", BackgroundColor3 = Color3.fromRGB(140,40,40), Font = Enum.Font.GothamBold, TextColor3 = PAL.text })
                    new("UICorner", { Parent = yes, CornerRadius = UDim.new(0,8) })
                    new("UICorner", { Parent = no, CornerRadius = UDim.new(0,8) })

                    local function cleanup()
                        if M and M.Parent then M:Destroy() end
                        modalActive = false
                    end
                    yes.MouseButton1Click:Connect(function()
                        delayValue = cur
                        lastDelay = cur
                        wasUnder = true
                        cleanup()
                    end)
                    no.MouseButton1Click:Connect(function()
                        delaySlider.SetValue(lastDelay)
                        delayValue = lastDelay
                        wasUnder = false
                        cleanup()
                    end)
                else
                    lastDelay = cur
                    if cur >= 0.2 then wasUnder = false end
                    delayValue = lastDelay
                end
            end)
        end
    end)
end

-- Update delayValue while dragging too
task.spawn(function()
    while true do
        delayValue = tonumber(delaySlider.GetValue()) or delayValue
        task.wait(0.1)
    end
end)

-- Walkspeed apply updating (low cost)
task.spawn(function()
    while true do
        task.wait(0.2)
        if wsEnabled then
            local ch = LocalPlayer.Character
            if ch then
                local hum = ch:FindFirstChildOfClass("Humanoid")
                if hum then
                    local v = tonumber(wsSlider.GetValue()) or WALK_DEFAULT
                    pcall(function() hum.WalkSpeed = v end)
                end
            end
        end
    end
end)

-- Mods: AutoFarm target indicator (small, optional) - show current target name & distance
local indicator = new("TextLabel", { Parent = Main, Position = UDim2.new(0,12,1,-56), Size = UDim2.new(1,-24,0,20), BackgroundTransparency = 1, Text = "", Font = Enum.Font.Gotham, TextSize = 13, TextColor3 = PAL.text, TextXAlignment = Enum.TextXAlignment.Left })

-- Utility: remove stray highlights on cleanup
local function cleanupAllHighlights()
    for m,h in pairs(highlights) do
        pcall(function() if h and h.Parent then h:Destroy() end end)
        highlights[m] = nil; highlightColor[m] = nil
    end
end

-- Ensure npcList initially populated
Evaluate()

-- Debug safety: clean on reset
Screen.Destroying:Connect(function()
    cleanupAllHighlights()
end)

-- End of script
