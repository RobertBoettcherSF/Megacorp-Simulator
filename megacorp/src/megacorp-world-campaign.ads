--  SPDX-License-Identifier: MIT
--  Copyright (c) 2026 Robert Boettcher

with Ada.Text_IO;
with Megacorp.Parameters;
with Megacorp.RNG;

--  Item 16. One strategic day for the non-player corporations.
--  A day is income, tax, defence, one attack, and revolts.
--  The fight is a formula, not a city mission. See DESIGN.md.
package Megacorp.World.Campaign is
   procedure Advance (Item : in out Atlas)
     with Post => Coherent (Item);

   procedure Run (Item : in out Atlas; Days : Natural)
     with Post => Coherent (Item);

   function Coherent (Item : Atlas) return Boolean;

   --  Cash moved only by Earned and Spent since Opening.
   function Books_Balance
     (Opening, Now : Atlas) return Boolean;

   function Holdings (Item : Atlas; Corp : Positive) return Natural;

   function Play
     (Seed : RNG.Word;
      Size : Parameters.Generator_Parameters;
      Days : Natural) return Atlas;

   procedure Put_Day
     (File : Ada.Text_IO.File_Type;
      Item : Atlas;
      Day : Natural);

   procedure Write
     (Path : String;
      Seed : RNG.Word;
      Size : Parameters.Generator_Parameters;
      Days : Natural;
      Version : String);
end Megacorp.World.Campaign;
