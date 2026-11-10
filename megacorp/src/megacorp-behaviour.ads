--  SPDX-License-Identifier: MIT
--  Copyright (c) 2026 Robert Boettcher

with Ada.Containers.Vectors;
with Megacorp.Actions;
with Megacorp.Map;
with Megacorp.Peds;
with Megacorp.RNG;
with Megacorp.Vehicles;
with Megacorp.Weapons;
use type Ada.Containers.Count_Type;

--  Item 10. A small mood machine on the action queue.
--  Civilians wander, then flee from gunfire. Panic spreads by
--  radius. Guards patrol and shoot hostiles they can see.
--  Police warn, then fire. An agent can persuade a civilian.
--  Each ped has its own child of the scene seed.
package Megacorp.Behaviour is
   type Role is (Civilian, Guard, Police, Hostile, Agent);

   type Mood is
     (Calm, Wander, Patrol, Flee, Warn, Engage, Persuaded);

   --  Chebyshev tiles. Sight is inside the pistol's reach, so a
   --  guard does not fire at someone this machine cannot see.
   --  Hearing is wider, so a shot carries past vision.
   Hear_Radius    : constant := 8;
   Sight_Radius   : constant := 6;
   Spread_Radius  : constant := 4;
   Warn_Ticks     : constant := 12;
   Persuade_Ticks : constant := 8;
   Wander_Every   : constant := 8;

   type Mind is private;

   type Crowd is array (Positive range <>) of Mind;

   function Enlist
     (Who : Peds.Ped_Id;
      Job : Role;
      At_Point : Map.Point;
      M : Map.City;
      Seed : RNG.Word := 1;
      Patrol_A : Map.Point := (X => 1, Y => 1);
      Patrol_B : Map.Point := (X => 1, Y => 1)) return Mind
     with Pre =>
       Map.In_Bounds (M, At_Point.X, At_Point.Y)
       and then Map.Tile_At (M, At_Point.X, At_Point.Y).Walkable
       and then Map.In_Bounds (M, Patrol_A.X, Patrol_A.Y)
       and then Map.In_Bounds (M, Patrol_B.X, Patrol_B.Y),
       Post =>
         Ident (Enlist'Result) = Who
         and then Job_Of (Enlist'Result) = Job
         and then (if Job = Guard
                   then Mood_Of (Enlist'Result) = Patrol
                   else Mood_Of (Enlist'Result) = Calm);

   procedure Arm
     (Group : in out Crowd;
      Index : Positive;
      Gun : Weapons.Kind;
      Rounds : Natural)
     with Pre => Index in Group'Range;

   function Ident (M : Mind) return Peds.Ped_Id;
   function Job_Of (M : Mind) return Role;
   function Mood_Of (M : Mind) return Mood;
   function Role_Token (Job : Role) return String;
   function Mood_Token (Which : Mood) return String;

   type Frame is record
      Tick       : Natural := 0;
      Ident      : Peds.Ped_Id := 1;
      X          : Positive := 1;
      Y          : Positive := 1;
      Along      : Natural := 0;
      Facing     : Map.Eight_Way := Map.South;
      State      : Peds.State_Kind := Peds.Standing;
      Temper     : Mood := Calm;
      Job        : Role := Civilian;
      Has_Action : Boolean := False;
      Action     : Actions.Token_Strings.Bounded_String;
      Health     : Natural := Peds.Full_Health;
      Ammo       : Natural := 0;
      Alive      : Boolean := True;
      Fired      : Boolean := False;
      Landed     : Boolean := False;
      At_X       : Positive := 1;
      At_Y       : Positive := 1;
   end record;

   package Frame_Lists is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Frame);

   --  One action tick, then the mood update. Items and vehicles
   --  are the mission's. An empty fleet is a mission with no cars.
   procedure Step
     (Group : in out Crowd;
      M : Map.City;
      Items : in out Actions.Bag;
      Fleet : in out Vehicles.Fleet;
      At_Tick : Positive)
     with Pre => Distinct (Group);

   procedure Order
     (Group : in out Crowd;
      Index : Positive;
      Planned : Actions.Action_Array;
      How : Actions.Mode)
     with Pre =>
       Index in Group'Range
       and then Planned'Length in 1 .. Actions.Capacity;

   function Observe (Person : Mind) return Frame;

   function Run
     (M : Map.City;
      Start : Crowd;
      Max_Ticks : Natural) return Frame_Lists.Vector
     with Pre => Start'Length > 0 and then Distinct (Start),
       Post =>
         Run'Result.Length =
           Ada.Containers.Count_Type (Max_Ticks + 1) * Start'Length;

   --  The road scene drawn for each export seed.
   type Street_Plan is record
      Hostile_A : Map.Point := (X => 1, Y => 1);
      Civ_A     : Map.Point := (X => 1, Y => 1);
      Civ_B     : Map.Point := (X => 1, Y => 1);
      Police_At : Map.Point := (X => 1, Y => 1);
      Patrol_A  : Map.Point := (X => 1, Y => 1);
      Patrol_B  : Map.Point := (X => 1, Y => 1);
      Hostile_B : Map.Point := (X => 1, Y => 1);
      Guard_At  : Map.Point := (X => 1, Y => 1);
   end record;

   function Street (M : Map.City) return Street_Plan;

   function Run_Street
     (M : Map.City; Seed : RNG.Word) return Frame_Lists.Vector;

   function Distinct (Group : Crowd) return Boolean;

private
   type Mind is record
      Person   : Actions.Actor;
      Job      : Role := Civilian;
      Temper   : Mood := Calm;
      Seed     : RNG.Word := 1;
      Dice     : RNG.Generator;
      Patrol_A : Map.Point := (X => 1, Y => 1);
      Patrol_B : Map.Point := (X => 1, Y => 1);
      Go_B     : Boolean := True;
      Warn_Left : Natural := 0;
      Persuade_Left : Natural := 0;
      Focus    : Peds.Ped_Id := 1;
      Has_Focus : Boolean := False;
      Gun      : Weapons.Kind := Weapons.Pistol;
   end record
     with Type_Invariant =>
       Mind.Warn_Left <= Warn_Ticks
       and then Mind.Persuade_Left <= Persuade_Ticks;
end Megacorp.Behaviour;
