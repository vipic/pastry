import { readFileSync } from "node:fs";
import { pathToFileURL } from "node:url";

export function evaluateCoverage(summary, policy) {
  const units = summary?.data;
  if (!Array.isArray(units) || units.length !== 1 || !Array.isArray(units[0].files)) {
    throw new Error("覆盖率数据缺少唯一编译单元或文件明细");
  }
  const files = new Map();
  for (const file of units[0].files) {
    const marker = "/Sources/Pastry/";
    if (typeof file.filename !== "string" || !file.filename.includes(marker)) continue;
    const name = file.filename.slice(file.filename.lastIndexOf(marker) + marker.length);
    if (files.has(name)) throw new Error(`重复覆盖率文件：${name}`);
    files.set(name, file.summary?.lines);
  }
  if (!policy || Array.isArray(policy) || typeof policy !== "object" || !Object.keys(policy).length) {
    throw new Error("覆盖率策略不能为空");
  }
  const failures = [];
  const rows = [];
  for (const [name, minimum] of Object.entries(policy)) {
    if (!Number.isFinite(minimum) || minimum <= 0 || minimum > 100) throw new Error(`非法覆盖率门槛：${name}`);
    const lines = files.get(name);
    if (!lines || !Number.isInteger(lines.count) || !Number.isInteger(lines.covered) || lines.count <= 0 || lines.covered < 0 || lines.covered > lines.count) {
      failures.push(`${name}：缺少有效的非空覆盖率数据`);
      continue;
    }
    const percent = lines.covered / lines.count * 100;
    rows.push(`${name}：${percent.toFixed(2)}%（最低 ${minimum}%）`);
    if (percent < minimum) failures.push(`${name}：${percent.toFixed(2)}% < ${minimum}%`);
  }
  return { rows, failures };
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    const summary = JSON.parse(readFileSync(0, "utf8"));
    const policy = JSON.parse(readFileSync(new URL("./coverage-policy.json", import.meta.url), "utf8"));
    const result = evaluateCoverage(summary, policy);
    console.log(result.rows.join("\n"));
    if (result.failures.length) throw new Error(result.failures.join("\n"));
    console.log("关键业务与安全逻辑覆盖率门禁通过");
  } catch (error) {
    console.error(`覆盖率门禁失败：${error.message}`);
    process.exitCode = 1;
  }
}
