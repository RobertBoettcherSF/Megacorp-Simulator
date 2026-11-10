--  SPDX-License-Identifier: MIT
--  Copyright (c) 2026 Robert Boettcher

--  Disk backend. Logical paths are relative to Root. This is the
--  only unit that calls the host file system for asset reads.
package Megacorp.Data.Virtual_FS.Native is
   type Disk (Length : Natural) is new Backend with private;

   function Open (Root : String) return Disk
     with Pre => Root'Length > 0,
       Post => Open'Result.Length = Root'Length;

   overriding function Exists
     (Store : Disk; Path : String) return Boolean;

   overriding function Read
     (Store : Disk; Path : String) return String
     with Pre => Exists (Store, Path);

   overriding function List
     (Store : Disk; Path : String) return Name_Lists.Vector
     with Pre => Is_Logical_Path (Path);

private
   type Disk (Length : Natural) is new Backend with record
      Root : String (1 .. Length);
   end record;
end Megacorp.Data.Virtual_FS.Native;
