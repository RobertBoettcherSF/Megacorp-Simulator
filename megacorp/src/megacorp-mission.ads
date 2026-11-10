--  SPDX-License-Identifier: MIT
--  Copyright (c) 2026 Robert Boettcher

with Ada.Containers.Vectors;
with Ada.Directories;
with Ada.Text_IO;
with Megacorp.Actions;
with Megacorp.Behaviour;
with Megacorp.Map;
with Megacorp.Peds;
with Megacorp.RNG;
with Megacorp.Vehicles;
use type Ada.Containers.Count_Type;

--  Item 11. One mission: the map, the cast, the cars, the items,
--  and the objectives. Fixed ticks until win, loss, or timeout.
--  The script is the recorded input. Item 12 is not implemented.
package Megacorp.Mission is
   type Objective_Kind is (Eliminate, Acquire, Persuade, Evacuate);

   type Status is (Running, Won, Lost, Timed_Out);

   type Cause is (In_Progress, Objectives_Met, Squad_Lost, Time_Up);

   Max_Goals : constant := 8;

   type Objective (Kind : Objective_Kind := Eliminate) is record
      case Kind is
         when Eliminate =>
            Target : Peds.Ped_Id := 1;
         when Acquire =>
            Item : Actions.Item_Id := 1;
         when Persuade =>
            Contact : Peds.Ped_Id := 1;
         when Evacuate =>
            Zone_X : Positive := 1;
            Zone_Y : Positive := 1;
      end case;
   end record;

   type Objective_List is array (Positive range <>) of Objective;

   type Report is record
      Outcome      : Status := Running;
      Why          : Cause := In_Progress;
      Tick         : Natural := 0;
      Agents_Alive : Natural := 0;
      Met          : Natural := 0;
      Total        : Natural := 0;
   end record;

   function Coherent (R : Report; Max_Ticks : Natural) return Boolean is
     (case R.Outcome is
         when Won =>
            R.Why = Objectives_Met
            and then R.Met = R.Total
            and then R.Agents_Alive > 0
            and then R.Tick <= Max_Ticks,
         when Lost =>
            R.Why = Squad_Lost
            and then R.Agents_Alive = 0
            and then R.Tick <= Max_Ticks,
         when Timed_Out =>
            R.Why = Time_Up and then R.Tick = Max_Ticks,
         when Running =>
            R.Why = In_Progress);

   type Verb is (Walk, Wait, Pick, Shoot, Turn);

   type Command is record
      At_Tick : Positive := 1;
      Who     : Peds.Ped_Id := 1;
      What    : Verb := Wait;
      X       : Positive := 1;
      Y       : Positive := 1;
      Ticks   : Positive := 1;
      Item    : Actions.Item_Id := 1;
      Target  : Peds.Ped_Id := 1;
      Dir     : Map.Eight_Way := Map.South;
   end record;

   package Command_Lists is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Command);

   package Frame_Lists renames Behaviour.Frame_Lists;

   type Done_Set is array (1 .. Max_Goals) of Boolean;

   type Goal_Row is record
      Tick      : Natural := 0;
      Met       : Natural := 0;
      Item_Here : Boolean := False;
      Done      : Done_Set := (others => False);
   end record;

   package Goal_Lists is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Goal_Row);

   type Trace is record
      Outcome  : Report;
      Frames   : Frame_Lists.Vector;
      Goals    : Goal_Lists.Vector;
      Item_X   : Positive := 1;
      Item_Y   : Positive := 1;
      Has_Item : Boolean := False;
   end record;

   function Play
     (M : Map.City;
      Group : in out Behaviour.Crowd;
      Items : in out Actions.Bag;
      Fleet : in out Vehicles.Fleet;
      Goals : Objective_List;
      Lines : Command_Lists.Vector;
      Max_Ticks : Natural) return Trace
     with Pre =>
       Max_Ticks >= 1
       and then Goals'Length in 1 .. Max_Goals
       and then Behaviour.Distinct (Group),
       Post => Coherent (Play'Result.Outcome, Max_Ticks);

   function Load (Path : String) return Command_Lists.Vector
     with Pre => Ada.Directories.Exists (Path);

   procedure Dump (Lines : Command_Lists.Vector; Path : String)
     with Pre => Path'Length > 0;

   procedure Put
     (File : Ada.Text_IO.File_Type;
      Seed : RNG.Word;
      R : Report);

   function Status_Token (Which : Status) return String;
   function Cause_Token (Which : Cause) return String;
   function Kind_Token (Which : Objective_Kind) return String;

   --  The street mission drawn for each export seed. It persuades,
   --  picks up a case, eliminates a guard, and walks to a zone.
   type Fixture_Plan is record
      Agent   : Map.Point := (X => 1, Y => 1);
      Contact : Map.Point := (X => 1, Y => 1);
      Case_At : Map.Point := (X => 1, Y => 1);
      Stand   : Map.Point := (X => 1, Y => 1);
      Target  : Map.Point := (X => 1, Y => 1);
      Zone    : Map.Point := (X => 1, Y => 1);
   end record;

   function Fixture_Of (M : Map.City) return Fixture_Plan;

   function Demonstration
     (M : Map.City;
      Seed : RNG.Word;
      Max_Ticks : Natural := 200) return Trace
     with Pre => Max_Ticks >= 1;
end Megacorp.Mission;
