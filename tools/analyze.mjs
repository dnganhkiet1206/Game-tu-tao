import { AnalysisHandle } from "@gdscript-analyzer/core";
import { readFileSync, readdirSync, statSync } from "node:fs";
import { join, relative } from "node:path";

// Semantic analysis of every .gd file with the Godot-faithful analyzer.
// Setup:  npm i @gdscript-analyzer/core   then:  node tools/analyze.mjs
import { fileURLToPath } from "node:url";
import { dirname } from "node:path";
const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");

function walk(dir, out = []) {
  for (const name of readdirSync(dir)) {
    const p = join(dir, name);
    const st = statSync(p);
    if (st.isDirectory()) {
      if (![".git", ".godot", "node_modules", "build"].includes(name)) walk(p, out);
    } else if (name.endsWith(".gd")) out.push(p);
  }
  return out;
}

const az = new AnalysisHandle();
az.setProjectConfig(readFileSync(join(ROOT, "project.godot"), "utf8"));

const files = walk(ROOT).sort();
const texts = new Map();
for (const f of files) {
  const res = "res://" + relative(ROOT, f).replaceAll("\\", "/");
  const text = readFileSync(f, "utf8");
  texts.set(res, text);
  az.openDocument(res, text, res);
}
az.setWorkspaceComplete(true);
az.setWarningOverride("engine-defaults");

function lineOf(text, byteOffset) {
  const buf = Buffer.from(text, "utf8").subarray(0, byteOffset).toString("utf8");
  return buf.split("\n").length;
}

let errors = 0, warnings = 0;
for (const [res, text] of texts) {
  const diags = az.diagnostics(res);
  if (!diags || diags.length === 0) continue;
  const shown = [];
  for (const d of diags) {
    const sevRaw = (d.severity ?? d.level ?? "?").toString().toLowerCase();
    const sev = sevRaw.includes("err") ? "ERROR" : sevRaw.includes("warn") ? "warn" : sevRaw;
    const off = d.range?.start ?? d.start ?? d.offset ?? 0;
    const line = typeof off === "number" ? lineOf(text, off) : "?";
    const msg = d.message ?? JSON.stringify(d);
    const code = d.code ?? "";
    if (sev === "ERROR") errors++; else warnings++;
    shown.push(`  ${sev} L${line} [${code}] ${msg}`);
  }
  if (shown.length) {
    console.log(res.replace("res://", ""));
    for (const s of shown) console.log(s);
  }
}
console.log(`\n=== TOTAL: ${errors} errors, ${warnings} warnings across ${files.length} files ===`);
