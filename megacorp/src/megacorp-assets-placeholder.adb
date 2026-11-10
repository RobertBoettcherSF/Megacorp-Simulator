--  SPDX-License-Identifier: MIT
--  Copyright (c) 2026 Robert Boettcher

with Ada.Strings.Fixed;

package body Megacorp.Assets.Placeholder is

   function Read_Int_After (Line, Marker : String) return Integer;
   function Read_Name_After (Line, Marker : String) return String;
   function Terrain_Of (Name : String) return Map.Terrain;
   procedure Consider (Line : String; Set : in out Tileset);

   function Complete (Set : Tileset) return Boolean is
   begin
      for Kind in Map.Terrain loop
         for Level in Map.Height_Level loop
            if not Set.Seen (Kind, Level) then
               return False;
            end if;
         end loop;
      end loop;
      return True;
   end Complete;

   function Has_Tile
     (Set : Tileset;
      Kind : Map.Terrain;
      Level : Map.Height_Level) return Boolean
   is
   begin
      return Set.Seen (Kind, Level);
   end Has_Tile;

   function Tile_Id
     (Set : Tileset;
      Kind : Map.Terrain;
      Level : Map.Height_Level) return Natural
   is
   begin
      return Set.Ids (Kind, Level);
   end Tile_Id;

   function Read_Int_After (Line, Marker : String) return Integer is
      Mark : constant Natural :=
        Ada.Strings.Fixed.Index (Line, Marker);
      Pos : Natural;
      Value : Integer := 0;
   begin
      pragma Assert (Mark > 0);
      Pos := Mark + Marker'Length;
      while Pos <= Line'Last and then Line (Pos) = ' ' loop
         Pos := Pos + 1;
      end loop;
      pragma Assert (Pos <= Line'Last);
      while Pos <= Line'Last and then Line (Pos) in '0' .. '9' loop
         Value := Value * 10
           + (Character'Pos (Line (Pos)) - Character'Pos ('0'));
         Pos := Pos + 1;
      end loop;
      return Value;
   end Read_Int_After;

   function Read_Name_After (Line, Marker : String) return String is
      Mark  : constant Natural :=
        Ada.Strings.Fixed.Index (Line, Marker);
      First : Natural;
      Last  : Natural;
   begin
      pragma Assert (Mark > 0);
      First := Mark + Marker'Length;
      Last := First;
      while Last <= Line'Last and then Line (Last) /= '"' loop
         Last := Last + 1;
      end loop;
      pragma Assert (Last <= Line'Last and then Last > First);
      return Line (First .. Last - 1);
   end Read_Name_After;

   function Terrain_Of (Name : String) return Map.Terrain is
   begin
      if Name = "open" then
         return Map.Open_Ground;
      elsif Name = "road" then
         return Map.Road;
      elsif Name = "pavement" then
         return Map.Pavement;
      elsif Name = "building" then
         return Map.Building;
      elsif Name = "water" then
         return Map.Water;
      else
         raise Constraint_Error;
      end if;
   end Terrain_Of;

   procedure Consider (Line : String; Set : in out Tileset) is
      Id     : Natural;
      Height : Natural;
      Column : Natural;
      Row    : Natural;
      Kind   : Map.Terrain;
      Name   : constant String :=
        Read_Name_After (Line, """terrain"": """);
   begin
      Id := Read_Int_After (Line, """id"":");
      Height := Read_Int_After (Line, """height"":");
      Column := Read_Int_After (Line, """column"":");
      Row := Read_Int_After (Line, """row"":");
      Kind := Terrain_Of (Name);
      pragma Assert (Height <= Map.Height_Level'Last);
      pragma Assert (Column = Height);
      pragma Assert (Row = Map.Terrain'Pos (Kind));
      pragma Assert (Id = Row * 16 + Height);
      pragma Assert (not Set.Seen (Kind, Height));
      Set.Ids (Kind, Height) := Id;
      Set.Seen (Kind, Height) := True;
   end Consider;

   function Load
     (Store : Files.Backend'Class) return Tileset
   is
      Text  : constant String := Store.Read ("assets/tiles.json");
      Set   : Tileset;
      Start : Natural := Text'First;
      Stop  : Natural;
   begin
      pragma Assert (Read_Int_After (Text, """tile_width"":") > 0);
      pragma Assert (Read_Int_After (Text, """columns"":") = 16);
      while Start <= Text'Last loop
         Stop := Start;
         while Stop <= Text'Last and then Text (Stop) /= ASCII.LF loop
            Stop := Stop + 1;
         end loop;
         if Stop > Start
           and then Ada.Strings.Fixed.Index
             (Text (Start .. Stop - 1), """id""") > 0
         then
            Consider (Text (Start .. Stop - 1), Set);
         end if;
         exit when Stop > Text'Last;
         Start := Stop + 1;
      end loop;
      pragma Assert (Complete (Set));
      return Set;
   end Load;

end Megacorp.Assets.Placeholder;
