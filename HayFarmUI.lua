if getgenv then
    if getgenv().__HayFarmExample then
        pcall(function()
            getgenv().__HayFarmExample:Destroy()
        end)
    end
end

local LIB_URL = "https://raw.githubusercontent.com/Xyraniz/VaultUI/refs/heads/main/Libraries/Armenta-Lib/source.lua"
local FyyUI = loadstring(game:HttpGet(LIB_URL))()

-- ============================================
-- HAY FARMING MODULE (Embedded)
-- ============================================
local HayFarming = {
    autoHay = false,
    autoSell = false,
    findKeys = false,
    
    isRunning = false,
    totalCollected = 0,
    totalSold = 0,
    currentHay = 0,
    
    config = {
        collectRange = 100,
        maxHayBeforeSell = 25,
        sellAttempts = 3,
        debugMode = false
    },
    
    _loopConnection = nil,
    _uiRefs = {},
}

-- Core functions
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local localPlayer = Players.LocalPlayer
local character = localPlayer and localPlayer.Character
local humanoid = character and character:FindFirstChildWhichIsA("Humanoid")
local rootPart = character and character:FindFirstChild("HumanoidRootPart")

-- Get RemoteEvents
local NeedleHaystack, PickHay, SellHay
local function setupRemotes()
    local success = pcall(function()
        NeedleHaystack = ReplicatedStorage:WaitForChild("NeedleHaystack")
        PickHay = NeedleHaystack:WaitForChild("PickHay")
        SellHay = NeedleHaystack:WaitForChild("SellHay")
    end)
    return success
end
setupRemotes()

function HayFarming:getHayCount()
    local count = 0
    local heldHay = Workspace:FindFirstChild("HeldHayClient")
    if heldHay then count = #heldHay:GetChildren() end
    local hayHeld = localPlayer:GetAttribute("HayHeld")
    if hayHeld then count = math.max(count, hayHeld) end
    return count
end

function HayFarming:getHayCapacity()
    local capacity = localPlayer:GetAttribute("HayCapacity") or 25
    if localPlayer:GetAttribute("InfiniteBagOwned") == true then
        return math.huge
    end
    return capacity
end

function HayFarming:findHayPieces()
    local hayPieces = {}
    local haystackClient = Workspace:FindFirstChild("HaystackClient")
    if haystackClient then
        for _, descendant in ipairs(haystackClient:GetDescendants()) do
            if descendant:IsA("BasePart") and descendant.Name == "HayPiece" then
                if descendant:GetAttribute("HayId") and descendant.Transparency < 0.9 then
                    table.insert(hayPieces, descendant)
                end
            end
        end
    end
    return hayPieces
end

function HayFarming:findSellPoint()
    local sellModel = Workspace:FindFirstChild("SellModel")
    if sellModel then
        local cow = sellModel:FindFirstChild("Cow")
        if cow then
            local root = cow:FindFirstChild("HumanoidRootPart") or cow:FindFirstChildWhichIsA("BasePart")
            if root then return root end
        end
    end
    for _, part in ipairs(CollectionService:GetTagged("SellPart")) do
        if part:IsA("BasePart") then return part end
    end
    return nil
end

function HayFarming:findNearestPart(parts, currentPos, maxDistance)
    local nearest, nearestDist = nil, maxDistance or math.huge
    for _, part in ipairs(parts) do
        if part and part:IsA("BasePart") and part.Parent then
            local pos = part.Position
            local dist = (pos - currentPos).Magnitude
            if dist < nearestDist then
                nearestDist = dist
                nearest = part
            end
        end
    end
    return nearest, nearestDist
end

function HayFarming:moveTo(position)
    if not character or not humanoid or not rootPart then return end
    humanoid:MoveTo(position)
end

function HayFarming:lookAtPosition(position)
    if not rootPart then return end
    local lookAt = CFrame.lookAt(rootPart.Position, position)
    rootPart.CFrame = lookAt
    task.wait(0.2)
end

function HayFarming:collectHay(hayPiece)
    if not hayPiece or not hayPiece:IsA("BasePart") then return false end
    if hayPiece.Transparency >= 0.9 then return false end
    
    local hayId = hayPiece:GetAttribute("HayId")
    if not hayId then return false end
    
    self:moveTo(hayPiece.Position)
    task.wait(0.2)
    
    if PickHay then
        PickHay:FireServer(hayId, {})
        return true
    end
    return false
end

function HayFarming:sellHay()
    local hayCount = self:getHayCount()
    if hayCount == 0 then return false end
    
    local sellPoint = self:findSellPoint()
    if not sellPoint then return false end
    
    local distance = (rootPart.Position - sellPoint.Position).Magnitude
    if distance > 15 then
        self:moveTo(sellPoint.Position)
        task.wait(1)
    end
    
    self:lookAtPosition(sellPoint.Position)
    task.wait(0.3)
    
    for attempt = 1, self.config.sellAttempts do
        if SellHay then
            SellHay:FireServer()
            task.wait(0.5)
            
            local newCount = self:getHayCount()
            if newCount < hayCount then
                self.totalSold = self.totalSold + (hayCount - newCount)
                return true
            end
        end
        
        if attempt < self.config.sellAttempts then
            local offset = Vector3.new(math.random(-3, 3), 0, math.random(-3, 3))
            self:moveTo(sellPoint.Position + offset)
            task.wait(0.5)
            self:lookAtPosition(sellPoint.Position)
            task.wait(0.3)
        end
    end
    
    return false
end

function HayFarming:farmingCycle()
    character = localPlayer.Character
    humanoid = character and character:FindFirstChildWhichIsA("Humanoid")
    rootPart = character and character:FindFirstChild("HumanoidRootPart")
    
    if not character or not humanoid or not rootPart then
        return "no_character"
    end
    
    if humanoid.Health <= 0 then
        return "dead"
    end
    
    local currentPos = rootPart.Position
    local hayPieces = self:findHayPieces()
    local hayCount = self:getHayCount()
    local hayCapacity = self:getHayCapacity()
    
    self.currentHay = hayCount
    self:_updateUIStats()
    
    if self.autoSell and hayCount >= self.config.maxHayBeforeSell then
        local success = self:sellHay()
        if success then return "sold" end
    end
    
    if self.autoSell and #hayPieces == 0 and hayCount > 0 then
        local success = self:sellHay()
        if success then return "sold_last" end
    end
    
    if self.autoHay and #hayPieces > 0 and hayCount < hayCapacity then
        local nearestHay, distance = self:findNearestPart(hayPieces, currentPos, self.config.collectRange)
        
        if nearestHay then
            local success = self:collectHay(nearestHay)
            if success then
                self.totalCollected = self.totalCollected + 1
                return "collected"
            end
            return "failed"
        else
            local anyHay = self:findNearestPart(hayPieces, currentPos)
            if anyHay then
                self:moveTo(anyHay.Position)
                return "moving"
            end
        end
    end
    
    return "idle"
end

function HayFarming:start()
    if self.isRunning then return end
    self.isRunning = true
    self.totalCollected = 0
    self.totalSold = 0
    
    if self._loopConnection then
        self._loopConnection:Disconnect()
    end
    
    self._loopConnection = RunService.Heartbeat:Connect(function()
        if not self.isRunning then
            self._loopConnection:Disconnect()
            self._loopConnection = nil
            return
        end
        if tick() % 0.5 < 0.05 then
            self:farmingCycle()
        end
    end)
end

function HayFarming:stop()
    self.isRunning = false
    if self._loopConnection then
        self._loopConnection:Disconnect()
        self._loopConnection = nil
    end
end

function HayFarming:_updateUIStats()
    if self._uiRefs.statsLabel then
        self._uiRefs.statsLabel.Text = string.format(
            "🧹 Hay: %d | Collected: %d | Sold: %d | Capacity: %d",
            self.currentHay,
            self.totalCollected,
            self.totalSold,
            self:getHayCapacity()
        )
    end
end

function HayFarming:createUIControls(menu, tab)
    local haySection = tab:Collapsible("🌾 Hay Farming", { DefaultOpen = true })
    
    -- Toggles
    local autoHayToggle = haySection:Toggle({
        Text = "Auto Hay",
        Description = "Automatically collect hay from nearby haystacks",
        Default = false,
        Flag = "AutoHay",
        Callback = function(state)
            self.autoHay = state
            if state and not self.isRunning then
                self:start()
            elseif not state and not self.autoSell and not self.findKeys then
                self:stop()
            end
        end
    })
    self._uiRefs.autoHayToggle = autoHayToggle
    
    local autoSellToggle = haySection:Toggle({
        Text = "Auto Sell",
        Description = "Automatically sell hay when inventory is full",
        Default = false,
        Flag = "AutoSell",
        Callback = function(state)
            self.autoSell = state
            if state and not self.isRunning then
                self:start()
            elseif not state and not self.autoHay and not self.findKeys then
                self:stop()
            end
        end
    })
    self._uiRefs.autoSellToggle = autoSellToggle
    
    local findKeysToggle = haySection:Toggle({
        Text = "Find Keys",
        Description = "🔑 Search for hidden keys in the haystack (Coming soon)",
        Default = false,
        Flag = "FindKeys",
        Callback = function(state)
            self.findKeys = state
            if state then
                print("🔑 Find Keys - Coming soon!")
            end
        end
    })
    self._uiRefs.findKeysToggle = findKeysToggle
    
    -- Stats
    local statsLabel = haySection:Label({
        Text = "🧹 Hay: 0 | Collected: 0 | Sold: 0 | Capacity: 25",
        Color = Color3.fromRGB(200, 200, 210)
    })
    self._uiRefs.statsLabel = statsLabel
    
    -- Action Buttons
    local actionRow = haySection:Columns({ Ratio = { 1, 1 }, Gap = 8 })
    
    actionRow:Column(1):Button({
        Text = "Collect Now",
        Icon = "hand-grab",
        Callback = function()
            self:farmingCycle()
        end
    })
    
    actionRow:Column(2):Button({
        Text = "Sell Now",
        Icon = "coins",
        Callback = function()
            self:sellHay()
            self:_updateUIStats()
        end
    })
    
    -- Settings
    local settingsSection = haySection:Collapsible("⚙️ Settings", { DefaultOpen = false })
    
    settingsSection:Slider({
        Text = "Collection Range",
        Description = "How far to search for hay",
        Min = 20,
        Max = 200,
        Step = 5,
        Default = 100,
        Suffix = " studs",
        Flag = "CollectRange",
        Callback = function(value)
            self.config.collectRange = value
        end
    })
    
    settingsSection:Slider({
        Text = "Sell Threshold",
        Description = "Sell when inventory reaches this amount",
        Min = 1,
        Max = 50,
        Step = 1,
        Default = 25,
        Suffix = " hay",
        Flag = "SellThreshold",
        Callback = function(value)
            self.config.maxHayBeforeSell = value
        end
    })
    
    settingsSection:Slider({
        Text = "Sell Attempts",
        Description = "How many times to try selling",
        Min = 1,
        Max = 5,
        Step = 1,
        Default = 3,
        Suffix = " attempts",
        Flag = "SellAttempts",
        Callback = function(value)
            self.config.sellAttempts = value
        end
    })
    
    settingsSection:Toggle({
        Text = "Debug Mode",
        Description = "Show detailed debug messages",
        Default = false,
        Flag = "DebugMode",
        Callback = function(state)
            self.config.debugMode = state
        end
    })
    
    -- Status
    local statusLabel = settingsSection:Label({
        Text = "⏸️ Idle",
        Color = Color3.fromRGB(150, 150, 160)
    })
    self._uiRefs.statusLabel = statusLabel
    
    -- Update status periodically
    task.spawn(function()
        while not self._destroyed do
            task.wait(1)
            if self._uiRefs.statusLabel then
                if self.isRunning then
                    local status = "▶️ Running"
                    if self.autoHay then status = status .. " | Collecting" end
                    if self.autoSell then status = status .. " | Selling" end
                    if self.findKeys then status = status .. " | 🔑 Searching" end
                    self._uiRefs.statusLabel.Text = status
                else
                    self._uiRefs.statusLabel.Text = "⏸️ Idle"
                end
            end
        end
    end)
    
    return {
        autoHayToggle = autoHayToggle,
        autoSellToggle = autoSellToggle,
        findKeysToggle = findKeysToggle,
        statsLabel = statsLabel,
        statusLabel = statusLabel
    }
end

-- ============================================
-- CREATE THE MENU
-- ============================================

local Menu = FyyUI.Menu({
    Title = "🌾 Hay Farm Bot",
    Theme = "Violet",
    Size = UDim2.fromOffset(500, 550),
    MinSize = Vector2.new(400, 400),
    MaxSize = Vector2.new(800, 650),
    Resizable = true,
    Shadow = true,
    HasOutline = true,
    Responsive = true,
    Scale = 1,
    Stats = {
        Enabled = true,
        TabName = "Overview",
        TabIcon = "layout-dashboard",
        ShowProfile = true,
        ShowGame = true,
        ShowServer = true,
        ShowSupport = true,
    },
    Support = {
        Title = "Hay Farming Bot",
        Description = "Auto-collect and sell hay in the game.",
        ButtonText = "Open Repository",
        Discord = "https://github.com/srtwins/HayFarm",
        ButtonIcon = "github",
    },
})

if getgenv then
    getgenv().__HayFarmExample = Menu
end

-- ============================================
-- CREATE TABS
-- ============================================

local FarmingTab = Menu:Tab({ Text = "🌾 Farming", Icon = "wheat" })
local StatsTab = Menu:Tab({ Text = "📊 Stats", Icon = "chart-bar" })
local ConfigTab = Menu:ConfigTab({
    Text = "⚙️ Config",
    Icon = "save",
    Folder = "HayFarmBot",
    DefaultProfile = "Default",
    LoadCallbacks = true,
    AllowDelete = true,
    AllowImportExport = true,
})

-- ============================================
-- FARMING TAB
-- ============================================

FarmingTab:BoldLabel({ 
    Text = "Hay Farming Controls", 
    Description = "Auto-collect and sell hay automatically." 
})

-- Create Hay Farming UI
HayFarming:createUIControls(Menu, FarmingTab)

-- Additional info
FarmingTab:Divider()
FarmingTab:Label({
    Text = "💡 Press <b>Ctrl+K</b> to toggle this menu",
    Color = Color3.fromRGB(150, 150, 160)
})

-- ============================================
-- STATS TAB
-- ============================================

StatsTab:BoldLabel({ 
    Text = "Farming Statistics", 
    Description = "Real-time farming data." 
})

local statsColumns = StatsTab:Columns({ Ratio = { 1, 1, 1 }, Gap = 8 })

statsColumns:Column(1):BoldLabel({ 
    Text = "🌾 Hay", 
    Description = "Current hay in inventory" 
})
local hayCountLabel = statsColumns:Column(1):Label({
    Text = "0",
    Color = Color3.fromRGB(255, 200, 100)
})

statsColumns:Column(2):BoldLabel({ 
    Text = "📦 Collected", 
    Description = "Total hay collected" 
})
local collectedLabel = statsColumns:Column(2):Label({
    Text = "0",
    Color = Color3.fromRGB(100, 200, 255)
})

statsColumns:Column(3):BoldLabel({ 
    Text = "💰 Sold", 
    Description = "Total hay sold" 
})
local soldLabel = statsColumns:Column(3):Label({
    Text = "0",
    Color = Color3.fromRGB(100, 255, 150)
})

-- Live stats update
task.spawn(function()
    while true do
        task.wait(1)
        if hayCountLabel and hayCountLabel.TextLabel then
            hayCountLabel.TextLabel.Text = tostring(HayFarming:getHayCount())
        end
        if collectedLabel and collectedLabel.TextLabel then
            collectedLabel.TextLabel.Text = tostring(HayFarming.totalCollected)
        end
        if soldLabel and soldLabel.TextLabel then
            soldLabel.TextLabel.Text = tostring(HayFarming.totalSold)
        end
    end
end)

StatsTab:Divider()

StatsTab:Button({
    Text = "Reset Statistics",
    Icon = "rotate-ccw",
    Callback = function()
        HayFarming.totalCollected = 0
        HayFarming.totalSold = 0
        Menu:Notify({
            Title = "Stats Reset",
            Content = "All statistics have been reset.",
            Type = "Info",
            Duration = 2,
        })
    end
})

-- ============================================
-- KEYBIND
-- ============================================

local UserInputService = game:GetService("UserInputService")

UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    if input.KeyCode == Enum.KeyCode.RightControl or input.KeyCode == Enum.KeyCode.K then
        if input.KeyCode == Enum.KeyCode.K and (UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)) then
            Menu:ToggleVisibility()
        elseif input.KeyCode == Enum.KeyCode.RightControl then
            Menu:ToggleVisibility()
        end
    end
end)

-- ============================================
-- DESTROY HANDLER
-- ============================================

Menu:OnDestroy(function()
    HayFarming:stop()
    if getgenv then
        getgenv().__HayFarmExample = nil
    end
end)

-- ============================================
-- WELCOME NOTIFICATION
-- ============================================

Menu:Notify({
    Title = "🌾 Hay Farming Bot",
    Content = "Loaded successfully! Press Ctrl+K or Right Control to toggle the menu.",
    Type = "Success",
    Duration = 5,
})

print("✅ Hay Farming Bot loaded!")
print("📖 Press Ctrl+K or Right Control to toggle the menu")
print("📊 Hay count:", HayFarming:getHayCount())
print("🌾 Hay pieces:", #HayFarming:findHayPieces())

return { Menu = Menu, HayFarming = HayFarming }
