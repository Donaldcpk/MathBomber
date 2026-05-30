--[[
	【總統極致防呆修復版】Place 基礎結構、UI 補齊與 Remotes 節點生成腳本
	用法：Roblox Studio -> View -> Command Bar -> 貼上整段 -> Enter 執行
	功能：
	1. 確保 ReplicatedStorage 內有 Remotes 資料夾與所有通訊 Remotes。
	2. 確保 ReplicatedStorage 內有 Modules 資料夾，並自動將 TSADatabase 移入該目錄。
	3. 確保 StarterGui 內有 MathQuizScreen 且啟用。
	4. 建立 PVE_Arena 結構、Grid 資料夾、Bombs 資料夾、Coins 資料夾，以及將 TSABoss 座標強制修正至網格內 Z=-12 的安全位置，且 unanchor 物理。
	5. 補齊基本的安全的 SpawnLocation 起始點於 (gx=1, gz=9)，世界坐標為 (-30, 0.5, 24)。
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local Workspace = game:GetService("Workspace")

print("=== 總統級 Studio 結構與關卡節點修復啟動 ===")

-- 輔助函式：確保資料夾存在
local function ensureFolder(parent: Instance, name: string): Folder
	local f = parent:FindFirstChild(name)
	if not f then
		f = Instance.new("Folder")
		f.Name = name
		f.Parent = parent
	end
	return f :: Folder
end

-- 輔助函式：確保通訊 Remote 存在
local function ensureRemote(className: string, parent: Instance, name: string)
	local r = parent:FindFirstChild(name)
	if not r then
		r = Instance.new(className)
		r.Name = name
		r.Parent = parent
		print("已補齊通訊節點：", name, "(" .. className .. ")")
	end
	return r
end

-- 1. 確保 Remotes 資料夾與所有 Remote 節點
local remotes = ensureFolder(ReplicatedStorage, "Remotes")
ensureRemote("RemoteEvent", remotes, "ShowMathUI")
ensureRemote("RemoteFunction", remotes, "VerifyAnswer")
ensureRemote("BindableEvent", remotes, "BossBombHit")
ensureRemote("BindableEvent", remotes, "MapRebuilt")
ensureRemote("RemoteEvent", remotes, "PlaceBomb")
ensureRemote("RemoteEvent", remotes, "ReturnToLobby")
ensureRemote("BindableEvent", remotes, "ServerRebuildArena")
ensureRemote("RemoteEvent", remotes, "SyncPVETimer")

-- 新增：關卡進度控制 Remotes
ensureRemote("RemoteEvent", remotes, "ShowWinUI")
ensureRemote("RemoteEvent", remotes, "ShowLoseUI")
ensureRemote("RemoteEvent", remotes, "RequestNextLevel")
ensureRemote("RemoteEvent", remotes, "RequestRetry")
ensureRemote("RemoteFunction", remotes, "BuyShopItem")

-- 新增：PVE/PVP 雙流向大廳及選關/佇列 Remotes
ensureRemote("RemoteEvent", remotes, "RequestPVEMatch")
ensureRemote("RemoteFunction", remotes, "GetPlayerProgression")
ensureRemote("RemoteEvent", remotes, "JoinPVPQueue")
ensureRemote("RemoteEvent", remotes, "LeavePVPQueue")
ensureRemote("RemoteEvent", remotes, "PVELobbyUpdate")
ensureRemote("RemoteEvent", remotes, "PVPStartMatch")

-- 2. 確保 Modules 資料夾存在，並將 TSADatabase 移入
local modules = ensureFolder(ReplicatedStorage, "Modules")
local tsaDb = ReplicatedStorage:FindFirstChild("TSADatabase")
if tsaDb then
	tsaDb.Parent = modules
	print("已將 TSADatabase 成功移入 Modules 資料夾")
end

-- 3. 確保 StarterGui 內有 MathQuizScreen 且啟用
local mathQuizScreen = StarterGui:FindFirstChild("MathQuizScreen")
if not mathQuizScreen then
	mathQuizScreen = Instance.new("ScreenGui")
	mathQuizScreen.Name = "MathQuizScreen"
	mathQuizScreen.ResetOnSpawn = true
	mathQuizScreen.Parent = StarterGui
	print("已補齊 ScreenGui: MathQuizScreen")
end

-- 【自動清理】清理舊版 PVEWelcomeLoader 與 WelcomeFrame 以防干擾全新的 MainMenuGui
pcall(function()
	if mathQuizScreen then
		local oldLoader = mathQuizScreen:FindFirstChild("PVEWelcomeLoader")
		if oldLoader then
			oldLoader:Destroy()
			print("[Setup] 已自動清理舊的 PVEWelcomeLoader 腳本，避免與新大廳衝突！")
		end
		
		local oldWelcome = mathQuizScreen:FindFirstChild("WelcomeFrame")
		if oldWelcome then
			oldWelcome:Destroy()
			print("[Setup] 已自動清理舊的 WelcomeFrame UI，保持大廳乾淨！")
		end
	end
end)

-- 新增：確保 StarterGui 內有主大廳 MainMenuGui
local mainMenuGui = StarterGui:FindFirstChild("MainMenuGui")
if not mainMenuGui then
	mainMenuGui = Instance.new("ScreenGui")
	mainMenuGui.Name = "MainMenuGui"
	mainMenuGui.ResetOnSpawn = false
	mainMenuGui.Enabled = false -- 預設關閉，由 LoadingGui 載入後喚醒
	mainMenuGui.Parent = StarterGui
	print("已補齊 ScreenGui: MainMenuGui")
elseif mainMenuGui:IsA("ScreenGui") then
	mainMenuGui.ResetOnSpawn = false
	print("已更新 ScreenGui: MainMenuGui.ResetOnSpawn = false")
else
	print("已偵測到 MainMenuGui 為 " .. mainMenuGui.ClassName .. "，不重複建立 ScreenGui。")
end

-- 清理 StarterPlayerScripts 底下的重複 MainMenuGui 腳本（確保 MainMenuGui 為 Single Source of Truth，防範競態）
pcall(function()
	local StarterPlayer = game:GetService("StarterPlayer")
	local StarterPlayerScripts = StarterPlayer:WaitForChild("StarterPlayerScripts", 2)
	if StarterPlayerScripts then
		local dupMenu = StarterPlayerScripts:FindFirstChild("MainMenuGui")
		if dupMenu then
			dupMenu:Destroy()
			print("[Setup] 已自動清理 StarterPlayerScripts 底下的重複 MainMenuGui 腳本")
		end
	end
end)

-- 新增：確保 ReplicatedFirst 內有預加載 LoadingGui
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local loadingGui = ReplicatedFirst:FindFirstChild("LoadingGui")
if not loadingGui then
	loadingGui = Instance.new("ScreenGui")
	loadingGui.Name = "LoadingGui"
	loadingGui.ResetOnSpawn = false
	loadingGui.IgnoreGuiInset = true
	loadingGui.DisplayOrder = 9999
	loadingGui.Parent = ReplicatedFirst
	print("已補齊 ReplicatedFirst ScreenGui: LoadingGui")
end

-- 移除預設血條與名字，保持 UI 清爽與 100% 經典
pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
end)

-- PVE Arena + Boss
local arena = Workspace:FindFirstChild("PVE_Arena")
if not arena then
	arena = Instance.new("Folder")
	arena.Name = "PVE_Arena"
	arena.Parent = Workspace
	print("已建立 PVE_Arena")
end

ensureFolder(arena, "Grid")
ensureFolder(arena, "Bombs")
ensureFolder(arena, "Coins")
ensureFolder(arena, "Minions")

-- 建立競技場地板 ArenaFloor
local floor = arena:FindFirstChild("ArenaFloor") :: Part?
if not floor then
	floor = Instance.new("Part")
	floor.Name = "ArenaFloor"
	floor.Size = Vector3.new(300, 1, 200)
	floor.Position = Vector3.new(0, 0, -2)
	floor.Anchored = true
	floor.Color = Color3.fromRGB(55, 55, 65)
	floor.Material = Enum.Material.Concrete
	floor.Parent = arena
	print("已建立 ArenaFloor 地板")
else
	floor.Size = Vector3.new(300, 1, 200)
	floor.Position = Vector3.new(0, 0, -2)
	print("已更新 ArenaFloor 地板尺寸為 300x200 且置中於 (0, 0, -2)")
end

local boss = arena:FindFirstChild("TSABoss")
if not boss then
	boss = Instance.new("Model")
	boss.Name = "TSABoss"
	boss.Parent = arena

	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(4, 6, 4)
	root.Anchored = false -- 確保 Boss 巡邏 AI 可走動
	root.CanCollide = true
	root.Position = Vector3.new(0, 3, 0) -- 修正位置：移入網格中央（安全區 (0, 0)，絕不卡石塊）
	root.Color = Color3.fromRGB(180, 40, 40)
	root.Parent = boss

	local hum = Instance.new("Humanoid")
	hum.Name = "Humanoid"
	hum.MaxHealth = 150
	hum.Health = 150
	hum.WalkSpeed = 4
	hum.Parent = boss

	boss.PrimaryPart = root
	print("已建立 TSABoss 預設模型")
end

-- 確保 Boss 一定在網格內且未被錨定，並清理測試 ProximityPrompt
local rootPart = boss:FindFirstChild("HumanoidRootPart")
if rootPart then
	rootPart.Position = Vector3.new(0, 3, 0)
	rootPart.Anchored = false
	rootPart.CanCollide = true
	
	-- 【極致優化】自動清除開發測試用的 ProximityPrompt，確保正式發行版清爽無遮擋
	local oldPrompt = rootPart:FindFirstChild("TestHitBoss")
	if oldPrompt then
		oldPrompt:Destroy()
		print("[Setup] 已自動清理測試 ProximityPrompt [E]！")
	end
end

-- Spawn
-- 【極致修復】清除舊有的 SpawnLocation，並在安全起跑點 (gx=1, gz=9) 建立全新 SpawnLocation，防卡死在牆頂
for _, item in ipairs(Workspace:GetChildren()) do
	if item:IsA("SpawnLocation") and item.Name ~= "MathBomberSpawn" then
		item:Destroy()
		print("已清理舊有 SpawnLocation:", item.Name)
	end
end

local spawn = Workspace:FindFirstChild("MathBomberSpawn") :: SpawnLocation?
if not spawn then
	spawn = Instance.new("SpawnLocation")
	spawn.Name = "MathBomberSpawn"
	spawn.Size = Vector3.new(6, 1, 6)
	spawn.Anchored = true
	spawn.Color = Color3.fromRGB(80, 180, 80)
	spawn.Neutral = true
	spawn.Parent = Workspace
	print("已成功在安全出發區 (gx=-30, gz=20) 建立 SpawnLocation！")
end
spawn.Position = Vector3.new(-120, 0.5, 80)

print("Setup 完成：Remotes、MathQuizScreen、PVE_Arena/TSABoss、MathBomberSpawn")
print("")
print("【重要】主大廳腳本必須存在，否則進遊戲會直接看到地圖、無法選關：")
print("  1) ReplicatedFirst 內要有 ScreenGui「LoadingGui」，底下 LocalScript 貼上 LoadingGui.client.luau")
print("  2) StarterPlayer > StarterPlayerScripts 建立 LocalScript 命名「MainMenuGui」，貼上 MainMenuGui.client.luau")
print("     （不要只建空的 ScreenGui；腳本放 StarterPlayerScripts 最穩，會自動執行）")
print("  3) 刪除 MathQuizScreen 底下舊的 PVEWelcomeLoader（Setup 已嘗試自動刪除）")
print("")
print("下一步：貼上伺服器與 HUD 腳本後，點擊 Play 測試！")
print("=== Done ===")
