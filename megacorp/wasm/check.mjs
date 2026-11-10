import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";

const root = new URL("../..", import.meta.url).pathname;
const native = execFileSync(
  `${root}megacorp/bin/megacorp`,
  ["--engine-check"],
  { encoding: "utf8" }
);
const lines = native.split("\n").filter((line) => line.startsWith("engine-check"));
if (lines.length !== 2) {
  throw new Error(native);
}
const expected = lines.map((line) => line.trim().split(" ").pop());
const bytes = readFileSync(`${root}web/megacorp.wasm`);
const mod = await WebAssembly.instantiate(bytes, {});
const api = mod.instance.exports;
api.adainit();
api.megacorp_init(42);
function digest() {
  const view = new DataView(api.memory.buffer);
  const ptr = api.megacorp_state();
  const low = view.getUint32(ptr + 16, true);
  const high = view.getUint32(ptr + 20, true);
  return high.toString(16).padStart(8, "0")
    + low.toString(16).padStart(8, "0");
}
const day0 = digest();
api.megacorp_step(10);
const day10 = digest();
if (day0 !== expected[0] || day10 !== expected[1]) {
  throw new Error(`${day0} ${day10} vs ${expected.join(" ")}`);
}
console.log(JSON.stringify({ day0, day10, match: true }));
