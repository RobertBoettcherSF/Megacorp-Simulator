--  SPDX-License-Identifier: MIT
--  Copyright (c) 2026 Robert Boettcher

package body Megacorp.Shots is
   use type Map.Point;
   use type Map.Terrain;

   function Sign_Of (Diff : Integer) return Integer;

   function Sign_Of (Diff : Integer) return Integer is
   begin
      if Diff > 0 then
         return 1;
      elsif Diff < 0 then
         return -1;
      else
         return 0;
      end if;
   end Sign_Of;

   function Distance (From, To : Map.Point) return Natural is
   begin
      return Natural'Max
        (abs (From.X - To.X), abs (From.Y - To.Y));
   end Distance;

   function In_Range
     (Gun : Weapons.Kind; From, To : Map.Point) return Boolean
   is
   begin
      return Distance (From, To) <= Weapons.Profile (Gun).Reach;
   end In_Range;

   function Blocked
     (M : Map.City; From, To : Map.Point) return Boolean
   is
      X   : Integer := From.X;
      Y   : Integer := From.Y;
      DX  : constant Integer := abs (To.X - From.X);
      DY  : constant Integer := abs (To.Y - From.Y);
      SX  : constant Integer := Sign_Of (To.X - From.X);
      SY  : constant Integer := Sign_Of (To.Y - From.Y);
      Err : Integer := DX - DY;
      E2  : Integer;
   begin
      if From = To then
         return False;
      end if;
      loop
         E2 := 2 * Err;
         if E2 > -DY then
            Err := Err - DY;
            X := X + SX;
         end if;
         if E2 < DX then
            Err := Err + DX;
            Y := Y + SY;
         end if;
         exit when X = To.X and then Y = To.Y;
         if Map.In_Bounds (M, X, Y)
           and then Map.Tile_At (M, X, Y).Kind = Map.Building
         then
            return True;
         end if;
      end loop;
      return False;
   end Blocked;

   function Hit_Chance
     (Gun : Weapons.Kind; From, To : Map.Point) return Natural
   is
      Dist : constant Natural := Distance (From, To);
      Far  : constant Positive := Weapons.Profile (Gun).Reach;
      Drop : Natural;
   begin
      if Dist > Far then
         return 0;
      elsif Dist <= 1 then
         return 100;
      end if;
      Drop := (60 * (Dist - 1)) / (Far - 1);
      if Drop >= 100 then
         return 0;
      end if;
      return 100 - Drop;
   end Hit_Chance;

   function Lands
     (Gun : Weapons.Kind;
      From, To : Map.Point;
      Dice : in out RNG.Generator) return Boolean
   is
      Odds : constant Natural := Hit_Chance (Gun, From, To);
   begin
      return RNG.Chance (Dice, Odds, 100);
   end Lands;
end Megacorp.Shots;
