# MathBomber - Roblox Studio 專案設置與腳本導入指南

> **快速更新舊 Place？** 直接照 [`STUDIO_SYNC.md`](STUDIO_SYNC.md) 逐步操作（含 v0.5.0 完整 12 檔對照表）。

本專案採 **手動複製貼上** 同步（尚未配置 Rojo）。所有原始碼在 `roblox/src/`。

---

## 導入三部曲

### 1. 一鍵生成基礎節點

**View → Command Bar**，貼上 [`tools/studio/00_SetupPlaceStructure.luau`](../tools/studio/00_SetupPlaceStructure.luau) 全文，按 Enter。

會自動建立：`Remotes`（含 v0.5.0 房號/閃現/穿彈 Remote）、`PVE_Arena`、`ArenaFloor`、`MainMenuGui` ScreenGui 空殼、`LoadingGui` 空殼、安全 Spawn 等。

### 2. 貼上全部腳本

| 本機檔案 | Studio 位置 | 類型 |
|---------|------------|------|
| `ServerScriptService/BossGameManager.server.luau` | `ServerScriptService → BossGameManager` | Script |
| `ServerScriptService/BomberGameManager.server.luau` | `ServerScriptService → BomberGameManager` | Script |
| `ServerScriptService/PlayerDataStore.server.luau` | `ServerScriptService → PlayerDataStore` | Script |
| `ServerScriptService/PVPExplosionEngine.server.luau` | `ServerScriptService → PVPExplosionEngine` | Script |
| `ReplicatedStorage/Modules/TSADatabase.luau` | `ReplicatedStorage → Modules → TSADatabase` | ModuleScript |
| `ReplicatedFirst/LoadingGui.client.luau` | `ReplicatedFirst → LoadingGui → LocalScript` | LocalScript |
| `StarterGui/MainMenuGui.client.luau` | `StarterGui → MainMenuGui → LocalScript` | LocalScript |
| `StarterGui/MathQuizScreen/QuizUI.client.luau` | `StarterGui → MathQuizScreen → QuizUI` | LocalScript |
| `StarterGui/MathQuizScreen/PlayerHUD.client.luau` | `StarterGui → MathQuizScreen → PlayerHUD` | LocalScript |
| `StarterGui/MathQuizScreen/OcclusionFade.client.luau` | `StarterGui → MathQuizScreen → OcclusionFade` | LocalScript |
| `StarterPlayer/StarterPlayerScripts/BomberControls.client.luau` | `StarterPlayerScripts → BomberControls` | LocalScript |
| `StarterPlayer/StarterPlayerScripts/CameraControls.client.luau` | `StarterPlayerScripts → CameraControls` | LocalScript |

**MainMenuGui 規則**：LocalScript 必須在 `StarterGui/MainMenuGui` ScreenGui 底下，**不要**放在 `StarterPlayerScripts`。

**不要貼**：`PVEWelcomeLoader.client.luau`（已廢棄）。

**MathQuizScreen 載入順序**：PlayerHUD → QuizUI → OcclusionFade（右鍵 ↑）。

### 3. 題庫（僅在重新 Bulk Import TSA 圖片時）

見 [`docs/TSA-ROBLOX-工作流程.md`](../docs/TSA-ROBLOX-工作流程.md)。

---

## v0.5.0 新功能摘要

- **地圖 5 虛空塌陷**：炸彈波及地磚 → 抖動 0.5s → 變致命虛空
- **閃現靴 (Q)**、**量子穿彈水 (6s)**
- **PVP 本地 6 位房號**：創房 / 加入 / 房主開始

---

## 常見問題

| 症狀 | 修復 |
|------|------|
| 跳過主選單 | MainMenuGui LocalScript 位置錯誤 |
| 放炸彈無反應 | 檢查 BomberGameManager + BomberControls |
| HUD 消失 | PlayerHUD 排在 QuizUI 之前 |
| Boss 浮空 | 重跑 Setup 腳本修正 TSABoss 位置 |

完整排查見 [`STUDIO_SYNC.md`](STUDIO_SYNC.md)。
