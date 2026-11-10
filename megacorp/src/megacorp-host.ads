--  SPDX-License-Identifier: MIT
--  Copyright (c) 2026 Robert Boettcher

--  Host services for item 1: a monotonic clock and a log.
--  Filesystem and browser storage hooks arrive with the virtual
--  filesystem (item 4) and browser storage (item 21). This package
--  does not talk to SDL, the DOM, or a socket.
package Megacorp.Host is
   type Log_Level is (Debug, Info, Warning, Error);

   procedure Log (Level : Log_Level; Message : String)
     with Pre => Message'Length > 0;

   subtype Milliseconds is Long_Long_Integer range 0 .. Long_Long_Integer'Last;

   --  Milliseconds since this process first read the monotonic clock.
   --  Does not go backwards during one run. Not a wall clock.
   function Monotonic_Milliseconds return Milliseconds;
end Megacorp.Host;
