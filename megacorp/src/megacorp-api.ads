--  SPDX-License-Identifier: MIT
--  Copyright (c) 2026 Robert Boettcher

with Interfaces;
with System;
with Megacorp.RNG;
with Megacorp.World;

--  Item 20. The live world the browser reads. The same subprograms
--  run in the native smoke test and in the WebAssembly module.
--  The core still does not know about the canvas.
package Megacorp.API is
   procedure Init (Seed : Interfaces.Unsigned_32)
     with Export,
          Convention => C,
          External_Name => "megacorp_init";

   procedure Step (Days : Interfaces.Unsigned_32)
     with Export,
          Convention => C,
          External_Name => "megacorp_step";

   function State return System.Address
     with Export,
          Convention => C,
          External_Name => "megacorp_state";

   function State_Size return Interfaces.Unsigned_32
     with Export,
          Convention => C,
          External_Name => "megacorp_state_size";

   function Digest return RNG.Word;

   function Digest_Text return String;

   --  The same mix the module stores, so a native world can be
   --  compared with the bytes the browser reads.
   function Fingerprint
     (Item : World.Atlas;
      Day : Natural) return RNG.Word;

   --  Show an atlas the store loaded. The pure Init/Step path
   --  does not use this.
   procedure Install (Item : World.Atlas; Day : Natural);
end Megacorp.API;
