# 🎮 MathBomber - Roblox Studio 專案設置與腳本導入指南

親愛的總統！這是 MathBomber 的 Roblox 原始碼與結構配置說明文件。我們所有的核心邏輯已全面優化完畢，採用 **SOLID 原則** 與 **自癒機制（Self-Healing ScreenGui）** 設計，保證您在 Roblox Studio 內一鍵啟動、完美運行！

---

## 📂 腳本對應與放置位置

請在您的 Roblox Studio 中，將本目錄 `roblox/src/` 內的所有檔案，複製並貼到對應的節點下：

| 檔案名稱 | 放置位置 (Roblox Explorer) | 類型 | 說明 |
| :--- | :--- | :--- | :--- |
| `00_SetupPlaceStructure.luau` | **Command Bar (命令列)** 直接貼上執行 | 命令列工具 | 一鍵建立所有資料夾、Remotes 節點與安全 SpawnLocation |
| `TSADatabase.luau` | `ReplicatedStorage` -> `Modules` -> **ModuleScript** | 數據模組 | 所有 TSA 數學題目名稱、羅建 Asset ID 與正確答案對照表 |
| `BossGameManager.server.luau`| `ServerScriptService` -> **Script** | 伺服端核心 | Boss 智慧巡邏、碰撞扣血、Stun眩暈、**關卡晉級與答題無敵狀態管理** |
| `BomberGameManager.server.luau`| `ServerScriptService` -> **Script** | 伺服端核心 | 地圖隨機生成（**鐵箱與 TNT 連鎖炸藥桶**）、炸彈放置、**地面十字預警投影**、史萊姆小怪巡邏 |
| `PlayerDataStore.server.luau`| `ServerScriptService` -> **Script** | 伺服端核心 | 玩家資料快照同步、**金幣屬性商店（升級生命/範圍/速度）後台** |
| `QuizUI.client.luau` | `StarterGui` -> `MathQuizScreen` -> **LocalScript** | 客戶端 UI | **黃金分割 UI 比例優化**、彈出答題視窗、自癒渲染、答對/答錯閃紅動畫 |
| `PlayerHUD.client.luau` | `StarterGui` -> `MathQuizScreen` -> **LocalScript** | 客戶端 UI | **狀態 HUD（15顆紅心同步）**、通關與失敗結算面板、**金幣商店互動介面** |
| `OcclusionFade.client.luau` | `StarterGui` -> `MathQuizScreen` -> **LocalScript** | 客戶端 UI | **75度縱深遮擋透視**（當角色或 Boss 被方塊擋住時，方塊自動變半透明） |
| `BomberControls.client.luau` | `StarterPlayer` -> `StarterPlayerScripts` -> **LocalScript** | 客戶端控制 | 鍵盤【空格鍵】放炸彈，**全面停用跳躍功能**（還原經典策略） |

---

## 🚀 導入與啟動三部曲

### 1. 一鍵生成基礎節點與安全出生點
在 Roblox Studio 中，開啟 **View** -> **Command Bar**，複製 `tools/studio/00_SetupPlaceStructure.luau` 的所有內容，貼入 Command Bar 並按下 `Enter` 執行。
> 這會自動建立 `Remotes` 資料夾與所有通信遠端，並在安全起跑點建立 SpawnLocation。

### 2. 貼上核心代碼
依照上表，在 `ReplicatedStorage`、`ServerScriptService`、`StarterGui`、`StarterPlayerScripts` 分別建立對應的 `Script`、`LocalScript` 與 `ModuleScript`，將我們為您寫好的代碼貼入其中，並將名稱命名一致（副檔名 `.server.luau` 為 Script，`.client.luau` 為 LocalScript，`.luau` 為 ModuleScript）。

### 3. 匯入題圖並一鍵生成題庫
1. 開啟 **Asset Manager** -> **Bulk Import** 大量匯入 `初中題庫/TSA/` 內所有的題圖 PNG。
2. 匯入完成後，在 Command Bar 貼入 `tools/studio/01_ImportLocalTSA_BuildMap.luau` 取得對照 ID 並複製 Output 到 `data/tsa-image-ids-paste.txt`。
3. 執行本機 Node 腳本生成題庫，並直接替換 `TSADatabase` 的 ModuleScript 代碼：
   ```bash
   node tools/parse-tsa-output.mjs data/tsa-image-ids-paste.txt
   node tools/patch-question-database-tsa.mjs
   node tools/generate-tsa-database.mjs
   ```

---

## 🏆 第二階段進階遊戲打磨特色
- **75度縱深遮擋透視**：再也不用擔心走到方塊後面看不到自己了！方塊會優雅地變為半透明。
- **地面十字高亮預警投影**：放炸彈時地表會投射紅光十字，清楚標示 3 格爆炸安全區，消除 3D 傾斜錯覺。
- **屬性提升商店**：金幣不再是裝飾！您可以在 HUD 中點擊「商店」，使用金幣永久提升生命上限（150HP）、爆炸範圍（8格）與跑速（22）！
- **多樣化特殊方塊**：鐵礦箱需要炸 2 次、TNT 連鎖炸藥桶能瞬間引爆周圍一格並形成連鎖大反應！
- **關卡遞增挑戰**：支援 1~3 關，Boss 血量與跑速遞增、小怪數量增多、解鎖特殊道具，給學生最刺激的答題體驗！

---

## 🏆 第三階段：PVE 關卡挑戰與 PVP 萬花筒雙向解鎖機制 (Progression & Fair PVP)

為了解決傳統 PVP 模式對新手不友善以及 PVE 數值崩壞問題，我們精心設計了**雙向公平解鎖系統**：

### 1. PVP 競技場屬性重置與公平機制
- 為了確保對戰的純粹公平與競技性，當玩家進入 **PVP 競技場（關卡 4）**時，所有人在 PVE 商店購買的永久屬性升級會**暫時失效並全部重置為基礎標準值**：
  - **最大生命值**：50 HP（5 顆心）
  - **初始炸彈數量**：1 顆
  - **初始爆炸威力**：3 格
  - **移動速度**：16
- 如此一來，PVP 戰鬥純粹考驗玩家的**走位、炸彈安放時機與戰術策略**，新手玩家與資深玩家均能平起平坐，享受極致公平對決！

### 2. PVE 通關解鎖 PVP 局內隨機道具/箱子進度
- 雖然 PVE 商店數值不帶入 PVP，但玩家在 PVE 中通關挑戰，能為 **整個伺服器的所有玩家解鎖 PVP 競技場中的全新方塊與強力道具**！
- **通關解鎖進度（每兩關解鎖一樣新元素）**：
  - 🔓 **通關 PVE 第 3 關**：解鎖後續更多 PVE 關卡挑戰。
  - 🔓 **通關 PVE 第 5 關**：在 PVP 競技場中，摧毀箱子有機率掉落 **「愛心道具（❤️）」**（可為受傷的玩家恢復 1 顆心）。
  - 🔓 **通關 PVE 第 7 關**：在 PVP 競技場中，將有機率隨機生成 **「鐵礦箱（IronBrick）」**（需要炸 2 次，大大增加阻擋戰術與生存容錯）。
  - 🔓 **通關 PVE 第 9 關**：在 PVP 競技場中，摧毀箱子有機率掉落 **「威力道具（🔥）」**（永久增加 +1 炸彈爆炸格數）。
  - 🔓 **通關 PVE 第 11 關**：在 PVP 競技場中，將有機率隨機生成 **「TNT 連鎖炸藥桶」**（受到任何爆炸波及會立刻瞬爆，引起極具觀賞性的連鎖大爆炸！）。
  - 🔓 **通關 PVE 第 13 關**：在 PVP 競技場中，摧毀箱子有機率掉落 **「炸彈數量道具（💣）」**（增加可同時放置的炸彈上限 +1）。

---

## 🔧 常見問題修復（架構級）

| 症狀 | 根因 | 修復要點 |
|------|------|----------|
| 紅心/金幣 HUD 消失 | 多個 LocalScript 對 `MathQuizScreenGui` 執行 `:Destroy()` | 三個 UI 腳本改為「有則沿用、無則新建」 |
| 撿不到金幣 | 未在伺服器綁定 `Touched` + `leaderstats.Gold` | `spawnGoldCoin` +50 金 |
| 炸彈縫隙上牆 | 炸彈過矮變台階 | `Block` 3.8×**4.0**×3.8 |
| Boss 在箱頂 | `MoveTo` 防卡牆 + 中央有磚 | 中央 5×5 白名單 + `PivotTo` Y=2 |
| 炸 Boss 無題目 | `BossBombHit` 未觸發 | 爆炸 `Overlap` + `BossBombHit:Fire(player, boss)` |

**載入順序建議**：在 Studio 將 `PlayerHUD` LocalScript 排在 `QuizUI`、`PVEWelcomeLoader` **之前**（右鍵 ↑）。

本工程師已全力以赴！祝您與學生玩得開心！如有任何體驗回饋，隨時吩咐！
