--  SPDX-License-Identifier: MIT
--  Copyright (c) 2026 Robert Boettcher

with Ada.Containers.Vectors;
with Megacorp.Map;
with Megacorp.Weapons;
use type Ada.Containers.Count_Type;
use type Megacorp.Map.Point;

--  Item 6. One ped on a Megacorp.Path route, advanced by a fixed tick.
--  The position inside a tile is an integer count of sub-tile steps
--  (Along, 0 at the tile centre, toward the next route tile). Facing
--  is the eight-way direction of travel. Speed is sub-tile steps per
--  tick. There is no floating point.
--  Peds occupy their current tile, and also the next tile once a
--  crossing has started. A ped whose next tile is taken waits. After
--  Wait_Limit ticks the ped with the greater id repaths once, treating
--  the other peds' tiles as blocked for that search. The lower id
--  keeps its route. Ticks run in ascending id order, so two peds cannot
--  both enter one free tile on the same tick.
package Megacorp.Peds is
   Steps_Per_Tile : constant := 8;
   Default_Speed  : constant Positive := 1;
   Wait_Limit     : constant := 3;
   Full_Health    : constant := 100;

   subtype Ped_Id is Positive range 1 .. 8;

   type State_Kind is (Standing, Walking, Arrived);

   type Ped is private;

   type Crowd is array (Positive range <>) of Ped;

   function Spawn
     (Who : Ped_Id;
      Start, Goal : Map.Point;
      M : Map.City;
      Speed : Positive := Default_Speed) return Ped
     with Pre =>
       Map.In_Bounds (M, Start.X, Start.Y)
       and then Map.In_Bounds (M, Goal.X, Goal.Y)
       and then Map.Tile_At (M, Start.X, Start.Y).Walkable
       and then Map.Tile_At (M, Goal.X, Goal.Y).Walkable
       and then Speed <= Steps_Per_Tile;

   function Ident (P : Ped) return Ped_Id;
   function Tile_X (P : Ped) return Positive;
   function Tile_Y (P : Ped) return Positive;
   function Along (P : Ped) return Natural
     with Post => Along'Result < Steps_Per_Tile;
   function Facing (P : Ped) return Map.Eight_Way;
   function State_Of (P : Ped) return State_Kind;
   function Speed_Of (P : Ped) return Positive;
   function Health_Of (P : Ped) return Natural
     with Post => Health_Of'Result <= Full_Health;
   function Is_Alive (P : Ped) return Boolean;
   function Ammo_Of (P : Ped) return Natural;

   procedure Arm
     (P : in out Ped; Gun : Weapons.Kind; Rounds : Natural)
     with Post => Ammo_Of (P) = Rounds;

   procedure Spend_Round (P : in out Ped)
     with Pre => Ammo_Of (P) > 0,
       Post => Ammo_Of (P) = Ammo_Of (P)'Old - 1;

   procedure Hurt (P : in out Ped; Amount : Natural)
     with Post =>
       Health_Of (P) <= Health_Of (P)'Old
       and then (if not Is_Alive (P) then Health_Of (P) = 0);

   procedure Face_Toward (P : in out Ped; Target : Map.Point);

   --  A ped standing on one tile, with no route yet.
   function Place
     (Who : Ped_Id;
      At_Point : Map.Point;
      M : Map.City;
      Speed : Positive := Default_Speed) return Ped
     with Pre =>
       Map.In_Bounds (M, At_Point.X, At_Point.Y)
       and then Map.Tile_At (M, At_Point.X, At_Point.Y).Walkable
       and then Speed <= Steps_Per_Tile,
       Post =>
         Ident (Place'Result) = Who
         and then Tile_X (Place'Result) = At_Point.X
         and then Tile_Y (Place'Result) = At_Point.Y
         and then State_Of (Place'Result) = Standing
         and then Along (Place'Result) = 0;

   procedure Set_Facing (P : in out Ped; Dir : Map.Eight_Way);

   --  Stop on the current tile. Drops a half-finished crossing.
   procedure Halt (P : in out Ped)
     with Post =>
       State_Of (P) = Standing and then Along (P) = 0;

   --  Replace the route with a walk to Goal. Accepted is false when
   --  no walk path exists; the ped is left where it stands.
   procedure Command_Walk
     (Group : in out Crowd;
      Index : Positive;
      Goal : Map.Point;
      M : Map.City;
      Accepted : out Boolean)
     with Pre =>
       Index in Group'Range
       and then Distinct_Ids (Group)
       and then Map.In_Bounds (M, Goal.X, Goal.Y)
       and then Map.Tile_At (M, Goal.X, Goal.Y).Walkable;

   --  Ticks needed to finish one tile at this speed.
   function Ticks_To_Cross (Speed : Positive) return Positive
     with Pre => Speed <= Steps_Per_Tile,
       Post =>
         Ticks_To_Cross'Result * Speed >= Steps_Per_Tile
         and then (Ticks_To_Cross'Result - 1) * Speed
           < Steps_Per_Tile;

   function Distinct_Ids (Group : Crowd) return Boolean;

   procedure Tick (Group : in out Crowd; M : Map.City)
     with Pre => Distinct_Ids (Group);

   type Frame is record
      Tick   : Natural;
      Ident  : Ped_Id;
      X      : Positive;
      Y      : Positive;
      Along  : Natural;
      Facing : Map.Eight_Way;
      State  : State_Kind;
   end record;

   package Frame_Lists is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Frame);

   --  Tick 0, then each tick until every ped has arrived or
   --  Max_Ticks is reached. One frame per ped per recorded tick,
   --  in crowd order.
   function Run
     (M : Map.City;
      Start : Crowd;
      Max_Ticks : Natural) return Frame_Lists.Vector
     with Pre =>
       Start'Length > 0 and then Distinct_Ids (Start),
       Post => Run'Result.Length >= Start'Length;

private
   package Step_Lists is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Map.Point);

   type Ped is record
      Ident   : Ped_Id := 1;
      X       : Positive := 1;
      Y       : Positive := 1;
      Goal_X  : Positive := 1;
      Goal_Y  : Positive := 1;
      Along   : Natural := 0;
      Facing  : Map.Eight_Way := Map.South;
      Speed   : Positive := Default_Speed;
      State   : State_Kind := Standing;
      Wait    : Natural := 0;
      Cursor  : Positive := 1;
      Health  : Natural := Full_Health;
      Alive   : Boolean := True;
      Ammo    : Natural := 0;
      Route   : Step_Lists.Vector;
   end record
     with Type_Invariant =>
       Ped.Along < Steps_Per_Tile
       and then Ped.Speed <= Steps_Per_Tile
       and then Ped.Health <= Full_Health
       and then (if Ped.State = Arrived then Ped.Along = 0)
       and then (if not Ped.Alive then Ped.Health = 0);
end Megacorp.Peds;
