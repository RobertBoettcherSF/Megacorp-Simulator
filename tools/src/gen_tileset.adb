--  SPDX-License-Identifier: MIT
--  Copyright (c) 2026 Robert Boettcher

with Ada.Command_Line;
with Ada.Text_IO;
with Tile_Art;

procedure Gen_Tileset is
begin
   if Ada.Command_Line.Argument_Count = 0 then
      Tile_Art.Write ("web/assets");
   else
      Tile_Art.Write (Ada.Command_Line.Argument (1));
   end if;
   Ada.Text_IO.Put_Line ("wrote placeholder tileset");
end Gen_Tileset;
