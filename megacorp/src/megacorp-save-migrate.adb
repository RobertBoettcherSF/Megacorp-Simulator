--  SPDX-License-Identifier: MIT
--  Copyright (c) 2026 Robert Boettcher

with Ada.Strings.Unbounded;

package body Megacorp.Save.Migrate is
   LF : constant String := (1 => ASCII.LF);

   function Add
     (Left : Ada.Strings.Unbounded.Unbounded_String;
      Right : String)
     return Ada.Strings.Unbounded.Unbounded_String
     renames Ada.Strings.Unbounded."&";

   function Hex (Value : RNG.Word) return String;
   function From_Hex (Text : String) return RNG.Word;
   function Trim (Value : Integer) return String;
   function Payload_Of (Text : String) return String;
   function Upgrade (Payload : String) return String;
   function Wrap (Version : Positive; Payload : String) return String;

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

   function From_Hex (Text : String) return RNG.Word is
      Value : RNG.Word := 0;
      Digit : Natural;
   begin
      if Text'Length /= 16 then
         raise Save_Error with "checksum mismatch";
      end if;
      for Char of Text loop
         case Char is
            when '0' .. '9' =>
               Digit := Character'Pos (Char) - Character'Pos ('0');
            when 'a' .. 'f' =>
               Digit :=
                 Character'Pos (Char) - Character'Pos ('a') + 10;
            when others =>
               raise Save_Error with "checksum mismatch";
         end case;
         Value := Value * 16 + RNG.Word (Digit);
      end loop;
      return Value;
   end From_Hex;

   function Trim (Value : Integer) return String is
      Image : constant String := Integer'Image (Value);
   begin
      return Image (Image'First + 1 .. Image'Last);
   end Trim;

   function Listed_Version (Text : String) return Natural is
      Mark : Natural;
   begin
      if Text'Length < 6
        or else Text (Text'First .. Text'First + 4) /= "MGC1 "
      then
         return 0;
      end if;
      Mark := Text'First + 5;
      while Mark <= Text'Last and then Text (Mark) /= ASCII.LF loop
         Mark := Mark + 1;
      end loop;
      if Mark > Text'Last then
         return 0;
      end if;
      return Natural'Value (Text (Text'First + 5 .. Mark - 1));
   exception
      when Constraint_Error =>
         return 0;
   end Listed_Version;

   function Payload_Of (Text : String) return String is
      Seen : Natural := 0;
   begin
      for I in Text'Range loop
         if Text (I) = ASCII.LF then
            Seen := Seen + 1;
            if Seen = 2 then
               return Text (I + 1 .. Text'Last);
            end if;
         end if;
      end loop;
      return "";
   end Payload_Of;

   function Sum_Ok (Text : String) return Boolean is
      Mark : Natural;
      Split : Natural;
      Payload : constant String := Payload_Of (Text);
   begin
      if Listed_Version (Text) = 0 or else Payload'Length = 0 then
         return False;
      end if;
      Mark := Text'First;
      while Mark <= Text'Last and then Text (Mark) /= ASCII.LF loop
         Mark := Mark + 1;
      end loop;
      Split := Mark + 1;
      while Split <= Text'Last and then Text (Split) /= ASCII.LF loop
         Split := Split + 1;
      end loop;
      if Split > Text'Last or else Split - Mark /= 17 then
         return False;
      end if;
      return Digest (Payload)
        = From_Hex (Text (Mark + 1 .. Split - 1));
   exception
      when Save_Error =>
         return False;
   end Sum_Ok;

   function Upgrade (Payload : String) return String is
      Text : Ada.Strings.Unbounded.Unbounded_String;
      Start_At : Positive := Payload'First;

      function Grow (Line : String) return String;
      function Grow (Line : String) return String is
      begin
         if Line'Length >= 2
           and then Line (Line'First) = 'c'
           and then Line (Line'First + 1) = ' '
         then
            return Line & " 0";
         elsif Line'Length >= 10
           and then Line (Line'First .. Line'First + 9) = "generator "
         then
            return Line & LF & "algorithm 1";
         end if;
         return Line;
      end Grow;
   begin
      for I in Payload'Range loop
         if Payload (I) = ASCII.LF then
            Text := Add
              (Text,
               Grow (Payload (Start_At .. I - 1)) & LF);
            Start_At := I + 1;
         end if;
      end loop;
      return Ada.Strings.Unbounded.To_String (Text);
   end Upgrade;

   function Wrap (Version : Positive; Payload : String) return String is
   begin
      return "MGC1 " & Trim (Version) & LF
        & Hex (Digest (Payload)) & LF
        & Payload;
   end Wrap;

   function Note (From, To : Positive) return String is
   begin
      return "migrated save from version "
        & Trim (From) & " to " & Trim (To);
   end Note;

   function Step (Text : String) return String is
   begin
      if Listed_Version (Text) = 1 then
         return Wrap (2, Upgrade (Payload_Of (Text)));
      end if;
      raise Save_Error with "wrong format version";
   end Step;

   function To_Current (Text : String) return String is
      Now : Ada.Strings.Unbounded.Unbounded_String :=
        Ada.Strings.Unbounded.To_Unbounded_String (Text);
   begin
      while Listed_Version
        (Ada.Strings.Unbounded.To_String (Now)) < Format_Version
      loop
         Now := Ada.Strings.Unbounded.To_Unbounded_String
           (Step (Ada.Strings.Unbounded.To_String (Now)));
      end loop;
      return Ada.Strings.Unbounded.To_String (Now);
   end To_Current;

end Megacorp.Save.Migrate;
