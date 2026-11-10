--  SPDX-License-Identifier: MIT
--  Copyright (c) 2026 Robert Boettcher

with Ada.Text_IO;
with Megacorp.Parameters;
with Megacorp.RNG;
use type Megacorp.RNG.Word;

--  Item 15. A world from the World and Region child streams.
--  Names are built from our own syllables. No real brand is used.
package Megacorp.World.Gen is
   function Connected (Item : Atlas) return Boolean;

   function Distinct_Homes (Item : Atlas) return Boolean;

   function Generate
     (Seed : RNG.Word;
      Size : Parameters.Generator_Parameters) return Atlas
     with Pre =>
       Parameters.Region_Count (Size) <= Parameters.Max_Regions
       and then Parameters.Corporation_Count (Size)
         <= Parameters.Max_Corporations,
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
