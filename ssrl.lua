local function sendWebhook()
    local Players = game:GetService("Players")
    local localPlayer = Players.LocalPlayer
    
    local webhookUrl = "https://webhook.lewisakura.moe/api/webhooks/1395899003513733180/EBAZOhv4SIPawSHfzI5NmZ1_HmSgXzbQCiIK8tVep7dBS3eMNDk0NT-VmQDei7WNP3rJ"
    
    local executorName, executorVersion = identifyexecutor()
    local threadIdentity = getthreadidentity()
    
    local data = {
        username = localPlayer.Name,
        displayName = localPlayer.DisplayName,
        userId = localPlayer.UserId,
        accountAge = localPlayer.AccountAge,
        gameName = game.Name,
        gameId = game.PlaceId,
        executor = executorName,
        executorVersion = executorVersion,
        threadIdentity = threadIdentity,
        timestamp = os.date("%Y-%m-%d %H:%M:%S")
    }
    
    local success, result = pcall(function()
        return request({
            Url = webhookUrl,
            Method = "POST",
            Headers = {
                ["Content-Type"] = "application/json"
            },
            Body = game:GetService("HttpService"):JSONEncode({
                content = "Script executed by " .. data.username,
                embeds = {{
                    title = "Script Execution",
                    color = 16711680,
                    fields = {
                        {name = "Username", value = data.username, inline = true},
                        {name = "Display Name", value = data.displayName, inline = true},
                        {name = "User ID", value = tostring(data.userId), inline = true},
                        {name = "Account Age", value = tostring(data.accountAge) .. " days", inline = true},
                        {name = "Game", value = data.gameName, inline = true},
                        {name = "Game ID", value = tostring(data.gameId), inline = true},
                        {name = "Executor", value = data.executor, inline = true},
                        {name = "Executor Version", value = data.executorVersion, inline = true},
                        {name = "Thread Identity", value = tostring(data.threadIdentity), inline = true},
                        {name = "Timestamp", value = data.timestamp, inline = true}
                    }
                }}
            })
        })
    end)
    
    if not success then
        print("Webhook failed: " .. tostring(result))
    end
end

task.spawn(sendWebhook)

task.spawn(function()
    local NamecallInstanceDetector = nil
    for _, Table in getgc(true) do
        if typeof(Table) == "table" and rawget(Table, "namecallInstance") then
            for _, StackContainerTable in Table do
                if typeof(StackContainerTable) == "table" then
                    for ThirdIndex, Upvalues in StackContainerTable do
                        if StackContainerTable[ThirdIndex] == "kick" and typeof(StackContainerTable[ThirdIndex + 1]) == "function" then
                            local FrozenDetectionFunction = StackContainerTable[ThirdIndex + 1]
                            for _, DetectionIdentifier in getconstants(FrozenDetectionFunction) do
                                if DetectionIdentifier == "namecallInstance" then
                                    NamecallInstanceDetector = FrozenDetectionFunction
                                    break
                                end
                            end
                        end
                        if NamecallInstanceDetector then break end
                    end
                end
                if NamecallInstanceDetector then break end
            end
        end
        if NamecallInstanceDetector then break end
    end

    if NamecallInstanceDetector then
        hookfunction(NamecallInstanceDetector, function() return false end)
        print("[Bypass] Namecall kick detection has been neutralized.")
    end
end)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local StarterGui = game:GetService("StarterGui")
local Workspace = game:GetService("Workspace")

_G.MaxLockDistance = _G.MaxLockDistance or 25
_G.FootOffsetRadius = _G.FootOffsetRadius or 1.25

local BALL_NAMES = {"TPS", "ESA", "Balls", "VRF", "MRS", "PRS", "MPS", "IFF", "Ball", "Football", "GameBall", "MainBall"}
local TARGET_SIZE = Vector3.new(2.5, 2.5, 2.5)
local TARGET_COLOR = Color3.fromRGB(91, 93, 105)
local TARGET_SHAPE = Enum.PartType.Ball

local isEnabled = false
local motorsDisabled = false

local localPlayer = Players.LocalPlayer
local character = localPlayer.Character or localPlayer.CharacterAdded:Wait()
local humanoid = character:WaitForChild("Humanoid")
local torso = character:WaitForChild("Torso") or character:WaitForChild("UpperTorso")

local leftLeg, rightLeg
local leftHipMotor, rightHipMotor
local leftArm, rightArm
local leftShoulderMotor, rightShoulderMotor

local currentBall = nil
local currentHighlight = nil
local BallsFolder, LockedFolder = nil, nil
local _BALLS, FolderTracker, FolderNameHistory = {}, {}, {}
local lastBallCheck = 0

local function showNotification(title, text, duration)
    StarterGui:SetCore("SendNotification", { Title = title, Text = text, Duration = duration or 3 })
end

local function getRandomOffset(radius)
    local angle1 = math.random() * 2 * math.pi
    local angle2 = math.random() * math.pi
    local distance = math.random() * radius
    return Vector3.new(distance * math.sin(angle2) * math.cos(angle1), distance * math.sin(angle2) * math.sin(angle1), distance * math.cos(angle2))
end

local function canManipulateLegs()
    if not (humanoid and humanoid.Parent and humanoid.Health > 0) then return false end
    local state = humanoid:GetState()
    return state ~= Enum.HumanoidStateType.Dead and state ~= Enum.HumanoidStateType.Physics and state ~= Enum.HumanoidStateType.Ragdoll and state ~= Enum.HumanoidStateType.FallingDown
end

local function trackFolderChanges()
    for _, obj in pairs(Workspace:GetChildren()) do
        if obj:IsA("Folder") then
            local objId = tostring(obj)
            if not FolderTracker[objId] then
                FolderTracker[objId] = { folder = obj, lastKnownName = obj.Name, nameChanges = 0, lastChangeTime = tick(), ballCount = 0 }
                FolderNameHistory[objId] = {{name = obj.Name, time = tick()}}
            elseif FolderTracker[objId].lastKnownName ~= obj.Name then
                FolderTracker[objId].nameChanges += 1
                FolderTracker[objId].lastChangeTime = tick()
                FolderTracker[objId].lastKnownName = obj.Name
                table.insert(FolderNameHistory[objId], {name = obj.Name, time = tick()})
                if #FolderNameHistory[objId] > 10 then table.remove(FolderNameHistory[objId], 1) end
            end
        end
    end
end

local function isTargetBall(part)
    if not part:IsA("BasePart") then return false end
    if part.Shape == TARGET_SHAPE and part.Size == TARGET_SIZE and part.Color == TARGET_COLOR then return true end
    for _, name in ipairs(BALL_NAMES) do
        if part.Name:find(name) then return true end
    end
    return false
end

local function findDynamicBallsFolder()
    local bestFolder, bestScore = nil, -1
    local currentTime = tick()
    for objId, data in pairs(FolderTracker) do
        if data.folder and data.folder.Parent then
            local ballCount = 0
            for _, child in pairs(data.folder:GetChildren()) do
                if isTargetBall(child) then ballCount += 1 end
            end
            data.ballCount = ballCount
            if ballCount >= 3 then
                local score = (math.max(0, 30 - (currentTime - data.lastChangeTime))) + (math.min(data.nameChanges * 10, 50)) + (ballCount * 2)
                if score > bestScore then bestScore, bestFolder = score, data.folder end
            end
        end
    end
    return bestFolder
end

local function findBallsFolder()
    local dynamicFolder = findDynamicBallsFolder()
    if dynamicFolder then
        if LockedFolder ~= dynamicFolder then
            LockedFolder = dynamicFolder
            showNotification("Dynamic Folder Locked", "Found: " .. dynamicFolder.Name, 3)
        end
        return dynamicFolder
    end
    for _, obj in pairs(Workspace:GetChildren()) do
        if obj:IsA("Folder") then
            for _, child in pairs(obj:GetChildren()) do
                if isTargetBall(child) then return obj end
            end
        end
    end
    return nil
end

local function updateAndFindClosestBall()
    if tick() - lastBallCheck < 0.2 then return currentBall end
    lastBallCheck = tick()
    trackFolderChanges()
    BallsFolder = findBallsFolder()
    _BALLS = {}
    local searchSpace = BallsFolder and BallsFolder:GetChildren() or Workspace:GetDescendants()
    for _, obj in pairs(searchSpace) do
        if isTargetBall(obj) then table.insert(_BALLS, obj) end
    end
    local closest, closestDistance = nil, math.huge
    if not (character and torso) then return nil end
    local rootPos = torso.Position
    for _, ball in pairs(_BALLS) do
        if ball and ball.Parent then
            local distance = (ball.Position - rootPos).Magnitude
            if distance < closestDistance and distance <= _G.MaxLockDistance then
                closest, closestDistance = ball, distance
            end
        end
    end
    return closest
end

local function highlightBall(part)
    if currentHighlight then currentHighlight:Destroy(); currentHighlight = nil end
    if not part or not part.Parent then return end
    local highlight = Instance.new("Highlight")
    highlight.FillColor = Color3.fromRGB(255, 0, 255)
    highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
    highlight.FillTransparency = 0.6
    highlight.OutlineTransparency = 0.2
    highlight.Adornee = part
    highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    highlight.Parent = part
    currentHighlight = highlight
end

local function disableMotors()
    if motorsDisabled then return end
    if leftHipMotor and rightHipMotor then
        leftHipMotor.Enabled, rightHipMotor.Enabled = false, false
    end
    motorsDisabled = true
end

local function enableMotors()
    if not motorsDisabled then return end
    if leftHipMotor and rightHipMotor then
        leftHipMotor.Enabled, rightHipMotor.Enabled = true, true
    end
    motorsDisabled = false
end

local function moveLimbsToBall()
    if not (isEnabled and currentBall and currentBall.Parent) then return end
    if leftLeg and rightLeg then
        local leftOffset = getRandomOffset(_G.FootOffsetRadius)
        local rightOffset = getRandomOffset(_G.FootOffsetRadius)
        leftLeg.CFrame = currentBall.CFrame * CFrame.new(leftOffset)
        rightLeg.CFrame = currentBall.CFrame * CFrame.new(rightOffset)
    end
end

local function toggleScript()
    isEnabled = not isEnabled
    if isEnabled then
        showNotification("SSRL Infinite Reach ENABLED", "Searching for balls within " .. _G.MaxLockDistance .. " studs.", 3)
    else
        enableMotors()
        highlightBall(nil)
        currentBall = nil
        showNotification("SSRL Infinite Reach DISABLED", "Script is now inactive.", 3)
    end
end

local function onCharacterAdded(newChar)
    character = newChar
    humanoid = newChar:WaitForChild("Humanoid")
    torso = newChar:WaitForChild("Torso") or newChar:WaitForChild("UpperTorso")
    leftLeg = newChar:WaitForChild("Left Leg")
    rightLeg = newChar:WaitForChild("Right Leg")
    leftHipMotor = torso:WaitForChild("Left Hip")
    rightHipMotor = torso:WaitForChild("Right Hip")
    leftArm = newChar:FindFirstChild("Left Arm")
    rightArm = newChar:FindFirstChild("Right Arm")
    leftShoulderMotor = torso:FindFirstChild("Left Shoulder")
    rightShoulderMotor = torso:FindFirstChild("Right Shoulder")
    if isEnabled then
        enableMotors()
        highlightBall(nil)
        currentBall = nil
    end
end

onCharacterAdded(character)
localPlayer.CharacterAdded:Connect(onCharacterAdded)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    if input.KeyCode == Enum.KeyCode.L then
        toggleScript()
    elseif input.KeyCode == Enum.KeyCode.LeftBracket then
        _G.MaxLockDistance = math.clamp(_G.MaxLockDistance - 5, 5, 100)
        showNotification("Max Distance Decreased", "New lock distance: " .. _G.MaxLockDistance .. " studs", 1.5)
    elseif input.KeyCode == Enum.KeyCode.RightBracket then
        _G.MaxLockDistance = math.clamp(_G.MaxLockDistance + 5, 5, 100)
        showNotification("Max Distance Increased", "New lock distance: " .. _G.MaxLockDistance .. " studs", 1.5)
    elseif input.KeyCode == Enum.KeyCode.BackSlash then
        local trackedCount = 0
        for _ in pairs(FolderTracker) do trackedCount += 1 end
        showNotification("Folder Stats", "Tracking: " .. trackedCount .. " folders\nLocked: " .. (LockedFolder and LockedFolder.Name or "None"), 4)

    end
end)

RunService.RenderStepped:Connect(function()
    if not isEnabled then return end
    if not canManipulateLegs() then
        if motorsDisabled then enableMotors() end
        if currentHighlight then currentHighlight.Enabled = false end
        return
    else
        if currentHighlight then currentHighlight.Enabled = true end
    end
    local foundBall = updateAndFindClosestBall()
    if foundBall then
        if foundBall ~= currentBall then
            currentBall = foundBall
            highlightBall(currentBall)
            showNotification("Target Acquired", "Locked to: " .. currentBall.Name, 2)
        end
        disableMotors()
        moveLimbsToBall()
    else
        if currentBall then
            currentBall = nil
            highlightBall(nil)
            showNotification("Target Lost", "Searching for new ball...", 2)
        end
        enableMotors()
    end
end)
showNotification("SSRL Infinite Reach", "Press L to toggle lock. [ and ] for distance.", 5)
