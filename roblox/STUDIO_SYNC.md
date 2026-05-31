# Roblox Studio 更新同步清單（已有舊 Place）

本專案**沒有 Rojo 自動同步**。每次更新請依序完成以下步驟（約 20–30 分鐘）。

---

## 步驟 0：備份（必做）

1. 開啟 Roblox Studio，載入你的 MathBomber Place。
2. **File → Save to File**，存一份 `.rbxl` 到本機（例如 `MathBomber-backup-2026-05-31.rbxl`）。

---

## 步驟 1：一鍵修復結構（Command Bar）

1. **View → Command Bar**
2. 在本機打開 [`tools/studio/00_SetupPlaceStructure.luau`](../tools/studio/00_SetupPlaceStructure.luau)，**全選複製**
3. 貼到 Command Bar，按 **Enter**
4. 確認 Output 出現 `=== Done ===`

---

## 步驟 2：貼上腳本（整份覆蓋舊程式碼）

副檔名對照：`.server.luau` → **Script**，`.client.luau` → **LocalScript**，`.luau`（Modules）→ **ModuleScript**

### 優先更新（v0.5.0 有改動，必貼）

| 本機檔案 | Studio 位置 | 類型 |
|---------|------------|------|
| [`BomberGameManager.server.luau`](src/ServerScriptService/BomberGameManager.server.luau) | `ServerScriptService → BomberGameManager` | Script |
| [`PVPExplosionEngine.server.luau`](src/ServerScriptService/PVPExplosionEngine.server.luau) | `ServerScriptService → PVPExplosionEngine` | Script |
| [`MainMenuGui.client.luau`](src/StarterGui/MainMenuGui.client.luau) | `StarterGui → MainMenuGui → LocalScript` | LocalScript |
| [`PlayerHUD.client.luau`](src/StarterGui/MathQuizScreen/PlayerHUD.client.luau) | `StarterGui → MathQuizScreen → PlayerHUD` | LocalScript |
| [`BomberControls.client.luau`](src/StarterPlayer/StarterPlayerScripts/BomberControls.client.luau) | `StarterPlayer → StarterPlayerScripts → BomberControls` | LocalScript |

### 其餘腳本（建議全量覆蓋）

| 本機檔案 | Studio 位置 | 類型 |
|---------|------------|------|
| [`BossGameManager.server.luau`](src/ServerScriptService/BossGameManager.server.luau) | `ServerScriptService → BossGameManager` | Script |
| [`PlayerDataStore.server.luau`](src/ServerScriptService/PlayerDataStore.server.luau) | `ServerScriptService → PlayerDataStore` | Script |
| [`TSADatabase.luau`](src/ReplicatedStorage/Modules/TSADatabase.luau) | `ReplicatedStorage → Modules → TSADatabase` | ModuleScript |
| [`LoadingGui.client.luau`](src/ReplicatedFirst/LoadingGui.client.luau) | `ReplicatedFirst → LoadingGui → LocalScript` | LocalScript |
| [`QuizUI.client.luau`](src/StarterGui/MathQuizScreen/QuizUI.client.luau) | `StarterGui → MathQuizScreen → QuizUI` | LocalScript |
| [`OcclusionFade.client.luau`](src/StarterGui/MathQuizScreen/OcclusionFade.client.luau) | `StarterGui → MathQuizScreen → OcclusionFade` | LocalScript |
| [`CameraControls.client.luau`](src/StarterPlayer/StarterPlayerScripts/CameraControls.client.luau) | `StarterPlayer → StarterPlayerScripts → CameraControls` | LocalScript |

### 不要貼 / 要刪除

- `PVEWelcomeLoader`（Legacy，Setup 會自動刪）
- `StarterPlayerScripts` 底下的 `MainMenuGui`（錯誤位置）
- `ReplicatedStorage` 根目錄的 `TSADatabase`（應只在 `Modules` 內）

---

## 步驟 3：清理與載入順序

在 `MathQuizScreen` 內，LocalScript 順序（右鍵 ↑ 上移）：

1. `PlayerHUD`
2. `QuizUI`
3. `OcclusionFade`

---

## 步驟 4：Play 測試（F5）

- [ ] 載入畫面 → 顯示「競技大廳」（不是直接進遊戲）
- [ ] PVE 選關 → 血條/金幣/計時 → E 或空白鍵放炸彈
- [ ] PVP 選地圖 → 匹配或「創房/加入 6 位房號」
- [ ] 地圖 5 / PVE 第 5 關：炸彈波及地磚會塌陷成虛空
- [ ] 撿 👟 後按 **Q** 閃現 3 格；撿 🧪 後 6 秒可穿炸彈

---

## 步驟 5：存檔與 Publish

1. **Cmd+S** 儲存 Place
2. **File → Publish to Roblox**（若要線上玩到）

---

## 常見錯誤

| 症狀 | 修復 |
|------|------|
| 跳過主選單直接進遊戲 | `MainMenuGui` LocalScript 必須在 `StarterGui/MainMenuGui` 下，不在 StarterPlayerScripts |
| 放炸彈沒反應 | 確認 `BomberGameManager`、`BomberControls` 已貼上；Output 無紅字 |
| PVP 爆炸無折射 | 確認 `PVPExplosionEngine` Script 存在 |
| ResetOnSpawn is not a valid member of LocalScript | MainMenuGui 必須是 ScreenGui + 子 LocalScript，不是 LocalScript 根節點 |
