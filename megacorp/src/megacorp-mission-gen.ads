--  SPDX-License-Identifier: MIT
--  Copyright (c) 2026 Robert Boettcher

with Megacorp.Behaviour;
with Megacorp.Map;
with Megacorp.Map.Gen;
with Megacorp.RNG;

--  Item 14. People, cars, and a mission recipe on a generated city.
--  The recipe is the objectives, where they sit, how hard the
--  opposition is, and the tick cap. The auto-squad can win it.
package Megacorp.Mission.Gen is
   type Recipe_Kind is (Briefing, Snatch, Contract);

   type Opposition is (Light, Firm, Heavy);

   --  Caps chosen in 0.15.0. The ped id type allows 256 and the
   --  vehicle id type allows 64. A 128x128 crowd stays under these.
   Max_People : constant := 96;
   Max_Motors : constant := 16;

   type Duty is
     (Lead, Ally, Contact, Sentry, Post, Citizen, Driver, Officer);

   type Seat is record
      Spot  : Map.Point := (X => 1, Y => 1);
      Job   : Behaviour.Role := Behaviour.Civilian;
      Work  : Duty := Citizen;
      Aim   : Map.Point := (X => 1, Y => 1);
      Motor : Positive := 1;
   end record;

   type Seat_List is array (1 .. Max_People) of Seat;

   type Motor is record
      Spot  : Map.Point := (X => 1, Y => 1);
      Aim   : Map.Point := (X => 1, Y => 1);
      Moves : Boolean := False;
      Van   : Boolean := False;
   end record;

   type Motor_List is array (1 .. Max_Motors) of Motor;

   type Scene is record
      Kind      : Recipe_Kind := Briefing;
      Level     : Opposition := Light;
      Cap       : Natural := 100;
      Squad     : Natural := 1;
      Contact   : Map.Point := (X => 1, Y => 1);
      Agent     : Map.Point := (X => 1, Y => 1);
      Case_At   : Map.Point := (X => 1, Y => 1);
      Stand     : Map.Point := (X => 1, Y => 1);
      Target    : Map.Point := (X => 1, Y => 1);
      Zone      : Map.Point := (X => 1, Y => 1);
      Guard     : Map.Point := (X => 1, Y => 1);
      Resident  : Map.Point := (X => 1, Y => 1);
      Driver    : Map.Point := (X => 1, Y => 1);
      Police_A  : Map.Point := (X => 1, Y => 1);
      Beat_A    : Map.Point := (X => 1, Y => 1);
      Police_B  : Map.Point := (X => 1, Y => 1);
      Beat_B    : Map.Point := (X => 1, Y => 1);
      Park_A    : Map.Point := (X => 1, Y => 1);
      Park_B    : Map.Point := (X => 1, Y => 1);
      Car       : Map.Point := (X => 1, Y => 1);
      Car_Goal  : Map.Point := (X => 1, Y => 1);
      Cache     : Map.Point := (X => 1, Y => 1);
      People    : Natural := 0;
      Seat      : Seat_List;
      Motors    : Natural := 0;
      Motor     : Motor_List;
   end record;

   function Build (M : Map.City; Seed : RNG.Word) return Scene
     with Pre => M.Width >= 32 and then M.Height >= 32;

   --  The recipe Build would pick, without generating the city.
   function Preview (Seed : RNG.Word) return Recipe_Kind;

   function Same (A, B : Scene) return Boolean;

   function Reachable (M : Map.City; Plan : Scene) return Boolean;

   function In_Band (M : Map.City; Plan : Scene) return Boolean;

   function Civilians_In
     (M : Map.City;
      Plan : Scene;
      Which : Map.Gen.District) return Natural;

   function Play
     (M : Map.City;
      Seed : RNG.Word;
      Max_Ticks : Natural) return Trace
     with Pre =>
       Max_Ticks >= 1
       and then M.Width >= 32
       and then M.Height >= 32;

   function Solve (M : Map.City; Seed : RNG.Word) return Trace
     with Pre => M.Width >= 32 and then M.Height >= 32,
       Post => Solve'Result.Outcome.Outcome = Won;

   --  The slum civilian's car is not on its start tile after a win.
   function Car_Moved (M : Map.City; Seed : RNG.Word) return Boolean
     with Pre => M.Width >= 32 and then M.Height >= 32;
end Megacorp.Mission.Gen;
