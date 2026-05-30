--[[
	【固定俯視 60 度角非旋轉視角優化】CameraControls
	功能：
	1. 徹底解決旋轉鏡頭導致的「眩暈感/3D 空間迷失」問題。
	2. 鎖定鏡頭在世界坐標系中永遠面對同一個朝向（朝向正北偏下 60 度），角色左右轉彎時，鏡頭絕對不旋轉。
	3. 將視角高度與傾斜度調校為「完美 60 度角縱深」，視野更開闊，高度極其舒適。
	4. 鏡頭僅進行平滑的平移追蹤（Lerp 跟隨），帶來最經典、最舒適的 3D 炸彈人關卡俯瞰視角體驗。
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

-- 設置為自訂 Camera 模式
camera.CameraType = Enum.CameraType.Scriptable

-- 60度經典固定視角參數
local ANGLE_DEG = 60 -- 60 度俯視角
local DISTANCE = 24 -- 鏡頭到角色的距離 (提供開闊的視野)
local CAMERA_SMOOTH_RATE = 14 -- 越大越快跟上（用 dt 指數平滑，避免抖動）

-- 計算世界坐標系下的固定偏移向量 (面對正北 -Z 俯瞰角色)
-- 60度俯角：Y 軸高度偏移 = DISTANCE * sin(60)，Z 軸後退偏移 = DISTANCE * cos(60)
local radAngle = math.rad(ANGLE_DEG)
local heightOffset = DISTANCE * math.sin(radAngle)
local depthOffset = DISTANCE * math.cos(radAngle)
local cameraOffset = Vector3.new(0, heightOffset, depthOffset) -- 固定偏移量

-- 當前相機的 CFrame
local currentCameraCFrame = camera.CFrame

player.CharacterAdded:Connect(function()
	currentCameraCFrame = camera.CFrame
end)

RunService.RenderStepped:Connect(function(dt)
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	
	if root then
		local charPos = root.Position
		
		-- 目標位置 = 角色當前位置 + 世界坐標固定偏移
		local targetPosition = charPos + cameraOffset
		
		-- 計算 CFrame：從相機位置看著角色中心
		local targetCFrame = CFrame.lookAt(targetPosition, charPos)

		local alpha = 1 - math.exp(-CAMERA_SMOOTH_RATE * dt)
		currentCameraCFrame = currentCameraCFrame:Lerp(targetCFrame, alpha)
		camera.CFrame = currentCameraCFrame
	else
		currentCameraCFrame = camera.CFrame
	end
end)

print("[CameraControls] 經典 3D 炸彈人 60 度固定俯視角跟隨加載成功！已徹底解決轉彎暈鏡問題。")
