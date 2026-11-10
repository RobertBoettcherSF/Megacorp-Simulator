--  SPDX-License-Identifier: MIT
--  Copyright (c) 2026 Robert Boettcher

with Ada.Containers.Vectors;
with Megacorp.Map;
use type Megacorp.Map.Point;

--  Item 5. A* on a city map.
--  Walk uses the walkable flag. Drive uses the drivable flag.
--  Eight directions. A diagonal step is refused when either
--  orthogonal neighbour it cuts across is blocked.
--  Costs are integers: 10 orthogonal, 14 diagonal.
--  Equal keys break toward the smaller heuristic, then smaller
--  Y, then smaller X, so one query has one path.
package Megacorp.Path is
   type Mode is (Walk, Drive);

   type Status is (Found, No_Path, Budget_Exceeded);

   type Result is private;

   function Kind (Route : Result) return Status;

   function Length (Route : Result) return Natural
     with Post =>
       (if Kind (Route) = Found then Length'Result > 0
        else Length'Result = 0);

   function Step
     (Route : Result; Index : Positive) return Map.Point
     with Pre =>
       Kind (Route) = Found and then Index <= Length (Route);

   --  Node expansions. A 128x128 search fits under this.
   Default_Budget : constant Positive := 65_536;

   --  Tiles treated as impassable for one search. The start tile
   --  is never treated as blocked, so a search can leave it.
   package Block_Lists is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Map.Point);

   function Steps_Fit
     (M : Map.City;
      From, To : Map.Point;
      Route : Result) return Boolean;

   function Find
     (M : Map.City;
      From, To : Map.Point;
      How : Mode;
      Budget : Positive;
      Blocked : Block_Lists.Vector) return Result
     with Pre =>
       Map.In_Bounds (M, From.X, From.Y)
       and then Map.In_Bounds (M, To.X, To.Y),
       Post =>
         (if Kind (Find'Result) = Found
          then Steps_Fit (M, From, To, Find'Result));

   function Find
     (M : Map.City;
      From, To : Map.Point;
      How : Mode;
      Budget : Positive := Default_Budget) return Result
     is (Find (M, From, To, How, Budget, Block_Lists.Empty_Vector))
     with Pre =>
       Map.In_Bounds (M, From.X, From.Y)
       and then Map.In_Bounds (M, To.X, To.Y),
       Post =>
         (if Kind (Find'Result) = Found
          then Steps_Fit (M, From, To, Find'Result));

private
   package Point_Lists is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Map.Point);

   type Result is record
      Kind  : Status := No_Path;
      Steps : Point_Lists.Vector;
   end record
     with Type_Invariant =>
       (if Result.Kind = Found
        then not Result.Steps.Is_Empty
        else Result.Steps.Is_Empty);
end Megacorp.Path;
