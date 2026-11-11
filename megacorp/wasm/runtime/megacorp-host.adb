--  SPDX-License-Identifier: MIT
--  Copyright (c) 2026 Robert Boettcher

--  Wasm stand-in. The browser has no Ada console. Messages from
--  the save loader are dropped here; the page shows the day.
package body Megacorp.Host is
   procedure Log (Level : Log_Level; Message : String) is
      pragma Unreferenced (Level, Message);
   begin
      null;
   end Log;

   function Monotonic_Milliseconds return Milliseconds is
   begin
      return 0;
   end Monotonic_Milliseconds;
end Megacorp.Host;
