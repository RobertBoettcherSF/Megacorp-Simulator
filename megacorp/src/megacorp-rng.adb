--  SPDX-License-Identifier: MIT
--  Copyright (c) 2026 Robert Boettcher

with Ada.Unchecked_Conversion;

package body Megacorp.RNG is
   --  SplitMix64 increment. Odd, so multiplication by it is a
   --  bijection on Word.
   Golden : constant Word := 16#9E37_79B9_7F4A_7C15#;
   Mix_1  : constant Word := 16#BF58_476D_1CE4_E5B9#;
   Mix_2  : constant Word := 16#94D0_49BB_1331_11EB#;

   function To_Word is new Ada.Unchecked_Conversion
     (Long_Long_Integer, Word);
   function To_Long is new Ada.Unchecked_Conversion
     (Word, Long_Long_Integer);

   function Mix (Value : Word) return Word;
   function Split_Next (State : in out Word) return Word;
   function Rotl (Value : Word; Amount : Natural) return Word;
   function Rejection_Limit (Count : Word) return Word;

   function Mix (Value : Word) return Word is
      Z : Word := Value;
   begin
      Z := (Z xor Interfaces.Shift_Right (Z, 30)) * Mix_1;
      Z := (Z xor Interfaces.Shift_Right (Z, 27)) * Mix_2;
      return Z xor Interfaces.Shift_Right (Z, 31);
   end Mix;

   function Split_Next (State : in out Word) return Word is
   begin
      State := State + Golden;
      return Mix (State);
   end Split_Next;

   function Rotl (Value : Word; Amount : Natural) return Word is
     (Interfaces.Rotate_Left (Value, Amount));

   function Make (Seed : Word) return Generator is
      State : Word := Seed;
      S0    : Word;
      S1    : Word;
      S2    : Word;
      S3    : Word;
   begin
      S0 := Split_Next (State);
      S1 := Split_Next (State);
      S2 := Split_Next (State);
      S3 := Split_Next (State);
      pragma Assert (Alive ((S0, S1, S2, S3)));
      return (Origin_Seed => Seed, S => (S0, S1, S2, S3));
   end Make;

   function Restore
     (Seed : Word; S0, S1, S2, S3 : Word) return Generator
   is
   begin
      return (Origin_Seed => Seed, S => (S0, S1, S2, S3));
   end Restore;

   function Origin (G : Generator) return Word is
   begin
      return G.Origin_Seed;
   end Origin;

   function State_Word
     (G : Generator; Index : Positive) return Word
   is
   begin
      return G.S (Index);
   end State_Word;

   function Next (G : in out Generator) return Word is
      Result : constant Word := Rotl (G.S (2) * 5, 7) * 9;
      T      : constant Word := Interfaces.Shift_Left (G.S (2), 17);
   begin
      G.S (3) := G.S (3) xor G.S (1);
      G.S (4) := G.S (4) xor G.S (2);
      G.S (2) := G.S (2) xor G.S (3);
      G.S (1) := G.S (1) xor G.S (4);
      G.S (3) := G.S (3) xor T;
      G.S (4) := Rotl (G.S (4), 45);
      return Result;
   end Next;

   function Derive (Parent : Word; Key : Word) return Word is
   begin
      return Mix (Parent + Golden * Key);
   end Derive;

   function Domain_Key
     (Kind : Domain; Index : Stream_Index) return Word
   is
   begin
      return Word (Domain'Pos (Kind)) * 16#1_0000_0000#
        + Word (Index);
   end Domain_Key;

   function Child
     (Parent : Generator; Key : Word) return Generator
   is
   begin
      return Make (Derive (Origin (Parent), Key));
   end Child;

   function Child
     (Parent : Generator; Kind : Domain; Index : Stream_Index)
     return Generator
   is
   begin
      return Child (Parent, Domain_Key (Kind, Index));
   end Child;

   --  2**64 mod Count, or 0 when Count divides 2**64.
   function Rejection_Limit (Count : Word) return Word is
      Leftover : constant Word := (Word'Last mod Count) + 1;
   begin
      if Leftover = Count then
         return 0;
      end if;
      return Leftover;
   end Rejection_Limit;

   function Uniform
     (G : in out Generator; Low, High : Long_Long_Integer)
     return Long_Long_Integer
   is
      Distance : constant Word := To_Word (High) - To_Word (Low);
      Count    : Word;
      Limit    : Word;
      Draw     : Word;
   begin
      if Distance = Word'Last then
         return To_Long (Next (G));
      end if;
      Count := Distance + 1;
      Limit := Rejection_Limit (Count);
      loop
         Draw := Next (G);
         exit when Draw >= Limit;
      end loop;
      return To_Long (To_Word (Low) + Draw mod Count);
   end Uniform;

   function Pick
     (G : in out Generator; Low, High : Integer) return Integer
   is
      Value : constant Long_Long_Integer :=
        Uniform
          (G, Long_Long_Integer (Low), Long_Long_Integer (High));
   begin
      return Integer (Value);
   end Pick;

   function Chance
     (G : in out Generator;
      Numerator : Natural;
      Denominator : Positive) return Boolean
   is
   begin
      if Numerator = 0 then
         return False;
      end if;
      if Numerator = Denominator then
         return True;
      end if;
      return Uniform (G, 1, Long_Long_Integer (Denominator))
        <= Long_Long_Integer (Numerator);
   end Chance;

   procedure Shuffle
     (G : in out Generator; Items : in out Collection)
   is
      Low_Pos : Long_Long_Integer;
      Chosen  : Long_Long_Integer;
      Moved   : Item;
      From    : Index;
      To      : Index;
   begin
      if Items'Length <= 1 then
         return;
      end if;
      Low_Pos := Long_Long_Integer (Index'Pos (Items'First));
      for Pos in reverse
        Long_Long_Integer (Index'Pos (Index'Succ (Items'First)))
        .. Long_Long_Integer (Index'Pos (Items'Last))
      loop
         Chosen := Uniform (G, Low_Pos, Pos);
         To := Index'Val (Pos);
         From := Index'Val (Chosen);
         Moved := Items (To);
         Items (To) := Items (From);
         Items (From) := Moved;
      end loop;
   end Shuffle;

end Megacorp.RNG;
