--[[
	【縱深視角優化】南面高大牆體動態半透明遮擋淡入淡出 (OcclusionFade)
	功能：
	1. 解決 75 度視角縱深下，高大方塊（南面方塊）遮擋後面角色與 Boss 的「視覺死角」問題。
	2. 當玩家或 Boss 走到方塊後方時，系統自動利用 Raycast 偵測視線遮擋。
	3. 使用 TweenService 平滑地將遮擋方塊的透明度（Transparency）暫時調至 0.45，確保玩家隨時看清自己與 Boss 的位置。
	4. 當離開遮擋範圍時，平滑恢復原先的透明度（0）。
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local arena = workspace:WaitForChild("PVE_Arena", 10)
local gridFolder = arena and arena:WaitForChild("Grid", 10)
local bossModel = arena and arena:WaitForChild("TSABoss", 10)

-- 儲存目前正在被半透明化的方塊及其原本的透明度
local fadedParts = {} -- maps part -> originalTransparency

-- ==================== 視線射線偵測 ====================

local function getBlockingParts(targetPos: Vector3): {BasePart}
	if not gridFolder or not bossModel then return {} end
	local blocking = {}
	local ignoreList = { player.Character, bossModel }
	local camPos = camera.CFrame.Position
	local dir = targetPos - camPos
	
	-- 最多向上偵測 6 層遮擋（處理多重牆體遮擋）
	for i = 1, 6 do
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = ignoreList
		
		local result = workspace:Raycast(camPos, dir, params)
		if result and result.Instance and result.Instance:IsA("BasePart") then
			local part = result.Instance
			if part:IsDescendantOf(gridFolder) and part.Name ~= "HardWall" then
				-- 只對可破壞方塊（木箱、鐵箱、TNT）進行半透明處理，外圍邊界硬牆不調整
				table.insert(blocking, part)
			end
			-- 將此方塊加入忽略清單，以便繼續偵測後方的其他遮擋物
			table.insert(ignoreList, part)
		else
			break
		end
	end
	return blocking
end

-- ==================== 每幀更新遮擋狀態 ====================

RunService.Heartbeat:Connect(function()
	if not bossModel then return end
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local bossRoot = bossModel:FindFirstChild("HumanoidRootPart")
	
	local currentBlocking = {}

	-- 1. 偵測玩家的遮擋方塊
	if root then
		local parts = getBlockingParts(root.Position)
		for _, part in ipairs(parts) do
			currentBlocking[part] = true
		end
	end

	-- 2. 偵測 Boss 的遮擋方塊
	if bossRoot then
		local parts = getBlockingParts(bossRoot.Position)
		for _, part in ipairs(parts) do
			currentBlocking[part] = true
		end
	end

	-- 3. 套用半透明淡入特效 (透明度 0.45)
	for part in pairs(currentBlocking) do
		if not fadedParts[part] then
			fadedParts[part] = part.Transparency
			TweenService:Create(part, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Transparency = 0.45
			}):Play()
		end
	end

	-- 4. 恢復原狀淡出特效 (恢復原本透明度，通常為 0)
	for part, origTrans in pairs(fadedParts) do
		if not currentBlocking[part] then
			fadedParts[part] = nil
			TweenService:Create(part, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Transparency = origTrans
			}):Play()
		end
	end
end)

print("[OcclusionFade] 動態遮擋牆體半透明化優化加載成功！已完美解決 75 度角視覺盲區。")
