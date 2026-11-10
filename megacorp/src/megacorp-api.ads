--  SPDX-License-Identifier: MIT
--  Copyright (c) 2026 Robert Boettcher

--  Items 20 and 22. Messages between this core and the thin
--  browser layer (in-process when compiled to WebAssembly, the
--  same messages over a WebSocket if that fallback is used).
--  The core does not know about the DOM, canvas, or sockets.
--  Spec only in 0.1.0.
package Megacorp.API is
end Megacorp.API;
