--  SPDX-License-Identifier: MIT
--  Copyright (c) 2026 Robert Boettcher

with Interfaces;
with System;

--  Item 21. The browser calls these. They read and write the
--  version-2 snapshot and the delta log through the host files.
package Megacorp.Wasm_Store is
   procedure Boot (Seed : Interfaces.Unsigned_32)
     with Export,
          Convention => C,
          External_Name => "megacorp_boot";

   procedure Advance (Days : Interfaces.Unsigned_32)
     with Export,
          Convention => C,
          External_Name => "megacorp_advance";

   procedure Reset (Seed : Interfaces.Unsigned_32)
     with Export,
          Convention => C,
          External_Name => "megacorp_reset";

   function Import_Buffer return System.Address
     with Export,
          Convention => C,
          External_Name => "megacorp_import_buffer";

   function Import_Capacity return Interfaces.Unsigned_32
     with Export,
          Convention => C,
          External_Name => "megacorp_import_capacity";

   function Commit_Asset
     (Name : System.Address;
      Name_Len : Interfaces.Unsigned_32;
      Data_Len : Interfaces.Unsigned_32) return Interfaces.Unsigned_32
     with Export,
          Convention => C,
          External_Name => "megacorp_commit_asset";

   --  Item 22. One city command, then a batch of fixed ticks.
   procedure Command (Code, A, B, C, D, E : Integer)
     with Export,
          Convention => C,
          External_Name => "megacorp_command";

   procedure Play_Ticks (Count : Interfaces.Unsigned_32)
     with Export,
          Convention => C,
          External_Name => "megacorp_play";

   function City_State return System.Address
     with Export,
          Convention => C,
          External_Name => "megacorp_city";

   function City_State_Size return Interfaces.Unsigned_32
     with Export,
          Convention => C,
          External_Name => "megacorp_city_size";

   function Brief return System.Address
     with Export,
          Convention => C,
          External_Name => "megacorp_brief";

   function Brief_Size return Interfaces.Unsigned_32
     with Export,
          Convention => C,
          External_Name => "megacorp_brief_size";

   --  Item 25. Roster, research, and the player's funds.
   --  JavaScript only reads this buffer.
   function Office return System.Address
     with Export,
          Convention => C,
          External_Name => "megacorp_office";

   function Office_Size return Interfaces.Unsigned_32
     with Export,
          Convention => C,
          External_Name => "megacorp_office_size";

   --  Item 26. The current menu. JavaScript only draws it.
   function Menu_State return System.Address
     with Export,
          Convention => C,
          External_Name => "megacorp_menu";

   function Menu_State_Size return Interfaces.Unsigned_32
     with Export,
          Convention => C,
          External_Name => "megacorp_menu_size";

   --  Item 27. Event codes for the ticks just run, plus the
   --  voice and ambient tables.
   function Sound_State return System.Address
     with Export,
          Convention => C,
          External_Name => "megacorp_sound";

   function Sound_State_Size return Interfaces.Unsigned_32
     with Export,
          Convention => C,
          External_Name => "megacorp_sound_size";
end Megacorp.Wasm_Store;
