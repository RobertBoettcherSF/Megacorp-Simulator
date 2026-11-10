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
    const rest = frame.queue && frame.queue.length
      ? frame.queue.join(", ")
      : "(none)";
    const hp = typeof frame.health === "number"
      ? ` hp ${frame.health}${frame.alive === false ? " down" : ""} ammo ${frame.ammo}`
      : "";
    return `Ped ${ped.id}: ${action}${hp} — remaining: ${rest}`;
  }).filter(Boolean).join("   ");
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
    if (currentMotion().item) {
      status.textContent =
        "Paths, ped motion, and action queues are precomputed by Ada, not run in the browser.";
    } else if (currentMotion().label === "Firefight") {
      status.textContent =
        "Paths, ped motion, and shots are precomputed by Ada, not run in the browser.";
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
    const angle = ANGLE[frame.facing] ?? 0;
    ctx.fillStyle = ped.id === 1 ? "#ffe14a" : "#7fd0ff";
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

function draw() {
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
  canvas.addEventListener("click", (event) => {
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
  await loadFile(index.maps[select.selectedIndex].file);
}

function showError(err) {
  document.getElementById("hover").textContent =
    `Could not load map data (${err}).`;
}

main().catch(showError);
