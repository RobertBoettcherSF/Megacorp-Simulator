--  SPDX-License-Identifier: MIT
--  Copyright (c) 2026 Robert Boettcher

--  Item 21. Browser files. The bytes live in the host (OPFS, or
--  IndexedDB / localStorage when that is missing). This unit only
--  copies them. It does not know which store the host picked.
package Megacorp.Data.Virtual_FS.Browser is
   type Disk is new Backend with private;

   function Open return Disk;

   overriding function Exists
     (Store : Disk; Path : String) return Boolean;

   overriding function Read
     (Store : Disk; Path : String) return String
     with Pre => Exists (Store, Path);

   overriding function List
     (Store : Disk; Path : String) return Name_Lists.Vector
     with Pre => Is_Logical_Path (Path);

   overriding procedure Write
     (Store : in out Disk;
      Path : String;
      Data : String)
     with Pre => Is_Logical_Path (Path) and then Path'Length > 0;

   overriding procedure Append
     (Store : in out Disk;
      Path : String;
      Data : String)
     with Pre => Is_Logical_Path (Path) and then Path'Length > 0;

private
   type Disk is new Backend with null record;
end Megacorp.Data.Virtual_FS.Browser;
