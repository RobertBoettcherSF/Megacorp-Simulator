--  SPDX-License-Identifier: MIT
--  Copyright (c) 2026 Robert Boettcher

with Megacorp.RNG;
with Megacorp.Weapons;
use type Megacorp.Weapons.Kind;

--  Item 25. Named operatives. Stats and the name come from the
--  world seed and the roster index, so a hire replays.
package Megacorp.Agents is
   Name_Max   : constant := 12;
   Max_Roster : constant := 6;
   Squad_Slots : constant := 4;
   Augment_Slots : constant := 2;

   type Operative is record
      Name_Len : Natural := 0;
      Name     : String (1 .. Name_Max) := (others => ' ');
      Health   : Natural := 100;
      Accuracy : Natural := 50;
      Speed    : Natural := 50;
      Morale   : Natural := 50;
      Augments : Natural := 0;
      Gun      : Weapons.Kind := Weapons.Pistol;
      Armour   : Natural := 0;
      Alive    : Boolean := True;
   end record;

   type Roster_Table is array (1 .. Max_Roster) of Operative;
   type Pick_Table is array (1 .. Squad_Slots) of Natural;

   function Person
     (Seed : RNG.Word;
      Index : Positive) return Operative
     with Pre => Index <= Max_Roster,
          Post =>
            Person'Result.Name_Len = 6
            and then Person'Result.Alive
            and then Person'Result.Health in 60 .. 100
            and then Person'Result.Accuracy in 25 .. 95
            and then Person'Result.Speed in 25 .. 95
            and then Person'Result.Morale in 40 .. 80
            and then Person'Result.Augments = 0
            and then Person'Result.Armour = 0
            and then Person'Result.Gun = Weapons.Pistol;

   function Name_Of (Who : Operative) return String
     with Post => Name_Of'Result'Length = Who.Name_Len;
end Megacorp.Agents;
