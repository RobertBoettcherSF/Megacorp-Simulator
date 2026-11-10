--  SPDX-License-Identifier: MIT
--  Copyright (c) 2026 Robert Boettcher

with Megacorp.Parameters;
with Megacorp.RNG;

--  Item 15. One persistent world: regions, corporations, and
--  the roads between regions. Counts come from the generator
--  parameters. Item 16 advances this atlas one day at a time.
package Megacorp.World is
   Max_Name  : constant := 24;
   Max_Links : constant := 2048;

   type Trait is (Aggressive, Mercantile, Scientific, Secretive);

   type Name is record
      Length : Natural := 0;
      Text   : String (1 .. Max_Name) := (others => ' ');
   end record;

   function Image (Item : Name) return String;

   type Corporation is record
      Title : Name;
      Red   : Natural := 0;
      Green : Natural := 0;
      Blue  : Natural := 0;
      Home       : Positive := 1;
      Cash       : Natural := 0;
      Kind       : Trait := Mercantile;
      Eliminated : Boolean := False;
      Earned     : Natural := 0;
      Spent      : Natural := 0;
   end record;

   type Region is record
      Title      : Name;
      Population : Natural := 0;
      Tech       : Natural := 0;
      Tax        : Natural := 0;
      Unrest     : Natural := 0;
      Owner      : Positive := 1;
      Defence    : Natural := 0;
      City       : RNG.Word := 0;
      X          : Natural := 0;
      Y          : Natural := 0;
   end record;

   type Link is record
      Left  : Positive := 1;
      Right : Positive := 1;
   end record;

   type Corp_List is
     array (1 .. Parameters.Max_Corporations) of Corporation;
   type Region_List is
     array (1 .. Parameters.Max_Regions) of Region;
   type Link_List is array (1 .. Max_Links) of Link;

   type Atlas is record
      Seed    : RNG.Word := 0;
      Regions : Positive := 1;
      Corps   : Positive := 1;
      Links   : Natural := 0;
      Company : Corp_List;
      Area    : Region_List;
      Road    : Link_List;
   end record;
end Megacorp.World;
