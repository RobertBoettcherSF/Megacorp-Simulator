--  SPDX-License-Identifier: MIT
--  Copyright (c) 2026 Robert Boettcher

with Ada.Strings.Unbounded;
with Megacorp.Host;
with Megacorp.Save.Migrate;
with Megacorp.Weapons;

package body Megacorp.Save is
   use type Map.Terrain;
   use type Parameters.Play_Mode;
   use type Weapons.Kind;

   Basis : constant RNG.Word := 16#CBF2_9CE4_8422_2325#;
   Prime : constant RNG.Word := 16#0000_0100_0000_01B3#;

   function Add
     (Left : Ada.Strings.Unbounded.Unbounded_String;
      Right : String)
     return Ada.Strings.Unbounded.Unbounded_String
     renames Ada.Strings.Unbounded."&";

   function Hex (Value : RNG.Word) return String;
   function From_Hex (Text : String) return RNG.Word;
   function Trim (Value : Integer) return String;
   function Trim_Word (Value : RNG.Word) return String;
   function Mode_Name (Play : Parameters.Play_Mode) return String;
   function Mode_Of (Text : String) return Parameters.Play_Mode;
   function Outcome_Name (Which : Mission_Outcome) return String;
   function Outcome_Of (Text : String) return Mission_Outcome;
   function Terrain_Code (Kind : Map.Terrain) return Character;
   function Terrain_Of (Code : Character) return Map.Terrain;
   function Bit (Flag : Boolean) return Character;
   function Flag (Code : Character) return Boolean;
   function Encode
     (Snap : Snapshot;
      Legacy : Boolean := False) return String;
   function Wrap
     (Version : Positive;
      Payload : String) return String;
   function Stamp_Image (Snap : Snapshot) return String;
   procedure Set_Stamp (Snap : in out Snapshot; Text : String);
   function Decode (Payload : String) return Snapshot;
   function Gun_Of (Text : String) return Weapons.Kind;
   function Field (Line : String; Index : Positive) return String;
   function Head (Text : String) return Character;
   function Line_Of
     (Text : String; Index : Positive) return String;

   function Digest (Text : String) return RNG.Word is
      Hash : RNG.Word := Basis;
   begin
      for Char of Text loop
         Hash := Hash xor RNG.Word (Character'Pos (Char));
         Hash := Hash * Prime;
      end loop;
      return Hash;
   end Digest;

   function Hex (Value : RNG.Word) return String is
      Glyphs : constant String := "0123456789abcdef";
      Result : String (1 .. 16);
      Rest : RNG.Word := Value;
   begin
      for I in reverse 1 .. 16 loop
         Result (I) :=
           Glyphs (Natural (Rest and 16#F#) + 1);
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
               Digit := Character'Pos (Char) - Character'Pos ('a') + 10;
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
      if Image (Image'First) = ' ' then
         return Image (Image'First + 1 .. Image'Last);
      end if;
      return Image;
   end Trim;

   function Trim_Word (Value : RNG.Word) return String is
      Image : constant String := RNG.Word'Image (Value);
   begin
      return Image (Image'First + 1 .. Image'Last);
   end Trim_Word;

   function Mode_Name (Play : Parameters.Play_Mode) return String is
   begin
      case Play is
         when Parameters.Scenario =>
            return "scenario";
         when Parameters.Free_Play =>
            return "free";
         when Parameters.Auto_Play =>
            return "auto";
      end case;
   end Mode_Name;

   function Mode_Of (Text : String) return Parameters.Play_Mode is
   begin
      if Text = "scenario" then
         return Parameters.Scenario;
      elsif Text = "free" then
         return Parameters.Free_Play;
      elsif Text = "auto" then
         return Parameters.Auto_Play;
      end if;
      raise Save_Error with "not a Megacorp save";
   end Mode_Of;

   function Outcome_Name (Which : Mission_Outcome) return String is
   begin
      case Which is
         when Won =>
            return "won";
         when Lost =>
            return "lost";
         when Timed_Out =>
            return "timeout";
      end case;
   end Outcome_Name;

   function Outcome_Of (Text : String) return Mission_Outcome is
   begin
      if Text = "won" then
         return Won;
      elsif Text = "lost" then
         return Lost;
      elsif Text = "timeout" then
         return Timed_Out;
      end if;
      raise Save_Error with "not a Megacorp save";
   end Outcome_Of;

   function Terrain_Code (Kind : Map.Terrain) return Character is
   begin
      case Kind is
         when Map.Open_Ground =>
            return '.';
         when Map.Road =>
            return '+';
         when Map.Pavement =>
            return '=';
         when Map.Building =>
            return 'B';
         when Map.Water =>
            return '~';
      end case;
   end Terrain_Code;

   function Terrain_Of (Code : Character) return Map.Terrain is
   begin
      case Code is
         when '.' =>
            return Map.Open_Ground;
         when '+' =>
            return Map.Road;
         when '=' =>
            return Map.Pavement;
         when 'B' =>
            return Map.Building;
         when '~' =>
            return Map.Water;
         when others =>
            raise Save_Error with "not a Megacorp save";
      end case;
   end Terrain_Of;

   function Bit (Flag : Boolean) return Character is
   begin
      if Flag then
         return '1';
      end if;
      return '0';
   end Bit;

   function Flag (Code : Character) return Boolean is
   begin
      if Code = '1' then
         return True;
      elsif Code = '0' then
         return False;
      end if;
      raise Save_Error with "not a Megacorp save";
   end Flag;

   function Field (Line : String; Index : Positive) return String is
      Seen : Natural := 0;
      Start : Positive;
      Cursor : Positive := Line'First;
   begin
      while Cursor <= Line'Last loop
         while Cursor <= Line'Last and then Line (Cursor) = ' ' loop
            Cursor := Cursor + 1;
         end loop;
         exit when Cursor > Line'Last;
         Seen := Seen + 1;
         Start := Cursor;
         while Cursor <= Line'Last and then Line (Cursor) /= ' ' loop
            Cursor := Cursor + 1;
         end loop;
         if Seen = Index then
            return Line (Start .. Cursor - 1);
         end if;
      end loop;
      return "";
   end Field;

   function Head (Text : String) return Character is
   begin
      if Text'Length = 0 then
         raise Save_Error with "not a Megacorp save";
      end if;
      return Text (Text'First);
   end Head;

   function Stamp_Image (Snap : Snapshot) return String is
   begin
      if Snap.Stamp_Len = 0 then
         return Version;
      end if;
      return Snap.Stamp (1 .. Snap.Stamp_Len);
   end Stamp_Image;

   procedure Set_Stamp (Snap : in out Snapshot; Text : String) is
   begin
      if Text'Length = 0 or else Text'Length > Stamp_Max then
         raise Save_Error with "not a Megacorp save";
      end if;
      Snap.Stamp := (others => ' ');
      Snap.Stamp_Len := Text'Length;
      Snap.Stamp (1 .. Text'Length) := Text;
   end Set_Stamp;

   function Encode
     (Snap : Snapshot;
      Legacy : Boolean := False) return String
   is
      Text : Ada.Strings.Unbounded.Unbounded_String;
      Corp : Ada.Strings.Unbounded.Unbounded_String;
   begin
      Text := Add (Text, "seed " & Trim_Word (Snap.Seed) & ASCII.LF);
      Text := Add (Text, "day " & Trim (Snap.Day) & ASCII.LF);
      Text := Add (Text, "mode " & Mode_Name (Snap.Play) & ASCII.LF);
      Text := Add (Text, "locked " & Bit (Snap.Locked) & ASCII.LF);
      Text := Add
        (Text, "generator " & Stamp_Image (Snap) & ASCII.LF);
      if not Legacy then
         Text := Add
           (Text, "algorithm " & Trim (Snap.Algorithm) & ASCII.LF);
      end if;
      Text := Add (Text, "corps " & Trim (Snap.Corps) & ASCII.LF);
      for I in 1 .. Snap.Corps loop
         Corp := Add
           (Corp,
            "c " & Trim (I)
            & " " & Trim (Snap.Company (I).Cash)
            & " " & Trim (Snap.Company (I).Earned)
            & " " & Trim (Snap.Company (I).Spent)
            & " " & Bit (Snap.Company (I).Eliminated));
         if not Legacy then
            Corp := Add
              (Corp, " " & Trim (Snap.Company (I).Research));
         end if;
         Text := Add
           (Text,
            Ada.Strings.Unbounded.To_String (Corp) & ASCII.LF);
         Corp := Ada.Strings.Unbounded.Null_Unbounded_String;
      end loop;
      Text := Add (Text, "regions " & Trim (Snap.Regions) & ASCII.LF);
      for I in 1 .. Snap.Regions loop
         declare
            Row : Ada.Strings.Unbounded.Unbounded_String;
         begin
            Row := Add
              (Row,
               "r " & Trim (I)
               & " " & Trim (Snap.Area (I).Owner)
               & " " & Trim (Snap.Area (I).Tax)
               & " " & Trim (Snap.Area (I).Unrest)
               & " " & Trim (Snap.Area (I).Defence)
               & " " & Trim (Snap.Area (I).Tech)
               & " " & Bit (Snap.Area (I).Visited));
            if Snap.Area (I).Has_City then
               Row := Add
                 (Row, " " & Trim_Word (Snap.Area (I).City));
            end if;
            Text := Add
              (Text,
               Ada.Strings.Unbounded.To_String (Row) & ASCII.LF);
         end;
      end loop;
      Text := Add (Text, "patches " & Trim (Snap.Patches) & ASCII.LF);
      for I in 1 .. Snap.Patches loop
         Text := Add
           (Text,
            "p " & Trim (Snap.Patch (I).Region)
            & " " & Trim (Snap.Patch (I).X)
            & " " & Trim (Snap.Patch (I).Y)
            & " " & Terrain_Code (Snap.Patch (I).Kind)
            & " " & Trim (Snap.Patch (I).Level)
            & " " & Bit (Snap.Patch (I).Walk)
            & " " & Bit (Snap.Patch (I).Drive)
            & ASCII.LF);
      end loop;
      Text := Add (Text, "squad " & Trim (Snap.Squad) & ASCII.LF);
      for I in 1 .. Snap.Squad loop
         Text := Add
           (Text,
            "a " & Trim (I)
            & " " & Trim (Snap.Agent (I).Health)
            & " " & Trim (Snap.Agent (I).Ammo)
            & " " & Trim (Snap.Agent (I).Region)
            & ASCII.LF);
      end loop;
      Text := Add
        (Text, "missions " & Trim (Snap.Missions) & ASCII.LF);
      for I in 1 .. Snap.Missions loop
         Text := Add
           (Text,
            "m " & Trim (Snap.Mission (I).Region)
            & " " & Outcome_Name (Snap.Mission (I).Outcome)
            & " " & Trim (Snap.Mission (I).Tick)
            & ASCII.LF);
      end loop;
      if not Legacy then
         Text := Add (Text, "funds " & Trim (Snap.Funds) & ASCII.LF);
         Text := Add (Text, "grant " & Trim (Snap.Grant) & ASCII.LF);
         Text := Add
           (Text, "roster " & Trim (Snap.Roster_Count) & ASCII.LF);
         for I in 1 .. Snap.Roster_Count loop
            Text := Add
              (Text,
               "op " & Agents.Name_Of (Snap.Roster (I))
               & " " & Trim (Snap.Roster (I).Health)
               & " " & Trim (Snap.Roster (I).Accuracy)
               & " " & Trim (Snap.Roster (I).Speed)
               & " " & Trim (Snap.Roster (I).Morale)
               & " " & Trim (Snap.Roster (I).Augments)
               & " " & Weapons.Token (Snap.Roster (I).Gun)
               & " " & Trim (Snap.Roster (I).Armour)
               & " " & Bit (Snap.Roster (I).Alive)
               & ASCII.LF);
         end loop;
         Text := Add
           (Text,
            "picks " & Trim (Snap.Pick (1))
            & " " & Trim (Snap.Pick (2))
            & " " & Trim (Snap.Pick (3))
            & " " & Trim (Snap.Pick (4))
            & ASCII.LF);
         Text := Add (Text, "unlock");
         for Item in Research.Branch loop
            Text := Add (Text, " " & Bit (Snap.Known (Item)));
         end loop;
         Text := Add (Text, (1 => ASCII.LF));
      end if;
      return Ada.Strings.Unbounded.To_String (Text);
   end Encode;

   function Wrap
     (Version : Positive;
      Payload : String) return String
   is
   begin
      return "MGC1" & ' ' & Trim (Version) & ASCII.LF
        & Hex (Digest (Payload)) & ASCII.LF
        & Payload;
   end Wrap;

   function Image (Snap : Snapshot) return String is
   begin
      return Wrap (Format_Version, Encode (Snap, False));
   end Image;

   function Legacy_Seal (Snap : Snapshot) return RNG.Word is
   begin
      return Digest (Wrap (1, Encode (Snap, True)));
   end Legacy_Seal;

   function Bytes (Snap : Snapshot) return Natural is
   begin
      return Image (Snap)'Length;
   end Bytes;

   function Line_Of
     (Text : String; Index : Positive) return String
   is
      Seen : Natural := 0;
      Start : Positive := Text'First;
   begin
      for I in Text'Range loop
         if Text (I) = ASCII.LF then
            Seen := Seen + 1;
            if Seen = Index then
               if I = Start then
                  return "";
               end if;
               return Text (Start .. I - 1);
            end if;
            Start := I + 1;
         end if;
      end loop;
      return "";
   end Line_Of;

   function Gun_Of (Text : String) return Weapons.Kind is
   begin
      if Text = "pistol" then
         return Weapons.Pistol;
      elsif Text = "smg" then
         return Weapons.SMG;
      elsif Text = "rifle" then
         return Weapons.Rifle;
      end if;
      raise Save_Error with "not a Megacorp save";
   end Gun_Of;

   function Decode (Payload : String) return Snapshot is
      Snap : Snapshot;
      Cursor : Positive := 1;
      Line : constant String := Line_Of (Payload, 1);
      Count : Natural;
   begin
      if Field (Line, 1) /= "seed" then
         raise Save_Error with "not a Megacorp save";
      end if;
      Snap.Seed := RNG.Word'Value (Field (Line, 2));
      Cursor := 2;
      declare
         Day_Line : constant String := Line_Of (Payload, Cursor);
      begin
         Snap.Day := Natural'Value (Field (Day_Line, 2));
      end;
      Cursor := 3;
      Snap.Play := Mode_Of (Field (Line_Of (Payload, Cursor), 2));
      Cursor := 4;
      Snap.Locked := Flag (Head (Field (Line_Of (Payload, Cursor), 2)));
      Cursor := 5;
      declare
         Mark : constant String := Line_Of (Payload, Cursor);
      begin
         if Field (Mark, 1) /= "generator" then
            raise Save_Error with "not a Megacorp save";
         end if;
         Set_Stamp (Snap, Field (Mark, 2));
      end;
      Cursor := 6;
      declare
         Mark : constant String := Line_Of (Payload, Cursor);
      begin
         if Field (Mark, 1) /= "algorithm" then
            raise Save_Error with "not a Megacorp save";
         end if;
         Snap.Algorithm := Positive'Value (Field (Mark, 2));
         if Snap.Algorithm > World.Gen.Max_Algorithm then
            raise Save_Error with "unknown generator version";
         end if;
      end;
      Cursor := 7;
      Snap.Corps := Positive'Value (Field (Line_Of (Payload, Cursor), 2));
      for I in 1 .. Snap.Corps loop
         Cursor := Cursor + 1;
         declare
            Row : constant String := Line_Of (Payload, Cursor);
            Study : constant String := Field (Row, 7);
         begin
            Snap.Company (I).Cash := Natural'Value (Field (Row, 3));
            Snap.Company (I).Earned := Natural'Value (Field (Row, 4));
            Snap.Company (I).Spent := Natural'Value (Field (Row, 5));
            Snap.Company (I).Eliminated := Flag (Head (Field (Row, 6)));
            if Study'Length = 0 then
               raise Save_Error with "not a Megacorp save";
            end if;
            Snap.Company (I).Research := Natural'Value (Study);
         end;
      end loop;
      Cursor := Cursor + 1;
      Snap.Regions := Positive'Value (Field (Line_Of (Payload, Cursor), 2));
      for I in 1 .. Snap.Regions loop
         Cursor := Cursor + 1;
         declare
            Row : constant String := Line_Of (Payload, Cursor);
         begin
            Snap.Area (I).Owner := Positive'Value (Field (Row, 3));
            Snap.Area (I).Tax := Natural'Value (Field (Row, 4));
            Snap.Area (I).Unrest := Natural'Value (Field (Row, 5));
            Snap.Area (I).Defence := Natural'Value (Field (Row, 6));
            Snap.Area (I).Tech := Natural'Value (Field (Row, 7));
            Snap.Area (I).Visited := Flag (Head (Field (Row, 8)));
            declare
               City_Text : constant String := Field (Row, 9);
            begin
               if City_Text'Length > 0 then
                  Snap.Area (I).Has_City := True;
                  Snap.Area (I).City := RNG.Word'Value (City_Text);
               end if;
            end;
         end;
      end loop;
      Cursor := Cursor + 1;
      Count := Natural'Value (Field (Line_Of (Payload, Cursor), 2));
      if Count > Max_Patches then
         raise Save_Error with "not a Megacorp save";
      end if;
      Snap.Patches := Count;
      for I in 1 .. Snap.Patches loop
         Cursor := Cursor + 1;
         declare
            Row : constant String := Line_Of (Payload, Cursor);
            Code : constant String := Field (Row, 5);
         begin
            Snap.Patch (I).Region := Positive'Value (Field (Row, 2));
            Snap.Patch (I).X := Positive'Value (Field (Row, 3));
            Snap.Patch (I).Y := Positive'Value (Field (Row, 4));
            if Code'Length /= 1 then
               raise Save_Error with "not a Megacorp save";
            end if;
            Snap.Patch (I).Kind := Terrain_Of (Code (Code'First));
            Snap.Patch (I).Level :=
              Map.Height_Level'Value (Field (Row, 6));
            Snap.Patch (I).Walk := Flag (Head (Field (Row, 7)));
            Snap.Patch (I).Drive := Flag (Head (Field (Row, 8)));
         end;
      end loop;
      Cursor := Cursor + 1;
      Snap.Squad := Natural'Value (Field (Line_Of (Payload, Cursor), 2));
      if Snap.Squad > Squad_Size then
         raise Save_Error with "not a Megacorp save";
      end if;
      for I in 1 .. Snap.Squad loop
         Cursor := Cursor + 1;
         declare
            Row : constant String := Line_Of (Payload, Cursor);
         begin
            Snap.Agent (I).Health := Natural'Value (Field (Row, 3));
            Snap.Agent (I).Ammo := Natural'Value (Field (Row, 4));
            Snap.Agent (I).Region := Positive'Value (Field (Row, 5));
         end;
      end loop;
      declare
         Mark : constant String := Line_Of (Payload, Cursor + 1);
      begin
         if Field (Mark, 1) = "missions" then
            Cursor := Cursor + 1;
            Count := Natural'Value (Field (Mark, 2));
            if Count > Max_Missions then
               raise Save_Error with "not a Megacorp save";
            end if;
            Snap.Missions := Count;
            for I in 1 .. Snap.Missions loop
               Cursor := Cursor + 1;
               declare
                  Row : constant String := Line_Of (Payload, Cursor);
               begin
                  Snap.Mission (I).Region :=
                    Positive'Value (Field (Row, 2));
                  Snap.Mission (I).Outcome :=
                    Outcome_Of (Field (Row, 3));
                  Snap.Mission (I).Tick :=
                    Natural'Value (Field (Row, 4));
               end;
            end loop;
         end if;
      end;
      Cursor := Cursor + 1;
      declare
         Mark : constant String := Line_Of (Payload, Cursor);
      begin
         if Field (Mark, 1) /= "funds" then
            raise Save_Error with "not a Megacorp save";
         end if;
         Snap.Funds := Integer'Value (Field (Mark, 2));
      end;
      Cursor := Cursor + 1;
      Snap.Grant :=
        Natural'Value (Field (Line_Of (Payload, Cursor), 2));
      Cursor := Cursor + 1;
      Count := Natural'Value (Field (Line_Of (Payload, Cursor), 2));
      if Count > Agents.Max_Roster then
         raise Save_Error with "not a Megacorp save";
      end if;
      Snap.Roster_Count := Count;
      for I in 1 .. Snap.Roster_Count loop
         Cursor := Cursor + 1;
         declare
            Row : constant String := Line_Of (Payload, Cursor);
            Title : constant String := Field (Row, 2);
         begin
            if Title'Length = 0
              or else Title'Length > Agents.Name_Max
            then
               raise Save_Error with "not a Megacorp save";
            end if;
            Snap.Roster (I).Name := (others => ' ');
            Snap.Roster (I).Name_Len := Title'Length;
            Snap.Roster (I).Name (1 .. Title'Length) := Title;
            Snap.Roster (I).Health :=
              Natural'Value (Field (Row, 3));
            Snap.Roster (I).Accuracy :=
              Natural'Value (Field (Row, 4));
            Snap.Roster (I).Speed :=
              Natural'Value (Field (Row, 5));
            Snap.Roster (I).Morale :=
              Natural'Value (Field (Row, 6));
            Snap.Roster (I).Augments :=
              Natural'Value (Field (Row, 7));
            Snap.Roster (I).Gun := Gun_Of (Field (Row, 8));
            Snap.Roster (I).Armour :=
              Natural'Value (Field (Row, 9));
            Snap.Roster (I).Alive :=
              Flag (Head (Field (Row, 10)));
         end;
      end loop;
      Cursor := Cursor + 1;
      declare
         Mark : constant String := Line_Of (Payload, Cursor);
      begin
         if Field (Mark, 1) /= "picks" then
            raise Save_Error with "not a Megacorp save";
         end if;
         for I in Snap.Pick'Range loop
            Snap.Pick (I) :=
              Natural'Value (Field (Mark, I + 1));
         end loop;
      end;
      Cursor := Cursor + 1;
      declare
         Mark : constant String := Line_Of (Payload, Cursor);
      begin
         if Field (Mark, 1) /= "unlock" then
            raise Save_Error with "not a Megacorp save";
         end if;
         for Item in Research.Branch loop
            Snap.Known (Item) := Flag
              (Head (Field
                 (Mark, Research.Branch'Pos (Item) + 2)));
         end loop;
      end;
      return Snap;
   end Decode;

   function Capture
     (Item : World.Atlas;
      Day : Natural;
      Play : Parameters.Play_Mode;
      Algorithm : Positive := World.Gen.Current_Algorithm)
      return Snapshot
   is
      Snap : Snapshot;
   begin
      Snap.Play := Play;
      Snap.Locked := Play = Parameters.Scenario;
      Snap.Algorithm := Algorithm;
      Set_Stamp (Snap, Version);
      Snap.Squad := Squad_Size;
      for I in 1 .. Squad_Size loop
         Snap.Agent (I).Health := 100;
         Snap.Agent (I).Ammo := 12;
         Snap.Agent (I).Region := Item.Company (1).Home;
      end loop;
      Take (Snap, Item, Day);
      Snap.Funds := 2400;
      Snap.Grant := 0;
      Snap.Roster_Count := 2;
      Snap.Roster (1) := Agents.Person (Item.Seed, 1);
      Snap.Roster (2) := Agents.Person (Item.Seed, 2);
      Snap.Pick := (1, 2, 0, 0);
      Snap.Known := (others => False);
      return Snap;
   end Capture;

   procedure Take
     (Snap : in out Snapshot;
      Item : World.Atlas;
      Day : Natural)
   is
   begin
      Snap.Seed := Item.Seed;
      Snap.Day := Day;
      Snap.Regions := Item.Regions;
      Snap.Corps := Item.Corps;
      for I in 1 .. Item.Corps loop
         Snap.Company (I).Cash := Item.Company (I).Cash;
         Snap.Company (I).Earned := Item.Company (I).Earned;
         Snap.Company (I).Spent := Item.Company (I).Spent;
         Snap.Company (I).Eliminated := Item.Company (I).Eliminated;
      end loop;
      for I in 1 .. Item.Regions loop
         Snap.Area (I).Owner := Item.Area (I).Owner;
         Snap.Area (I).Tax := Item.Area (I).Tax;
         Snap.Area (I).Unrest := Item.Area (I).Unrest;
         Snap.Area (I).Defence := Item.Area (I).Defence;
         Snap.Area (I).Tech := Item.Area (I).Tech;
         declare
            Expected : constant RNG.Word :=
              World.Gen.City_Of
                (Item.Seed, Snap.Algorithm, I);
         begin
            if Item.Area (I).City = Expected then
               Snap.Area (I).Has_City := False;
            else
               Snap.Area (I).Has_City := True;
               Snap.Area (I).City := Item.Area (I).City;
            end if;
         end;
      end loop;
   end Take;

   procedure Restore
     (Snap : Snapshot;
      Item : in out World.Atlas)
   is
   begin
      for I in 1 .. Item.Corps loop
         Item.Company (I).Cash := Snap.Company (I).Cash;
         Item.Company (I).Earned := Snap.Company (I).Earned;
         Item.Company (I).Spent := Snap.Company (I).Spent;
         Item.Company (I).Eliminated := Snap.Company (I).Eliminated;
      end loop;
      for I in 1 .. Item.Regions loop
         Item.Area (I).Owner := Snap.Area (I).Owner;
         Item.Area (I).Tax := Snap.Area (I).Tax;
         Item.Area (I).Unrest := Snap.Area (I).Unrest;
         Item.Area (I).Defence := Snap.Area (I).Defence;
         Item.Area (I).Tech := Snap.Area (I).Tech;
         if Snap.Area (I).Has_City then
            Item.Area (I).City := Snap.Area (I).City;
         end if;
      end loop;
   end Restore;

   function Already
     (Snap : Snapshot; Region, X, Y : Positive) return Boolean
   is
   begin
      for I in 1 .. Snap.Patches loop
         if Snap.Patch (I).Region = Region
           and then Snap.Patch (I).X = X
           and then Snap.Patch (I).Y = Y
         then
            return True;
         end if;
      end loop;
      return False;
   end Already;

   procedure Damage
     (Snap : in out Snapshot;
      Region, X, Y : Positive;
      Cell : Map.Tile)
   is
      Slot : Natural := 0;
   begin
      for I in 1 .. Snap.Patches loop
         if Snap.Patch (I).Region = Region
           and then Snap.Patch (I).X = X
           and then Snap.Patch (I).Y = Y
         then
            Slot := I;
         end if;
      end loop;
      if Slot = 0 then
         Snap.Patches := Snap.Patches + 1;
         Slot := Snap.Patches;
      end if;
      Snap.Patch (Slot) :=
        (Region => Region,
         X => X,
         Y => Y,
         Kind => Cell.Kind,
         Level => Cell.Level,
         Walk => Cell.Walkable,
         Drive => Cell.Drivable);
      Snap.Area (Region).Visited := True;
   end Damage;

   procedure Apply_Patches
     (Snap : Snapshot;
      Region : Positive;
      City : in out Map.City)
   is
      Cell : Map.Tile;
   begin
      for I in 1 .. Snap.Patches loop
         if Snap.Patch (I).Region = Region then
            Cell.Kind := Snap.Patch (I).Kind;
            Cell.Level := Snap.Patch (I).Level;
            Cell.Walkable := Snap.Patch (I).Walk;
            Cell.Drivable := Snap.Patch (I).Drive;
            Map.Set_Tile
              (City, Snap.Patch (I).X, Snap.Patch (I).Y, Cell);
         end if;
      end loop;
   end Apply_Patches;

   procedure Store
     (Disk : in out Data.Virtual_FS.Backend'Class;
      Path : String;
      Snap : Snapshot)
   is
   begin
      Data.Virtual_FS.Write (Disk, Path, Image (Snap));
   end Store;

   function Looks_Saved (Text : String) return Boolean is
      Mark : Natural;
      Split : Natural;
   begin
      if Text'Length < 24 then
         return False;
      end if;
      if Text (Text'First .. Text'First + 4) /= "MGC1 " then
         return False;
      end if;
      Mark := Text'First + 5;
      while Mark <= Text'Last and then Text (Mark) /= ASCII.LF loop
         if Text (Mark) not in '0' .. '9' then
            return False;
         end if;
         Mark := Mark + 1;
      end loop;
      if Mark > Text'Last then
         return False;
      end if;
      Split := Mark + 1;
      if Split + 16 > Text'Last then
         return False;
      end if;
      for I in Split .. Split + 15 loop
         if Text (I) not in '0' .. '9'
           and then Text (I) not in 'a' .. 'f'
         then
            return False;
         end if;
      end loop;
      return Text (Split + 16) = ASCII.LF;
   end Looks_Saved;

   function Load
     (Disk : Data.Virtual_FS.Backend'Class;
      Path : String) return Snapshot
   is
      Text : constant String := Data.Virtual_FS.Read (Disk, Path);
      Mark : Natural;
      Split : Natural;
      Listed : Natural;
   begin
      if Text'Length < 8 or else Text (Text'First .. Text'First + 4) /= "MGC1 "
      then
         raise Save_Error with "not a Megacorp save";
      end if;
      Mark := Text'First + 5;
      while Mark <= Text'Last and then Text (Mark) /= ASCII.LF loop
         Mark := Mark + 1;
      end loop;
      if Mark > Text'Last then
         raise Save_Error with "not a Megacorp save";
      end if;
      begin
         Listed := Natural'Value
           (Text (Text'First + 5 .. Mark - 1));
      exception
         when Constraint_Error =>
            raise Save_Error with "not a Megacorp save";
      end;
      if Listed < 1 then
         raise Save_Error with "not a Megacorp save";
      end if;
      if Listed > Format_Version then
         raise Save_Error with "wrong format version";
      end if;
      Split := Mark + 1;
      while Split <= Text'Last and then Text (Split) /= ASCII.LF loop
         Split := Split + 1;
      end loop;
      if Split > Text'Last or else Split < Mark + 17 then
         raise Save_Error with "checksum mismatch";
      end if;
      declare
         Sum : constant RNG.Word :=
           From_Hex (Text (Mark + 1 .. Split - 1));
         Payload_Text : constant String :=
           Text (Split + 1 .. Text'Last);
         Current : constant String :=
           (if Listed = Format_Version then Text
            else Migrate.To_Current (Text));
         Body_At : Natural := Current'First;
         Seen : Natural := 0;
      begin
         if Digest (Payload_Text) /= Sum then
            raise Save_Error with "checksum mismatch";
         end if;
         if Listed < Format_Version then
            Host.Log
              (Host.Info,
               Migrate.Note (Listed, Format_Version));
         end if;
         for I in Current'Range loop
            if Current (I) = ASCII.LF then
               Seen := Seen + 1;
               if Seen = 2 then
                  Body_At := I + 1;
                  exit;
               end if;
            end if;
         end loop;
         begin
            return Decode (Current (Body_At .. Current'Last));
         exception
            when Constraint_Error =>
               raise Save_Error with "not a Megacorp save";
         end;
      end;
   end Load;

   function Rebuild
     (Snap : Snapshot;
      Size : Parameters.Generator_Parameters) return World.Atlas
   is
      Result : World.Atlas;
   begin
      if Snap.Algorithm > World.Gen.Max_Algorithm then
         raise Save_Error with "unknown generator version";
      end if;
      Result := World.Gen.Generate
        (Snap.Seed, Size, Snap.Algorithm);
      Restore (Snap, Result);
      return Result;
   end Rebuild;

   function Same (Left, Right : Snapshot) return Boolean is
   begin
      if Left.Seed /= Right.Seed
        or else Left.Day /= Right.Day
        or else Left.Play /= Right.Play
        or else Left.Locked /= Right.Locked
        or else Left.Regions /= Right.Regions
        or else Left.Corps /= Right.Corps
        or else Left.Patches /= Right.Patches
        or else Left.Squad /= Right.Squad
        or else Left.Missions /= Right.Missions
        or else Left.Funds /= Right.Funds
        or else Left.Grant /= Right.Grant
        or else Left.Roster_Count /= Right.Roster_Count
        or else Left.Algorithm /= Right.Algorithm
        or else Left.Stamp_Len /= Right.Stamp_Len
        or else (Left.Stamp_Len > 0
                 and then Left.Stamp (1 .. Left.Stamp_Len)
                   /= Right.Stamp (1 .. Left.Stamp_Len))
      then
         return False;
      end if;
      for I in 1 .. Left.Corps loop
         if Left.Company (I).Cash /= Right.Company (I).Cash
           or else Left.Company (I).Earned /= Right.Company (I).Earned
           or else Left.Company (I).Spent /= Right.Company (I).Spent
           or else Left.Company (I).Eliminated
             /= Right.Company (I).Eliminated
           or else Left.Company (I).Research
             /= Right.Company (I).Research
         then
            return False;
         end if;
      end loop;
      for I in 1 .. Left.Regions loop
         if Left.Area (I).Owner /= Right.Area (I).Owner
           or else Left.Area (I).Tax /= Right.Area (I).Tax
           or else Left.Area (I).Unrest /= Right.Area (I).Unrest
           or else Left.Area (I).Defence /= Right.Area (I).Defence
           or else Left.Area (I).Tech /= Right.Area (I).Tech
           or else Left.Area (I).Visited /= Right.Area (I).Visited
           or else Left.Area (I).Has_City /= Right.Area (I).Has_City
           or else (Left.Area (I).Has_City
                    and then Left.Area (I).City /= Right.Area (I).City)
         then
            return False;
         end if;
      end loop;
      for I in 1 .. Left.Patches loop
         if Left.Patch (I).Region /= Right.Patch (I).Region
           or else Left.Patch (I).X /= Right.Patch (I).X
           or else Left.Patch (I).Y /= Right.Patch (I).Y
           or else Left.Patch (I).Kind /= Right.Patch (I).Kind
           or else Left.Patch (I).Level /= Right.Patch (I).Level
           or else Left.Patch (I).Walk /= Right.Patch (I).Walk
           or else Left.Patch (I).Drive /= Right.Patch (I).Drive
         then
            return False;
         end if;
      end loop;
      for I in 1 .. Left.Squad loop
         if Left.Agent (I).Health /= Right.Agent (I).Health
           or else Left.Agent (I).Ammo /= Right.Agent (I).Ammo
           or else Left.Agent (I).Region /= Right.Agent (I).Region
         then
            return False;
         end if;
      end loop;
      for I in 1 .. Left.Missions loop
         if Left.Mission (I).Region /= Right.Mission (I).Region
           or else Left.Mission (I).Outcome /= Right.Mission (I).Outcome
           or else Left.Mission (I).Tick /= Right.Mission (I).Tick
         then
            return False;
         end if;
      end loop;
      for I in 1 .. Left.Roster_Count loop
         if Left.Roster (I).Name_Len /= Right.Roster (I).Name_Len
           or else Left.Roster (I).Name (1 .. Left.Roster (I).Name_Len)
             /= Right.Roster (I).Name
               (1 .. Right.Roster (I).Name_Len)
           or else Left.Roster (I).Health /= Right.Roster (I).Health
           or else Left.Roster (I).Accuracy
             /= Right.Roster (I).Accuracy
           or else Left.Roster (I).Speed /= Right.Roster (I).Speed
           or else Left.Roster (I).Morale /= Right.Roster (I).Morale
           or else Left.Roster (I).Augments
             /= Right.Roster (I).Augments
           or else Left.Roster (I).Gun /= Right.Roster (I).Gun
           or else Left.Roster (I).Armour /= Right.Roster (I).Armour
           or else Left.Roster (I).Alive /= Right.Roster (I).Alive
         then
            return False;
         end if;
      end loop;
      for I in Left.Pick'Range loop
         if Left.Pick (I) /= Right.Pick (I) then
            return False;
         end if;
      end loop;
      for Item in Research.Branch loop
         if Left.Known (Item) /= Right.Known (Item) then
            return False;
         end if;
      end loop;
      return True;
   end Same;

end Megacorp.Save;
