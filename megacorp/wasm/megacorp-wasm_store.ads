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
end Megacorp.Wasm_Store;
