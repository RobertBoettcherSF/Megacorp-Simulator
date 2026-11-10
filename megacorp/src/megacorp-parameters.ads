--  SPDX-License-Identifier: MIT
--  Copyright (c) 2026 Robert Boettcher

--  Generator parameters and the region re-roll rule (decisions of
--  2026-11-10). Defaults: 4 corporations, 40 regions, 128x128 city
--  maps. Scenario worlds are locked once generated. Free play and
--  auto-play may re-roll unvisited regions; visited regions stay.
package Megacorp.Parameters is
   Min_Corporations : constant := 1;
   Max_Corporations : constant := 16;
   Min_Regions      : constant := 1;
   Max_Regions      : constant := 512;
   Min_City_Map_Edge : constant := 1;
   Max_City_Map_Edge : constant := 1024;

   Default_Corporations    : constant := 4;
   Default_Regions         : constant := 40;
   Default_City_Map_Width  : constant := 128;
   Default_City_Map_Height : constant := 128;

   type Play_Mode is (Scenario, Free_Play, Auto_Play);

   type Generator_Parameters is private;

   function Defaults return Generator_Parameters
     with Post =>
       Corporation_Count (Defaults'Result) = Default_Corporations
       and then Region_Count (Defaults'Result) = Default_Regions
       and then City_Map_Width (Defaults'Result) = Default_City_Map_Width
       and then City_Map_Height (Defaults'Result)
         = Default_City_Map_Height;

   function Make
     (Corporations : Integer;
      Regions      : Integer;
      Map_Width    : Integer;
      Map_Height   : Integer) return Generator_Parameters
     with Pre =>
       Corporations in Min_Corporations .. Max_Corporations
       and then Regions in Min_Regions .. Max_Regions
       and then Map_Width in Min_City_Map_Edge .. Max_City_Map_Edge
       and then Map_Height in Min_City_Map_Edge .. Max_City_Map_Edge,
       Post =>
         Corporation_Count (Make'Result) = Corporations
         and then Region_Count (Make'Result) = Regions
         and then City_Map_Width (Make'Result) = Map_Width
         and then City_Map_Height (Make'Result) = Map_Height;

   function Corporation_Count
     (P : Generator_Parameters) return Positive;
   function Region_Count (P : Generator_Parameters) return Positive;
   function City_Map_Width (P : Generator_Parameters) return Positive;
   function City_Map_Height (P : Generator_Parameters) return Positive;

   --  True only for free play and auto-play. A scenario world is
   --  locked, including regions nobody has visited yet.
   function Unvisited_Regions_May_Reroll
     (Mode : Play_Mode) return Boolean
     with Post =>
       Unvisited_Regions_May_Reroll'Result = (Mode /= Scenario);

   --  Visited regions stay as left in every mode.
   function Region_May_Reroll
     (Mode : Play_Mode; Visited : Boolean) return Boolean
     with Post =>
       Region_May_Reroll'Result =
         (not Visited and then Unvisited_Regions_May_Reroll (Mode));

private
   type Generator_Parameters is record
      Corporations : Integer := Default_Corporations;
      Regions      : Integer := Default_Regions;
      Map_Width    : Integer := Default_City_Map_Width;
      Map_Height   : Integer := Default_City_Map_Height;
   end record
     with Type_Invariant => Valid (Generator_Parameters);

   function Valid (P : Generator_Parameters) return Boolean;
end Megacorp.Parameters;
