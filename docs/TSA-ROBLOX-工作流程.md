# TSA 題圖 Roblox 資產工作流程

> **專案根目錄**：`/Users/cdlanod/Documents/Education/MathBomber`  
> **本地 PNG**：`初中題庫/TSA/2024TSA/`、`初中題庫/TSA/2025TSA/`（共 160 張）  
> **題庫**：`questionDatabase.js` → `TSA_ALL`（160 題）

---

## 一、我們學到的教訓（不要再踩）

| 做法 | 結果 |
|------|------|
| Bulk Import 到 Asset Manager | ✅ 圖在雲端，但 **Luau 無法列出** |
| 拖入 / Insert 成 Decal | ⚠️ 全部叫 `Decal`，**順序 ≠ 檔名順序** |
| `GetProductInfoAsync` 反查檔名 | ❌ 私有遊戲資產查不到 |
| Import Queue 隔天再看 | ❌ **通常已清空**，只剩 Asset Manager |
| 用 Decal 順序對 TSA2024Q1、Q10… | ❌ Q1 在第 70 個，Q10 不在第 71 個 |

**結論**：必須有一份 **`檔名 → rbxassetid` 對照表**（JSON），作為單一真相來源。

---

## 二、標準流程（從現在起照這個做）

```
本地 PNG (160)
    ↓ ① Studio：01_ImportLocalTSA_BuildMap.luau（或保留舊 ID 見第三節）
Output：TSA2024Q1:rbxassetid://...
    ↓ ② Mac：parse-tsa-output.mjs
data/tsa-image-ids.json
    ↓ ③ Mac：patch-question-database-tsa.mjs
questionDatabase.js（每題多 rbxImageId）
    ↓ ④ Roblox 遊戲程式
ImageLabel.Image = question.rbxImageId
```

---

## 三、一次拿到全部 160 個 ID（推薦）

### 步驟 1：Studio Command Bar

1. 打開 `tools/studio/01_ImportLocalTSA_BuildMap.luau`
2. **全選複製** → Command Bar → Enter
3. 檔案選擇器 → 選 `初中題庫/TSA/2024TSA` → Cmd+A → 開啟
4. **再執行一次**腳本 → 選 `2025TSA` → Cmd+A → 開啟

### 步驟 2：存 Output

1. View → Output → 全選複製
2. 存成：`data/tsa-image-ids-paste.txt`

### 步驟 3：Mac 終端機

```bash
cd /Users/cdlanod/Documents/Education/MathBomber
node tools/parse-tsa-output.mjs data/tsa-image-ids-paste.txt
node tools/patch-question-database-tsa.mjs
```

完成後檢查 `data/tsa-image-ids.json` 應有 **160 筆**。

### 步驟 4：遊戲內使用

```lua
local TSAImages = require(game.ServerStorage.TSAImageMap.TSAImageIds)
-- TSAImages["TSA2024Q1"] → "137144300741977"
ImageLabel.Image = "rbxassetid://" .. TSAImages["TSA2024Q1"]
```

或從 `questionDatabase` 讀 `rbxImageId` 欄位。

---

## 四、若堅持用「昨晚 Bulk Import」的舊 ID

1. 執行 `tools/studio/02_ExportDecalIdsOnly.luau` → 得到 160 個 `rbxassetid://`
2. Asset Manager 逐張查 **Properties → Asset ID**（或網頁 Creator Dashboard）
3. 手動整理成 `TSA2024Q1|137144300741977` 貼到 `data/tsa-image-ids-paste.txt`
4. 執行 `parse-tsa-output.mjs` + `patch-question-database-tsa.mjs`

已知錨點（供核對）：

- `TSA2024Q1` → `137144300741977`
- `TSA2024Q10` → `115500650359874`

---

## 五、檔案說明

| 檔案 | 用途 |
|------|------|
| `data/tsa-image-ids.json` | **單一真相**：檔名 → Asset ID |
| `data/tsa-filename-order.json` | 160 個檔名（字串排序，僅參考） |
| `tools/studio/01_ImportLocalTSA_BuildMap.luau` | 本地匯入 + 輸出對照表 |
| `tools/studio/02_ExportDecalIdsOnly.luau` | 僅匯出 Decal 內 ID |
| `tools/parse-tsa-output.mjs` | Output 貼文 → JSON |
| `tools/patch-question-database-tsa.mjs` | JSON → 寫入 questionDatabase |

---

## 六、之後新增 TSA 題圖

1. PNG 命名：`TSA{年}Q{題號}.png`（例 `TSA2026Q1.png`）
2. 放入 `初中題庫/TSA/2026TSA/`
3. 跑 **01_ImportLocalTSA_BuildMap** → 更新 JSON
4. 跑 **patch-question-database-tsa.mjs**
5. **不要**再依賴 Decal / Import Queue

---

## 七、可刪除的東西（取得 ID 後）

- `ServerStorage/TSAImages` 內 160 個 Decal（遊戲只用 `rbxassetid` 字串）
- Asset Manager 內重複上傳的舊圖（若用方案三重新匯入）

---

## 八、questionDatabase 欄位約定

```javascript
{
  "Note": "TSA_ALL_1",
  "GUID": "2024TSA/TSA2024Q1",      // 保留，對應本地路徑語意
  "rbxImageId": "rbxassetid://137144300741977",  // Roblox 專用
  ...
}
```

Roblox 端讀 `rbxImageId`；RPG Maker / MZ 仍用 `GUID` 路徑。
