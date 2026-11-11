// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Robert Boettcher
//
// Thin file store for the Ada module. OPFS when the origin allows
// it. IndexedDB when it does not. The two save files are also
// mirrored in localStorage so a reload does not need a sync
// access handle.
const MegacorpStore = (() => {
  const files = new Map();
  let memory = null;
  let mode = "idb";
  let opfsRoot = null;
  let db = null;
  let chain = Promise.resolve();

  function latin1(bytes) {
    let text = "";
    for (let i = 0; i < bytes.length; i += 1) {
      text += String.fromCharCode(bytes[i]);
    }
    return text;
  }

  function fromLatin1(text) {
    const bytes = new Uint8Array(text.length);
    for (let i = 0; i < text.length; i += 1) {
      bytes[i] = text.charCodeAt(i) & 255;
    }
    return bytes;
  }

  function readStr(ptr, len) {
    return latin1(new Uint8Array(memory.buffer, ptr, len));
  }

  function dayOf(bytes) {
    const text = new TextDecoder().decode(bytes);
    const match = text.match(/\nday (\d+)/);
    return match ? Number(match[1]) : -1;
  }

  function continued(snapshot, log) {
    if (!snapshot) {
      return -1;
    }
    const base = dayOf(snapshot);
    if (base < 0 || !log) {
      return base;
    }
    let steps = 0;
    const text = new TextDecoder().decode(log);
    text.split("\n").forEach((line) => {
      if (line.startsWith("day ")) {
        steps += 1;
      }
    });
    return base + steps;
  }

  function openIdb() {
    return new Promise((resolve, reject) => {
      const request = indexedDB.open("megacorp", 1);
      request.onupgradeneeded = () => {
        request.result.createObjectStore("files");
      };
      request.onsuccess = () => resolve(request.result);
      request.onerror = () => reject(request.error);
    });
  }

  function idbGet(name) {
    return new Promise((resolve) => {
      const tx = db.transaction("files", "readonly");
      const request = tx.objectStore("files").get(name);
      request.onsuccess = () => {
        const value = request.result;
        if (!value) {
          resolve(null);
          return;
        }
        resolve(value instanceof Uint8Array ? value : new Uint8Array(value));
      };
      request.onerror = () => resolve(null);
    });
  }

  function idbPut(name, bytes) {
    return new Promise((resolve) => {
      const tx = db.transaction("files", "readwrite");
      tx.objectStore("files").put(bytes, name);
      tx.oncomplete = () => resolve();
      tx.onerror = () => resolve();
    });
  }

  async function opfsGet(path) {
    const parts = path.split("/");
    let dir = opfsRoot;
    for (let i = 0; i < parts.length - 1; i += 1) {
      dir = await dir.getDirectoryHandle(parts[i]);
    }
    const handle = await dir.getFileHandle(parts[parts.length - 1]);
    const file = await handle.getFile();
    return new Uint8Array(await file.arrayBuffer());
  }

  async function opfsPut(path, bytes) {
    const parts = path.split("/");
    let dir = opfsRoot;
    for (let i = 0; i < parts.length - 1; i += 1) {
      dir = await dir.getDirectoryHandle(parts[i], { create: true });
    }
    const handle = await dir.getFileHandle(parts[parts.length - 1], {
      create: true
    });
    const writable = await handle.createWritable();
    await writable.write(bytes);
    await writable.close();
  }

  function remember(name, bytes) {
    const copy = bytes.slice();
    files.set(name, copy);
    if (name.startsWith("slot.")) {
      try {
        localStorage.setItem(`mgc:${name}`, latin1(copy));
      } catch (err) {
        /* The origin quota is full. OPFS or IndexedDB still run. */
      }
    }
    chain = chain.then(async () => {
      if (mode === "opfs" && opfsRoot) {
        await opfsPut(name, copy);
      } else if (db) {
        await idbPut(name, copy);
      }
    }).catch(() => {});
  }

  async function listOpfs(dir, prefix) {
    const names = [];
    for await (const [name, handle] of dir.entries()) {
      const path = prefix ? `${prefix}/${name}` : name;
      if (handle.kind === "directory") {
        names.push(...await listOpfs(handle, path));
      } else {
        names.push(path);
      }
    }
    return names;
  }

  function idbKeys() {
    return new Promise((resolve) => {
      const tx = db.transaction("files", "readonly");
      const request = tx.objectStore("files").getAllKeys();
      request.onsuccess = () => resolve(request.result || []);
      request.onerror = () => resolve([]);
    });
  }

  async function readStored(name) {
    if (mode === "opfs" && opfsRoot) {
      return opfsGet(name);
    }
    if (db) {
      return idbGet(name);
    }
    return null;
  }

  async function open() {
    const forced = new URLSearchParams(location.search).get("store") === "idb";
    if (!forced && navigator.storage && navigator.storage.getDirectory) {
      try {
        opfsRoot = await navigator.storage.getDirectory();
        mode = "opfs";
      } catch (err) {
        mode = "idb";
      }
    }
    if (mode !== "opfs") {
      try {
        db = await openIdb();
        mode = "idb";
      } catch (err) {
        mode = "local";
      }
    }
    for (let i = 0; i < localStorage.length; i += 1) {
      const key = localStorage.key(i);
      if (key && key.startsWith("mgc:")) {
        files.set(key.slice(4), fromLatin1(localStorage.getItem(key)));
      }
    }
    let names = ["slot.mgc", "slot.log"];
    try {
      if (mode === "opfs" && opfsRoot) {
        names = names.concat(await listOpfs(opfsRoot, ""));
      } else if (db) {
        names = names.concat(await idbKeys());
      }
    } catch (err) {
      /* A missing directory is a new world. */
    }
    const remote = new Map();
    for (const name of names) {
      if (remote.has(name)) {
        continue;
      }
      try {
        const bytes = await readStored(name);
        if (bytes) {
          remote.set(name, bytes);
        }
      } catch (err) {
        /* This name is not in the origin store yet. */
      }
    }
    const localSnap = files.get("slot.mgc") || null;
    const localLog = files.get("slot.log") || null;
    if (continued(remote.get("slot.mgc"), remote.get("slot.log"))
        > continued(localSnap, localLog)) {
      files.set("slot.mgc", remote.get("slot.mgc"));
      if (remote.has("slot.log")) {
        files.set("slot.log", remote.get("slot.log"));
      }
    }
    remote.forEach((bytes, name) => {
      if (!name.startsWith("slot.")) {
        files.set(name, bytes);
      }
    });
    return mode;
  }

  function imports() {
    return {
      env: {
        host_exists(ptr, len) {
          return files.has(readStr(ptr, len)) ? 1 : 0;
        },
        host_length(ptr, len) {
          const data = files.get(readStr(ptr, len));
          return data ? data.length : -1;
        },
        host_read(pathPtr, pathLen, dest, destLen) {
          const data = files.get(readStr(pathPtr, pathLen));
          if (!data) {
            return;
          }
          new Uint8Array(memory.buffer, dest, destLen).set(data.subarray(0, destLen));
        },
        host_write(pathPtr, pathLen, dataPtr, dataLen) {
          remember(readStr(pathPtr, pathLen), new Uint8Array(memory.buffer, dataPtr, dataLen));
        },
        host_append(pathPtr, pathLen, dataPtr, dataLen) {
          const name = readStr(pathPtr, pathLen);
          const prev = files.get(name) || new Uint8Array();
          const extra = new Uint8Array(memory.buffer, dataPtr, dataLen);
          const next = new Uint8Array(prev.length + extra.length);
          next.set(prev);
          next.set(extra, prev.length);
          remember(name, next);
        }
      }
    };
  }

  function bind(mem) {
    memory = mem;
  }

  function get(name) {
    return files.get(name) || null;
  }

  function flush() {
    return chain;
  }

  return { open, imports, bind, get, flush };
})();
