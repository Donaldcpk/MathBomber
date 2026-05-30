--[[
	【大作感主頁面與基礎導航系統】MainMenuGui.client
	位置：StarterGui -> MainMenuGui (LocalScript)
	功能：
	1. 提供遊戲大廳的主選單控制（支援 PVE、PVP、商店、排行榜）。
	2. 實作漂浮的主標題動畫（"Geometric Matrix Arena"）。
	3. 四大主按鈕的切換：流暢的 Tweening 補間動畫（淡入淡出、尺寸微縮放）。
	4. 鏡頭繞軸巡禮動畫：在選單中時，相機自動忽視玩家角色，並在 3D 地圖中央上方進行電影級繞圈與起伏。
	5. 整合與自癒：動態生成 ScreenGui 和所有 Sub-Frames，免除手動建 UI 煩惱。
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local player = Players.LocalPlayer or Players:GetPropertyChangedSignal("LocalPlayer"):Wait()
local playerGui = player:WaitForChild("PlayerGui")

-- 防止同時放在 StarterGui 與 StarterPlayerScripts 時重複建立兩套大廳
if playerGui:GetAttribute("MainMenuGuiInitialized") == true then
	return
end
playerGui:SetAttribute("MainMenuGuiInitialized", true)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local RequestRetry = Remotes:WaitForChild("RequestRetry")
local RequestPVEMatch = Remotes:WaitForChild("RequestPVEMatch", 5) :: RemoteEvent?
if not RequestPVEMatch then
	RequestPVEMatch = Instance.new("RemoteEvent")
	RequestPVEMatch.Name = "RequestPVEMatch"
	RequestPVEMatch.Parent = Remotes
end

local GetPlayerProgression = Remotes:WaitForChild("GetPlayerProgression", 5) :: RemoteFunction?
if not GetPlayerProgression then
	GetPlayerProgression = Instance.new("RemoteFunction")
	GetPlayerProgression.Name = "GetPlayerProgression"
	GetPlayerProgression.Parent = Remotes
end

local JoinPVPQueue = Remotes:WaitForChild("JoinPVPQueue", 5) :: RemoteEvent?
if not JoinPVPQueue then
	JoinPVPQueue = Instance.new("RemoteEvent")
	JoinPVPQueue.Name = "JoinPVPQueue"
	JoinPVPQueue.Parent = Remotes
end

local LeavePVPQueue = Remotes:WaitForChild("LeavePVPQueue", 5) :: RemoteEvent?
if not LeavePVPQueue then
	LeavePVPQueue = Instance.new("RemoteEvent")
	LeavePVPQueue.Name = "LeavePVPQueue"
	LeavePVPQueue.Parent = Remotes
end

local PVELobbyUpdate = Remotes:WaitForChild("PVELobbyUpdate", 5) :: RemoteEvent?
if not PVELobbyUpdate then
	PVELobbyUpdate = Instance.new("RemoteEvent")
	PVELobbyUpdate.Name = "PVELobbyUpdate"
	PVELobbyUpdate.Parent = Remotes
end

local PVPStartMatch = Remotes:WaitForChild("PVPStartMatch", 5) :: RemoteEvent?
if not PVPStartMatch then
	PVPStartMatch = Instance.new("RemoteEvent")
	PVPStartMatch.Name = "PVPStartMatch"
	PVPStartMatch.Parent = Remotes
end

-- ==================== 建立音效 ====================
local clickSound = Instance.new("Sound")
clickSound.Name = "ClickSound"
clickSound.SoundId = "rbxassetid://9120380938"
clickSound.Volume = 0.5
clickSound.Parent = SoundService

-- 與 LoadingGui 同步的載入完成信號（修復 ReplicatedFirst 比 StarterGui 先跑完導致大廳永不顯示）
local LOADING_DONE_ATTR = "LoadingComplete"
local LOBBY_HIDE_CFRAME = CFrame.new(0, -250, 0)
local SPAWN_CFRAME = CFrame.new(-30, 3, 24)

local function setLobbyCharacterHidden(hidden: boolean)
	local char = player.Character
	if not char then
		return
	end
	local hum = char:FindFirstChildOfClass("Humanoid")
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?

	if hidden then
		if hum then
			hum.WalkSpeed = 0
			hum.JumpPower = 0
			hum.JumpHeight = 0
		end
		if root then
			root.AssemblyLinearVelocity = Vector3.zero
			root.AssemblyAngularVelocity = Vector3.zero
			char:PivotTo(LOBBY_HIDE_CFRAME)
		end
		for _, inst in ipairs(char:GetDescendants()) do
			if inst:IsA("BasePart") then
				inst.Transparency = 1
				inst.CanCollide = false
			elseif inst:IsA("Decal") or inst:IsA("Texture") then
				inst.Transparency = 1
			end
		end
	else
		for _, inst in ipairs(char:GetDescendants()) do
			if inst:IsA("BasePart") then
				inst.Transparency = 0
				inst.CanCollide = inst.Name ~= "HumanoidRootPart" or true
			elseif inst:IsA("Decal") or inst:IsA("Texture") then
				inst.Transparency = 0
			end
		end
		if hum then
			hum.WalkSpeed = 16
		end
		char:PivotTo(SPAWN_CFRAME)
	end
end

-- ==================== 建立主 UI 結構 ====================
local screenGui = nil
for _, child in ipairs(playerGui:GetChildren()) do
	if child.Name == "MainMenuGui" and child:IsA("ScreenGui") then
		screenGui = child
		break
	end
end

if not screenGui then
	screenGui = Instance.new("ScreenGui")
	screenGui.Name = "MainMenuGui"
	screenGui.ResetOnSpawn = false
	screenGui.Parent = playerGui
else
	screenGui.ResetOnSpawn = false
end
screenGui.DisplayOrder = 100
screenGui.IgnoreGuiInset = true
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Enabled = false

-- 若上次殘留則清掉（避免重複疊加）
local oldCanvas = screenGui:FindFirstChild("MainMenuCanvas")
if oldCanvas then
	oldCanvas:Destroy()
end

-- 覆蓋全螢幕的 Frame，比 CanvasGroup 清晰
local mainMenuCanvas = Instance.new("Frame")
mainMenuCanvas.Name = "MainMenuCanvas"
mainMenuCanvas.Size = UDim2.fromScale(1, 1)
mainMenuCanvas.BackgroundTransparency = 1
mainMenuCanvas.Parent = screenGui

-- 主面板 (MainFrame)
local mainFrame = Instance.new("Frame")
mainFrame.Name = "MainFrame"
mainFrame.Size = UDim2.fromScale(1, 1)
mainFrame.BackgroundTransparency = 1
mainFrame.Parent = mainMenuCanvas

-- 建立背景半透明漸層
local bgGradient = Instance.new("Frame")
bgGradient.Size = UDim2.fromScale(1, 1)
bgGradient.BackgroundColor3 = Color3.fromRGB(12, 10, 20)
bgGradient.BackgroundTransparency = 0.25
bgGradient.BorderSizePixel = 0
bgGradient.Parent = mainFrame

local uigrad = Instance.new("UIGradient")
uigrad.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(15, 15, 30)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(8, 8, 15))
})
uigrad.Rotation = 45
uigrad.Parent = bgGradient

-- 置中大控制面板
local centerPanel = Instance.new("Frame")
centerPanel.Name = "CenterPanel"
centerPanel.Size = UDim2.fromOffset(800, 520)
centerPanel.Position = UDim2.fromScale(0.5, 0.5)
centerPanel.AnchorPoint = Vector2.new(0.5, 0.5)
centerPanel.BackgroundColor3 = Color3.fromRGB(24, 24, 38)
centerPanel.BorderSizePixel = 0
centerPanel.Parent = mainFrame

local cpCorner = Instance.new("UICorner")
cpCorner.CornerRadius = UDim.new(0, 16)
cpCorner.Parent = centerPanel

local cpStroke = Instance.new("UIStroke")
cpStroke.Color = Color3.fromRGB(85, 95, 140)
cpStroke.Thickness = 4
cpStroke.Parent = centerPanel

-- 浮動主標題 ("Geometric Matrix Arena")
local title = Instance.new("TextLabel")
title.Name = "Title"
title.Size = UDim2.new(1, 0, 0, 60)
title.Position = UDim2.new(0, 0, 0, 25)
title.BackgroundTransparency = 1
title.Text = "競技大廳"
title.Font = Enum.Font.GothamBold
title.TextSize = 34
title.TextColor3 = Color3.fromRGB(255, 215, 0)
title.Parent = centerPanel

-- 標題浮動動畫 (Sin 波動)
task.spawn(function()
	local t = 0
	while title.Parent do
		t += 0.05
		title.Position = UDim2.new(0, 0, 0, 25 + math.sin(t) * 5)
		task.wait(0.03)
	end
end)

-- 左側導航按鈕欄 (Navigation Panel)
local navPanel = Instance.new("Frame")
navPanel.Name = "NavPanel"
navPanel.Size = UDim2.new(0, 220, 1, -120)
navPanel.Position = UDim2.new(0, 25, 0, 95)
navPanel.BackgroundTransparency = 1
navPanel.Parent = centerPanel

local navLayout = Instance.new("UIListLayout")
navLayout.Padding = UDim.new(0, 12)
navLayout.FillDirection = Enum.FillDirection.Vertical
navLayout.Parent = navPanel

-- 建立通用大按鈕函數
local function createNavButton(name: string, text: string, color: Color3)
	local btn = Instance.new("TextButton")
	btn.Name = name
	btn.Size = UDim2.new(1, 0, 0, 48)
	btn.BackgroundColor3 = color
	btn.Text = text
	btn.Font = Enum.Font.GothamBold
	btn.TextSize = 16
	btn.TextColor3 = Color3.new(1, 1, 1)
	btn.Parent = navPanel

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = btn

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.new(1, 1, 1)
	stroke.Transparency = 0.8
	stroke.Thickness = 1.5
	stroke.Parent = btn

	-- 按鈕懸停特效
	btn.MouseEnter:Connect(function()
		TweenService:Create(btn, TweenInfo.new(0.2), { BackgroundColor3 = color:Lerp(Color3.new(1, 1, 1), 0.15) }):Play()
		TweenService:Create(stroke, TweenInfo.new(0.2), { Transparency = 0.3 }):Play()
	end)
	btn.MouseLeave:Connect(function()
		TweenService:Create(btn, TweenInfo.new(0.2), { BackgroundColor3 = color }):Play()
		TweenService:Create(stroke, TweenInfo.new(0.2), { Transparency = 0.8 }):Play()
	end)

	return btn
end

local btnPVE = createNavButton("Btn_PVE", "🌟 PVE 冒險闖關", Color3.fromRGB(46, 125, 50))
local btnPVP = createNavButton("Btn_PVP", "⚔️ PVP 萬花筒競技", Color3.fromRGB(106, 27, 154))
local btnShop = createNavButton("Btn_Shop", "🛒 裝備商店", Color3.fromRGB(198, 105, 0))
local btnLeaderboard = createNavButton("Btn_Leaderboard", "🏆 排行榜", Color3.fromRGB(21, 101, 192))

-- 右側子選單框架容器
local contentPanel = Instance.new("Frame")
contentPanel.Name = "ContentPanel"
contentPanel.Size = UDim2.new(1, -290, 1, -120)
contentPanel.Position = UDim2.new(0, 265, 0, 95)
contentPanel.BackgroundColor3 = Color3.fromRGB(18, 18, 28)
contentPanel.Parent = centerPanel

local cpCorner2 = Instance.new("UICorner")
cpCorner2.CornerRadius = UDim.new(0, 12)
cpCorner2.Parent = contentPanel

local cpStroke2 = Instance.new("UIStroke")
cpStroke2.Color = Color3.fromRGB(60, 60, 85)
cpStroke2.Thickness = 2
cpStroke2.Parent = contentPanel

-- 建立 4 個子頁面的 Frame
local function createSubFrame(name: string)
	local f = Instance.new("Frame")
	f.Name = name
	f.Size = UDim2.fromScale(1, 1)
	f.BackgroundTransparency = 1
	f.Visible = false
	f.Parent = contentPanel
	return f
end

local framePVE = createSubFrame("Frame_PVE")
local framePVP = createSubFrame("Frame_PVP")
local frameShop = createSubFrame("Frame_Shop")
local frameLeaderboard = createSubFrame("Frame_Leaderboard")

-- ==================== 1. PVE 關卡選擇面板配置 ====================
local pveTitle = Instance.new("TextLabel")
pveTitle.Size = UDim2.new(1, 0, 0, 30)
pveTitle.Position = UDim2.new(0, 15, 0, 10)
pveTitle.BackgroundTransparency = 1
pveTitle.Text = "請選擇 PVE 挑戰關卡："
pveTitle.Font = Enum.Font.GothamBold
pveTitle.TextSize = 16
pveTitle.TextColor3 = Color3.fromRGB(80, 220, 100)
pveTitle.TextXAlignment = Enum.TextXAlignment.Left
pveTitle.Parent = framePVE

local pveScroll = Instance.new("ScrollingFrame")
pveScroll.Name = "PVEScroll"
pveScroll.Size = UDim2.new(1, -20, 1, -55)
pveScroll.Position = UDim2.new(0, 10, 0, 45)
pveScroll.BackgroundTransparency = 1
pveScroll.BorderSizePixel = 0
pveScroll.ScrollBarThickness = 6
pveScroll.ScrollBarImageColor3 = Color3.fromRGB(80, 80, 110)
pveScroll.CanvasSize = UDim2.new(0, 0, 0, 1850) -- 30關卡需要更長的捲動高度
pveScroll.ScrollingDirection = Enum.ScrollingDirection.Y
pveScroll.Parent = framePVE

local pveGrid = Instance.new("UIGridLayout")
pveGrid.CellSize = UDim2.new(0.47, 0, 0, 110)
pveGrid.CellPadding = UDim2.new(0.04, 0, 0, 10)
pveGrid.FillDirection = Enum.FillDirection.Horizontal
pveGrid.SortOrder = Enum.SortOrder.LayoutOrder
pveGrid.Parent = pveScroll

-- PVE 關卡卡片動態載入函數
local function buildPVEMapCards()
	-- 清空既有卡片
	for _, child in ipairs(pveScroll:GetChildren()) do
		if child:IsA("Frame") then child:Destroy() end
	end

	-- 查詢解鎖數據
	local unlockedMaps = {}
	local success, result = pcall(function()
		return GetPlayerProgression:InvokeServer()
	end)
	if success and typeof(result) == "table" then
		unlockedMaps = result
	else
		-- 降級預設：解鎖前 1 關
		unlockedMaps = { ["Map1"] = true }
	end

	-- 建立 Map 1 到 Map 30
	for i = 1, 30 do
		local mapKey = "Map" .. i
		local isUnlocked = unlockedMaps[mapKey] == true

		local card = Instance.new("Frame")
		card.Name = "MapCard_" .. i
		card.BackgroundColor3 = Color3.fromRGB(35, 35, 48)
		card.BorderSizePixel = 0
		card.LayoutOrder = i
		card.Parent = pveScroll

		local cc = Instance.new("UICorner")
		cc.CornerRadius = UDim.new(0, 8)
		cc.Parent = card

		local cs = Instance.new("UIStroke")
		cs.Color = isUnlocked and Color3.fromRGB(50, 160, 90) or Color3.fromRGB(60, 60, 70)
		cs.Thickness = 1.5
		cs.Parent = card

		-- 地圖縮圖
		local thumb = Instance.new("ImageLabel")
		thumb.Name = "Thumbnail"
		thumb.Size = UDim2.new(0, 80, 0, 80)
		thumb.Position = UDim2.new(0, 10, 0.5, -40)
		thumb.AnchorPoint = Vector2.new(0, 0.5)
		thumb.BackgroundTransparency = 1
		thumb.Image = "rbxassetid://10850239" -- 使用內建科技網格/炸彈圖樣
		thumb.ImageColor3 = isUnlocked and Color3.fromRGB(150, 200, 255) or Color3.fromRGB(80, 80, 85)
		thumb.Parent = card

		local thumbCorner = Instance.new("UICorner")
		thumbCorner.CornerRadius = UDim.new(0, 6)
		thumbCorner.Parent = thumb

		-- 關卡標題與描述
		local titleL = Instance.new("TextLabel")
		titleL.Size = UDim2.new(1, -110, 0, 22)
		titleL.Position = UDim2.new(0, 100, 0, 12)
		titleL.BackgroundTransparency = 1
		titleL.Text = "🟢 第 " .. i .. " 關 " .. (isUnlocked and "" or "🔒")
		titleL.Font = Enum.Font.GothamBold
		titleL.TextSize = 12
		titleL.TextColor3 = isUnlocked and Color3.fromRGB(80, 220, 100) or Color3.fromRGB(130, 130, 140)
		titleL.TextXAlignment = Enum.TextXAlignment.Left
		titleL.Parent = card

		-- 關卡特殊解鎖描述
		local rewardText = "通關獲得金幣獎勵，用於升級角色屬性！"
		if i == 5 then rewardText = "🎁 獎勵：解鎖 PVP 額外愛心 💖"
		elseif i == 7 then rewardText = "🧱 獎勵：解鎖 PVP 鐵礦磚塊！"
		elseif i == 11 then rewardText = "💥 獎勵：解鎖 PVP TNT 炸藥桶！"
		elseif i == 15 then rewardText = "🔥 獎勵：解鎖 PVP 威力藥水道具！"
		elseif i == 20 then rewardText = "⚡ 獎勵：解鎖 PVP 經典雷擊環境！"
		elseif i == 25 then rewardText = "🌀 獎勵：解鎖 PVP Conveyor 傳送帶！"
		elseif i == 30 then rewardText = "🏆 獎勵：解鎖 PVP 歐幾里得終極大亂鬥！"
		end

		local descL = Instance.new("TextLabel")
		descL.Size = UDim2.new(1, -110, 0, 36)
		descL.Position = UDim2.new(0, 100, 0, 34)
		descL.BackgroundTransparency = 1
		descL.Text = rewardText
		descL.Font = Enum.Font.Gotham
		descL.TextSize = 9
		descL.TextColor3 = Color3.fromRGB(160, 160, 180)
		descL.TextXAlignment = Enum.TextXAlignment.Left
		descL.TextWrapped = true
		descL.Parent = card

		-- Play Button
		local playBtn = Instance.new("TextButton")
		playBtn.Size = UDim2.new(1, -110, 0, 24)
		playBtn.Position = UDim2.new(0, 100, 0, 74)
		playBtn.BackgroundColor3 = isUnlocked and Color3.fromRGB(46, 125, 50) or Color3.fromRGB(60, 60, 70)
		playBtn.Text = isUnlocked and "開始挑戰" or "🔒 鎖定"
		playBtn.Font = Enum.Font.GothamBold
		playBtn.TextSize = 10
		playBtn.TextColor3 = Color3.new(1, 1, 1)
		playBtn.Active = isUnlocked
		playBtn.Parent = card

		local pcc = Instance.new("UICorner")
		pcc.CornerRadius = UDim.new(0, 4)
		pcc.Parent = playBtn

		if isUnlocked then
			playBtn.MouseButton1Click:Connect(function()
				clickSound:Play()
				-- 觸發 PVE 關卡啟動
				print("[MainMenu] 點擊啟動 PVE 關卡:", i)
				RequestPVEMatch:FireServer(mapKey)
				-- 關閉主選單，顯示遊戲 HUD
				screenGui.Enabled = false
				local pg = player:FindFirstChild("PlayerGui")
				local hudGui = pg and pg:FindFirstChild("MathQuizScreenGui")
				local hud = hudGui and hudGui:FindFirstChild("HUDFrame")
				if hud and hud:IsA("GuiObject") then
					(hud :: GuiObject).Visible = true
				end
			end)
		end

		-- Lock Overlay (灰色遮罩)
		if not isUnlocked then
			local lockOverlay = Instance.new("Frame")
			lockOverlay.Name = "LockOverlay"
			lockOverlay.Size = UDim2.fromScale(1, 1)
			lockOverlay.BackgroundColor3 = Color3.new(0, 0, 0)
			lockOverlay.BackgroundTransparency = 0.55
			lockOverlay.BorderSizePixel = 0
			lockOverlay.Parent = card

			local locCorner = Instance.new("UICorner")
			locCorner.CornerRadius = UDim.new(0, 8)
			locCorner.Parent = lockOverlay
		end
	end
end

-- ==================== 2. PVP 多人匹配大廳與地圖選擇 ====================
local pvpTitle = Instance.new("TextLabel")
pvpTitle.Size = UDim2.new(1, 0, 0, 24)
pvpTitle.Position = UDim2.new(0, 15, 0, 10)
pvpTitle.BackgroundTransparency = 1
pvpTitle.Text = "⚔️ PVP 萬花筒競技大廳 ⚔️"
pvpTitle.Font = Enum.Font.GothamBold
pvpTitle.TextSize = 16
pvpTitle.TextColor3 = Color3.fromRGB(170, 100, 255)
pvpTitle.TextXAlignment = Enum.TextXAlignment.Left
pvpTitle.Parent = framePVP

local pvpStatus = Instance.new("TextLabel")
pvpStatus.Name = "StatusLabel"
pvpStatus.Size = UDim2.new(1, -30, 0, 32)
pvpStatus.Position = UDim2.new(0, 15, 0, 36)
pvpStatus.BackgroundTransparency = 1
pvpStatus.Text = "請選擇對戰地圖 style，然後點選「加入匹配隊列」進行極限對決："
pvpStatus.Font = Enum.Font.GothamMedium
pvpStatus.TextSize = 11
pvpStatus.TextColor3 = Color3.fromRGB(180, 180, 200)
pvpStatus.TextXAlignment = Enum.TextXAlignment.Left
pvpStatus.TextWrapped = true
pvpStatus.Parent = framePVP

local pvpScroll = Instance.new("ScrollingFrame")
pvpScroll.Name = "PVPScroll"
pvpScroll.Size = UDim2.new(1, -20, 1, -165)
pvpScroll.Position = UDim2.new(0, 10, 0, 75)
pvpScroll.BackgroundTransparency = 1
pvpScroll.BorderSizePixel = 0
pvpScroll.ScrollBarThickness = 6
pvpScroll.ScrollBarImageColor3 = Color3.fromRGB(120, 80, 220)
pvpScroll.CanvasSize = UDim2.new(0, 0, 0, 560) -- 10個PVP地圖
pvpScroll.ScrollingDirection = Enum.ScrollingDirection.Y
pvpScroll.Parent = framePVP

local pvpGrid = Instance.new("UIGridLayout")
pvpGrid.CellSize = UDim2.new(0.47, 0, 0, 90)
pvpGrid.CellPadding = UDim2.new(0.04, 0, 0, 10)
pvpGrid.FillDirection = Enum.FillDirection.Horizontal
pvpGrid.SortOrder = Enum.SortOrder.LayoutOrder
pvpGrid.Parent = pvpScroll

local selectedPVPMapIndex = 1
local pvpCardStrokes = {}

local pvpMapDetails = {
	{ name = "經典交叉網格", desc = "標準鋼鐵水泥交叉網格，經典炸彈人考驗。" },
	{ name = "傳送帶工廠", desc = "地上佈滿自動移動的輸送帶，極考驗炸彈位移。" },
	{ name = "萬花筒折射迷宮", desc = "佈滿 45 度玻璃鏡面與分光稜鏡，火焰瘋狂折射！" },
	{ name = "巡邏哨兵矩陣", desc = "雷射防衛方塊在場地中自動來回梭巡，碰觸扣血。" },
	{ name = "算術虛空塌陷", desc = "地表板塊處於不穩定狀態，炸彈波及處塌陷為致命深淵！" },
	{ name = "坐標天雷神殿", desc = "天空每 10 秒鎖定 4 個隨機位置，預警 2 秒後降下重磅雷擊。" },
	{ name = "因數诅咒之室", desc = "地板顯示神秘倍數诅咒，火焰與毒霧覆蓋率雙倍增長。" },
	{ name = "終端收縮孤島", desc = "經典縮圈模式！四面外牆不斷縮緊，逼迫到中心決戰。" },
	{ name = "混沌變數 X 核心", desc = "高達 85% 機率掉落各種神秘詛咒與特殊強化道具！" },
	{ name = "歐幾里得大亂鬥", desc = "輸送帶、折射鏡、天雷、哨兵與虛空陷阱一併出現！" },
}

for i = 1, 10 do
	local card = Instance.new("TextButton")
	card.Name = "PVPMapCard_" .. i
	card.Text = ""
	card.BackgroundColor3 = Color3.fromRGB(30, 30, 42)
	card.BorderSizePixel = 0
	card.LayoutOrder = i
	card.Parent = pvpScroll

	local cc = Instance.new("UICorner")
	cc.CornerRadius = UDim.new(0, 8)
	cc.Parent = card

	local cs = Instance.new("UIStroke")
	cs.Color = (i == selectedPVPMapIndex) and Color3.fromRGB(170, 80, 255) or Color3.fromRGB(60, 60, 70)
	cs.Thickness = (i == selectedPVPMapIndex) and 2 or 1.2
	cs.Parent = card
	pvpCardStrokes[i] = cs

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, -20, 0, 22)
	title.Position = UDim2.new(0, 10, 0, 8)
	title.BackgroundTransparency = 1
	title.Text = ("🗺️ Map %d: %s"):format(i, pvpMapDetails[i].name)
	title.Font = Enum.Font.GothamBold
	title.TextSize = 11
	title.TextColor3 = (i == selectedPVPMapIndex) and Color3.fromRGB(190, 120, 255) or Color3.fromRGB(200, 200, 200)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = card

	local desc = Instance.new("TextLabel")
	desc.Size = UDim2.new(1, -20, 0, 46)
	desc.Position = UDim2.new(0, 10, 0, 30)
	desc.BackgroundTransparency = 1
	desc.Text = pvpMapDetails[i].desc
	desc.Font = Enum.Font.Gotham
	desc.TextSize = 9
	desc.TextColor3 = Color3.fromRGB(150, 150, 160)
	desc.TextXAlignment = Enum.TextXAlignment.Left
	desc.TextWrapped = true
	desc.Parent = card

	card.MouseButton1Click:Connect(function()
		clickSound:Play()
		selectedPVPMapIndex = i
		-- 重新整理所有外邊框亮起
		for j = 1, 10 do
			pvpCardStrokes[j].Color = (j == selectedPVPMapIndex) and Color3.fromRGB(170, 80, 255) or Color3.fromRGB(60, 60, 70)
			pvpCardStrokes[j].Thickness = (j == selectedPVPMapIndex) and 2 or 1.2
			local cardTitle = pvpScroll:FindFirstChild("PVPMapCard_" .. j):FindFirstChildOfClass("TextLabel")
			if cardTitle then
				cardTitle.TextColor3 = (j == selectedPVPMapIndex) and Color3.fromRGB(190, 120, 255) or Color3.fromRGB(200, 200, 200)
			end
		end
		print("[MainMenu] 已選擇 PVP 地圖:", i, pvpMapDetails[i].name)
	end)
end

local pvpQueueBtn = Instance.new("TextButton")
pvpQueueBtn.Name = "Btn_Queue"
pvpQueueBtn.Size = UDim2.new(0.8, 0, 0, 42)
pvpQueueBtn.Position = UDim2.new(0.1, 0, 1, -55)
pvpQueueBtn.BackgroundColor3 = Color3.fromRGB(120, 80, 200)
pvpQueueBtn.Text = "⚔️ 加入匹配隊列 ⚔️"
pvpQueueBtn.Font = Enum.Font.GothamBold
pvpQueueBtn.TextSize = 14
pvpQueueBtn.TextColor3 = Color3.new(1, 1, 1)
pvpQueueBtn.Parent = framePVP

local qCorner = Instance.new("UICorner")
qCorner.CornerRadius = UDim.new(0, 8)
qCorner.Parent = pvpQueueBtn

local isQueued = false

pvpQueueBtn.MouseButton1Click:Connect(function()
	clickSound:Play()
	if not isQueued then
		-- 加入匹配
		JoinPVPQueue:FireServer(selectedPVPMapIndex)
		isQueued = true
		pvpQueueBtn.Text = "🛑 取消匹配..."
		pvpQueueBtn.BackgroundColor3 = Color3.fromRGB(150, 40, 40)
	else
		-- 離開匹配
		LeavePVPQueue:FireServer()
		isQueued = false
		pvpQueueBtn.Text = "⚔️ 加入匹配隊列 ⚔️"
		pvpQueueBtn.BackgroundColor3 = Color3.fromRGB(120, 80, 200)
		pvpStatus.Text = "已取消匹配。請點選上方卡片選擇對戰地圖，並加入匹配隊列："
	end
end)

PVELobbyUpdate.OnClientEvent:Connect(function(count, required)
	if isQueued then
		pvpStatus.Text = ("🔍 正在尋找同學中... (%d / %d) 👥 (已自動準備隨時引入 NPC Bots 中)"):format(count, required)
	end
end)

PVPStartMatch.OnClientEvent:Connect(function(selectedMapName)
	isQueued = false
	pvpQueueBtn.Text = "⚔️ 加入匹配隊列 ⚔️"
	pvpQueueBtn.BackgroundColor3 = Color3.fromRGB(120, 80, 200)
	pvpStatus.Text = "🎮 匹配成功！即將進入 PVP 萬花筒競技場！"

	-- 開始 5 秒倒數
	task.spawn(function()
		for i = 5, 1, -1 do
			pvpStatus.Text = ("🎮 匹配成功！即將進入: %s (倒數 %d 秒)"):format(selectedMapName, i)
			task.wait(1)
		end
		
		-- 倒數結束，隱藏選單
		screenGui.Enabled = false
		local pg = player:FindFirstChild("PlayerGui")
		local hudGui = pg and pg:FindFirstChild("MathQuizScreenGui")
		local hud = hudGui and hudGui:FindFirstChild("HUDFrame")
		if hud and hud:IsA("GuiObject") then
			(hud :: GuiObject).Visible = true
		end
	end)
end)

-- ==================== 3. 裝備商店面板配置 ====================
-- 直接重定向至我們已寫好的 HUDFrame 屬性商店 (保持 DRY 與自癒相容性)
local shopInfo = Instance.new("TextLabel")
shopInfo.Size = UDim2.fromScale(1, 1)
shopInfo.BackgroundTransparency = 1
shopInfo.Text = "🛒 裝備屬性商店：\n\n您可以使用 PVE 挑戰中賺取的金幣，直接點擊左上角 HUD 中的「🛒 商店」按鈕，實時升級您的最大生命上限、炸彈範圍與移動速度！\n\n（註：所有屬性在進入 PVP 萬花筒競技場時會公平重置，保障絕對技術競爭！）"
shopInfo.Font = Enum.Font.GothamBold
shopInfo.TextSize = 14
shopInfo.TextColor3 = Color3.fromRGB(240, 160, 40)
shopInfo.TextWrapped = true
shopInfo.Parent = frameShop

-- ==================== 4. 排行榜面板配置 ====================
local lbLabel = Instance.new("TextLabel")
lbLabel.Size = UDim2.fromScale(1, 1)
lbLabel.BackgroundTransparency = 1
lbLabel.Text = "🏆 幾何矩陣對戰排行榜：\n\n（排行榜功能由 Roblox 右上角 leaderstats 系統實時提供）\n\n與同學們在同一伺服器競爭！看看誰的金幣賺得最多，誰通關的關卡最遠！加油，數學炸彈人之王非你莫屬！"
lbLabel.Font = Enum.Font.GothamBold
lbLabel.TextSize = 14
lbLabel.TextColor3 = Color3.fromRGB(80, 180, 255)
lbLabel.TextWrapped = true
lbLabel.Parent = frameLeaderboard


-- ==================== 核心：流暢 Navigation 補間動畫 ====================

local currentFrame = nil

local function switchTab(targetFrame: Frame)
	if currentFrame == targetFrame then return end

	clickSound:Play()

	-- 如果是 PVE，刷新關卡解鎖進度
	if targetFrame == framePVE then
		task.spawn(buildPVEMapCards)
	end

	-- 1. 隱藏並縮放當前 tab
	if currentFrame then
		local old = currentFrame
		-- 縮放效果 + 隱藏
		old:TweenSize(UDim2.fromScale(0.9, 0.9), "Out", "Quad", 0.15, true)
		task.delay(0.15, function()
			old.Visible = false
		end)
	end

	-- 2. 顯示並彈入目標 tab
	currentFrame = targetFrame
	targetFrame.Size = UDim2.fromScale(0.9, 0.9)
	targetFrame.Visible = true
	targetFrame:TweenSize(UDim2.fromScale(1, 1), "Out", "Back", 0.25, true)
end

-- 綁定按鈕
btnPVE.MouseButton1Click:Connect(function() switchTab(framePVE) end)
btnPVP.MouseButton1Click:Connect(function() switchTab(framePVP) end)
btnShop.MouseButton1Click:Connect(function() switchTab(frameShop) end)
btnLeaderboard.MouseButton1Click:Connect(function() switchTab(frameLeaderboard) end)

-- 預設顯示 PVE
task.spawn(function()
	task.wait(0.2)
	switchTab(framePVE)
end)


-- ==================== 5. 電影級 3D 鏡頭繞圈背景動畫 ====================

local camera = workspace.CurrentCamera
local renderConn = nil

local function startCinematicCamera()
	camera.CameraType = Enum.CameraType.Scriptable
	
	local centerPoint = Vector3.new(0, 4, 0) -- 競技場地圖中央
	local radius = 38 -- 繞行半徑
	local height = 24 -- 鏡頭高度
	local angle = 0

	if renderConn then renderConn:Disconnect() end

	renderConn = RunService.RenderStepped:Connect(function(dt)
		if not screenGui.Enabled then
			-- 當玩家進入 Match，關閉 MainMenuGui 時，解除相機接管
			camera.CameraType = Enum.CameraType.Custom
			if renderConn then
				renderConn:Disconnect()
				renderConn = nil
			end
			return
		end

		-- 雙重防禦：每幀強制隱藏大廳內角色並停用控制，徹底阻斷 race condition 與後台移動
		setLobbyCharacterHidden(true)
		toggleControls(false)

		-- 電影級繞行插值計算
		angle += dt * 0.12 -- 控制繞行速度
		local x = math.cos(angle) * radius
		local z = math.sin(angle) * radius
		-- 輕微上下起伏波動
		local currentHeight = height + math.sin(angle * 2) * 3

		local camPos = Vector3.new(x, currentHeight, z)
		camera.CFrame = CFrame.new(camPos, centerPoint)
	end)
end

-- ==================== 控制權鎖定（防主選單內移動角色） ====================
local function toggleControls(enable: boolean)
	local pScripts = player:FindFirstChild("PlayerScripts")
	local pModule = pScripts and pScripts:FindFirstChild("PlayerModule")
	if pModule then
		pcall(function()
			local activeControls = require(pModule):GetControls()
			if activeControls then
				if enable then
					activeControls:Enable()
				else
					activeControls:Disable()
				end
			end
		end)
	end
end

-- 監聽 ScreenGui 啟用狀態啟動相機與禁用控制權
screenGui:GetPropertyChangedSignal("Enabled"):Connect(function()
	if screenGui.Enabled then
		-- 主選單開啟時，隱藏 HUD
		local pg = player:FindFirstChild("PlayerGui")
		local hudGui = pg and pg:FindFirstChild("MathQuizScreenGui")
		local hud = hudGui and hudGui:FindFirstChild("HUDFrame")
		if hud and hud:IsA("GuiObject") then
			(hud :: GuiObject).Visible = false
		end
		toggleControls(false)
		startCinematicCamera()
	else
		camera.CameraType = Enum.CameraType.Custom
		toggleControls(true)
		setLobbyCharacterHidden(false)
		if renderConn then
			renderConn:Disconnect()
			renderConn = nil
		end
	end
end)

-- ==================== 載入完成後強制顯示大廳（根除競態） ====================

local function showMainLobby()
	if screenGui.Enabled then
		return
	end
	print("[MainMenuGui] 正在顯示主大廳...")
	screenGui.Enabled = true
	setLobbyCharacterHidden(true)
	toggleControls(false)
	startCinematicCamera()

	local hudGui = playerGui:FindFirstChild("MathQuizScreenGui")
	local hud = hudGui and hudGui:FindFirstChild("HUDFrame")
	if hud and hud:IsA("GuiObject") then
		(hud :: GuiObject).Visible = false
	end
end

local function waitForLoadingComplete()
	if ReplicatedStorage:GetAttribute(LOADING_DONE_ATTR) == true then
		return
	end
	local deadline = os.clock() + 120
	while os.clock() < deadline do
		if ReplicatedStorage:GetAttribute(LOADING_DONE_ATTR) == true then
			return
		end
		-- LoadingGui 已卸載且超過 2 秒，視為載入結束
		if not playerGui:FindFirstChild("LoadingGui") and os.clock() > 2 then
			ReplicatedStorage:SetAttribute(LOADING_DONE_ATTR, true)
			return
		end
		task.wait(0.1)
	end
	warn("[MainMenuGui] 等待 LoadingComplete 逾時，仍強制顯示大廳。")
	ReplicatedStorage:SetAttribute(LOADING_DONE_ATTR, true)
end

-- 載入一完成就顯示（即使 UI 還在建立中，屬性會觸發）
ReplicatedStorage:GetAttributeChangedSignal(LOADING_DONE_ATTR):Connect(function()
	if ReplicatedStorage:GetAttribute(LOADING_DONE_ATTR) == true then
		task.defer(showMainLobby)
	end
end)

-- 進場立刻隱藏角色，避免在大廳出現前能放炸彈
setLobbyCharacterHidden(true)

task.spawn(function()
	waitForLoadingComplete()
	showMainLobby()
end)

player.CharacterAdded:Connect(function()
	if screenGui.Enabled then
		setLobbyCharacterHidden(true)
		toggleControls(false)
	end
end)

print("[MainMenuGui] 幾何矩陣主選單系統加載完成！")
