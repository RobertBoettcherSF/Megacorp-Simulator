--  SPDX-License-Identifier: MIT
--  Copyright (c) 2026 Robert Boettcher

package body Megacorp.Agents is
   use type RNG.Word;

   --  Sixteen syllables of three letters. Two of them make a name.
   Syllables : constant String :=
     "arkbelcordandekfenhaljorkormarnolpeqrinsovwexzim";

   function Person
     (Seed : RNG.Word;
      Index : Positive) return Operative
   is
      G : RNG.Generator :=
        RNG.Child
          (RNG.Make (Seed), 16#A5_0000_0000# + RNG.Word (Index));
      Left : constant Natural := RNG.Pick (G, 0, 15);
      Right : constant Natural := RNG.Pick (G, 0, 15);
      Who : Operative;
   begin
      Who.Name_Len := 6;
      Who.Name (1 .. 3) :=
        Syllables (Left * 3 + 1 .. Left * 3 + 3);
      Who.Name (4 .. 6) :=
        Syllables (Right * 3 + 1 .. Right * 3 + 3);
      Who.Health := 60 + RNG.Pick (G, 0, 40);
      Who.Accuracy := 25 + RNG.Pick (G, 0, 70);
      Who.Speed := 25 + RNG.Pick (G, 0, 70);
      Who.Morale := 40 + RNG.Pick (G, 0, 40);
      Who.Augments := 0;
      Who.Armour := 0;
      Who.Gun := Weapons.Pistol;
      Who.Alive := True;
      return Who;
   end Person;

   function Name_Of (Who : Operative) return String is
   begin
      if Who.Name_Len = 0 then
         return "";
      end if;
      return Who.Name (1 .. Who.Name_Len);
   end Name_Of;
end Megacorp.Agents;
