// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Robert Boettcher
//
// Play the event codes and voice tables Ada already chose.
const MegacorpSound = (() => {
  let ctx = null;
  let master = null;
  let effects = null;
  let music = null;
  let noise = null;
  let seq = -1;
  let scene = -1;
  let loopTimer = 0;
  let tables = null;
  window.__soundEvents = 0;
  window.__soundMuted = false;

  function unlock() {
    const Audio = window.AudioContext || window.webkitAudioContext;
    if (!Audio) {
      return;
    }
    if (!ctx) {
      ctx = new Audio();
      master = ctx.createGain();
      effects = ctx.createGain();
      music = ctx.createGain();
      effects.connect(master);
      music.connect(master);
      master.connect(ctx.destination);
      const samples = ctx.sampleRate;
      const data = ctx.createBuffer(1, samples, samples);
      const channel = data.getChannelData(0);
      let state = 1;
      for (let i = 0; i < channel.length; i += 1) {
        state = (state * 1103515245 + 12345) % 2147483647;
        channel[i] = (state / 2147483647) * 2 - 1;
      }
      noise = data;
    }
    window.__audioUnlocked = true;
    if (ctx.state === "suspended") {
      window.__audioTried = true;
      try {
        const pending = ctx.resume();
        if (pending && pending.then) {
          pending.then(() => {
            window.__audioState = ctx.state;
          }).catch(() => {
            window.__audioState = ctx.state;
          });
        }
      } catch (err) {
        window.__audioNote = String(err);
      }
    }
    window.__audioState = ctx.state;
  }

  function read() {
    const wasm = window.wasmExports;
    if (!wasm || !wasm.megacorp_sound) {
      return null;
    }
    const view = new DataView(wasm.memory.buffer);
    let cursor = wasm.megacorp_sound();
    cursor += 1;
    const serial = view.getUint8(cursor);
    cursor += 1;
    const place = view.getUint8(cursor);
    cursor += 1;
    const level = view.getUint8(cursor);
    cursor += 1;
    const effect = view.getUint8(cursor);
    cursor += 1;
    const song = view.getUint8(cursor);
    cursor += 1;
    const count = view.getUint8(cursor);
    cursor += 1;
    const events = [];
    for (let i = 0; i < count; i += 1) {
      events.push(view.getUint8(cursor));
      cursor += 1;
    }
    const voices = [];
    for (let i = 0; i < 9; i += 1) {
      const shape = view.getUint8(cursor);
      cursor += 1;
      const freq = view.getUint16(cursor, true);
      cursor += 2;
      const ms = view.getUint16(cursor, true);
      cursor += 2;
      const attack = view.getUint8(cursor);
      cursor += 1;
      const gain = view.getUint8(cursor);
      cursor += 1;
      voices.push({ shape, freq, ms, attack, gain });
    }
    const bars = [];
    for (let s = 0; s < 3; s += 1) {
      const notes = [];
      for (let n = 0; n < 8; n += 1) {
        const freq = view.getUint16(cursor, true);
        cursor += 2;
        const ms = view.getUint16(cursor, true);
        cursor += 2;
        notes.push({ freq, ms });
      }
      bars.push(notes);
    }
    return { serial, place, level, effect, song, events, voices, bars };
  }

  function applyLevels(data) {
    if (!ctx || window.__soundMuted) {
      return;
    }
    const main = data.level / 100;
    try {
      master.gain.setValueAtTime(main, ctx.currentTime);
      effects.gain.setValueAtTime(data.effect / 100, ctx.currentTime);
      music.gain.setValueAtTime(data.song / 100, ctx.currentTime);
    } catch (err) {
      window.__audioNote = String(err);
    }
  }

  function playVoice(voice, bus) {
    if (!ctx || window.__soundMuted || voice.gain === 0) {
      return;
    }
    try {
    playVoiceBody(voice, bus);
    } catch (err) {
      window.__audioNote = String(err);
    }
  }

  function playVoiceBody(voice, bus) {
    const now = ctx.currentTime;
    const gain = ctx.createGain();
    const peak = voice.gain / 100;
    const attack = Math.max(0.005, voice.attack / 1000);
    const length = Math.max(attack + 0.02, voice.ms / 1000);
    gain.gain.setValueAtTime(0.0001, now);
    gain.gain.exponentialRampToValueAtTime(peak, now + attack);
    gain.gain.exponentialRampToValueAtTime(0.0001, now + length);
    gain.connect(bus || effects);
    if (voice.shape === 3) {
      const source = ctx.createBufferSource();
      source.buffer = noise;
      source.loop = true;
      source.connect(gain);
      source.start(now);
      source.stop(now + length);
      return;
    }
    const osc = ctx.createOscillator();
    const shapes = ["sine", "square", "sawtooth"];
    osc.type = shapes[voice.shape] || "sine";
    osc.frequency.setValueAtTime(voice.freq || 440, now);
    osc.connect(gain);
    osc.start(now);
    osc.stop(now + length);
  }

  function stopLoop() {
    if (loopTimer) {
      clearTimeout(loopTimer);
      loopTimer = 0;
    }
  }

  function startLoop(data) {
    stopLoop();
    scene = data.place;
    tables = data;
    const notes = data.bars[data.place] || [];
    let index = 0;
    const step = () => {
      if (scene !== data.place || !tables) {
        return;
      }
      const note = notes[index % notes.length];
      if (note && ctx && !window.__soundMuted) {
        playVoice({
          shape: 0,
          freq: note.freq,
          ms: note.ms,
          attack: 30,
          gain: 18
        }, music);
      }
      const wait = note ? note.ms : 240;
      index += 1;
      loopTimer = setTimeout(step, wait);
    };
    step();
  }

  function pump() {
    const data = read();
    if (!data) {
      return;
    }
    if (!tables) {
      tables = data;
    }
    applyLevels(data);
    if (data.serial === seq) {
      if (data.place !== scene) {
        startLoop(data);
      }
      return;
    }
    seq = data.serial;
    tables = data;
    data.events.forEach((code) => {
      const voice = data.voices[code - 1];
      if (voice) {
        playVoice(voice);
        window.__soundEvents += 1;
      }
    });
    if (data.place !== scene) {
      startLoop(data);
    }
  }

  window.addEventListener("pointerdown", unlock);
  window.addEventListener("keydown", unlock);
  document.addEventListener("visibilitychange", () => {
    window.__soundMuted = document.hidden;
    if (master && ctx) {
      master.gain.setValueAtTime(document.hidden ? 0 : 1, ctx.currentTime);
    }
  });

  const api = {
    unlock,
    pump,
    context() {
      return ctx;
    }
  };
  window.MegacorpSound = api;
  return api;
})();
