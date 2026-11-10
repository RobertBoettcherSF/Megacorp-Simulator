--  SPDX-License-Identifier: MIT
--  Copyright (c) 2026 Robert Boettcher

with Megacorp.Map;
with Megacorp.RNG;
with Megacorp.Weapons;

--  Item 8. Line of sight and the hit roll.
--  Buildings block. Other terrain does not. The roll is a child of
--  the caller's generator, so one shot does not move another stream.
package Megacorp.Shots is
   function Distance (From, To : Map.Point) return Natural;

   function In_Range
     (Gun : Weapons.Kind; From, To : Map.Point) return Boolean;

   --  True when a building tile lies strictly between the ends.
   function Blocked
     (M : Map.City; From, To : Map.Point) return Boolean;

   --  100 at one tile, 40 at the weapon's reach, 0 past it.
   function Hit_Chance
     (Gun : Weapons.Kind; From, To : Map.Point) return Natural
     with Post => Hit_Chance'Result <= 100;

   function Lands
     (Gun : Weapons.Kind;
      From, To : Map.Point;
      Dice : in out RNG.Generator) return Boolean
     with Pre => In_Range (Gun, From, To);
end Megacorp.Shots;
