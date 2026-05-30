--[[
	【專業資產預加載與動態載入畫面】LoadingGui.client
	位置：ReplicatedFirst -> LoadingGui (LocalScript)
	功能：
	1. 立即停用 Roblox 預設載入畫面。
	2. 建立精美的全螢幕載入 UI（背景、旋轉幾何圖標、進度條、狀態文字）。
	3. 動態解析 TSADatabase，將上百張 TSA 題圖、音效與核心特效範本加入預加載池。
	4. 使用 ContentProvider:PreloadAsync 進行異步預加載，精確更新進度條與百分比。
	5. 載入完成後，透過 CanvasGroup 進行流暢淡出，並啟用主功能大廳 MainMenuGui。
]]

local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

-- 全域載入完成信號（MainMenuGui 會監聽此屬性，避免 ReplicatedFirst 與 StarterGui 的競態）
local LOADING_DONE_ATTR = "LoadingComplete"
ReplicatedStorage:SetAttribute(LOADING_DONE_ATTR, false)

-- 1. 立即移除預設載入畫面，爭取首幀控制權
ReplicatedFirst:RemoveDefaultLoadingScreen()

local player = Players.LocalPlayer
while not player do
	task.wait()
	player = Players.LocalPlayer
end
local playerGui = player:WaitForChild("PlayerGui")

-- 建立 Loading Screen UI 容器
local loadingGui = Instance.new("ScreenGui")
loadingGui.Name = "LoadingGui"
loadingGui.IgnoreGuiInset = true
loadingGui.ResetOnSpawn = false
loadingGui.DisplayOrder = 9999 -- 確保在最上層
loadingGui.Parent = playerGui

-- 使用 CanvasGroup 以利整體淡出
local canvasGroup = Instance.new("CanvasGroup")
canvasGroup.Size = UDim2.fromScale(1, 1)
canvasGroup.BackgroundTransparency = 1
canvasGroup.Parent = loadingGui

-- 背景 Frame (暗色科技風格)
local background = Instance.new("Frame")
background.Size = UDim2.fromScale(1, 1)
background.BackgroundColor3 = Color3.fromRGB(15, 15, 25)
background.BorderSizePixel = 0
background.Parent = canvasGroup

-- 背景網格裝飾 (提高大作質感)
local gridDeco = Instance.new("Frame")
gridDeco.Size = UDim2.fromScale(1, 1)
gridDeco.BackgroundTransparency = 0.95
gridDeco.BackgroundColor3 = Color3.fromRGB(100, 110, 160)
gridDeco.Parent = background

local gridLayout = Instance.new("UIGridLayout")
gridLayout.CellSize = UDim2.fromOffset(40, 40)
gridLayout.CellPadding = UDim2.fromOffset(2, 2)
gridLayout.Parent = gridDeco

for i = 1, 150 do
	local box = Instance.new("Frame")
	box.BackgroundTransparency = 0.8
	box.BackgroundColor3 = Color3.fromRGB(20, 20, 35)
	box.BorderSizePixel = 0
	box.Parent = gridDeco
end

-- 載入核心內容框 (置中)
local container = Instance.new("Frame")
container.Size = UDim2.fromOffset(500, 300)
container.Position = UDim2.fromScale(0.5, 0.5)
container.AnchorPoint = Vector2.new(0.5, 0.5)
container.BackgroundTransparency = 1
container.Parent = canvasGroup

-- 旋轉幾何圖標 (代碼控制不間斷旋轉)
local spinner = Instance.new("ImageLabel")
spinner.Name = "Spinner"
spinner.Size = UDim2.fromOffset(80, 80)
spinner.Position = UDim2.fromScale(0.5, 0.3)
spinner.AnchorPoint = Vector2.new(0.5, 0.5)
spinner.BackgroundTransparency = 1
spinner.Image = "rbxassetid://10850239" -- 經典科技齒輪/炸彈貼圖
spinner.ImageColor3 = Color3.fromRGB(0, 200, 255)
spinner.Parent = container

-- 讓 spinner 不停旋轉
task.spawn(function()
	local rot = 0
	while spinner.Parent do
		rot = (rot + 4) % 360
		spinner.Rotation = rot
		task.wait(0.015)
	end
end)

-- 載入標題
local titleLabel = Instance.new("TextLabel")
titleLabel.Size = UDim2.new(1, 0, 0, 35)
titleLabel.Position = UDim2.fromScale(0.5, 0.5)
titleLabel.AnchorPoint = Vector2.new(0.5, 0.5)
titleLabel.BackgroundTransparency = 1
titleLabel.Text = "GEOMETRIC MATRIX ARENA"
titleLabel.Font = Enum.Font.GothamBold
titleLabel.TextSize = 24
titleLabel.TextColor3 = Color3.fromRGB(255, 215, 0)
titleLabel.Parent = container

-- 進度條外框
local barBackground = Instance.new("Frame")
barBackground.Name = "Bar_Bg"
barBackground.Size = UDim2.new(0.8, 0, 0, 10)
barBackground.Position = UDim2.fromScale(0.5, 0.65)
barBackground.AnchorPoint = Vector2.new(0.5, 0.5)
barBackground.BackgroundColor3 = Color3.fromRGB(30, 30, 45)
barBackground.BorderSizePixel = 0
barBackground.Parent = container

local barCorner = Instance.new("UICorner")
barCorner.CornerRadius = UDim.new(0, 5)
barCorner.Parent = barBackground

-- 進度條填充 (Bar_Fill)
local barFill = Instance.new("Frame")
barFill.Name = "Bar_Fill"
barFill.Size = UDim2.fromScale(0, 1)
barFill.BackgroundColor3 = Color3.fromRGB(0, 200, 255)
barFill.BorderSizePixel = 0
barFill.Parent = barBackground

local fillCorner = Instance.new("UICorner")
fillCorner.CornerRadius = UDim.new(0, 5)
fillCorner.Parent = barFill

-- 光暈發光特效
local fillStroke = Instance.new("UIStroke")
fillStroke.Color = Color3.fromRGB(0, 150, 255)
fillStroke.Thickness = 1.5
fillStroke.Parent = barFill

-- 狀態文字 (Txt_Status)
local statusLabel = Instance.new("TextLabel")
statusLabel.Name = "Txt_Status"
statusLabel.Size = UDim2.new(1, 0, 0, 25)
statusLabel.Position = UDim2.fromScale(0.5, 0.78)
statusLabel.AnchorPoint = Vector2.new(0.5, 0.5)
statusLabel.BackgroundTransparency = 1
statusLabel.Text = "Initializing Matrix..."
statusLabel.Font = Enum.Font.GothamMedium
statusLabel.TextSize = 12
statusLabel.TextColor3 = Color3.fromRGB(150, 160, 200)
statusLabel.Parent = container

-- ==================== 收集預加載資產 ====================

local preloadList = {}

-- 1. 加入通用 UI 與特效貼圖 (使用字串，避免 Instance.new 傳入 table 報錯)
table.insert(preloadList, "rbxassetid://10850239") -- 旋轉圖標
table.insert(preloadList, "rbxassetid://125000492086815") -- 預設地圖貼圖等

-- 2. 解析 TSADatabase 題庫圖標 (收集 ImageId 字串)
local success, result = pcall(function()
	local modules = ReplicatedStorage:WaitForChild("Modules", 5)
	if modules then
		local tsaDbModule = modules:WaitForChild("TSADatabase", 5)
		if tsaDbModule then
			local db = require(tsaDbModule) :: any
			if typeof(db) == "table" then
				for year, questions in pairs(db) do
					if typeof(questions) == "table" then
						for qKey, qData in pairs(questions) do
							if typeof(qData) == "table" and qData.ImageId then
								table.insert(preloadList, qData.ImageId)
							end
						end
					end
				end
			end
		end
	end
end)

if not success then
	warn("[Preloader] 讀取 TSADatabase 失敗或尚未建立，將執行基本資產預加載:", tostring(result))
end

-- ==================== 啟動 ContentProvider 預加載引擎 ====================

local totalAssets = #preloadList
print("[Preloader] 待預加載核心資產總數:", totalAssets)

if totalAssets > 0 then
	local loadedCount = 0
	
	-- 使用並行批次預載，每批 15 個，大幅提升載入速度且防止卡死
	local batchSize = 15
	for i = 1, totalAssets, batchSize do
		local batch = {}
		for j = i, math.min(i + batchSize - 1, totalAssets) do
			table.insert(batch, preloadList[j])
		end
		
		-- 異步加載整個批次
		pcall(function()
			ContentProvider:PreloadAsync(batch)
		end)
		
		loadedCount += #batch
		local ratio = math.clamp(loadedCount / totalAssets, 0, 1)
		
		-- 更新進度條與狀態文字
		barFill.Size = UDim2.fromScale(ratio, 1)
		statusLabel.Text = ("Loading Matrix Geometry: %d / %d Assets (%d%%)"):format(
			loadedCount, totalAssets, math.floor(ratio * 100)
		)
		
		-- 釋放執行緒，確保 UI 旋轉圖標不卡頓
		task.wait(0.03)
	end
else
	-- 無資產時直接跑進度條動畫
	TweenService:Create(barFill, TweenInfo.new(1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = UDim2.fromScale(1, 1) }):Play()
	statusLabel.Text = "Loading Matrix Geometry: 100% Completed!"
	task.wait(1)
end

-- ==================== 通知主大廳可以顯示（不依賴 MainMenuGui 是否已複製） ====================

statusLabel.Text = "Matrix Fully Synced. Entering Arena..."
task.wait(0.4)

-- 先發送信號，再淡出；MainMenuGui 腳本晚於 ReplicatedFirst 啟動時仍能收到
ReplicatedStorage:SetAttribute(LOADING_DONE_ATTR, true)
print("[Preloader] LoadingComplete = true，主大廳可安全顯示。")

-- LoadingGui 補間淡出
local fadeInfo = TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local fadeTween = TweenService:Create(canvasGroup, fadeInfo, { GroupTransparency = 1 })
fadeTween:Play()

fadeTween.Completed:Connect(function()
	loadingGui:Destroy()
	print("[Preloader] LoadingGui 成功卸載。進入主大廳！")
end)
