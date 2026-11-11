--  SPDX-License-Identifier: MIT
--  Copyright (c) 2026 Robert Boettcher

--  Enough of Unbounded_String for the save encoder. The wasm
--  runtime does not ship this unit.
package Ada.Strings.Unbounded is
   type Unbounded_String is private;
   Null_Unbounded_String : constant Unbounded_String;

   function To_Unbounded_String
     (Source : String) return Unbounded_String;

   function To_String (Source : Unbounded_String) return String;

   function "&"
     (Left : Unbounded_String;
      Right : String) return Unbounded_String;

private
   type String_Access is access all String;
   type Unbounded_String is record
      Ref : String_Access;
   end record;
   Null_Unbounded_String : constant Unbounded_String :=
     (Ref => null);
end Ada.Strings.Unbounded;
