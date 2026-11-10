--  SPDX-License-Identifier: MIT
--  Copyright (c) 2026 Robert Boettcher

with Ada.Text_IO;
with Megacorp.Parameters;
with Megacorp.RNG;
use type Megacorp.RNG.Word;

--  Item 15. A world from the World and Region child streams.
--  Names are built from our own syllables. No real brand is used.
package Megacorp.World.Gen is
   --  Algorithm 1 is the world built in 0.15.0. Algorithm 2
   --  changes only the city seed, so a stamp can be told apart.
   --  New games stay on algorithm 1. See DESIGN.md.
   Current_Algorithm : constant := 1;
   Max_Algorithm     : constant := 2;

   function Connected (Item : Atlas) return Boolean;

   function Distinct_Homes (Item : Atlas) return Boolean;

   function City_Of
     (Seed : RNG.Word;
      Algorithm : Positive;
      Region : Positive) return RNG.Word
     with Pre => Algorithm <= Max_Algorithm;

   function Generate
     (Seed : RNG.Word;
      Size : Parameters.Generator_Parameters;
      Algorithm : Positive := Current_Algorithm) return Atlas
     with Pre =>
       Parameters.Region_Count (Size) <= Parameters.Max_Regions
       and then Parameters.Corporation_Count (Size)
         <= Parameters.Max_Corporations
       and then Algorithm <= Max_Algorithm,
       Post =>
         Generate'Result.Seed = Seed
         and then Generate'Result.Regions
           = Parameters.Region_Count (Size)
         and then Generate'Result.Corps
           = Parameters.Corporation_Count (Size)
         and then Connected (Generate'Result)
         and then Distinct_Homes (Generate'Result);

   function Same (Left, Right : Atlas) return Boolean;

   procedure Put (File : Ada.Text_IO.File_Type; Item : Atlas);

   procedure Write
     (Path : String; Item : Atlas; Version : String);
end Megacorp.World.Gen;
