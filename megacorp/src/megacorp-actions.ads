--  SPDX-License-Identifier: MIT
--  Copyright (c) 2026 Robert Boettcher

with Ada.Containers.Vectors;
with Ada.Strings.Bounded;
with Megacorp.Map;
with Megacorp.Peds;
with Megacorp.RNG;
with Megacorp.Vehicles;
with Megacorp.Weapons;
use type Ada.Containers.Count_Type;

--  Item 7. One queue of actions per ped.
--  Each tick the front action runs. Done removes it and the next
--  action waits for the following tick. Failed clears the queue and
--  the ped stands. An order replaces the queue or appends to it, and
--  takes effect on the next tick. Walk_To uses Megacorp.Peds, so
--  blocking and repathing stay in the movement tick.
package Megacorp.Actions is
   Capacity : constant := 8;

   type Kind is
     (Walk_To, Wait, Turn_To, Follow, Pick_Up, Shoot_At,
      Enter_Vehicle, Exit_Vehicle, Drive_To, Shoot_Vehicle);

   type Mode is (Replace, Append);

   type Item_Id is range 1 .. 4;

   type Action (Which : Kind := Wait) is private;

   function Make_Walk (Goal : Map.Point) return Action;
   function Make_Wait (Ticks : Positive) return Action
     with Pre => Ticks <= 100;
   function Make_Turn (Dir : Map.Eight_Way) return Action;
   function Make_Follow (Target : Peds.Ped_Id) return Action;
   function Make_Pick (Item : Item_Id) return Action;
   function Make_Shoot
     (Target : Peds.Ped_Id; Gun : Weapons.Kind) return Action;
   function Make_Enter (Which : Vehicles.Vehicle_Id) return Action;
   function Make_Exit (Which : Vehicles.Vehicle_Id) return Action;
   function Make_Drive
     (Which : Vehicles.Vehicle_Id; Goal : Map.Point) return Action;
   function Make_Shoot_Vehicle
     (Which : Vehicles.Vehicle_Id; Gun : Weapons.Kind) return Action;

   function Token (A : Action) return String;

   type Action_Array is array (Positive range <>) of Action;

   type Item is record
      Ident : Item_Id := 1;
      X     : Positive := 1;
      Y     : Positive := 1;
      Here  : Boolean := True;
   end record;

   type Bag is array (Positive range <>) of Item;

   type Actor is private;

   type Cast is array (Positive range <>) of Actor;

   function Recruit
     (Who : Peds.Ped_Id;
      At_Point : Map.Point;
      M : Map.City;
      Seed : RNG.Word := 1) return Actor
     with Pre =>
       Map.In_Bounds (M, At_Point.X, At_Point.Y)
       and then Map.Tile_At (M, At_Point.X, At_Point.Y).Walkable;

   procedure Arm
     (Group : in out Cast;
      Index : Positive;
      Gun : Weapons.Kind;
      Rounds : Natural)
     with Pre => Index in Group'Range;

   function Length (A : Actor) return Natural
     with Post => Length'Result <= Capacity;

   function Is_Pending (A : Actor) return Boolean;

   --  How many more actions an order of this mode may carry.
   function Room (A : Actor; How : Mode) return Natural
     with Post => Room'Result <= Capacity;

   function Front (A : Actor) return Action
     with Pre => Length (A) > 0;

   function At_Queue (A : Actor; Index : Positive) return Action
     with Pre => Index <= Length (A);

   function Ped_Ident (A : Actor) return Peds.Ped_Id;
   function Ped_X (A : Actor) return Positive;
   function Ped_Y (A : Actor) return Positive;
   function Ped_Along (A : Actor) return Natural;
   function Ped_Facing (A : Actor) return Map.Eight_Way;
   function Ped_State (A : Actor) return Peds.State_Kind;
   function Ped_Health (A : Actor) return Natural;
   function Ped_Alive (A : Actor) return Boolean;
   function Ped_Ammo (A : Actor) return Natural;

   function Distinct (Group : Cast) return Boolean;

   --  Put a ped in a vehicle before the first tick. The ped rides
   --  from that vehicle's current tile.
   procedure Embark
     (Group : in out Cast;
      Index : Positive;
      Fleet : in out Vehicles.Fleet;
      Slot : Positive;
      Accepted : out Boolean)
     with Pre =>
       Index in Group'Range and then Slot in Fleet'Range;

   procedure Order
     (Group : in out Cast;
      Index : Positive;
      Actions : Action_Array;
      How : Mode)
     with Pre =>
       Index in Group'Range
       and then Actions'Length <= Room (Group (Index), How);

   procedure Tick
     (Group : in out Cast;
      M : Map.City;
      Items : in out Bag)
     with Pre => Distinct (Group);

   procedure Tick
     (Group : in out Cast;
      M : Map.City;
      Items : in out Bag;
      Fleet : in out Vehicles.Fleet)
     with Pre => Distinct (Group);

   Max_Token : constant := 40;

   package Token_Strings is new Ada.Strings.Bounded.Generic_Bounded_Length
     (Max_Token);

   type Token_List is array (1 .. Capacity) of Token_Strings.Bounded_String;

   --  What the front action was during this tick, and what is still
   --  queued behind it after the tick.
   type Snapshot is record
      Tick       : Natural := 0;
      Ident      : Peds.Ped_Id := 1;
      X          : Positive := 1;
      Y          : Positive := 1;
      Along      : Natural := 0;
      Facing     : Map.Eight_Way := Map.South;
      State      : Peds.State_Kind := Peds.Standing;
      Has_Action : Boolean := False;
      Action     : Token_Strings.Bounded_String;
      Rest_Count : Natural := 0;
      Rest       : Token_List;
      Item_Here  : Boolean := True;
      Health     : Natural := Peds.Full_Health;
      Ammo       : Natural := 0;
      Alive      : Boolean := True;
      Fired      : Boolean := False;
      Landed     : Boolean := False;
      At_X       : Positive := 1;
      At_Y       : Positive := 1;
   end record;

   package Shot_Lists is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Snapshot);

   --  Tick 0, then each tick until every queue is empty or Max_Ticks
   --  is reached. One snapshot per ped per recorded tick.
   function Run
     (M : Map.City;
      Start : Cast;
      Items : Bag;
      Max_Ticks : Natural) return Shot_Lists.Vector
     with Pre =>
       Start'Length > 0 and then Distinct (Start),
       Post => Run'Result.Length >= Start'Length;

   type Rider_Set is array (1 .. Vehicles.Max_Seats) of Natural;

   type Ride_Frame is record
      Tick   : Natural := 0;
      Ident  : Vehicles.Vehicle_Id := 1;
      Sort   : Vehicles.Kind := Vehicles.Car;
      X      : Positive := 1;
      Y      : Positive := 1;
      Along  : Natural := 0;
      Facing : Map.Eight_Way := Map.South;
      Motion : Vehicles.State_Kind := Vehicles.Parked;
      Health : Natural := 0;
      Cap    : Positive := 1;
      Intact : Boolean := True;
      Riders : Natural := 0;
      Rider  : Rider_Set := (others => 0);
   end record;

   package Ride_Lists is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Ride_Frame);

   type Outing is record
      Peds : Shot_Lists.Vector;
      Cars : Ride_Lists.Vector;
   end record;

   --  Where the scripted road demo places the car, the van, and
   --  the peds. The drive is Car_At to Goal.
   type Road_Plan is record
      Car_At     : Map.Point := (X => 1, Y => 1);
      Goal       : Map.Point := (X => 1, Y => 1);
      Board      : Map.Point := (X => 1, Y => 1);
      Ped_At     : Map.Point := (X => 1, Y => 1);
      Van_At     : Map.Point := (X => 1, Y => 1);
      Shooter_At : Map.Point := (X => 1, Y => 1);
   end record;

   function Vehicle_Demo (M : Map.City) return Road_Plan;

   function Run_Vehicles
     (M : Map.City; Seed : RNG.Word) return Outing;

   function Play
     (M : Map.City;
      Start : Cast;
      Items : Bag;
      Fleet : Vehicles.Fleet;
      Max_Ticks : Natural) return Outing
     with Pre =>
       Start'Length > 0 and then Distinct (Start),
       Post => Play'Result.Peds.Length >= Start'Length;

private
   type Action (Which : Kind := Wait) is record
      case Which is
         when Walk_To =>
            Goal : Map.Point := (X => 1, Y => 1);
         when Wait =>
            Total : Positive := 1;
            Left  : Natural := 1;
         when Turn_To =>
            Dir : Map.Eight_Way := Map.South;
         when Follow =>
            Target : Peds.Ped_Id := 1;
         when Pick_Up =>
            Item : Item_Id := 1;
         when Shoot_At =>
            Foe      : Peds.Ped_Id := 1;
            Gun      : Weapons.Kind := Weapons.Pistol;
            Aim_Left : Natural := 1;
            Gap      : Natural := 0;
         when Enter_Vehicle =>
            Board : Vehicles.Vehicle_Id := 1;
         when Exit_Vehicle =>
            Leave : Vehicles.Vehicle_Id := 1;
         when Drive_To =>
            Ride       : Vehicles.Vehicle_Id := 1;
            Drive_Goal : Map.Point := (X => 1, Y => 1);
         when Shoot_Vehicle =>
            Rig     : Vehicles.Vehicle_Id := 1;
            Rig_Gun : Weapons.Kind := Weapons.Pistol;
            Rig_Aim : Natural := 1;
            Rig_Gap : Natural := 0;
      end case;
   end record;

   type Action_Slots is array (1 .. Capacity) of Action;

   type Actor is record
      Walker        : Peds.Ped;
      Live          : Action_Slots;
      Live_Count    : Natural := 0;
      Pending       : Action_Slots;
      Pending_Count : Natural := 0;
      Pending_Mode  : Mode := Replace;
      Has_Pending   : Boolean := False;
      Commanded     : Boolean := False;
      Command_X     : Positive := 1;
      Command_Y     : Positive := 1;
      Failed        : Boolean := False;
      Settled       : Boolean := False;
      Has_Action    : Boolean := False;
      Action        : Token_Strings.Bounded_String;
      Rest_Count    : Natural := 0;
      Rest          : Token_List;
      Seed          : RNG.Word := 1;
      Shots_Fired   : Natural := 0;
      Fired_Now     : Boolean := False;
      Fired_Hit     : Boolean := False;
      Fired_X       : Positive := 1;
      Fired_Y       : Positive := 1;
   end record
     with Type_Invariant =>
       Actor.Live_Count <= Capacity
       and then Actor.Pending_Count <= Capacity
       and then Actor.Rest_Count <= Capacity;
end Megacorp.Actions;
