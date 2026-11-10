--  SPDX-License-Identifier: MIT
--  Copyright (c) 2026 Robert Boettcher

with Interfaces;
use type Interfaces.Unsigned_64;

--  Item 2. Deterministic PRNG and child streams.
--  xoshiro256** stepped with 64-bit integer arithmetic only.
--  A stream is opened from a seed with SplitMix64. A child stream
--  is SplitMix64's mix of the parent origin seed and a key, so
--  drawing from one stream never moves another.
package Megacorp.RNG is
   subtype Word is Interfaces.Unsigned_64;
   subtype Stream_Index is Interfaces.Unsigned_32;

   --  Append new literals. Pos is part of the child-stream key.
   type Domain is (World, Region, City, Block, Mission);

   --  Open a stream with Make or Restore. A default object is not
   --  a usable stream.
   type Generator is private;

   function Make (Seed : Word) return Generator
     with Post => Origin (Make'Result) = Seed;

   --  Install an explicit xoshiro256** state. Seed is the origin
   --  used by Child, not an input to SplitMix64.
   function Restore
     (Seed : Word; S0, S1, S2, S3 : Word) return Generator
     with Pre =>
       S0 /= 0 or else S1 /= 0 or else S2 /= 0 or else S3 /= 0,
       Post =>
         Origin (Restore'Result) = Seed
         and then State_Word (Restore'Result, 1) = S0
         and then State_Word (Restore'Result, 2) = S1
         and then State_Word (Restore'Result, 3) = S2
         and then State_Word (Restore'Result, 4) = S3;

   function Origin (G : Generator) return Word;

   function State_Word
     (G : Generator; Index : Positive) return Word
     with Pre => Index <= 4;

   function Next (G : in out Generator) return Word;

   --  Distinct keys from one parent produce distinct child seeds.
   function Derive (Parent : Word; Key : Word) return Word;

   function Domain_Key
     (Kind : Domain; Index : Stream_Index) return Word
     with Post =>
       Domain_Key'Result =
         Word (Domain'Pos (Kind)) * 16#1_0000_0000#
         + Word (Index);

   function Child
     (Parent : Generator; Key : Word) return Generator
     with Post =>
       Origin (Child'Result) = Derive (Origin (Parent), Key);

   function Child
     (Parent : Generator; Kind : Domain; Index : Stream_Index)
     return Generator
     with Post =>
       Origin (Child'Result) =
         Derive (Origin (Parent), Domain_Key (Kind, Index));

   --  Unbiased. Every value in Low .. High is equally likely.
   function Uniform
     (G : in out Generator; Low, High : Long_Long_Integer)
     return Long_Long_Integer
     with Pre => Low <= High,
       Post => Uniform'Result in Low .. High;

   --  Unbiased pick of one Integer in Low .. High.
   function Pick
     (G : in out Generator; Low, High : Integer) return Integer
     with Pre => Low <= High,
       Post => Pick'Result in Low .. High;

   --  True with probability Numerator / Denominator.
   --  Numerator 0 is always False. A full numerator is always True.
   function Chance
     (G : in out Generator;
      Numerator : Natural;
      Denominator : Positive) return Boolean
     with Pre => Numerator <= Denominator,
       Post =>
         (if Numerator = 0 then not Chance'Result)
         and then
           (if Numerator = Denominator then Chance'Result);

   --  Fisher-Yates. One draw per element after the first.
   generic
      type Item is private;
      type Index is (<>);
      type Collection is array (Index range <>) of Item;
   procedure Shuffle
     (G : in out Generator; Items : in out Collection);

private
   type State_Words is array (1 .. 4) of Word;

   function Alive (S : State_Words) return Boolean is
     (S (1) /= 0 or else S (2) /= 0
      or else S (3) /= 0 or else S (4) /= 0);

   --  (1, 0, 0, 0) only satisfies Alive for default initialization.
   --  Call Make or Restore. Do not draw from a default object.
   type Generator is record
      Origin_Seed : Word := 0;
      S           : State_Words := (1, 0, 0, 0);
   end record
     with Type_Invariant => Alive (Generator.S);
end Megacorp.RNG;
