--[[
	【經典炸彈人操作體驗】鍵盤放炸彈與極致禁用跳躍 (BomberControls)
	功能：
	1. 支援按【E 鍵】與【空白鍵 (Space)】放置炸彈，滿足所有玩家的操作習慣。
	2. 利用 Roblox 官方 ContextActionService 高優先級攔截（Sink），100% 吞掉空白鍵的跳躍指令，徹底解決跳上牆體的問題！
	3. 雙重保險：強制關閉 Humanoid Jumping 狀態與高度，防止任何物理或引擎 race condition 觸發跳躍。
]]

local Players = game:GetService("Players")
local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer

local function findMainMenuScreenGui(pg): ScreenGui?
	if not pg then return nil end
	for _, child in ipairs(pg:GetChildren()) do
		if child.Name == "MainMenuGui" and child:IsA("ScreenGui") then
			return child :: ScreenGui
		end
	end
	return nil
end
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local PlaceBomb = Remotes:WaitForChild("PlaceBomb")

-- ==================== 雙重物理保險：禁用 Humanoid 跳躍狀態 ====================

local function disableHumanoidJumping(char: Model)
	local hum = char:WaitForChild("Humanoid") :: Humanoid
	hum.JumpPower = 0
	hum.JumpHeight = 0
	hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
	hum:SetStateEnabled(Enum.HumanoidStateType.Climbing, false) -- 【防擠上牆】禁用爬牆狀態
	hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
	hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
	
	-- 每當 Humanoid 試圖進入 Jumping 狀態時，強制將其拉回 Running
	hum.StateChanged:Connect(function(_, state)
		if state == Enum.HumanoidStateType.Jumping or state == Enum.HumanoidStateType.Climbing then
			hum:ChangeState(Enum.HumanoidStateType.Running)
		end
	end)
	
	print("[BomberControls] 已停用跳躍與爬牆（不再每幀改 CFrame，避免畫面抖動）。")
end

player.CharacterAdded:Connect(disableHumanoidJumping)
if player.Character then
	disableHumanoidJumping(player.Character)
end

-- ==================== 物理保險：強制鎖定最大 Y 軸，徹底防範擠上牆/上箱 ====================
RunService.Heartbeat:Connect(function()
	local char = player.Character
	local rootPart = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if rootPart and hum and hum.Health > 0 then
		-- 地板一般在 Y=0.5，玩家站立時 RootPart.Y 約為 3.0。若大於 3.2 則判定為試圖上牆/被推高
		if rootPart.Position.Y > 3.2 then
			rootPart.AssemblyLinearVelocity = Vector3.new(rootPart.AssemblyLinearVelocity.X, 0, rootPart.AssemblyLinearVelocity.Z)
			rootPart.CFrame = CFrame.new(rootPart.Position.X, 3.0, rootPart.Position.Z) * (rootPart.CFrame - rootPart.Position)
		end
	end
end)

-- ==================== ContextActionService 攔截並綁定放炸彈 ====================

local function handlePlaceBomb(actionName: string, inputState: Enum.UserInputState, inputObject: InputObject)
	if inputState == Enum.UserInputState.Begin then
		local char = player.Character
		if not char then return Enum.ContextActionResult.Sink end

		-- 如果主選單開啟中，禁止放置炸彈
		local pg = player:FindFirstChild("PlayerGui")
		local mmGui = findMainMenuScreenGui(pg)
		if mmGui and mmGui.Enabled then
			print("[BomberControls] 主選單開啟中，禁止放置炸彈")
			return Enum.ContextActionResult.Sink
		end

		-- 如果正在答題中，禁止放置炸彈
		if char:GetAttribute("AnsweringQuiz") then
			print("[BomberControls] 正在答題中，禁止放置炸彈")
			return Enum.ContextActionResult.Sink
		end

		local hum = char:FindFirstChildOfClass("Humanoid")
		if hum and hum.Health > 0 then
			print("[BomberControls] 按鍵觸發放炸彈: " .. inputObject.KeyCode.Name)
			PlaceBomb:FireServer()
		end
	end
	
	-- Return Sink 100% 吞掉此按鍵的預設行為（防止空白鍵觸發跳躍！）
	return Enum.ContextActionResult.Sink
end

-- 綁定 E 鍵與 Space 鍵，並設置為高優先級，確保優先於 Roblox 預設控制
ContextActionService:BindActionAtPriority(
	"PlaceBombAction",
	handlePlaceBomb,
	false,
	Enum.ContextActionPriority.High.Value,
	Enum.KeyCode.Space,
	Enum.KeyCode.E
)

print("[BomberControls] 極致操作防線加載成功！按【E 鍵】或【空白鍵】皆可放炸彈，跳躍已被 100% 禁用。")
