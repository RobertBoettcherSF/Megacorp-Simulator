--  SPDX-License-Identifier: MIT
--  Copyright (c) 2026 Robert Boettcher

with Megacorp.RNG;

package body Megacorp.Sound is
   use type RNG.Word;

   Basis : constant RNG.Word := 16#CBF2_9CE4_8422_2325#;
   Prime : constant RNG.Word := 16#0000_0100_0000_01B3#;

   function Hex (Value : RNG.Word) return String;

   function Tone (Which : Kind) return Voice is
   begin
      case Which is
         when Click =>
            return (Square, 880, 40, 4, 28);
         when Gun =>
            return (Noise, 180, 90, 2, 70);
         when Hit =>
            return (Square, 160, 70, 2, 55);
         when Death =>
            return (Saw, 90, 320, 8, 60);
         when Foot =>
            return (Noise, 90, 28, 2, 18);
         when Win =>
            return (Sine, 523, 420, 20, 42);
         when Loss =>
            return (Saw, 110, 480, 30, 40);
         when Alarm =>
            return (Square, 740, 220, 6, 48);
         when Blip =>
            return (Sine, 660, 90, 4, 36);
         when Silent =>
            return (Sine, 440, 1, 1, 0);
      end case;
   end Tone;

   function Loop_Of (Which : Scene) return Bar is
      Result : Bar;
      Base : constant Natural := 90 + Scene'Pos (Which) * 55;
      Step : Natural;
   begin
      for I in Result'Range loop
         Step := (I * I * 13 + Scene'Pos (Which) * 17) mod 160;
         Result (I).Freq := Base + Step;
         Result (I).Ms := 200 + (I mod 3) * 80;
      end loop;
      return Result;
   end Loop_Of;

   procedure Clear (Log : in out Stream) is
   begin
      Log.Count := 0;
   end Clear;

   procedure Push (Log : in out Stream; Which : Kind) is
   begin
      if Which = Silent or else Log.Count >= Max_Events then
         return;
      end if;
      Log.Count := Log.Count + 1;
      Log.Item (Log.Count).Which := Which;
   end Push;

   procedure Add (Item : in out Tape; Which : Kind) is
   begin
      if Item.Count >= Tape_Max then
         return;
      end if;
      Item.Count := Item.Count + 1;
      Item.Code (Item.Count) := Which;
   end Add;

   function Hex (Value : RNG.Word) return String is
      Glyphs : constant String := "0123456789abcdef";
      Result : String (1 .. 16);
      Rest : RNG.Word := Value;
   begin
      for I in reverse 1 .. 16 loop
         Result (I) := Glyphs (Natural (Rest and 16#F#) + 1);
         Rest := Rest / 16;
      end loop;
      return Result;
   end Hex;

   function Seal (Item : Tape) return String is
      Hash : RNG.Word := Basis;
   begin
      for I in 1 .. Item.Count loop
         Hash := (Hash xor RNG.Word (Kind'Pos (Item.Code (I)))) * Prime;
      end loop;
      return Hex (Hash);
   end Seal;
end Megacorp.Sound;
