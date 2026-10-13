import assert from "node:assert/strict";
import test from "node:test";
import { spawnSync } from "node:child_process";
import { evaluateCoverage } from "../../scripts/coverage_gate.mjs";

const policy = { "Core/Example.swift": 80 };
function report(covered, count = 10) {
  return { data: [{ files: [{ filename: "/repo/Sources/Pastry/Core/Example.swift", summary: { lines: { covered, count, percent: 100 } } }] }] };
}

test("按真实行计数执行门槛，边界通过、低一行失败，不信任 percent 字段", () => {
  assert.equal(evaluateCoverage(report(8), policy).failures.length, 0);
  assert.equal(evaluateCoverage(report(7), policy).failures.length, 1);
});

test("缺失、空文件或损坏计数不能通过门禁", () => {
  for (const input of [report(0, 0), report(11), report(-1), report(1.5), { data: [{ files: [] }] }]) {
    assert.equal(evaluateCoverage(input, policy).failures.length, 1);
  }
  assert.throws(() => evaluateCoverage({}, policy), /覆盖率数据/);
  assert.throws(() => evaluateCoverage(report(10), {}), /策略不能为空/);
  assert.throws(() => evaluateCoverage(report(10), { "Core/Example.swift": 0 }), /非法覆盖率/);
});

test("命令入口遇到损坏数据或缺少关键模块返回非零状态", () => {
  for (const input of ["not-json", JSON.stringify({ data: [{ files: [] }] })]) {
    const result = spawnSync(process.execPath, [new URL("../../scripts/coverage_gate.mjs", import.meta.url).pathname], { input, encoding: "utf8" });
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /覆盖率门禁失败/);
  }
});
