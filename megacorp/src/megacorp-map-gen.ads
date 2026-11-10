--  SPDX-License-Identifier: MIT
--  Copyright (c) 2026 Robert Boettcher

with Megacorp.Parameters;
with Megacorp.RNG;

--  Item 13. A city from the City child of the world seed.
--  Roads form one grid, sidewalks are walkable, and a river
--  is crossed by bridges. Test_Layout stays for the old checks.
package Megacorp.Map.Gen is
   type District is (Corporate, Residential, Industrial, Slums);

   function Min_Storey (Which : District) return Height_Level;
   function Max_Storey (Which : District) return Height_Level;

   function District_At
     (From : RNG.Word;
      Width, Height : Positive;
      X, Y : Positive) return District
     with Pre =>
       Width <= Parameters.Max_City_Map_Edge
       and then Height <= Parameters.Max_City_Map_Edge
       and then X <= Width
       and then Y <= Height;

   function Roads_Connected (M : City) return Boolean;
   function Foot_Connected (M : City) return Boolean;

   function Generate
     (From : RNG.Word; Width, Height : Positive) return City
     with Pre =>
       Width <= Parameters.Max_City_Map_Edge
       and then Height <= Parameters.Max_City_Map_Edge,
       Post =>
         Generate'Result.Width = Width
         and then Generate'Result.Height = Height
         and then Layout_Seed (Generate'Result) = From
         and then Roads_Connected (Generate'Result)
         and then Foot_Connected (Generate'Result);

   function Generate
     (From : RNG.Word;
      Size : Parameters.Generator_Parameters) return City
     with Post =>
       Generate'Result.Width = Parameters.City_Map_Width (Size)
       and then Generate'Result.Height
         = Parameters.City_Map_Height (Size)
       and then Layout_Seed (Generate'Result) = From;
end Megacorp.Map.Gen;
