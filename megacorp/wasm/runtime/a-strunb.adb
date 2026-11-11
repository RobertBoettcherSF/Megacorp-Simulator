--  SPDX-License-Identifier: MIT
--  Copyright (c) 2026 Robert Boettcher

package body Ada.Strings.Unbounded is
   function To_Unbounded_String
     (Source : String) return Unbounded_String
   is
   begin
      if Source'Length = 0 then
         return Null_Unbounded_String;
      end if;
      return (Ref => new String'(Source));
   end To_Unbounded_String;

   function To_String (Source : Unbounded_String) return String is
   begin
      if Source.Ref = null then
         return "";
      end if;
      return Source.Ref.all;
   end To_String;

   function "&"
     (Left : Unbounded_String;
      Right : String) return Unbounded_String
   is
   begin
      return To_Unbounded_String (To_String (Left) & Right);
   end "&";
end Ada.Strings.Unbounded;
