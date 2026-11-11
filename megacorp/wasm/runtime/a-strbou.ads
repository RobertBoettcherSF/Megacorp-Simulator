--  SPDX-License-Identifier: MIT
--  Copyright (c) 2026 Robert Boettcher

--  Enough of bounded strings for action tokens in the wasm build.
package Ada.Strings.Bounded is
   generic
      Max : Positive;
   package Generic_Bounded_Length is
      type Bounded_String is private;

      function To_Bounded_String (Source : String) return Bounded_String;

      function To_String (Source : Bounded_String) return String;

      function Length (Source : Bounded_String) return Natural;

   private
      type Bounded_String is record
         Count : Natural := 0;
         Data  : String (1 .. Max) := (others => ' ');
      end record;
   end Generic_Bounded_Length;
end Ada.Strings.Bounded;
