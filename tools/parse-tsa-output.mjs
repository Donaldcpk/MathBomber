#!/usr/bin/env node
/**
 * 將 Studio Output 貼文轉成 data/tsa-image-ids.json
 *
 * 支援格式：
 *   TSA2024Q1:rbxassetid://137144300741977
 *   TSA2024Q1|137144300741977
 *   ["TSA2024Q1"] = "137144300741977",
 */
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(__dirname, '..');
const OUT = path.join(ROOT, 'data', 'tsa-image-ids.json');

const inputPath = process.argv[2];
if (!inputPath) {
  console.error('用法: node tools/parse-tsa-output.mjs <貼文檔案路徑>');
  console.error('例: node tools/parse-tsa-output.mjs data/tsa-image-ids-paste.txt');
  process.exit(1);
}

const text = fs.readFileSync(path.resolve(inputPath), 'utf8');
const images = {};

const patterns = [
  /(TSA\d{4}Q\d+):rbxassetid:\/\/(\d+)/g,
  /(TSA\d{4}Q\d+)\|(\d+)/g,
  /\["(TSA\d{4}Q\d+)"\]\s*=\s*"(\d+)"/g,
  /"(TSA\d{4}Q\d+)"\s*:\s*"(\d+)"/g,
];

for (const re of patterns) {
  let m;
  while ((m = re.exec(text)) !== null) {
    images[m[1]] = m[2];
  }
}

const count = Object.keys(images).length;
if (count === 0) {
  console.error('未解析到任何 TSA 項目，請確認貼文格式');
  process.exit(1);
}

const payload = {
  _comment: '單一真相來源：TSA 題圖 → Roblox Asset ID',
  _updated: new Date().toISOString().slice(0, 10),
  _source: path.basename(inputPath),
  _count: count,
  images,
};

fs.writeFileSync(OUT, JSON.stringify(payload, null, 2) + '\n', 'utf8');
console.log(`已寫入 ${OUT}（${count} 筆）`);

const expected = 160;
if (count < expected) {
  console.warn(`警告：預期 ${expected} 筆，目前只有 ${count} 筆`);
}
