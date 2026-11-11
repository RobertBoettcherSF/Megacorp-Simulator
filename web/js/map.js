"use strict";

// Drawing only. Tile ids, terrain, height, and flags come from the
// Ada export. The atlas geometry comes from assets/tiles.json.
const COLOUR = {
  ".": [112, 146, 104],
  "+": [72, 72, 78],
  "=": [186, 178, 164],
  "B": [154, 82, 60],
  "~": [46, 116, 166]
};

const CELL = 5;

let mapData = null;
let tileset = null;
let atlasPixels = null;
let atlasWidth = 0;
let view = "iso";
let tilePx = 6;
let isoScale = 1;
let selectedPath = 0;
let tick = 0;
let timer = null;

const STEP = {
  north: [0, -1],
  east: [1, 0],
  south: [0, 1],
  west: [-1, 0],
  north_east: [1, -1],
  south_east: [1, 1],
  south_west: [-1, 1],
  north_west: [-1, -1]
};

const ANGLE = {
  east: 0,
  south_east: Math.PI / 4,
  south: Math.PI / 2,
  south_west: (3 * Math.PI) / 4,
  west: Math.PI,
  north_west: (-3 * Math.PI) / 4,
  north: -Math.PI / 2,
  north_east: -Math.PI / 4
};

function shade(code, level) {
  const base = COLOUR[code] || [255, 0, 200];
  const scale = 0.48 + (level / 15) * 0.72;
  return base.map((channel) => {
    const value = Math.round(channel * scale);
    return Math.max(0, Math.min(255, value));
  });
}

function cellAt(data, x, y) {
  const row = data.rows[y - 1];
  const at = (x - 1) * CELL;
  const code = row.charAt(at);
  const level = parseInt(row.charAt(at + 1), 16);
  const flags = parseInt(row.charAt(at + 2), 16);
  const tileId = parseInt(row.slice(at + 3, at + 5), 16);
  const legend = data.legend || {};
  return {
    code,
    name: legend[code] || code,
    level,
    tileId,
    walk: (flags & 1) !== 0,
    drive: (flags & 2) !== 0
  };
}

function paintLegend(data) {
  const host = document.getElementById("legend");
  host.replaceChildren();
  [".", "+", "=", "B", "~"].forEach((code) => {
    if (!data.legend || !data.legend[code]) {
      return;
    }
    const item = document.createElement("span");
    item.className = "swatch";
    const chip = document.createElement("span");
    chip.className = "chip";
    const rgb = shade(code, 4);
    chip.style.background = `rgb(${rgb[0]},${rgb[1]},${rgb[2]})`;
    item.append(chip, document.createTextNode(data.legend[code]));
    host.append(item);
  });
}

function drawFlat(ctx) {
  const canvas = ctx.canvas;
  canvas.width = mapData.width * tilePx;
  canvas.height = mapData.height * tilePx;
  for (let y = 1; y <= mapData.height; y += 1) {
    const row = mapData.rows[y - 1];
    for (let x = 1; x <= mapData.width; x += 1) {
      const at = (x - 1) * CELL;
      const level = parseInt(row.charAt(at + 1), 16);
      const rgb = shade(row.charAt(at), level);
      ctx.fillStyle = `rgb(${rgb[0]},${rgb[1]},${rgb[2]})`;
      ctx.fillRect((x - 1) * tilePx, (y - 1) * tilePx, tilePx, tilePx);
    }
  }
  document.getElementById("zoom-label").textContent = `${tilePx} px`;
  drawPath(ctx);
  drawVehicles(ctx);
  drawPeds(ctx);
  drawShots(ctx);
  drawItem(ctx);
}

function anchor(x, y, scale) {
  const halfW = (tileset.tile_width * scale) / 2;
  const halfH = (tileset.diamond_height * scale) / 2;
  const cellH = tileset.cell_height * scale;
  const originX = mapData.height * halfW;
  const originY = cellH;
  const x0 = x - 1;
  const y0 = y - 1;
  return {
    sx: originX + (x0 - y0) * halfW,
    sy: originY + (x0 + y0) * halfH,
    halfW,
    cellH
  };
}

function canvasSize(scale) {
  const halfW = (tileset.tile_width * scale) / 2;
  const halfH = (tileset.diamond_height * scale) / 2;
  const cellH = tileset.cell_height * scale;
  return {
    width: (mapData.width + mapData.height) * halfW,
    height: cellH + (mapData.width + mapData.height - 2) * halfH
  };
}

function drawIso(ctx) {
  const scale = isoScale;
  const size = canvasSize(scale);
  const canvas = ctx.canvas;
  canvas.width = size.width;
  canvas.height = size.height;
  const tw = tileset.tile_width;
  const ch = tileset.cell_height;
  for (let y = 1; y <= mapData.height; y += 1) {
    for (let x = 1; x <= mapData.width; x += 1) {
      const cell = cellAt(mapData, x, y);
      const tile = tileset.byId[cell.tileId];
      const spot = anchor(x, y, scale);
      ctx.drawImage(
        tileset.image,
        tile.column * tw,
        tile.row * ch,
        tw,
        ch,
        spot.sx - spot.halfW,
        spot.sy - spot.cellH,
        tw * scale,
        ch * scale
      );
    }
  }
  document.getElementById("zoom-label").textContent = `${scale}×`;
  drawPath(ctx);
  drawVehicles(ctx);
  drawPeds(ctx);
  drawShots(ctx);
  drawItem(ctx);
}

function currentPath() {
  if (!mapData || !mapData.paths || mapData.paths.length === 0) {
    return null;
  }
  return mapData.paths[selectedPath] || mapData.paths[0];
}

function fillPaths(data) {
  const select = document.getElementById("path");
  select.replaceChildren();
  selectedPath = 0;
  tick = 0;
  stopPlayback();
  showTick();
  (data.paths || []).forEach((path, index) => {
    const option = document.createElement("option");
    option.value = String(index);
    option.textContent = `${path.label} (${path.status})`;
    select.append(option);
  });
  if (!data.paths || data.paths.length === 0) {
    refreshStatus();
    return;
  }
  refreshStatus();
}

function flatCenter(x, y) {
  return {
    x: (x - 0.5) * tilePx,
    y: (y - 0.5) * tilePx
  };
}

function isoCenter(x, y) {
  const cell = cellAt(mapData, x, y);
  const spot = anchor(x, y, isoScale);
  const localY = (tileset.cell_height - 1)
    - cell.level * tileset.level_px
    - tileset.diamond_height / 2;
  return {
    x: spot.sx,
    y: (spot.sy - spot.cellH) + localY * isoScale
  };
}

function markerPoint(x, y) {
  if (view === "iso") {
    return isoCenter(x, y);
  }
  return flatCenter(x, y);
}

function drawPath(ctx) {
  const path = currentPath();
  if (!path) {
    return;
  }
  const points = path.status === "found"
    ? path.tiles
    : [path.start, path.goal];
  ctx.save();
  ctx.lineWidth = view === "iso" ? 3 * isoScale : Math.max(2, tilePx / 3);
  ctx.strokeStyle = "#ffe14a";
  ctx.fillStyle = "#ffe14a";
  ctx.lineJoin = "round";
  ctx.lineCap = "round";
  ctx.beginPath();
  points.forEach((tile, index) => {
    const point = markerPoint(tile.x, tile.y);
    if (index === 0) {
      ctx.moveTo(point.x, point.y);
    } else {
      ctx.lineTo(point.x, point.y);
    }
  });
  if (path.status === "found") {
    ctx.stroke();
  }
  const start = markerPoint(path.start.x, path.start.y);
  const goal = markerPoint(path.goal.x, path.goal.y);
  const radius = view === "iso" ? 4 * isoScale : Math.max(3, tilePx / 2);
  ctx.fillStyle = "#7dffa1";
  ctx.beginPath();
  ctx.arc(start.x, start.y, radius, 0, Math.PI * 2);
  ctx.fill();
  ctx.fillStyle = "#ff6b6b";
  ctx.beginPath();
  ctx.arc(goal.x, goal.y, radius, 0, Math.PI * 2);
  ctx.fill();
  ctx.restore();
}

function currentMotion() {
  const path = currentPath();
  if (!path || !mapData || !mapData.motion) {
    return null;
  }
  return mapData.motion.find((item) => item.label === path.label) || null;
}

function frameAt(ped, at) {
  if (!ped.frames || ped.frames.length === 0) {
    return null;
  }
  const last = ped.frames.length - 1;
  return ped.frames[Math.max(0, Math.min(at, last))];
}

function maxTick() {
  const motion = currentMotion();
  if (!motion) {
    return 0;
  }
  let max = 0;
  motion.peds.forEach((ped) => {
    if (ped.frames && ped.frames.length > 0) {
      max = Math.max(max, ped.frames[ped.frames.length - 1].t);
    }
  });
  (motion.vehicles || []).forEach((car) => {
    if (car.frames && car.frames.length > 0) {
      max = Math.max(max, car.frames[car.frames.length - 1].t);
    }
  });
  return max;
}

function showTick() {
  const node = document.getElementById("tick");
  if (node) {
    node.textContent = String(tick);
  }
  const panel = document.getElementById("queue");
  if (!panel) {
    return;
  }
  const motion = currentMotion();
  const frames = motion && motion.peds && motion.peds[0]
    && motion.peds[0].frames;
  if (!frames || frames.length === 0 || frames[0].action === undefined) {
    panel.textContent = "No action queue on this trace.";
    return;
  }
  panel.textContent = motion.peds.map((ped) => {
    const frame = frameAt(ped, tick);
    if (!frame) {
      return "";
    }
    const action = frame.action || "(none)";
    const mood = frame.mood ? ` [${frame.mood}]` : "";
    const rest = frame.queue && frame.queue.length
      ? frame.queue.join(", ")
      : "(none)";
    const hp = typeof frame.health === "number"
      ? ` hp ${frame.health}${frame.alive === false ? " down" : ""} ammo ${frame.ammo}`
      : "";
    return `Ped ${ped.id}: ${action}${mood}${hp} — remaining: ${rest}`;
  }).filter(Boolean).join("   ");
  if (motion.vehicles) {
    const cars = motion.vehicles.map((car) => {
      const frame = frameAt(car, tick);
      if (!frame) {
        return "";
      }
      const state = frame.intact === false ? "wrecked" : frame.state;
      return `${car.kind} ${car.id}: ${state} hp ${frame.health}`;
    }).filter(Boolean).join("   ");
    if (cars) {
      panel.textContent = `${panel.textContent}   ${cars}`;
    }
  }
  if (motion.goals && motion.goal_ticks) {
    const row = motion.goal_ticks[Math.max(0, Math.min(tick, motion.goal_ticks.length - 1))];
    const text = motion.goals.map((goal, index) => {
      const done = row && row.done && row.done[index];
      return `${goal.name}: ${done ? "done" : "open"}`;
    }).join("   ");
    if (text) {
      panel.textContent = `${text}   ${panel.textContent}`;
    }
  }
}

function stopPlayback() {
  if (timer !== null) {
    clearInterval(timer);
    timer = null;
  }
}

function refreshStatus() {
  const status = document.getElementById("path-status");
  if (!mapData || !mapData.paths || mapData.paths.length === 0) {
    status.textContent = "Paths and ped motion are precomputed by Ada.";
    return;
  }
  if (currentMotion()) {
    if (currentMotion().label === "Mission"
      || currentMotion().label === "Generated") {
      status.textContent =
        "The mission trace is precomputed by Ada, not run in the browser.";
    } else if (currentMotion().item) {
      status.textContent =
        "Paths, ped motion, and action queues are precomputed by Ada, not run in the browser.";
    } else if (currentMotion().label === "Firefight") {
      status.textContent =
        "Paths, ped motion, and shots are precomputed by Ada, not run in the browser.";
    } else if (currentMotion().label === "Vehicles") {
      status.textContent =
        "Paths, driving, and shots are precomputed by Ada, not run in the browser.";
    } else if (currentMotion().label === "Behaviour") {
      status.textContent =
        "Moods, patrols, and shots are precomputed by Ada, not run in the browser.";
    } else {
      status.textContent =
        "Paths and ped motion are precomputed by Ada, not run in the browser.";
    }
    return;
  }
  status.textContent =
    "Paths are precomputed by Ada. This query has no ped trace.";
}

function pedPoint(frame, steps) {
  const delta = STEP[frame.facing] || [0, 0];
  const fraction = steps > 0 ? frame.along / steps : 0;
  if (view === "iso") {
    const from = isoCenter(frame.x, frame.y);
    const nx = frame.x + delta[0];
    const ny = frame.y + delta[1];
    if (fraction === 0
        || nx < 1 || ny < 1
        || nx > mapData.width || ny > mapData.height) {
      return from;
    }
    const to = isoCenter(nx, ny);
    return {
      x: from.x + (to.x - from.x) * fraction,
      y: from.y + (to.y - from.y) * fraction
    };
  }
  return {
    x: (frame.x + delta[0] * fraction - 0.5) * tilePx,
    y: (frame.y + delta[1] * fraction - 0.5) * tilePx
  };
}

function drawPeds(ctx) {
  const motion = currentMotion();
  if (!motion) {
    return;
  }
  const steps = motion.steps_per_tile;
  ctx.save();
  motion.peds.forEach((ped) => {
    const frame = frameAt(ped, tick);
    if (!frame) {
      return;
    }
    const at = pedPoint(frame, steps);
    const radius = view === "iso" ? 5 * isoScale : Math.max(4, tilePx * 0.45);
    if (frame.state === "riding") {
      const nudge = (ped.id % 2 === 0 ? 1 : -1) * radius * 0.7;
      at.x += nudge;
    }
    const angle = ANGLE[frame.facing] ?? 0;
    const ink = { 1: "#ffe14a", 2: "#7fd0ff", 3: "#ff8f6b", 4: "#d7c4ff" };
    const roleInk = {
      civilian: "#ffe14a",
      guard: "#e08a3c",
      police: "#7fd0ff",
      hostile: "#ff5a5a",
      agent: "#d7c4ff"
    };
    ctx.fillStyle = (ped.role && roleInk[ped.role]) || ink[ped.id] || "#f4f1ea";
    ctx.beginPath();
    ctx.arc(at.x, at.y, radius, 0, Math.PI * 2);
    ctx.fill();
    ctx.strokeStyle = "#1b140c";
    ctx.lineWidth = Math.max(2, radius * 0.45);
    ctx.beginPath();
    ctx.moveTo(at.x, at.y);
    ctx.lineTo(
      at.x + Math.cos(angle) * radius * 1.7,
      at.y + Math.sin(angle) * radius * 1.7
    );
    ctx.stroke();
    if (typeof frame.health === "number") {
      const bar = radius * 2.4;
      const thick = Math.max(3, radius * 0.35);
      const left = at.x - bar / 2;
      const top = at.y - radius * 2.4;
      ctx.fillStyle = "#241c18";
      ctx.fillRect(left, top, bar, thick);
      ctx.fillStyle = frame.alive === false ? "#8a847c" : "#5dce6a";
      ctx.fillRect(left, top, bar * Math.max(0, frame.health) / 100, thick);
    }
  });
  ctx.restore();
}

function drawVehicles(ctx) {
  const motion = currentMotion();
  if (!motion || !motion.vehicles) {
    return;
  }
  const steps = motion.steps_per_tile;
  ctx.save();
  motion.vehicles.forEach((car) => {
    const frame = frameAt(car, tick);
    if (!frame) {
      return;
    }
    const at = pedPoint(frame, steps);
    const radius = view === "iso" ? 6 * isoScale : Math.max(4, tilePx * 0.5);
    const length = (car.kind === "van" ? 2.6 : 1.8) * radius;
    const width = radius;
    const angle = ANGLE[frame.facing] ?? 0;
    ctx.save();
    ctx.translate(at.x, at.y);
    ctx.rotate(angle);
    ctx.fillStyle = frame.intact === false
      ? "#6e675f"
      : (car.kind === "van" ? "#e0a15a" : "#2fbfa8");
    ctx.strokeStyle = "#1b140c";
    ctx.lineWidth = Math.max(1, radius * 0.18);
    ctx.fillRect(-length / 2, -width / 2, length, width);
    ctx.strokeRect(-length / 2, -width / 2, length, width);
    ctx.restore();
    const maxHealth = frame.max || 1;
    const bar = length;
    const thick = Math.max(3, radius * 0.28);
    const left = at.x - bar / 2;
    const top = at.y + radius * 1.35;
    ctx.fillStyle = "#241c18";
    ctx.fillRect(left, top, bar, thick);
    ctx.fillStyle = frame.intact === false ? "#8a847c" : "#5dce6a";
    const fraction = Math.max(0, frame.health) / maxHealth;
    ctx.fillRect(left, top, bar * fraction, thick);
  });
  ctx.restore();
}

function drawShots(ctx) {
  const motion = currentMotion();
  if (!motion) {
    return;
  }
  ctx.save();
  ctx.lineWidth = view === "iso" ? 2 * isoScale : 2;
  motion.peds.forEach((ped) => {
    const frame = frameAt(ped, tick);
    if (!frame || !frame.shot) {
      return;
    }
    const from = markerPoint(frame.x, frame.y);
    const to = markerPoint(frame.shot.x, frame.shot.y);
    ctx.strokeStyle = frame.shot.hit ? "#ff5a5a" : "#9aa4b2";
    ctx.setLineDash(frame.shot.hit ? [] : [6, 4]);
    ctx.beginPath();
    ctx.moveTo(from.x, from.y);
    ctx.lineTo(to.x, to.y);
    ctx.stroke();
  });
  ctx.restore();
}

function drawItem(ctx) {
  const motion = currentMotion();
  if (!motion || !motion.item) {
    return;
  }
  const frame = frameAt(motion.peds[0], tick);
  if (!frame || frame.item_present === false) {
    return;
  }
  const at = markerPoint(motion.item.x, motion.item.y);
  const size = view === "iso" ? 7 * isoScale : Math.max(5, tilePx * 0.55);
  ctx.save();
  ctx.fillStyle = "#f2c14e";
  ctx.strokeStyle = "#1b140c";
  ctx.lineWidth = Math.max(1, size / 6);
  ctx.beginPath();
  ctx.moveTo(at.x, at.y - size);
  ctx.lineTo(at.x + size, at.y);
  ctx.lineTo(at.x, at.y + size);
  ctx.lineTo(at.x - size, at.y);
  ctx.closePath();
  ctx.fill();
  ctx.stroke();
  ctx.restore();
}

function nearestPrepared(x, y) {
  let best = 0;
  let bestDistance = Number.POSITIVE_INFINITY;
  (mapData.paths || []).forEach((path, index) => {
    const start = Math.abs(path.start.x - x) + Math.abs(path.start.y - y);
    const goal = Math.abs(path.goal.x - x) + Math.abs(path.goal.y - y);
    const distance = Math.min(start, goal);
    if (distance < bestDistance) {
      bestDistance = distance;
      best = index;
    }
  });
  return best;
}

let worldData = null;
let campaignData = null;
let campaignDay = 0;
let showWorld = false;

let wasmExports = null;
let wasmLive = false;
let strategicId = 0;
let writingDay = false;
let wasmTimer = null;

function readAscii(view, offset, length) {
  let text = "";
  for (let i = 0; i < length; i += 1) {
    const code = view.getUint8(offset + i);
    if (code === 0) {
      break;
    }
    text += String.fromCharCode(code);
  }
  return text;
}

function hexByte(value) {
  return value.toString(16).padStart(2, "0");
}

function readWasmWorld() {
  const view = new DataView(wasmExports.memory.buffer);
  let cursor = wasmExports.megacorp_state();
  const day = view.getUint32(cursor, true);
  cursor += 4;
  const regionCount = view.getUint32(cursor, true);
  cursor += 4;
  const corpCount = view.getUint32(cursor, true);
  cursor += 4;
  const linkCount = view.getUint32(cursor, true);
  cursor += 4;
  cursor += 8;
  const corporations = [];
  for (let i = 0; i < corpCount; i += 1) {
    const cash = view.getUint32(cursor, true);
    cursor += 4;
    const red = view.getUint8(cursor);
    cursor += 1;
    const green = view.getUint8(cursor);
    cursor += 1;
    const blue = view.getUint8(cursor);
    cursor += 1;
    const eliminated = view.getUint8(cursor) === 1;
    cursor += 1;
    const nameLength = view.getUint8(cursor);
    cursor += 1;
    const name = readAscii(view, cursor, nameLength);
    cursor += 24;
    corporations.push({
      id: i + 1,
      name,
      colour: `#${hexByte(red)}${hexByte(green)}${hexByte(blue)}`,
      cash,
      eliminated
    });
  }
  const regions = [];
  for (let i = 0; i < regionCount; i += 1) {
    const x = view.getUint16(cursor, true);
    cursor += 2;
    const y = view.getUint16(cursor, true);
    cursor += 2;
    const owner = view.getUint8(cursor);
    cursor += 1;
    const tax = view.getUint8(cursor);
    cursor += 1;
    const unrest = view.getUint8(cursor);
    cursor += 1;
    const defence = view.getUint8(cursor);
    cursor += 1;
    const tech = view.getUint8(cursor);
    cursor += 1;
    const population = view.getUint16(cursor, true);
    cursor += 2;
    const nameLength = view.getUint8(cursor);
    cursor += 1;
    const name = readAscii(view, cursor, nameLength);
    cursor += 24;
    regions.push({
      id: i + 1,
      name,
      x,
      y,
      population,
      tech,
      tax,
      unrest,
      defence,
      owner,
      city: `region-${i + 1}.json`
    });
  }
  const links = [];
  for (let i = 0; i < linkCount; i += 1) {
    const a = view.getUint16(cursor, true);
    cursor += 2;
    const b = view.getUint16(cursor, true);
    cursor += 2;
    links.push({ a, b });
  }
  return { day, corporations, regions, links };
}

function readBrief() {
  if (!wasmExports || !wasmExports.megacorp_brief) {
    return null;
  }
  const view = new DataView(wasmExports.memory.buffer);
  let cursor = wasmExports.megacorp_brief();
  cursor += 1;
  const regionCount = view.getUint8(cursor);
  cursor += 1;
  const corpCount = view.getUint8(cursor);
  cursor += 1;
  const newsCount = view.getUint8(cursor);
  cursor += 1;
  const regions = [];
  for (let i = 0; i < regionCount; i += 1) {
    const visited = view.getUint8(cursor) === 1;
    cursor += 1;
    const income = view.getUint16(cursor, true);
    cursor += 2;
    const influence = view.getUint8(cursor);
    cursor += 1;
    const pressure = view.getInt16(cursor, true);
    cursor += 2;
    const recipeCode = view.getUint8(cursor);
    cursor += 1;
    const nameLength = view.getUint8(cursor);
    cursor += 1;
    const recipe = readAscii(view, cursor, nameLength);
    cursor += 16;
    regions.push({
      visited, income, influence, pressure, recipeCode, recipe
    });
  }
  const corps = [];
  for (let i = 0; i < corpCount; i += 1) {
    const count = view.getUint8(cursor);
    cursor += 1;
    const strength = view.getUint16(cursor, true);
    cursor += 2;
    cursor += 1;
    corps.push({ count, strength });
  }
  const news = [];
  for (let i = 0; i < newsCount; i += 1) {
    const length = view.getUint8(cursor);
    cursor += 1;
    news.push(readAscii(view, cursor, length));
    cursor += 79;
  }
  return { regions, corps, news };
}

function showStrategic(regionId) {
  const world = readWasmWorld();
  const brief = readBrief();
  if (!brief || !world.regions[regionId - 1]) {
    return;
  }
  strategicId = regionId;
  const region = world.regions[regionId - 1];
  const row = brief.regions[regionId - 1];
  const owner = world.corporations[region.owner - 1];
  const panel = document.getElementById("region-panel");
  panel.dataset.region = String(regionId);
  panel.dataset.owner = owner ? owner.name : "";
  panel.dataset.population = String(region.population);
  panel.dataset.unrest = String(region.unrest);
  panel.dataset.influence = String(row.influence);
  panel.dataset.income = String(row.income);
  panel.dataset.pressure = String(row.pressure);
  panel.dataset.recipe = row.recipe;
  panel.dataset.visited = row.visited ? "yes" : "no";
  panel.replaceChildren();
  const lines = [
    region.name,
    `Owner ${owner ? owner.name : "none"}`,
    `Population ${region.population}`,
    `Unrest ${region.unrest}`,
    `Influence ${row.influence}`,
    `Income ${row.income}`,
    `AI pressure ${row.pressure}`,
    `Recipe ${row.recipe}`,
    row.visited ? "Visited" : "Unvisited"
  ];
  lines.forEach((text) => {
    const line = document.createElement("p");
    line.textContent = text;
    panel.appendChild(line);
  });
  const corps = document.getElementById("corp-panel");
  corps.replaceChildren();
  world.corporations.forEach((corp, index) => {
    const line = document.createElement("p");
    const held = brief.corps[index];
    line.textContent =
      `${corp.name}: ${held.count} regions, strength ${held.strength}`;
    corps.appendChild(line);
  });
  const log = document.getElementById("news");
  log.textContent = brief.news.length
    ? brief.news.join(" · ")
    : "No border fights yet.";
  document.getElementById("sheet").classList.add("open");
}

function readFixed(view, offset, width) {
  const length = view.getUint8(offset);
  const used = length < width ? length : width;
  return readAscii(view, offset + 1, used);
}

function readOffice() {
  if (!wasmExports || !wasmExports.megacorp_office) {
    return null;
  }
  const view = new DataView(wasmExports.memory.buffer);
  let cursor = wasmExports.megacorp_office();
  cursor += 1;
  const funds = view.getInt32(cursor, true);
  cursor += 4;
  const research = view.getUint16(cursor, true);
  cursor += 2;
  const grant = view.getUint16(cursor, true);
  cursor += 2;
  const debt = view.getUint8(cursor) === 1;
  cursor += 1;
  const count = view.getUint8(cursor);
  cursor += 1;
  const canHire = view.getUint8(cursor) === 1;
  cursor += 1;
  const hirePrice = view.getUint16(cursor, true);
  cursor += 2;
  const upkeep = view.getUint16(cursor, true);
  cursor += 2;
  const income = view.getUint16(cursor, true);
  cursor += 2;
  const nodes = [];
  for (let i = 0; i < 5; i += 1) {
    const open = view.getUint8(cursor) === 1;
    cursor += 1;
    const cost = view.getUint16(cursor, true);
    cursor += 2;
    const name = readFixed(view, cursor, 8);
    cursor += 9;
    nodes.push({ open, cost, name });
  }
  const roster = [];
  for (let i = 0; i < count; i += 1) {
    const alive = view.getUint8(cursor) === 1;
    cursor += 1;
    const health = view.getUint8(cursor);
    cursor += 1;
    const accuracy = view.getUint8(cursor);
    cursor += 1;
    const speed = view.getUint8(cursor);
    cursor += 1;
    const morale = view.getUint8(cursor);
    cursor += 1;
    const augments = view.getUint8(cursor);
    cursor += 1;
    cursor += 1;
    const armour = view.getUint8(cursor);
    cursor += 1;
    const name = readFixed(view, cursor, 12);
    cursor += 13;
    const weapon = readFixed(view, cursor, 6);
    cursor += 7;
    roster.push({
      alive, health, accuracy, speed, morale, augments, armour, name, weapon
    });
  }
  const picks = [];
  for (let i = 0; i < 4; i += 1) {
    picks.push(view.getUint8(cursor));
    cursor += 1;
  }
  const hiring = view.getUint8(cursor) === 1;
  cursor += 1;
  const candidate = readFixed(view, cursor, 12);
  cursor += 13;
  const candidateStats = {
    health: view.getUint8(cursor),
    accuracy: view.getUint8(cursor + 1),
    speed: view.getUint8(cursor + 2),
    morale: view.getUint8(cursor + 3)
  };
  return {
    funds, research, grant, debt, count, canHire, hirePrice,
    upkeep, income, nodes, roster, picks, hiring, candidate, candidateStats
  };
}

const MENU_ACT = {
  up: 0,
  down: 1,
  activate: 2,
  back: 3,
  scenario: 4,
  free: 5,
  continue: 6,
  brief: 7,
  start: 8,
  cancel: 9,
  ack: 10,
  pause: 11,
  resume: 12,
  save: 13,
  quit: 14,
  speed: 15,
  volume: 16,
  roll: 17,
  digit: 18,
  clear: 19,
  reroll: 20,
  openNew: 21,
  settings: 22,
  credits: 23,
  effects: 24,
  music: 25
};

function takeText(view, cursor, width) {
  const length = view.getUint8(cursor);
  const used = length < width ? length : width;
  return {
    text: readAscii(view, cursor + 1, used),
    cursor: cursor + 1 + width
  };
}

function readMenu() {
  if (!wasmExports || !wasmExports.megacorp_menu) {
    return null;
  }
  const view = new DataView(wasmExports.memory.buffer);
  let cursor = wasmExports.megacorp_menu();
  cursor += 1;
  const screen = view.getUint8(cursor);
  cursor += 1;
  const choice = view.getUint8(cursor);
  cursor += 1;
  const saved = view.getUint8(cursor) === 1;
  cursor += 1;
  const speed = view.getUint8(cursor);
  cursor += 1;
  const volume = view.getUint8(cursor);
  cursor += 1;
  const effects = view.getUint8(cursor);
  cursor += 1;
  const music = view.getUint8(cursor);
  cursor += 1;
  const mode = view.getUint8(cursor);
  cursor += 1;
  const locked = view.getUint8(cursor) === 1;
  cursor += 1;
  const region = view.getUint16(cursor, true);
  cursor += 2;
  const typed = view.getInt32(cursor, true);
  cursor += 4;
  const scenario = view.getUint8(cursor);
  cursor += 1;
  const outcome = view.getUint8(cursor);
  cursor += 1;
  const casualties = view.getUint8(cursor);
  cursor += 1;
  const loot = view.getInt32(cursor, true);
  cursor += 4;
  const before = view.getInt32(cursor, true);
  cursor += 4;
  const after = view.getInt32(cursor, true);
  cursor += 4;
  const reward = view.getUint16(cursor, true);
  cursor += 2;
  const objective = takeText(view, cursor, 64);
  cursor = objective.cursor;
  const threat = takeText(view, cursor, 32);
  cursor = threat.cursor;
  const regionName = takeText(view, cursor, 24);
  cursor = regionName.cursor;
  const count = view.getUint8(cursor);
  cursor += 1;
  const scenarios = [];
  for (let i = 0; i < count; i += 1) {
    const seed = view.getInt32(cursor, true);
    cursor += 4;
    const name = takeText(view, cursor, 16);
    cursor = name.cursor;
    scenarios.push({ seed, name: name.text });
  }
  const creditsN = view.getUint8(cursor);
  cursor += 1;
  const credits = [];
  for (let i = 0; i < creditsN; i += 1) {
    const line = takeText(view, cursor, 72);
    cursor = line.cursor;
    credits.push(line.text);
  }
  const trouble = view.getUint8(cursor);
  return {
    screen, choice, saved, speed, volume, effects, music, mode, locked,
    region, typed,
    scenario, outcome, casualties, loot, before, after, reward,
    objective: objective.text,
    threat: threat.text,
    regionName: regionName.text,
    scenarios, credits, trouble
  };
}

let menuStamp = "";
let playOn = false;

function menuCommand(act, arg) {
  wasmExports.megacorp_command(12, act, arg || 0, 0, 0, 0);
  const menu = readMenu();
  if (menu && (menu.screen === 4 || menu.screen === 6)) {
    if (!playOn && typeof MegacorpPlay !== "undefined") {
      MegacorpPlay.start(wasmExports);
      playOn = true;
    }
    if (typeof MegacorpPlay !== "undefined") {
      MegacorpPlay.setSpeed(menu.speed, false);
    }
    showWorld = menu.screen === 4;
    document.getElementById("world").textContent =
      showWorld ? "City" : "World map";
    showWasmDay();
    draw();
  }
  paintMenu();
  if (window.MegacorpSound) {
    window.MegacorpSound.pump();
  }
}

function addSlider(parent, label, value, id, act) {
  const row = document.createElement("label");
  const name = document.createElement("span");
  name.id = id + "-label";
  name.textContent = `${label} ${value}`;
  const input = document.createElement("input");
  input.id = id;
  input.type = "range";
  input.min = "0";
  input.max = "100";
  input.value = String(value);
  input.addEventListener("input", () => {
    menuCommand(act, Number(input.value));
  });
  row.appendChild(name);
  row.appendChild(input);
  parent.appendChild(row);
}

function syncVolumes(menu) {
  const rows = [
    ["vol-master", "Master", menu.volume],
    ["vol-effects", "Effects", menu.effects],
    ["vol-music", "Music", menu.music]
  ];
  rows.forEach((row) => {
    const input = document.getElementById(row[0]);
    const name = document.getElementById(row[0] + "-label");
    if (name) {
      name.textContent = `${row[1]} ${row[2]}`;
    }
    if (input && document.activeElement !== input) {
      input.value = String(row[2]);
    }
  });
}

function addChoice(parent, label, index, picked, onClick) {
  const button = document.createElement("button");
  button.type = "button";
  button.textContent = label;
  button.title = label;
  if (index === picked) {
    button.className = "picked";
  }
  button.addEventListener("click", onClick);
  parent.appendChild(button);
}

function paintMenu() {
  const menu = readMenu();
  const root = document.getElementById("menu");
  const body = document.getElementById("menu-body");
  const title = document.getElementById("menu-title");
  if (!menu || !root || !body || !title) {
    return;
  }
  const overlay = menu.screen !== 4 && menu.screen !== 6;
  root.hidden = !overlay;
  const reroll = document.getElementById("reroll");
  if (reroll) {
    reroll.hidden = !(menu.screen === 4 && menu.mode === 1 && !menu.locked);
  }
  root.dataset.screen = String(menu.screen);
  root.dataset.outcome = String(menu.outcome);
  root.dataset.loot = String(menu.loot);
  root.dataset.casualties = String(menu.casualties);
  root.dataset.before = String(menu.before);
  root.dataset.after = String(menu.after);
  root.dataset.saved = menu.saved ? "yes" : "no";
  root.dataset.region = menu.regionName;
  root.dataset.objective = menu.objective;
  root.dataset.threat = menu.threat;
  root.dataset.reward = String(menu.reward);
  root.dataset.master = String(menu.volume);
  root.dataset.effects = String(menu.effects);
  root.dataset.music = String(menu.music);
  root.dataset.trouble = String(menu.trouble || 0);
  syncVolumes(menu);
  const stamp = [
    menu.screen, menu.choice, menu.saved, menu.speed,
    menu.typed, menu.outcome, menu.loot, menu.regionName, menu.objective,
    menu.trouble
  ].join(":");
  if (stamp === menuStamp) {
    return;
  }
  menuStamp = stamp;
  body.replaceChildren();
  const names = ["Title", "New game", "Settings", "Credits", "Map",
    "Briefing", "Mission", "Debrief", "Paused"];
  title.textContent = names[menu.screen] || "Megacorp";
  if (menu.screen === 0) {
    if (menu.trouble === 1) {
      const warn = document.createElement("p");
      warn.id = "save-error";
      warn.textContent = "That save could not be read. Start a new game.";
      body.appendChild(warn);
    }
    addChoice(body, "New game", 0, menu.choice, () => menuCommand(MENU_ACT.openNew, 0));
    if (menu.saved) {
      addChoice(body, "Continue", 1, menu.choice, () => menuCommand(MENU_ACT.continue, 0));
      addChoice(body, "Settings", 2, menu.choice, () => menuCommand(MENU_ACT.settings, 0));
      addChoice(body, "Credits", 3, menu.choice, () => menuCommand(MENU_ACT.credits, 0));
    } else {
      addChoice(body, "Settings", 1, menu.choice, () => menuCommand(MENU_ACT.settings, 0));
      addChoice(body, "Credits", 2, menu.choice, () => menuCommand(MENU_ACT.credits, 0));
    }
  } else if (menu.screen === 1) {
    menu.scenarios.forEach((item, index) => {
      addChoice(
        body,
        `Scenario ${item.name} (seed ${item.seed})`,
        index,
        menu.choice,
        () => menuCommand(MENU_ACT.scenario, index + 1)
      );
    });
    addChoice(body, "Roll a free-play seed", 3, menu.choice, () => menuCommand(MENU_ACT.roll, 0));
    addChoice(
      body,
      `Start free play ${menu.typed}`,
      4,
      menu.choice,
      () => menuCommand(MENU_ACT.free, menu.typed)
    );
    addChoice(body, "Back", 5, menu.choice, () => menuCommand(MENU_ACT.back, 0));
    const hint = document.createElement("p");
    hint.textContent = "Type a seed, or roll one. A scenario locks the world.";
    body.appendChild(hint);
  } else if (menu.screen === 2) {
    ["Pause", "Speed 1x", "Speed 2x", "Speed 4x"].forEach((label, index) => {
      addChoice(body, label, index, menu.choice, () => menuCommand(MENU_ACT.speed, [0, 1, 2, 4][index]));
    });
    addChoice(body, "Back", 4, menu.choice, () => menuCommand(MENU_ACT.back, 0));
    addSlider(body, "Master", menu.volume, "vol-master", MENU_ACT.volume);
    addSlider(body, "Effects", menu.effects, "vol-effects", MENU_ACT.effects);
    addSlider(body, "Music", menu.music, "vol-music", MENU_ACT.music);
  } else if (menu.screen === 3) {
    menu.credits.forEach((line) => {
      const row = document.createElement("p");
      row.textContent = line;
      body.appendChild(row);
    });
    addChoice(body, "Back", 0, menu.choice, () => menuCommand(MENU_ACT.back, 0));
  } else if (menu.screen === 5) {
    const info = document.createElement("p");
    info.textContent =
      `${menu.regionName}. ${menu.objective} Enemy estimate: ${menu.threat}.`
      + ` Reward ${menu.reward}.`;
    body.appendChild(info);
    const office = readOffice();
    if (office) {
      office.roster.forEach((agent) => {
        const row = document.createElement("p");
        row.textContent =
          `${agent.name} ${agent.alive ? "ready" : "dead"}`
          + ` ${agent.weapon} aug ${agent.augments} arm ${agent.armour}`;
        body.appendChild(row);
      });
      const squad = document.createElement("p");
      squad.textContent = `Squad ${office.picks.join(" ")}`;
      body.appendChild(squad);
    }
    addChoice(body, "Start", 0, menu.choice, () => menuCommand(MENU_ACT.start, 0));
    addChoice(body, "Cancel", 1, menu.choice, () => menuCommand(MENU_ACT.cancel, 0));
  } else if (menu.screen === 7) {
    const word = menu.outcome === 2 ? "won" : (menu.outcome === 3 ? "lost" : "timeout");
    const info = document.createElement("p");
    info.textContent =
      `Outcome ${word}. Casualties ${menu.casualties}.`
      + ` Loot ${menu.loot}. Funds ${menu.before} to ${menu.after}.`;
    body.appendChild(info);
    addChoice(body, "Return to the map", 0, menu.choice, () => menuCommand(MENU_ACT.ack, 0));
  } else if (menu.screen === 8) {
    addChoice(body, "Resume", 0, menu.choice, () => menuCommand(MENU_ACT.resume, 0));
    addChoice(body, "Save", 1, menu.choice, () => menuCommand(MENU_ACT.save, 0));
    addChoice(body, "Quit to title", 2, menu.choice, () => menuCommand(MENU_ACT.quit, 0));
  }
}

function paintOffice() {
  const office = readOffice();
  const finance = document.getElementById("finance-panel");
  const study = document.getElementById("research-panel");
  const roster = document.getElementById("roster-panel");
  if (!office || !finance || !study || !roster) {
    return;
  }
  finance.dataset.funds = String(office.funds);
  finance.dataset.research = String(office.research);
  finance.dataset.grant = String(office.grant);
  finance.dataset.debt = office.debt ? "yes" : "no";
  finance.dataset.income = String(office.income);
  finance.dataset.upkeep = String(office.upkeep);
  finance.dataset.roster = String(office.count);
  finance.dataset.hire = String(office.hirePrice);
  finance.replaceChildren();
  [
    `Funds ${office.funds}`,
    `Income ${office.income}`,
    `Upkeep ${office.upkeep}`,
    `Research grant ${office.grant}`,
    office.debt ? "Debt: hiring closed" : "Books are open"
  ].forEach((text) => {
    const line = document.createElement("p");
    line.textContent = text;
    finance.appendChild(line);
  });
  study.replaceChildren();
  office.nodes.forEach((node) => {
    const line = document.createElement("p");
    line.textContent =
      `${node.name} ${node.cost} ${node.open ? "open" : "locked"}`;
    study.appendChild(line);
  });
  roster.replaceChildren();
  const squad = document.createElement("p");
  squad.textContent = `Squad ${office.picks.join(" ")}`;
  roster.appendChild(squad);
  office.roster.forEach((agent, index) => {
    const line = document.createElement("p");
    const state = agent.alive ? "ready" : "dead";
    line.textContent =
      `${agent.name} ${state} hp ${agent.health}`
      + ` acc ${agent.accuracy} spd ${agent.speed}`
      + ` mor ${agent.morale} ${agent.weapon}`
      + ` aug ${agent.augments} arm ${agent.armour}`;
    roster.appendChild(line);
    if (agent.alive && wasmExports) {
      const send = document.createElement("button");
      send.type = "button";
      send.textContent = `Send ${agent.name}`;
      send.addEventListener("click", () => {
        const slot = office.picks.findIndex((pick) => pick === 0);
        const chosen = slot < 0 ? 1 : slot + 1;
        wasmExports.megacorp_command(10, chosen, index + 1, 0, 0, 0);
        showWasmDay();
      });
      roster.appendChild(send);
    }
  });
  if (office.hiring) {
    const next = document.createElement("p");
    next.textContent =
      `Next hire ${office.candidate}`
      + ` hp ${office.candidateStats.health}`
      + ` for ${office.hirePrice}`;
    roster.appendChild(next);
  }
}

function showWasmDay() {
  const world = readWasmWorld();
  worldData = world;
  const cash = world.corporations
    .map((corp) => `${corp.id}:${corp.cash}`)
    .join(" ");
  document.getElementById("day-label").textContent = String(world.day);
  document.getElementById("path-status").textContent =
    `Day ${world.day} cash ${cash}`;
  document.getElementById("engine").textContent = "engine: wasm";
  document.getElementById("seed-label").textContent = "world 42";
  const brief = readBrief();
  const log = document.getElementById("news");
  if (brief && log) {
    log.textContent = brief.news.length
      ? brief.news.join(" · ")
      : "No border fights yet.";
    const corps = document.getElementById("corp-panel");
    corps.replaceChildren();
    world.corporations.forEach((corp, index) => {
      const line = document.createElement("p");
      const held = brief.corps[index];
      line.textContent =
        `${corp.name}: ${held.count} regions, strength ${held.strength}`;
      corps.appendChild(line);
    });
  }
  paintOffice();
  if (strategicId > 0) {
    showStrategic(strategicId);
  }
}

function ownerId(region, index) {
  if (wasmLive) {
    return region.owner;
  }
  const frame = campaignData && campaignData.frames
    && campaignData.frames[campaignDay];
  if (frame && frame.owner && frame.owner[index] != null) {
    return frame.owner[index];
  }
  return region.owner;
}

function regionPoint(region, width, height) {
  let maxX = 1;
  let maxY = 1;
  worldData.regions.forEach((item) => {
    maxX = Math.max(maxX, item.x);
    maxY = Math.max(maxY, item.y);
  });
  const pad = 28;
  return {
    x: pad + (region.x / maxX) * (width - pad * 2),
    y: pad + (region.y / maxY) * (height - pad * 2)
  };
}

function nearestRegion(x, y, width, height) {
  let best = worldData.regions[0];
  let bestDistance = Number.POSITIVE_INFINITY;
  worldData.regions.forEach((region) => {
    const at = regionPoint(region, width, height);
    const distance = (at.x - x) ** 2 + (at.y - y) ** 2;
    if (distance < bestDistance) {
      bestDistance = distance;
      best = region;
    }
  });
  return best;
}

function drawWorld() {
  const canvas = document.getElementById("map");
  const ctx = canvas.getContext("2d");
  const room = canvas.parentElement ? canvas.parentElement.clientWidth : 900;
  const width = Math.max(320, Math.min(900, room || 900));
  canvas.width = width;
  canvas.height = Math.round(width * 560 / 900);
  const brief = readBrief();
  const image = ctx.createImageData(canvas.width, canvas.height);
  for (let y = 0; y < canvas.height; y += 1) {
    for (let x = 0; x < canvas.width; x += 1) {
      const region = nearestRegion(x, y, canvas.width, canvas.height);
      const owner = worldData.corporations.find(
        (corp) => corp.id === ownerId(region, worldData.regions.indexOf(region)));
      const match = (owner && owner.colour.match(/#(..)(..)(..)/))
        || ["", "33", "33", "33"];
      const pixel = (y * canvas.width + x) * 4;
      image.data[pixel] = parseInt(match[1], 16);
      image.data[pixel + 1] = parseInt(match[2], 16);
      image.data[pixel + 2] = parseInt(match[3], 16);
      image.data[pixel + 3] = 255;
    }
  }
  ctx.putImageData(image, 0, 0);
  ctx.strokeStyle = "rgba(12, 12, 16, 0.45)";
  ctx.lineWidth = 1;
  worldData.links.forEach((link) => {
    const from = regionPoint(
      worldData.regions[link.a - 1], canvas.width, canvas.height);
    const to = regionPoint(
      worldData.regions[link.b - 1], canvas.width, canvas.height);
    ctx.beginPath();
    ctx.moveTo(from.x, from.y);
    ctx.lineTo(to.x, to.y);
    ctx.stroke();
  });
  worldData.regions.forEach((region, index) => {
    const row = brief && brief.regions[index];
    const at = regionPoint(region, canvas.width, canvas.height);
    const mine = region.owner === 1;
    ctx.beginPath();
    ctx.arc(at.x, at.y, mine ? 7 : 4, 0, Math.PI * 2);
    ctx.fillStyle = mine ? "#f4f1ea" : "#111216";
    ctx.fill();
    ctx.setLineDash(row && row.visited ? [] : [2, 2]);
    ctx.strokeStyle = mine ? "#f2d36b" : "#f4f1ea";
    ctx.lineWidth = mine ? 2 : 1;
    ctx.stroke();
    ctx.setLineDash([]);
  });
  document.getElementById("zoom-label").textContent = "world";
}

function draw() {
  if (showWorld && worldData) {
    drawWorld();
    return;
  }
  if (!mapData) {
    return;
  }
  const canvas = document.getElementById("map");
  const ctx = canvas.getContext("2d");
  if (view === "iso" && tileset) {
    drawIso(ctx);
  } else {
    drawFlat(ctx);
  }
}

function opaque(atlasX, atlasY) {
  if (!atlasPixels || atlasX < 0 || atlasY < 0 || atlasX >= atlasWidth) {
    return false;
  }
  const index = (atlasY * atlasWidth + atlasX) * 4 + 3;
  return atlasPixels[index] > 16;
}

// Used when the atlas pixels cannot be read (a tainted canvas).
// The diamond sits on the bottom of the cell; walls rise above it.
function hitsFootprint(localX, localY, level) {
  const tw = tileset.tile_width;
  const dh = tileset.diamond_height;
  const ch = tileset.cell_height;
  const cx = tw / 2;
  const cy = ch - dh / 2;
  const nx = Math.abs(localX + 0.5 - cx) / (tw / 2);
  const ny = Math.abs(localY + 0.5 - cy) / (dh / 2);
  if (nx + ny <= 1) {
    return true;
  }
  const columnTop = cy - dh / 2 - level * tileset.level_px;
  return localY >= columnTop
    && localY <= cy
    && Math.abs(localX + 0.5 - cx) <= tw * 0.28;
}

function pickIso(px, py) {
  const scale = isoScale;
  const tw = tileset.tile_width;
  const ch = tileset.cell_height;
  for (let y = mapData.height; y >= 1; y -= 1) {
    for (let x = mapData.width; x >= 1; x -= 1) {
      const spot = anchor(x, y, scale);
      const left = spot.sx - spot.halfW;
      const top = spot.sy - spot.cellH;
      if (px < left || py < top || px >= left + tw * scale
          || py >= top + ch * scale) {
        continue;
      }
      const cell = cellAt(mapData, x, y);
      const localX = Math.floor((px - left) / scale);
      const localY = Math.floor((py - top) / scale);
      let hit = false;
      if (atlasPixels) {
        const tile = tileset.byId[cell.tileId];
        hit = opaque(tile.column * tw + localX, tile.row * ch + localY);
      } else {
        hit = hitsFootprint(localX, localY, cell.level);
      }
      if (hit) {
        return { x, y };
      }
    }
  }
  return null;
}

function pickFlat(px, py) {
  return {
    x: Math.floor(px / tilePx) + 1,
    y: Math.floor(py / tilePx) + 1
  };
}

function showCell(x, y) {
  const info = document.getElementById("hover");
  if (x < 1 || y < 1 || x > mapData.width || y > mapData.height) {
    info.textContent = "Hover a tile.";
    return;
  }
  const cell = cellAt(mapData, x, y);
  const walk = cell.walk ? "yes" : "no";
  const drive = cell.drive ? "yes" : "no";
  info.textContent =
    `x ${x}  y ${y}  ${cell.name}  height ${cell.level}` +
    `  tile ${cell.tileId}  walk ${walk}  drive ${drive}`;
}

function loadAtlas(src, crossOrigin) {
  return new Promise((resolve, reject) => {
    const image = new Image();
    if (crossOrigin) {
      image.crossOrigin = "anonymous";
    }
    image.onload = () => resolve(image);
    image.onerror = () => reject(new Error("atlas image failed"));
    image.src = src;
  });
}

async function loadTileset() {
  const response = await fetch("assets/tiles.json");
  if (!response.ok) {
    throw new Error(response.statusText);
  }
  const index = await response.json();
  const byId = [];
  index.tiles.forEach((tile) => {
    byId[tile.id] = tile;
  });
  let image;
  try {
    image = await loadAtlas(index.atlas, true);
  } catch (err) {
    image = await loadAtlas(index.atlas, false);
  }
  const scratch = document.createElement("canvas");
  scratch.width = image.width;
  scratch.height = image.height;
  const ctx = scratch.getContext("2d");
  ctx.drawImage(image, 0, 0);
  atlasWidth = image.width;
  atlasPixels = null;
  try {
    atlasPixels = ctx.getImageData(0, 0, image.width, image.height).data;
  } catch (err) {
    // WebKit taints a canvas that drew a cross-origin atlas and throws
    // SecurityError. Hover then uses the diamond instead of alpha.
    atlasPixels = null;
  }
  tileset = {
    tile_width: index.tile_width,
    diamond_height: index.diamond_height,
    cell_height: index.cell_height,
    level_px: index.level_px,
    byId,
    image
  };
}

async function loadFile(file) {
  const response = await fetch(`data/${file}`);
  if (!response.ok) {
    throw new Error(response.statusText);
  }
  mapData = await response.json();
  document.getElementById("version").textContent = mapData.version;
  document.getElementById("seed-label").textContent =
    mapData.label || String(mapData.seed);
  paintLegend(mapData);
  fillPaths(mapData);
  draw();
}

function canvasPoint(event) {
  const canvas = document.getElementById("map");
  const rect = canvas.getBoundingClientRect();
  return {
    x: (event.clientX - rect.left) * (canvas.width / rect.width),
    y: (event.clientY - rect.top) * (canvas.height / rect.height)
  };
}

async function main() {
  try {
    await loadTileset();
  } catch (err) {
    // A failed atlas read must not skip the map. Flat view still draws.
    tileset = null;
    atlasPixels = null;
  }
  const indexResponse = await fetch("data/index.json");
  if (!indexResponse.ok) {
    throw new Error(indexResponse.statusText);
  }
  const index = await indexResponse.json();
  document.getElementById("version").textContent = index.version;
  const select = document.getElementById("seed");
  let chosen = 0;
  index.maps.forEach((entry, i) => {
    const option = document.createElement("option");
    option.value = entry.file;
    option.textContent = entry.label || String(entry.seed);
    if (entry.seed === 42) {
      chosen = i;
    }
    select.append(option);
  });
  select.selectedIndex = chosen;
  select.addEventListener("change", () => {
    const entry = index.maps[select.selectedIndex];
    loadFile(entry.file).catch(showError);
  });
  document.getElementById("path").addEventListener("change", (event) => {
    selectedPath = Number(event.target.value);
    tick = 0;
    stopPlayback();
    showTick();
    refreshStatus();
    draw();
  });
  document.getElementById("play").addEventListener("click", () => {
    stopPlayback();
    if (tick >= maxTick()) {
      return;
    }
    timer = setInterval(() => {
      if (tick >= maxTick()) {
        stopPlayback();
        return;
      }
      tick += 1;
      showTick();
      draw();
    }, 80);
  });
  document.getElementById("pause").addEventListener("click", () => {
    stopPlayback();
  });
  document.getElementById("step").addEventListener("click", () => {
    stopPlayback();
    if (tick < maxTick()) {
      tick += 1;
      showTick();
      draw();
    }
  });
  document.getElementById("view").addEventListener("click", () => {
    view = view === "iso" ? "flat" : "iso";
    document.getElementById("view").textContent =
      view === "iso" ? "Flat view" : "Isometric view";
    draw();
  });
  document.getElementById("zoom-in").addEventListener("click", () => {
    if (view === "iso") {
      isoScale = Math.min(3, isoScale + 1);
    } else {
      tilePx = Math.min(16, tilePx + 2);
    }
    draw();
  });
  document.getElementById("zoom-out").addEventListener("click", () => {
    if (view === "iso") {
      isoScale = Math.max(1, isoScale - 1);
    } else {
      tilePx = Math.max(2, tilePx - 2);
    }
    draw();
  });
  const canvas = document.getElementById("map");
  canvas.addEventListener("mousemove", (event) => {
    if (showWorld && worldData) {
      const point = canvasPoint(event);
      const region = nearestRegion(
        point.x, point.y, canvas.width, canvas.height);
      document.getElementById("hover").textContent = region.name;
      if (wasmLive) {
        showStrategic(region.id);
      }
      return;
    }
    if (!mapData) {
      return;
    }
    const point = canvasPoint(event);
    if (view === "iso") {
      const tile = pickIso(point.x, point.y);
      if (!tile) {
        document.getElementById("hover").textContent = "Hover a tile.";
        return;
      }
      showCell(tile.x, tile.y);
      return;
    }
    const tile = pickFlat(point.x, point.y);
    showCell(tile.x, tile.y);
  });
  canvas.addEventListener("mouseleave", () => {
    document.getElementById("hover").textContent = "Hover a tile.";
  });
  document.getElementById("world").addEventListener("click", () => {
    showWorld = !showWorld;
    document.getElementById("world").textContent =
      showWorld ? "City" : "World map";
    if (showWorld && worldData) {
      document.getElementById("seed-label").textContent =
        `world ${worldData.seed}`;
      document.getElementById("path-status").textContent =
        "Click a region to read it and open its city.";
      document.getElementById("hover").textContent = "Hover a region.";
      draw();
      return;
    }
    showWorld = false;
    draw();
  });
  canvas.addEventListener("click", (event) => {
    if (showWorld && worldData) {
      const point = canvasPoint(event);
      const region = nearestRegion(point.x, point.y, canvas.width, canvas.height);
      const owner = worldData.corporations.find(
        (corp) => corp.id === ownerId(
          region, worldData.regions.indexOf(region)));
      document.getElementById("path-status").textContent =
        `${region.name}: ${owner ? owner.name : "unclaimed"}`
        + ` · pop ${region.population}k · tech ${region.tech}`
        + ` · tax ${region.tax} · unrest ${region.unrest}`
        + ` · city seed ${region.city_seed}`;
      showStrategic(region.id);
      if (wasmLive && wasmExports && wasmExports.megacorp_command) {
        const menu = readMenu();
        if (menu && menu.screen === 4) {
          menuCommand(MENU_ACT.brief, region.id);
        }
        return;
      }
      showWorld = false;
      document.getElementById("world").textContent = "World map";
      const summary = `${region.name}: ${owner ? owner.name : "unclaimed"}`
        + ` · pop ${region.population}k · tech ${region.tech}`
        + ` · tax ${region.tax} · unrest ${region.unrest}`
        + ` · city seed ${region.city_seed}`;
      loadFile(region.city).then(() => {
        document.getElementById("path-status").textContent = summary;
      }).catch(showError);
      return;
    }
    if (!mapData || !mapData.paths) {
      return;
    }
    const point = canvasPoint(event);
    const tile = view === "iso" ? pickIso(point.x, point.y) : pickFlat(point.x, point.y);
    if (!tile) {
      return;
    }
    selectedPath = nearestPrepared(tile.x, tile.y);
    document.getElementById("path").value = String(selectedPath);
    tick = 0;
    stopPlayback();
    showTick();
    refreshStatus();
    draw();
  });
  try {
    const worldResponse = await fetch("data/world.json");
    if (worldResponse.ok) {
      worldData = await worldResponse.json();
    }
  } catch (err) {
    worldData = null;
  }
  try {
    const campaignResponse = await fetch("data/campaign.json");
    if (campaignResponse.ok) {
      campaignData = await campaignResponse.json();
      const slider = document.getElementById("day");
      slider.max = String(campaignData.days || 0);
      slider.addEventListener("input", () => {
        if (writingDay) {
          return;
        }
        if (wasmLive && wasmExports) {
          const target = Number(slider.value);
          const mission = window.__city && window.__city.mission;
          if (mission && mission.mode === 1) {
            return;
          }
          wasmExports.megacorp_reset(42);
          if (target > 0) {
            wasmExports.megacorp_advance(target);
          }
          showWasmDay();
          if (showWorld) {
            draw();
          }
          return;
        }
        campaignDay = Number(slider.value);
        document.getElementById("day-label").textContent =
          String(campaignDay);
        if (showWorld) {
          const frame = campaignData.frames[campaignDay];
          const cash = frame && frame.cash
            ? frame.cash.map((value, index) => `${index + 1}:${value}`).join(" ")
            : "";
          document.getElementById("path-status").textContent =
            `Day ${campaignDay} cash ${cash}`;
          draw();
        }
      });
    }
  } catch (err) {
    campaignData = null;
  }
  await loadFile(index.maps[select.selectedIndex].file);
  try {
    const response = await fetch("megacorp.wasm?v=028");
    if (!response.ok) {
      throw new Error(String(response.status));
    }
    const storeMode = await MegacorpStore.open();
    document.getElementById("store").textContent = storeMode;
    const bytes = await response.arrayBuffer();
    const mod = await WebAssembly.instantiate(bytes, MegacorpStore.imports());
    wasmExports = mod.instance.exports;
    window.wasmExports = wasmExports;
    MegacorpStore.bind(wasmExports.memory);
    wasmExports.adainit();
    try {
      wasmExports.megacorp_boot(42);
    } catch (err) {
      wasmExports.megacorp_reset(42);
    }
    wasmLive = true;
    showWorld = false;
    window.menuSetSpeed = (next) => {
      wasmExports.megacorp_command(12, MENU_ACT.speed, next, 0, 0, 0);
      paintMenu();
    };
    paintMenu();
    const loading = document.getElementById("loading");
    if (loading) {
      loading.hidden = true;
    }
    showHints();
    document.getElementById("new-world").addEventListener("click", () => {
      menuCommand(MENU_ACT.openNew, 0);
    });
    document.getElementById("game-menu").addEventListener("click", () => {
      menuCommand(MENU_ACT.pause, 0);
    });
    document.getElementById("reroll").addEventListener("click", () => {
      if (strategicId > 0) {
        menuCommand(MENU_ACT.reroll, strategicId);
        showWasmDay();
        draw();
      }
    });
    window.addEventListener("keydown", (event) => {
      const menu = readMenu();
      if (!menu) {
        return;
      }
      const overlay = menu.screen !== 4 && menu.screen !== 6;
      if (event.key === "Escape") {
        event.preventDefault();
        menuCommand(overlay ? MENU_ACT.back : MENU_ACT.pause, 0);
        return;
      }
      if (!overlay) {
        return;
      }
      if (event.key === "ArrowUp") {
        event.preventDefault();
        menuCommand(MENU_ACT.up, 0);
      } else if (event.key === "ArrowDown") {
        event.preventDefault();
        menuCommand(MENU_ACT.down, 0);
      } else if (event.key === "Enter") {
        event.preventDefault();
        menuCommand(MENU_ACT.activate, 0);
      } else if (menu.screen === 1 && event.key >= "0" && event.key <= "9") {
        event.preventDefault();
        menuCommand(MENU_ACT.digit, Number(event.key));
      } else if (menu.screen === 1 && event.key === "Backspace") {
        event.preventDefault();
        menuCommand(MENU_ACT.clear, 0);
      }
    });
    document.getElementById("import-asset").addEventListener("change", async (event) => {
      const file = event.target.files && event.target.files[0];
      if (!file) {
        return;
      }
      const bytes = new Uint8Array(await file.arrayBuffer());
      const cap = wasmExports.megacorp_import_capacity();
      if (bytes.length === 0 || bytes.length > cap) {
        document.getElementById("hover").textContent = "Import refused.";
        return;
      }
      const dest = wasmExports.megacorp_import_buffer();
      const mem = new Uint8Array(wasmExports.memory.buffer);
      mem.set(bytes, dest);
      const nameBytes = new TextEncoder().encode(file.name);
      const namePtr = dest + bytes.length;
      if (namePtr + nameBytes.length > mem.length) {
        document.getElementById("hover").textContent = "Import refused.";
        return;
      }
      mem.set(nameBytes, namePtr);
      const accepted = wasmExports.megacorp_commit_asset(
        namePtr, nameBytes.length, bytes.length);
      if (accepted !== 1) {
        document.getElementById("hover").textContent = "Import refused.";
        return;
      }
      document.getElementById("hover").textContent = `Imported ${file.name}.`;
    });
    canvas.addEventListener("pointermove", (event) => {
      if (!showWorld || !wasmLive || !worldData) {
        return;
      }
      const point = canvasPoint(event);
      const region = nearestRegion(
        point.x, point.y, canvas.width, canvas.height);
      showStrategic(region.id);
    });
    document.getElementById("sheet-handle").addEventListener("click", () => {
      document.getElementById("sheet").classList.toggle("open");
    });
    document.getElementById("hire").addEventListener("click", () => {
      wasmExports.megacorp_command(7, 0, 0, 0, 0, 0);
      showWasmDay();
    });
    document.getElementById("fund-0").addEventListener("click", () => {
      wasmExports.megacorp_command(8, 0, 0, 0, 0, 0);
      showWasmDay();
    });
    document.getElementById("fund-40").addEventListener("click", () => {
      wasmExports.megacorp_command(8, 40, 0, 0, 0, 0);
      showWasmDay();
    });
    document.getElementById("fund-80").addEventListener("click", () => {
      wasmExports.megacorp_command(8, 80, 0, 0, 0, 0);
      showWasmDay();
    });
  } catch (err) {
    document.getElementById("engine").textContent = "engine: trace";
    const loading = document.getElementById("loading");
    if (loading) {
      loading.hidden = true;
    }
    const fail = document.getElementById("boot-fail");
    if (fail) {
      fail.hidden = false;
      fail.textContent =
        "The simulation module did not load. The exported maps are still here.";
    }
  }
}

const HINTS = [
  "New game locks a scenario, or you can type a seed for free play.",
  "Open a region for its briefing, then press Start.",
  "Pause, 1x, 2x, and 4x run the campaign on the map.",
  "Hire agents and fund research from the side sheet. Debt stops hiring.",
  "Menu saves the game. Quit to the title and Continue restores it."
];

function showHints() {
  const box = document.getElementById("hints");
  const text = document.getElementById("hint-text");
  if (!box || !text || localStorage.getItem("megacorp-hints") === "seen") {
    return;
  }
  let step = 0;
  const paint = () => {
    text.textContent = HINTS[step];
    box.hidden = false;
  };
  paint();
  document.getElementById("hint-next").addEventListener("click", () => {
    step += 1;
    if (step >= HINTS.length) {
      localStorage.setItem("megacorp-hints", "seen");
      box.hidden = true;
      return;
    }
    paint();
  });
  document.getElementById("hint-skip").addEventListener("click", () => {
    localStorage.setItem("megacorp-hints", "seen");
    box.hidden = true;
  });
}

function showError(err) {
  document.getElementById("hover").textContent =
    `Could not load map data (${err}).`;
}

main().catch(showError);
