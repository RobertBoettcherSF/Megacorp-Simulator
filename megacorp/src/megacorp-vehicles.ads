--  SPDX-License-Identifier: MIT
--  Copyright (c) 2026 Robert Boettcher

with Ada.Containers.Vectors;
with Megacorp.Map;
with Megacorp.Path;
with Megacorp.Peds;
use type Megacorp.Map.Point;

--  Item 9. Cars and vans on the drive graph.
--  Position inside a tile is an integer count of sub-tile steps,
--  the same counter peds use. A vehicle holds its tile, and the
--  next tile once a crossing has started. An intact vehicle blocks
--  walking. A wreck blocks driving and does not block walking.
package Megacorp.Vehicles is
   --  64 is the cap chosen in 0.15.0. A city fleet is much smaller.
   --  The drive tick walks the fleet, not every id in this range.
   subtype Vehicle_Id is Positive range 1 .. 64;

   type Kind is (Car, Van);

   type State_Kind is (Parked, Driving, Arrived, Wrecked);

   --  Placeholder figures. A car is quicker and lighter. A van
   --  carries more and takes more fire. These numbers are ours.
   Car_Health : constant := 80;
   Van_Health : constant := 120;
   Car_Speed  : constant := 2;
   Van_Speed  : constant := 1;
   Car_Seats  : constant := 2;
   Van_Seats  : constant := 4;
   Max_Seats  : constant := 4;
   Wait_Limit : constant := 3;

   type Vehicle is private;

   type Fleet is array (Positive range <>) of Vehicle;

   function Health_Cap (Which : Kind) return Positive;
   function Step_Speed (Which : Kind) return Positive;
   function Seat_Cap (Which : Kind) return Positive;
   function Kind_Token (Which : Kind) return String;
   function State_Token (Motion : State_Kind) return String;

   function Park
     (Who : Vehicle_Id;
      Which : Kind;
      At_Point : Map.Point;
      M : Map.City;
      Dir : Map.Eight_Way := Map.South) return Vehicle
     with Pre =>
       Map.In_Bounds (M, At_Point.X, At_Point.Y)
       and then Map.Tile_At (M, At_Point.X, At_Point.Y).Drivable,
       Post =>
         Ident (Park'Result) = Who
         and then Sort_Of (Park'Result) = Which
         and then Tile_X (Park'Result) = At_Point.X
         and then Tile_Y (Park'Result) = At_Point.Y
         and then State_Of (Park'Result) = Parked
         and then Along (Park'Result) = 0
         and then Is_Intact (Park'Result)
         and then Health_Of (Park'Result) = Health_Cap (Which)
         and then Rider_Count (Park'Result) = 0;

   function Ident (V : Vehicle) return Vehicle_Id;
   function Sort_Of (V : Vehicle) return Kind;
   function Tile_X (V : Vehicle) return Positive;
   function Tile_Y (V : Vehicle) return Positive;
   function Along (V : Vehicle) return Natural
     with Post => Along'Result < Peds.Steps_Per_Tile;
   function Facing (V : Vehicle) return Map.Eight_Way;
   function State_Of (V : Vehicle) return State_Kind;
   function Speed_Of (V : Vehicle) return Positive;
   function Health_Of (V : Vehicle) return Natural;
   function Is_Intact (V : Vehicle) return Boolean;
   function Rider_Count (V : Vehicle) return Natural
     with Post => Rider_Count'Result <= Max_Seats;
   function Rider
     (V : Vehicle; Index : Positive) return Peds.Ped_Id
     with Pre => Index <= Rider_Count (V);

   function Aboard (V : Vehicle; Who : Peds.Ped_Id) return Boolean;

   --  Current tile, and the next route tile while a crossing is
   --  in progress. A wreck covers only the tile it stopped on.
   function Covers (V : Vehicle; X, Y : Positive) return Boolean;

   function Blocks_Walk (V : Vehicle; X, Y : Positive) return Boolean;

   procedure Board
     (V : in out Vehicle;
      Who : Peds.Ped_Id;
      Accepted : out Boolean)
     with Post =>
       (if Accepted
        then Aboard (V, Who) and then Is_Intact (V));

   procedure Alight
     (V : in out Vehicle;
      Who : Peds.Ped_Id;
      Accepted : out Boolean)
     with Post => (if Accepted then not Aboard (V, Who));

   procedure Clear_Riders (V : in out Vehicle)
     with Post => Rider_Count (V) = 0;

   function Find_Ride
     (Group : Fleet; Who : Peds.Ped_Id) return Natural;

   --  Walking: intact vehicles only. Otherwise wrecks too.
   --  Except is a fleet index to skip, or 0 to keep every vehicle.
   procedure Add_Blocks
     (Group : Fleet;
      Except : Natural;
      Walking : Boolean;
      Into : in out Path.Block_Lists.Vector);

   procedure Command_Drive
     (Group : in out Fleet;
      Index : Positive;
      Goal : Map.Point;
      M : Map.City;
      Foot : Path.Block_Lists.Vector;
      Accepted : out Boolean)
     with Pre =>
       Index in Group'Range
       and then Map.In_Bounds (M, Goal.X, Goal.Y);

   --  One tick of an already commanded drive. Other vehicles and
   --  Foot tiles (peds on foot) block the next step.
   procedure Advance
     (Group : in out Fleet;
      Index : Positive;
      M : Map.City;
      Foot : Path.Block_Lists.Vector)
     with Pre => Index in Group'Range;

   --  Stay on the current tile. An intact vehicle becomes parked.
   procedure Stop (V : in out Vehicle)
     with Post =>
       Along (V) = 0
       and then (if Is_Intact (V) then State_Of (V) = Parked);

   procedure Hurt (V : in out Vehicle; Amount : Natural)
     with Post =>
       Health_Of (V) <= Health_Of (V)'Old
       and then (if not Is_Intact (V)
                 then Health_Of (V) = 0
                   and then State_Of (V) = Wrecked
                   and then Along (V) = 0);

private
   package Step_Lists is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Map.Point);

   type Seat_List is array (1 .. Max_Seats) of Peds.Ped_Id;

   type Vehicle is record
      Ident  : Vehicle_Id := 1;
      Sort   : Kind := Car;
      X      : Positive := 1;
      Y      : Positive := 1;
      Goal_X : Positive := 1;
      Goal_Y : Positive := 1;
      Along  : Natural := 0;
      Facing : Map.Eight_Way := Map.South;
      Speed  : Positive := Car_Speed;
      Motion : State_Kind := Parked;
      Wait   : Natural := 0;
      Cursor : Positive := 1;
      Health : Natural := Car_Health;
      Intact : Boolean := True;
      Riders : Natural := 0;
      Seat   : Seat_List := (others => 1);
      Route  : Step_Lists.Vector;
   end record
     with Type_Invariant =>
       Vehicle.Along < Peds.Steps_Per_Tile
       and then Vehicle.Speed <= Peds.Steps_Per_Tile
       and then Vehicle.Riders <= Max_Seats
       and then Vehicle.Health <= Van_Health
       and then (if Vehicle.Sort = Car
                 then Vehicle.Health <= Car_Health
                   and then Vehicle.Riders <= Car_Seats)
       and then (if not Vehicle.Intact
                 then Vehicle.Health = 0
                   and then Vehicle.Motion = Wrecked)
       and then (if Vehicle.Motion /= Driving
                 then Vehicle.Along = 0);
end Megacorp.Vehicles;
