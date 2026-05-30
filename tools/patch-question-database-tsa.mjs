#!/usr/bin/env node
/**
 * 依 data/tsa-image-ids.json 為 questionDatabase.js 的 TSA_ALL 加上 rbxImageId
 */
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(__dirname, '..');
const MAP_PATH = path.join(ROOT, 'data', 'tsa-image-ids.json');
const DB_PATH = path.join(ROOT, 'questionDatabase.js');

const mapData = JSON.parse(fs.readFileSync(MAP_PATH, 'utf8'));
const images = mapData.images || {};
const mapCount = Object.keys(images).length;

if (mapCount === 0) {
  console.error('tsa-image-ids.json 沒有 images 資料');
  process.exit(1);
}

let db = fs.readFileSync(DB_PATH, 'utf8');
let patched = 0;
let missing = [];
let skipped = 0;

db = db.replace(
  /"GUID":\s*"((?:2024TSA|2025TSA)\/(TSA\d{4}Q\d+))"/g,
  (match, fullGuid, offset) => {
    const name = fullGuid.match(/TSA\d{4}Q\d+/)?.[0];
    if (!name) return match;

    const before = db.slice(Math.max(0, offset - 200), offset);
    if (before.includes('"rbxImageId"')) {
      skipped++;
      return match;
    }

    const id = images[name];
    if (!id) {
      missing.push(name);
      return match;
    }

    patched++;
    return `"rbxImageId": "rbxassetid://${id}",\n            "GUID": "${fullGuid}"`;
  }
);

fs.writeFileSync(DB_PATH, db, 'utf8');
console.log(`已更新 ${DB_PATH}`);
console.log(`加上 rbxImageId：${patched} 筆（已存在跳過：${skipped}）`);

if (missing.length > 0) {
  console.warn(`缺少對照的題目（${missing.length} 筆）：`);
  missing.slice(0, 10).forEach((n) => console.warn('  ' + n));
}
