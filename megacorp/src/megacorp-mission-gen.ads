--  SPDX-License-Identifier: MIT
--  Copyright (c) 2026 Robert Boettcher

with Megacorp.Map;
with Megacorp.Map.Gen;
with Megacorp.RNG;

--  Item 14. People, cars, and a mission recipe on a generated city.
--  The recipe is the objectives, where they sit, how hard the
--  opposition is, and the tick cap. The auto-squad can win it.
package Megacorp.Mission.Gen is
   type Recipe_Kind is (Briefing, Snatch, Contract);

   type Opposition is (Light, Firm, Heavy);

   type Scene is record
      Kind      : Recipe_Kind := Briefing;
      Level     : Opposition := Light;
      Cap       : Natural := 100;
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
   end record;

   function Build (M : Map.City; Seed : RNG.Word) return Scene
     with Pre => M.Width >= 32 and then M.Height >= 32;

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
