--[[
  答題 UI（Client）- 總統極致自癒防呆版 (黃金分割優化)
  功能：
  1. 解決 Folder 容器非 ScreenGui 導致 UI 隱形不顯示的 Roblox 引擎限制。
  2. 重新調整 UI 黃金分割比例：縮小 A/B/C/D 按鈕並將題目圖片顯示面積擴大 1.5 倍！
  3. 監聽 ShowMathUI 事件，彈出答題 UI，如果找不到 QuizFrame，將自動用代碼在本地 100% 完美補齊結構。
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local function findMainMenuScreenGui(): ScreenGui?
	for _, child in ipairs(playerGui:GetChildren()) do
		if child.Name == "MainMenuGui" and child:IsA("ScreenGui") then
			return child :: ScreenGui
		end
	end
	return nil
end

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local ShowMathUI = Remotes:WaitForChild("ShowMathUI")
local VerifyAnswer = Remotes:WaitForChild("VerifyAnswer")

-- 共用 UI 容器：絕不 Destroy 既有 ScreenGui，避免抹除 PlayerHUD 的紅心與金幣
local screenGui = playerGui:FindFirstChild("MathQuizScreenGui") :: ScreenGui?
if not screenGui then
	screenGui = Instance.new("ScreenGui")
	screenGui.Name = "MathQuizScreenGui"
	screenGui.ResetOnSpawn = true
	screenGui.Parent = playerGui
	print("[UI Engine] 成功建立全新的 MathQuizScreenGui 容器")
else
	print("[UI Engine] 發現已存在的容器，直接沿用，不進行 Destroy 防止 HUD 消失")
end
screenGui.DisplayOrder = math.max(screenGui.DisplayOrder, 20)

-- 尋找既有的 QuizFrame。若在 Folder 下，將其動態移至自癒 ScreenGui
local frame = script.Parent:FindFirstChild("QuizFrame") :: Frame
if not frame then
	frame = screenGui:FindFirstChild("QuizFrame") :: Frame
end

local isComplete = false
if frame then
	-- 驗證子物件是否完整
	local img = frame:FindFirstChild("QuestionImage")
	local btnA = frame:FindFirstChild("A")
	local btnB = frame:FindFirstChild("B")
	local btnC = frame:FindFirstChild("C")
	local btnD = frame:FindFirstChild("D")
	if img and btnA and btnB and btnC and btnD then
		isComplete = true
		frame.Parent = screenGui
		print("[QuizUI] 檢測到完整的既有 QuizFrame，沿用並移至 ScreenGui")
	else
		print("[QuizUI] 檢測到不完整的既有 QuizFrame，進行清理重建")
		frame:Destroy()
		frame = nil
	end
end

if not isComplete then
	warn("[QuizUI] 正在全新建立/補齊 3D 炸彈人答題 UI 結構...")
	
	frame = Instance.new("Frame")
	frame.Name = "QuizFrame"
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.Size = UDim2.fromScale(0.85, 0.85)
	frame.BackgroundColor3 = Color3.fromRGB(25, 25, 35)
	frame.BorderSizePixel = 0
	frame.Visible = false
	frame.Parent = screenGui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = frame

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(80, 80, 110)
	stroke.Thickness = 3
	stroke.Parent = frame

	-- 題目圖片 Label（擴大高度至 72%，字體更大清晰）
	local img = Instance.new("ImageLabel")
	img.Name = "QuestionImage"
	img.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	img.Position = UDim2.fromScale(0.05, 0.04)
	img.Size = UDim2.fromScale(0.9, 0.72)
	img.ScaleType = Enum.ScaleType.Fit
	img.BorderSizePixel = 0
	img.Parent = frame

	-- A/B/C/D 按鈕（精簡高度至 10%，擺放於 0.83 位置）
	local btnY = 0.83
	local labels = { "A", "B", "C", "D" }
	for i, label in ipairs(labels) do
		local btn = Instance.new("TextButton")
		btn.Name = label
		btn.Text = label
		btn.Font = Enum.Font.GothamBold
		btn.TextSize = 28
		btn.TextColor3 = Color3.new(1, 1, 1)
		btn.BackgroundColor3 = Color3.fromRGB(60, 120, 200)
		btn.Position = UDim2.fromScale(0.05 + (i - 1) * 0.24, btnY)
		btn.Size = UDim2.fromScale(0.18, 0.1) -- 縮小按鈕寬度 0.18，高度 0.1
		btn.Parent = frame
		
		local bc = Instance.new("UICorner")
		bc.CornerRadius = UDim.new(0, 8)
		bc.Parent = btn
	end
	print("[QuizUI] 答題 UI 黃金分割優化補齊完畢！")
end

local questionImage = frame:WaitForChild("QuestionImage") :: ImageLabel

local buttons = {
	A = frame:WaitForChild("A") :: TextButton,
	B = frame:WaitForChild("B") :: TextButton,
	C = frame:WaitForChild("C") :: TextButton,
	D = frame:WaitForChild("D") :: TextButton,
}

-- 核心修復：在 Sibling 渲染模式下，必須確保所有子物件 (Image, Buttons) 的 ZIndex 絕對高於父面板，否則會被背景色完全遮擋！
frame.ZIndex = 2
questionImage.ZIndex = 3
for _, btn in pairs(buttons) do
	btn.ZIndex = 3
end

local defaultColors = {}
for name, btn in pairs(buttons) do
	defaultColors[name] = btn.BackgroundColor3
end

local function flashWrong(btn: TextButton)
	local tween = TweenService:Create(btn, TweenInfo.new(0.15), {
		BackgroundColor3 = Color3.fromRGB(220, 60, 60),
	})
	tween:Play()
	tween.Completed:Connect(function()
		TweenService:Create(btn, TweenInfo.new(0.2), {
			BackgroundColor3 = defaultColors[btn.Name],
		}):Play()
	end)
end

ShowMathUI.OnClientEvent:Connect(function(imageId: string)
	print("[QuizUI] 🚀 收到 ShowMathUI 事件，載入題目圖片:", imageId)
	if typeof(imageId) ~= "string" or imageId == "" then
		warn("[QuizUI] 題目圖片 ID 無效，無法顯示答題 UI")
		return
	end
	questionImage.Image = imageId
	frame.Visible = true
	-- 核心修復：在 Sibling 渲染模式下，必須確保所有子物件 (Image, Buttons) 的 ZIndex 絕對高於父面板，否則會被背景色完全遮擋！
	frame.ZIndex = 2
	questionImage.ZIndex = 3
	for _, btn in pairs(buttons) do
		btn.ZIndex = 3
	end
	-- 關閉大廳以免遮住題目
	local mainMenu = findMainMenuScreenGui()
	if mainMenu then
		mainMenu.Enabled = false
	end
end)

for name, btn in pairs(buttons) do
	btn.MouseButton1Click:Connect(function()
		print("[QuizUI] 點擊選項:", name)
		local ok = VerifyAnswer:InvokeServer(name)
		if ok then
			print("[QuizUI] 🎉 答對了！隱藏答題 UI。")
			frame.Visible = false
		else
			print("[QuizUI] ❌ 答錯了！觸發閃紅特效。")
			flashWrong(btn)
		end
	end)
end

print("[QuizUI] 客戶端監聽程序與自癒掛載載入成功！")
