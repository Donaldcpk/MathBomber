import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(__dirname, '..');
const CSV_PATH = '/Users/cdlanod/Downloads/img id - 工作表1.csv';
const JSON_OUT_PATH = path.join(ROOT, 'data', 'tsa-image-ids.json');

try {
    const csvContent = fs.readFileSync(CSV_PATH, 'utf8');
    const lines = csvContent.split(/\r?\n/);
    const images = {};
    let count = 0;

    for (const line of lines) {
        if (!line.trim()) continue;
        const parts = line.split(',');
        if (parts.length < 2) continue;

        let name = parts[0].trim();
        const id = parts[1].trim();

        // 排除 CSV 表頭
        if (name === '圖片名稱' || id === '圖片 ID') continue;

        // 移除 "Images/" 前綴，如 Images/TSA2025Q3 -> TSA2025Q3
        name = name.replace(/^Images\//, '');

        if (name && id && /^\d+$/.test(id)) {
            images[name] = id;
            count++;
        }
    }

    const payload = {
        _comment: '單一真相來源：TSA 題圖 → Roblox Asset ID（從 img id - 工作表1.csv 解析）',
        _updated: new Date().toISOString().slice(0, 10),
        _source: 'img id - 工作表1.csv',
        _count: count,
        images
    };

    fs.writeFileSync(JSON_OUT_PATH, JSON.stringify(payload, null, 2) + '\n', 'utf8');
    console.log(`成功將 CSV 解析並寫入 ${JSON_OUT_PATH}，共 ${count} 筆圖片 ID。`);

} catch (err) {
    console.error(`解析 CSV 失敗：${err.message}`);
    process.exit(1);
}
