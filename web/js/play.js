// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Robert Boettcher
//
// Fixed-step clock and raw pointer events for the Ada city.
// Selection, orders, panning, and zoom are decided in the module.
const MegacorpPlay = (() => {
  const viewW = 480;
  const viewH = 480;
  const stepMs = 1000 / 30;
  const face = [
    [0, -1], [1, 0], [0, 1], [-1, 0],
    [1, -1], [1, 1], [-1, 1], [-1, -1]
  ];
  const ground = ["#6b8f71", "#5c6370", "#8d8478", "#3a3430", "#3d6f8f"];
  let wasm = null;
  let speed = 1;
  let acc = 0;
  let dayAcc = 0;
  let last = 0;
  const dayMs = 1000;
  let started = false;
  const pointers = new Map();
  let pinchDist = 0;

  function read() {
    const view = new DataView(wasm.memory.buffer);
    const base = wasm.megacorp_city();
    const width = view.getUint16(base, true);
    const height = view.getUint16(base + 2, true);
    const camX = view.getUint16(base + 4, true);
    const camY = view.getUint16(base + 6, true);
    const zoom = view.getUint8(base + 8);
    const peds = view.getUint8(base + 9);
    const cars = view.getUint8(base + 10);
    const tick = view.getUint32(base + 12, true);
    let cursor = base + 16;
    const terrain = new Uint8Array(wasm.memory.buffer, cursor, width * height);
    cursor += width * height;
    const people = [];
    for (let i = 0; i < peds; i += 1) {
      people.push({
        id: view.getUint8(cursor),
        x: view.getUint8(cursor + 1),
        y: view.getUint8(cursor + 2),
        along: view.getUint8(cursor + 3),
        facing: view.getUint8(cursor + 4),
        state: view.getUint8(cursor + 5),
        selected: view.getUint8(cursor + 6) === 1
      });
      cursor += 8;
    }
    const fleet = [];
    for (let i = 0; i < cars; i += 1) {
      fleet.push({
        id: view.getUint8(cursor),
        x: view.getUint8(cursor + 1),
        y: view.getUint8(cursor + 2),
        along: view.getUint8(cursor + 3),
        facing: view.getUint8(cursor + 4),
        state: view.getUint8(cursor + 5)
      });
      cursor += 8;
    }
    const mode = view.getUint8(base + 11);
    let mission = null;
    if (mode > 0 && cursor + 7 < view.byteLength) {
      const region = view.getUint16(cursor, true);
      const zoneX = view.getUint16(cursor + 2, true);
      const zoneY = view.getUint16(cursor + 4, true);
      const textLen = view.getUint8(cursor + 6);
      let text = "";
      for (let i = 0; i < textLen; i += 1) {
        text += String.fromCharCode(view.getUint8(cursor + 7 + i));
      }
      mission = { mode, region, zoneX, zoneY, text };
    }
    return {
      width, height, camX, camY, zoom, tick, terrain, people, fleet, mission
    };
  }

  function center(unit, camX, camY, zoom) {
    const step = face[unit.facing] || [0, 0];
    const shift = (unit.along / 8) * zoom;
    return {
      x: (unit.x - camX) * zoom + zoom / 2 + step[0] * shift,
      y: (unit.y - camY) * zoom + zoom / 2 + step[1] * shift
    };
  }

  function draw() {
    const canvas = document.getElementById("city");
    if (!canvas || !wasm) {
      return;
    }
    const city = read();
    if (!city.zoom || !city.width || !city.height) {
      window.__playError = `empty city ${city.width} ${city.zoom}`;
      return;
    }
    const ctx = canvas.getContext("2d");
    ctx.fillStyle = "#101216";
    ctx.fillRect(0, 0, viewW, viewH);
    const x0 = city.camX;
    const y0 = city.camY;
    const cols = Math.ceil(viewW / city.zoom) + 1;
    const rows = Math.ceil(viewH / city.zoom) + 1;
    for (let y = 0; y < rows; y += 1) {
      for (let x = 0; x < cols; x += 1) {
        const tx = x0 + x;
        const ty = y0 + y;
        if (tx < 1 || ty < 1 || tx > city.width || ty > city.height) {
          continue;
        }
        const kind = city.terrain[(ty - 1) * city.width + (tx - 1)];
        ctx.fillStyle = ground[kind] || ground[0];
        ctx.fillRect(x * city.zoom, y * city.zoom, city.zoom, city.zoom);
      }
    }
    const banner = document.getElementById("objective");
    if (banner && city.mission && city.mission.text) {
      const names = { 1: "Mission", 2: "Won", 3: "Lost", 4: "Lost" };
      banner.textContent =
        `${names[city.mission.mode] || "Mission"}: ${city.mission.text}`;
    }
    if (city.mission && city.mission.zoneX) {
      ctx.strokeStyle = "#f2d36b";
      ctx.lineWidth = 2;
      ctx.strokeRect(
        (city.mission.zoneX - city.camX) * city.zoom + 1,
        (city.mission.zoneY - city.camY) * city.zoom + 1,
        city.zoom - 2,
        city.zoom - 2
      );
    }
    const units = [];
    city.people.forEach((ped) => {
      const at = center(ped, city.camX, city.camY, city.zoom);
      ctx.fillStyle = ped.selected ? "#f2d36b" : "#f4f1ea";
      ctx.beginPath();
      ctx.arc(at.x, at.y, Math.max(3, city.zoom / 3), 0, Math.PI * 2);
      ctx.fill();
      if (ped.selected) {
        ctx.strokeStyle = "#f2d36b";
        ctx.strokeRect(
          (ped.x - city.camX) * city.zoom + 1,
          (ped.y - city.camY) * city.zoom + 1,
          city.zoom - 2,
          city.zoom - 2
        );
      }
      units.push({ ...ped, px: at.x, py: at.y });
    });
    city.fleet.forEach((car) => {
      const at = center(car, city.camX, city.camY, city.zoom);
      ctx.fillStyle = "#2fbfb0";
      ctx.fillRect(at.x - city.zoom / 3, at.y - city.zoom / 4, city.zoom / 1.5, city.zoom / 2);
    });
    const occupied = new Set(city.people.map((ped) => `${ped.x},${ped.y}`));
    let goal = null;
    const origin = city.people[0];
    if (origin) {
      for (let radius = 3; radius <= 8 && !goal; radius += 1) {
        for (let dy = -radius; dy <= radius && !goal; dy += 1) {
          for (let dx = -radius; dx <= radius && !goal; dx += 1) {
            if (Math.abs(dx) !== radius && Math.abs(dy) !== radius) {
              continue;
            }
            const x = origin.x + dx;
            const y = origin.y + dy;
            if (x < 1 || y < 1 || x > city.width || y > city.height) {
              continue;
            }
            if (occupied.has(`${x},${y}`)) {
              continue;
            }
            const kind = city.terrain[(y - 1) * city.width + (x - 1)];
            if (kind <= 2) {
              goal = {
                x,
                y,
                px: (x - city.camX) * city.zoom + city.zoom / 2,
                py: (y - city.camY) * city.zoom + city.zoom / 2
              };
            }
          }
        }
      }
    }
    const label = document.getElementById("sim-tick");
    if (label) {
      label.textContent = String(city.tick);
    }
    const missionGoal = city.mission && city.mission.zoneX ? {
      x: city.mission.zoneX,
      y: city.mission.zoneY,
      px: (city.mission.zoneX - city.camX) * city.zoom + city.zoom / 2,
      py: (city.mission.zoneY - city.camY) * city.zoom + city.zoom / 2
    } : goal;
    window.__city = {
      tick: city.tick,
      zoom: city.zoom,
      camX: city.camX,
      camY: city.camY,
      units,
      goal: missionGoal,
      mission: city.mission
    };
    if (city.mission && city.mission.mode >= 2 && window.readWasmWorld) {
      window.__world = window.readWasmWorld();
      if (window.showWasmDay) {
        window.showWasmDay();
      }
      if (window.draw) {
        window.draw();
      }
    }
  }

  function send(code, a, b, c, d, e) {
    wasm.megacorp_command(code | 0, a | 0, b | 0, c | 0, d | 0, e | 0);
    draw();
  }

  function keyCode(event) {
    switch (event.key) {
      case "ArrowLeft": return 1;
      case "ArrowRight": return 2;
      case "ArrowUp": return 3;
      case "ArrowDown": return 4;
      case "-":
      case "_": return 5;
      case "+":
      case "=": return 6;
      default: return 0;
    }
  }

  function canvasPos(event) {
    const canvas = document.getElementById("city");
    const rect = canvas.getBoundingClientRect();
    return {
      x: (event.clientX - rect.left) * (canvas.width / rect.width),
      y: (event.clientY - rect.top) * (canvas.height / rect.height)
    };
  }

  function pinch() {
    const pts = [...pointers.values()];
    if (pts.length < 2) {
      pinchDist = 0;
      return;
    }
    const dist = Math.hypot(pts[0].x - pts[1].x, pts[0].y - pts[1].y);
    const midX = (pts[0].x + pts[1].x) / 2;
    const midY = (pts[0].y + pts[1].y) / 2;
    if (!pinchDist) {
      pinchDist = dist;
      pts[0].midX = midX;
      pts[0].midY = midY;
      return;
    }
    let zoom = 0;
    if (dist > pinchDist * 1.08) {
      zoom = 1;
      pinchDist = dist;
    } else if (dist < pinchDist * 0.92) {
      zoom = -1;
      pinchDist = dist;
    }
    const panX = midX - (pts[0].midX || midX);
    const panY = midY - (pts[0].midY || midY);
    pts[0].midX = midX;
    pts[0].midY = midY;
    if (zoom !== 0 || panX !== 0 || panY !== 0) {
      send(4, panX, panY, zoom, 0, 0);
    }
  }

  function onDown(event) {
    const at = canvasPos(event);
    event.currentTarget.setPointerCapture(event.pointerId);
    pointers.set(event.pointerId, {
      x: at.x,
      y: at.y,
      sx: at.x,
      sy: at.y,
      touch: event.pointerType === "touch",
      panned: false
    });
  }

  function onMove(event) {
    const start = pointers.get(event.pointerId);
    if (!start) {
      return;
    }
    const at = canvasPos(event);
    const dx = at.x - start.x;
    const dy = at.y - start.y;
    start.x = at.x;
    start.y = at.y;
    if (pointers.size >= 2) {
      pinch();
      start.panned = true;
      return;
    }
    if (start.touch && (dx !== 0 || dy !== 0)) {
      send(5, dx, dy, 0, 0, 0);
      start.panned = true;
    }
  }

  function onUp(event) {
    const start = pointers.get(event.pointerId);
    pointers.delete(event.pointerId);
    if (pointers.size < 2) {
      pinchDist = 0;
    }
    if (!start) {
      return;
    }
    const dx = start.x - start.sx;
    const dy = start.y - start.sy;
    const moved = Math.hypot(dx, dy) > 6;
    if (!start.touch && moved) {
      send(2, start.sx, start.sy, start.x, start.y, 0);
    } else if (!start.panned && !moved) {
      send(1, start.sx, start.sy, 0, 0, 0);
    }
  }

  function setSpeed(next) {
    speed = next;
    ["sim-pause", "sim-1", "sim-2", "sim-4"].forEach((id) => {
      const button = document.getElementById(id);
      if (!button) {
        return;
      }
      const mine = (id === "sim-pause" && next === 0)
        || (id === "sim-1" && next === 1)
        || (id === "sim-2" && next === 2)
        || (id === "sim-4" && next === 4);
      button.setAttribute("aria-pressed", mine ? "true" : "false");
    });
  }

  function frame(now) {
    if (!last) {
      last = now;
    }
    let dt = now - last;
    if (dt > 100) {
      dt = 100;
    }
    last = now;
    if (speed > 0) {
      acc += dt * speed;
    }
    let ticks = 0;
    while (acc >= stepMs && ticks < 8) {
      acc -= stepMs;
      ticks += 1;
    }
    if (ticks > 0) {
      try {
        wasm.megacorp_play(ticks);
      } catch (err) {
        window.__playError = String(err);
        speed = 0;
      }
    }
    const mission = window.__city && window.__city.mission;
    if (speed > 0 && !(mission && mission.mode === 1)) {
      dayAcc += dt * speed;
      let days = 0;
      while (dayAcc >= dayMs && days < 4) {
        dayAcc -= dayMs;
        days += 1;
      }
      if (days > 0) {
        try {
          wasm.megacorp_advance(days);
        } catch (err) {
          dayAcc = 0;
        }
        if (window.showWasmDay) {
          window.showWasmDay();
        }
        if (window.draw) {
          window.draw();
        }
      }
    }
    draw();
    requestAnimationFrame(frame);
  }

  function start(exports) {
    wasm = exports;
    if (started) {
      draw();
      return;
    }
    started = true;
    try {
      draw();
    } catch (err) {
      window.__playError = String(err);
    }
    const canvas = document.getElementById("city");
    canvas.width = viewW;
    canvas.height = viewH;
    canvas.addEventListener("pointerdown", onDown);
    canvas.addEventListener("pointermove", onMove);
    canvas.addEventListener("pointerup", onUp);
    canvas.addEventListener("pointercancel", onUp);
    window.addEventListener("keydown", (event) => {
      if (event.repeat) {
        return;
      }
      const code = keyCode(event);
      if (!code) {
        return;
      }
      event.preventDefault();
      send(3, code, 0, 0, 0, 0);
    });
    document.getElementById("sim-pause").addEventListener("click", () => setSpeed(0));
    document.getElementById("sim-1").addEventListener("click", () => setSpeed(1));
    document.getElementById("sim-2").addEventListener("click", () => setSpeed(2));
    document.getElementById("sim-4").addEventListener("click", () => setSpeed(4));
    setSpeed(1);
    requestAnimationFrame(frame);
  }

  return { start };
})();
