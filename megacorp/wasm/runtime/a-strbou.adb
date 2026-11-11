--  SPDX-License-Identifier: MIT
--  Copyright (c) 2026 Robert Boettcher

package body Ada.Strings.Bounded is
   package body Generic_Bounded_Length is
      function To_Bounded_String (Source : String) return Bounded_String is
         Result : Bounded_String;
         Last : Natural;
      begin
         Last := Source'Length;
         if Last > Max then
            Last := Max;
         end if;
         Result.Count := Last;
         if Last > 0 then
            Result.Data (1 .. Last) :=
              Source (Source'First .. Source'First + Last - 1);
         end if;
         return Result;
      end To_Bounded_String;

      function To_String (Source : Bounded_String) return String is
      begin
         return Source.Data (1 .. Source.Count);
      end To_String;

      function Length (Source : Bounded_String) return Natural is
      begin
         return Source.Count;
      end Length;
   end Generic_Bounded_Length;
end Ada.Strings.Bounded;
