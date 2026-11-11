--  SPDX-License-Identifier: MIT
--  Copyright (c) 2026 Robert Boettcher

with Megacorp.Parameters;
with Megacorp.World.Campaign;
with Megacorp.World.Gen;

package body Megacorp.API is
   use type Interfaces.Unsigned_32;
   use type RNG.Word;

   Basis : constant RNG.Word := 16#CBF2_9CE4_8422_2325#;
   Prime : constant RNG.Word := 16#0000_0100_0000_01B3#;
   Limit : constant := 32768;

   type Octet is new Interfaces.Unsigned_8;
   type Store is array (0 .. Limit - 1) of Octet;

   Globe : World.Atlas;
   Clock : Natural := 0;
   Buf   : Store := (others => 0);
   Used  : Natural := 0;
   Mark  : RNG.Word := 0;

   function Mix (Hash : RNG.Word; Value : Natural) return RNG.Word;
   procedure Put_U8 (Value : Natural);
   procedure Put_U16 (Value : Natural);
   procedure Put_U32 (Value : Interfaces.Unsigned_32);
   procedure Put_Name (Item : World.Name);
   procedure Publish;

   function Mix (Hash : RNG.Word; Value : Natural) return RNG.Word is
   begin
      return (Hash xor RNG.Word (Value mod 256)) * Prime;
   end Mix;

   function Fingerprint
     (Item : World.Atlas;
      Day : Natural) return RNG.Word
   is
      Hash : RNG.Word := Basis;
   begin
      Hash := Mix (Hash, Day);
      Hash := Mix (Hash, Day / 256);
      for I in 1 .. Item.Regions loop
         Hash := Mix (Hash, Item.Area (I).Owner);
         Hash := Mix (Hash, Item.Area (I).Tax);
         Hash := Mix (Hash, Item.Area (I).Unrest);
         Hash := Mix (Hash, Item.Area (I).Defence);
         Hash := Mix (Hash, Item.Area (I).Tech);
         Hash := Mix (Hash, Item.Area (I).X);
         Hash := Mix (Hash, Item.Area (I).X / 256);
         Hash := Mix (Hash, Item.Area (I).Y);
         Hash := Mix (Hash, Item.Area (I).Y / 256);
      end loop;
      for C in 1 .. Item.Corps loop
         Hash := Mix (Hash, Item.Company (C).Cash);
         Hash := Mix (Hash, Item.Company (C).Cash / 256);
         Hash := Mix (Hash, Item.Company (C).Cash / 65536);
         if Item.Company (C).Eliminated then
            Hash := Mix (Hash, 1);
         else
            Hash := Mix (Hash, 0);
         end if;
      end loop;
      return Hash;
   end Fingerprint;

   procedure Put_U8 (Value : Natural) is
   begin
      Buf (Used) := Octet (Value mod 256);
      Used := Used + 1;
   end Put_U8;

   procedure Put_U16 (Value : Natural) is
   begin
      Put_U8 (Value);
      Put_U8 (Value / 256);
   end Put_U16;

   procedure Put_U32 (Value : Interfaces.Unsigned_32) is
      Rest : Interfaces.Unsigned_32 := Value;
   begin
      for Drop in 1 .. 4 loop
         Put_U8 (Natural (Rest mod 256));
         Rest := Rest / 256;
      end loop;
   end Put_U32;

   procedure Put_Name (Item : World.Name) is
   begin
      Put_U8 (Item.Length);
      for I in 1 .. World.Max_Name loop
         if I <= Item.Length then
            Put_U8 (Character'Pos (Item.Text (I)));
         else
            Put_U8 (0);
         end if;
      end loop;
   end Put_Name;

   procedure Publish is
   begin
      Mark := Fingerprint (Globe, Clock);
      Used := 0;
      Put_U32 (Interfaces.Unsigned_32 (Clock));
      Put_U32 (Interfaces.Unsigned_32 (Globe.Regions));
      Put_U32 (Interfaces.Unsigned_32 (Globe.Corps));
      Put_U32 (Interfaces.Unsigned_32 (Globe.Links));
      Put_U32 (Interfaces.Unsigned_32 (Mark and 16#FFFF_FFFF#));
      Put_U32
        (Interfaces.Unsigned_32
           (Interfaces.Shift_Right (Mark, 32)));
      for C in 1 .. Globe.Corps loop
         Put_U32 (Interfaces.Unsigned_32 (Globe.Company (C).Cash));
         Put_U8 (Globe.Company (C).Red);
         Put_U8 (Globe.Company (C).Green);
         Put_U8 (Globe.Company (C).Blue);
         if Globe.Company (C).Eliminated then
            Put_U8 (1);
         else
            Put_U8 (0);
         end if;
         Put_Name (Globe.Company (C).Title);
      end loop;
      for I in 1 .. Globe.Regions loop
         Put_U16 (Globe.Area (I).X);
         Put_U16 (Globe.Area (I).Y);
         Put_U8 (Globe.Area (I).Owner);
         Put_U8 (Globe.Area (I).Tax);
         Put_U8 (Globe.Area (I).Unrest);
         Put_U8 (Globe.Area (I).Defence);
         Put_U8 (Globe.Area (I).Tech);
         Put_U16 (Globe.Area (I).Population);
         Put_Name (Globe.Area (I).Title);
      end loop;
      for I in 1 .. Globe.Links loop
         Put_U16 (Globe.Road (I).Left);
         Put_U16 (Globe.Road (I).Right);
      end loop;
   end Publish;

   procedure Install (Item : World.Atlas; Day : Natural) is
   begin
      Globe := Item;
      Clock := Day;
      Publish;
   end Install;

   procedure Init (Seed : Interfaces.Unsigned_32) is
   begin
      Globe := World.Gen.Generate
        (RNG.Word (Seed), Parameters.Defaults);
      Clock := 0;
      Publish;
   end Init;

   procedure Step (Days : Interfaces.Unsigned_32) is
   begin
      for Drop in 1 .. Natural (Days) loop
         World.Campaign.Advance (Globe);
      end loop;
      Clock := Clock + Natural (Days);
      Publish;
   end Step;

   function State return System.Address is
   begin
      return Buf'Address;
   end State;

   function State_Size return Interfaces.Unsigned_32 is
   begin
      return Interfaces.Unsigned_32 (Used);
   end State_Size;

   function Digest return RNG.Word is
   begin
      return Mark;
   end Digest;

   function Digest_Text return String is
      Glyphs : constant String := "0123456789abcdef";
      Result : String (1 .. 16);
      Rest : RNG.Word := Mark;
   begin
      for I in reverse 1 .. 16 loop
         Result (I) := Glyphs (Natural (Rest mod 16) + 1);
         Rest := Rest / 16;
      end loop;
      return Result;
   end Digest_Text;

end Megacorp.API;
