--  SPDX-License-Identifier: MIT
--  Copyright (c) 2026 Robert Boettcher

package body Megacorp.Assets.Import is
   function Has (Text, Needle : String) return Boolean;
   function Suffix (Name, Tail : String) return Boolean;
   function Png (Data : String) return Boolean;

   function Has (Text, Needle : String) return Boolean is
   begin
      if Needle'Length = 0 or else Text'Length < Needle'Length then
         return False;
      end if;
      for I in Text'First .. Text'Last - Needle'Length + 1 loop
         if Text (I .. I + Needle'Length - 1) = Needle then
            return True;
         end if;
      end loop;
      return False;
   end Has;

   function Suffix (Name, Tail : String) return Boolean is
   begin
      return Name'Length >= Tail'Length
        and then Name (Name'Last - Tail'Length + 1 .. Name'Last) = Tail;
   end Suffix;

   function Png (Data : String) return Boolean is
   begin
      return Data'Length >= 8
        and then Character'Pos (Data (Data'First)) = 16#89#
        and then Data (Data'First + 1 .. Data'First + 3) = "PNG"
        and then Character'Pos (Data (Data'First + 4)) = 13
        and then Character'Pos (Data (Data'First + 5)) = 10
        and then Character'Pos (Data (Data'First + 6)) = 16#1A#
        and then Character'Pos (Data (Data'First + 7)) = 10;
   end Png;

   function Accepts (Name : String; Data : String) return Boolean is
   begin
      if Name'Length = 0 or else Data'Length = 0 then
         return False;
      end if;
      if Suffix (Name, ".png") then
         return Png (Data);
      elsif Suffix (Name, ".json") then
         return Has (Data, "tile_width") and then Has (Data, "tiles");
      end if;
      return False;
   end Accepts;
end Megacorp.Assets.Import;
