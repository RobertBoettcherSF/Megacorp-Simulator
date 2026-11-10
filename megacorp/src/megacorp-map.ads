--  SPDX-License-Identifier: MIT
--  Copyright (c) 2026 Robert Boettcher

with Megacorp.Parameters;
with Megacorp.RNG;
use type Megacorp.RNG.Word;

--  Item 3. One city tile map.
--  X increases east, Y increases south, both counted from 1.
--  Test_Layout is a seeded stand-in. The city-block generator
--  (item 13) replaces it later.
package Megacorp.Map is
   type Terrain is
     (Open_Ground, Road, Pavement, Building, Water);

   subtype Height_Level is Natural range 0 .. 15;

   type Tile is record
      Kind     : Terrain := Open_Ground;
      Level    : Height_Level := 1;
      Walkable : Boolean := True;
      Drivable : Boolean := False;
   end record;

   type City (Width, Height : Positive) is private;

   type Point is record
      X : Positive;
      Y : Positive;
   end record;

   type Four_Way is (North, East, South, West);
   type Eight_Way is
     (North, East, South, West,
      North_East, South_East, South_West, North_West);

   function Layout_Seed (M : City) return RNG.Word;

   function In_Bounds (M : City; X, Y : Integer) return Boolean;

   function Tile_At (M : City; X, Y : Integer) return Tile
     with Pre => In_Bounds (M, X, Y);

   function Has_Neighbour_4
     (M : City; X, Y : Integer; Dir : Four_Way) return Boolean
     with Pre => In_Bounds (M, X, Y);

   function Neighbour_4
     (M : City; X, Y : Integer; Dir : Four_Way) return Point
     with Pre => Has_Neighbour_4 (M, X, Y, Dir),
       Post =>
         In_Bounds
           (M, Neighbour_4'Result.X, Neighbour_4'Result.Y)
         and then
           abs (Neighbour_4'Result.X - X)
           + abs (Neighbour_4'Result.Y - Y) = 1;

   function Has_Neighbour_8
     (M : City; X, Y : Integer; Dir : Eight_Way) return Boolean
     with Pre => In_Bounds (M, X, Y);

   function Neighbour_8
     (M : City; X, Y : Integer; Dir : Eight_Way) return Point
     with Pre => Has_Neighbour_8 (M, X, Y, Dir),
       Post =>
         In_Bounds
           (M, Neighbour_8'Result.X, Neighbour_8'Result.Y)
         and then
           (Neighbour_8'Result.X /= X
            or else Neighbour_8'Result.Y /= Y)
         and then abs (Neighbour_8'Result.X - X) <= 1
         and then abs (Neighbour_8'Result.Y - Y) <= 1;

   --  Road grid, pavement, building blocks, and a river.
   --  The stream is the city-1 child of From. Same seed, same map.
   function Blank (Width, Height : Positive) return City
     with Pre =>
       Width <= Parameters.Max_City_Map_Edge
       and then Height <= Parameters.Max_City_Map_Edge,
       Post =>
         Blank'Result.Width = Width
         and then Blank'Result.Height = Height;

   procedure Set_Tile
     (M : in out City; X, Y : Integer; Cell : Tile)
     with Pre => In_Bounds (M, X, Y),
       Post => Tile_At (M, X, Y) = Cell;

   function Test_Layout
     (From : RNG.Word; Width, Height : Positive) return City
     with Pre =>
       Width <= Parameters.Max_City_Map_Edge
       and then Height <= Parameters.Max_City_Map_Edge,
       Post =>
         Test_Layout'Result.Width = Width
         and then Test_Layout'Result.Height = Height
         and then Layout_Seed (Test_Layout'Result) = From;

   function Test_Layout
     (From : RNG.Word;
      Size : Parameters.Generator_Parameters) return City
     with Post =>
       Test_Layout'Result.Width = Parameters.City_Map_Width (Size)
       and then Test_Layout'Result.Height
         = Parameters.City_Map_Height (Size)
       and then Layout_Seed (Test_Layout'Result) = From;

   function Terrain_Code (Kind : Terrain) return Character
     with Post => Terrain_Code'Result in '.' | '+' | '=' | 'B' | '~';

   --  Clip to the map. Row 1 of the window is the northern edge
   --  of the requested rectangle.
   procedure Put_Window
     (M : City;
      First_X, First_Y : Positive;
      Columns, Rows : Natural);

   --  Northwest corner, then a window on the river when the
   --  layout has one.
   procedure Put_Sample (M : City);

   --  Seeds written for the browser page, in file order.
   Export_Seed_Count : constant := 3;
   type Export_Seed_List is
     array (1 .. Export_Seed_Count) of RNG.Word;
   Export_Seeds : constant Export_Seed_List := (1, 42, 100);

   --  Write index.json and one JSON map per export seed.
   --  Each cell is five characters: terrain, hex height, flags,
   --  and two hex digits of the placeholder tile id.
   --  Flags: bit 0 walkable, bit 1 drivable, as a digit 0..3.
   procedure Export_Maps (Directory : String; Version : String)
     with Pre => Directory'Length > 0 and then Version'Length > 0;

private
   type Tile_Grid is
     array (Positive range <>, Positive range <>) of Tile;

   type City (Width, Height : Positive) is record
      From_Seed : RNG.Word := 0;
      Cell      : Tile_Grid (1 .. Width, 1 .. Height);
   end record;
end Megacorp.Map;
