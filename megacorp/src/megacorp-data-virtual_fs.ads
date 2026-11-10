--  SPDX-License-Identifier: MIT
--  Copyright (c) 2026 Robert Boettcher

with Ada.Containers.Indefinite_Vectors;

--  Item 4. Read files by a logical path such as "assets/tiles.json".
--  The core uses this interface only. Megacorp.Data.Virtual_FS.Native
--  is the disk backend. A later WASM host can implement Backend with
--  OPFS or fetch. Callers take Backend'Class.
package Megacorp.Data.Virtual_FS is
   package Name_Lists is new Ada.Containers.Indefinite_Vectors
     (Index_Type => Positive, Element_Type => String);

   type Backend is interface;

   --  True for an ordinary file. Directories and missing paths are
   --  false. An unsafe path (absolute, or a ".." segment) is false.
   function Exists
     (Store : Backend; Path : String) return Boolean is abstract;

   function Read
     (Store : Backend; Path : String) return String is abstract
     with Pre'Class => Exists (Store, Path);

   --  Simple names in a logical directory, sorted. Empty if the
   --  directory is missing. Path "" lists the backend root.
   function List
     (Store : Backend; Path : String) return Name_Lists.Vector
      is abstract
     with Pre'Class => Is_Logical_Path (Path);

   function Is_Logical_Path (Path : String) return Boolean;
end Megacorp.Data.Virtual_FS;
