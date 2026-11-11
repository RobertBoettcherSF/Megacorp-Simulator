--  SPDX-License-Identifier: MIT
--  Copyright (c) 2026 Robert Boettcher

--  The live world never builds a city. The save log mentions the
--  map types, so this body exists for the wasm link only.
package body Megacorp.Map is
   function Layout_Seed (M : City) return RNG.Word is
   begin
      return M.From_Seed;
   end Layout_Seed;

   function In_Bounds (M : City; X, Y : Integer) return Boolean is
   begin
      return X in 1 .. M.Width and then Y in 1 .. M.Height;
   end In_Bounds;

   function Tile_At (M : City; X, Y : Integer) return Tile is
   begin
      return M.Cell (X, Y);
   end Tile_At;

   type Delta_XY is record
      DX : Integer;
      DY : Integer;
   end record;

   Four_Step : constant array (Four_Way) of Delta_XY :=
     (North => (DX => 0, DY => -1),
      East  => (DX => 1, DY => 0),
      South => (DX => 0, DY => 1),
      West  => (DX => -1, DY => 0));

   Eight_Step : constant array (Eight_Way) of Delta_XY :=
     (North => (DX => 0, DY => -1),
      East => (DX => 1, DY => 0),
      South => (DX => 0, DY => 1),
      West => (DX => -1, DY => 0),
      North_East => (DX => 1, DY => -1),
      South_East => (DX => 1, DY => 1),
      South_West => (DX => -1, DY => 1),
      North_West => (DX => -1, DY => -1));

   function Has_Neighbour_4
     (M : City; X, Y : Integer; Dir : Four_Way) return Boolean
   is
      Step : constant Delta_XY := Four_Step (Dir);
   begin
      return In_Bounds (M, X + Step.DX, Y + Step.DY);
   end Has_Neighbour_4;

   function Neighbour_4
     (M : City; X, Y : Integer; Dir : Four_Way) return Point
   is
      Step : constant Delta_XY := Four_Step (Dir);
   begin
      return (X => X + Step.DX, Y => Y + Step.DY);
   end Neighbour_4;

   function Has_Neighbour_8
     (M : City; X, Y : Integer; Dir : Eight_Way) return Boolean
   is
      Step : constant Delta_XY := Eight_Step (Dir);
   begin
      return In_Bounds (M, X + Step.DX, Y + Step.DY);
   end Has_Neighbour_8;

   function Neighbour_8
     (M : City; X, Y : Integer; Dir : Eight_Way) return Point
   is
      Step : constant Delta_XY := Eight_Step (Dir);
   begin
      return (X => X + Step.DX, Y => Y + Step.DY);
   end Neighbour_8;

   function Blank (Width, Height : Positive) return City is
      Result : City (Width, Height);
   begin
      return Result;
   end Blank;

   procedure Set_Tile
     (M : in out City; X, Y : Integer; Cell : Tile)
   is
   begin
      M.Cell (X, Y) := Cell;
   end Set_Tile;

   function Test_Layout
     (From : RNG.Word; Width, Height : Positive) return City
   is
      Result : City (Width, Height);
   begin
      Result.From_Seed := From;
      return Result;
   end Test_Layout;

   function Test_Layout
     (From : RNG.Word;
      Size : Parameters.Generator_Parameters) return City
   is
   begin
      return Test_Layout
        (From,
         Parameters.City_Map_Width (Size),
         Parameters.City_Map_Height (Size));
   end Test_Layout;

   function Terrain_Code (Kind : Terrain) return Character is
   begin
      case Kind is
         when Open_Ground =>
            return '.';
         when Road =>
            return '+';
         when Pavement =>
            return '=';
         when Building =>
            return 'B';
         when Water =>
            return '~';
      end case;
   end Terrain_Code;

   procedure Put_Window
     (M : City;
      First_X, First_Y : Positive;
      Columns, Rows : Natural)
   is
      pragma Unreferenced (M, First_X, First_Y, Columns, Rows);
   begin
      null;
   end Put_Window;

   procedure Put_Sample (M : City) is
      pragma Unreferenced (M);
   begin
      null;
   end Put_Sample;

   procedure Export_Maps (Directory : String; Version : String) is
      pragma Unreferenced (Directory, Version);
   begin
      null;
   end Export_Maps;
end Megacorp.Map;
