--  SPDX-License-Identifier: MIT
--  Copyright (c) 2026 Robert Boettcher

with Megacorp.Host;
with Megacorp.Parameters;
with Megacorp.Play;
with Megacorp.World.Campaign;

package body Megacorp.Save.Log is
   use type Parameters.Play_Mode;

   Basis : constant RNG.Word := 16#CBF2_9CE4_8422_2325#;
   Prime : constant RNG.Word := 16#0000_0100_0000_01B3#;
   Mix_A : constant RNG.Word := 16#18_0000_0001#;
   Mix_B : constant RNG.Word := 16#18_0000_0002#;

   LF : constant String := (1 => ASCII.LF);
   Torn_Note : constant String := "torn delta record dropped";
   Base_Note : constant String := "delta base mismatch";

   function Digest (Text : String) return RNG.Word;
   function Hex (Value : RNG.Word) return String;
   function From_Hex (Text : String) return RNG.Word;
   function Trim (Value : Integer) return String;
   function Trim_Word (Value : RNG.Word) return String;
   function Bit (Flag : Boolean) return Character;
   function Flag (Code : Character) return Boolean;
   function Field (Line : String; Index : Positive) return String;
   function Head (Text : String) return Character;
   function Terrain_Code (Kind : Map.Terrain) return Character;
   function Terrain_Of (Code : Character) return Map.Terrain;
   function Outcome_Name (Which : Mission_Outcome) return String;
   function Outcome_Of (Text : String) return Mission_Outcome;
   function Wording (Ev : Event) return String;
   function Payload_Of (Line : String) return String;
   function Signed (Line : String) return Boolean;
   function Parse (Payload : String; Ev : out Event) return Boolean;
   function Seal (Snap : Snapshot) return RNG.Word;
   function Header (Snap : Snapshot) return String;
   function Line_Text (Ev : Event) return String;
   procedure Refuse (Snap : Snapshot; Region : Positive);
   procedure Guard (Snap : Snapshot; Ev : Event);
   procedure Apply
     (Snap : in out Snapshot;
      Item : in out World.Atlas;
      Ev : Event);

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
      raise Save_Error with "not a Megacorp delta";
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
         raise Save_Error with "not a Megacorp delta";
      end if;
      return Text (Text'First);
   end Head;

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
            raise Save_Error with "not a Megacorp delta";
      end case;
   end Terrain_Of;

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
      raise Save_Error with "not a Megacorp delta";
   end Outcome_Of;

   function Wording (Ev : Event) return String is
   begin
      case Ev.Kind is
         when Kind_Day =>
            if Ev.Input = Tax_Input then
               return "day tax " & Trim (Ev.Region)
                 & " " & Trim (Ev.Tax);
            end if;
            return "day none";
         when Kind_Region =>
            return "region " & Trim (Ev.Region)
              & " " & Trim (Ev.Owner)
              & " " & Trim (Ev.Tax)
              & " " & Trim (Ev.Unrest)
              & " " & Trim (Ev.Defence)
              & " " & Trim (Ev.Tech)
              & " " & Bit (Ev.Visited);
         when Kind_Mission =>
            return "mission " & Trim (Ev.Region)
              & " " & Outcome_Name (Ev.Outcome)
              & " " & Trim (Ev.Tick);
         when Kind_Tile =>
            return "patch " & Trim (Ev.Region)
              & " " & Trim (Ev.X)
              & " " & Trim (Ev.Y)
              & " " & Terrain_Code (Ev.Terrain)
              & " " & Trim (Ev.Level)
              & " " & Bit (Ev.Walk)
              & " " & Bit (Ev.Drive);
         when Kind_Squad =>
            return "squad " & Trim (Ev.Slot)
              & " " & Trim (Ev.Health)
              & " " & Trim (Ev.Ammo)
              & " " & Trim (Ev.Region);
         when Kind_Reroll =>
            return "reroll " & Trim (Ev.Region)
              & " " & Trim_Word (Ev.City);
         when Kind_Order =>
            return "order " & Trim (Ev.Code)
              & " " & Trim (Ev.A)
              & " " & Trim (Ev.B)
              & " " & Trim (Ev.C)
              & " " & Trim (Ev.D)
              & " " & Trim (Ev.E);
         when Kind_Ticks =>
            return "ticks " & Trim (Ev.Code);
      end case;
   end Wording;

   function Payload_Of (Line : String) return String is
   begin
      return Line (Line'First .. Line'Last - 17);
   end Payload_Of;

   function Signed (Line : String) return Boolean is
   begin
      if Line'Length < 18 then
         return False;
      end if;
      if Line (Line'Last - 16) /= ' ' then
         return False;
      end if;
      return Digest (Payload_Of (Line))
        = From_Hex (Line (Line'Last - 15 .. Line'Last));
   exception
      when Save_Error =>
         return False;
   end Signed;

   function Parse (Payload : String; Ev : out Event) return Boolean is
      Kind : constant String := Field (Payload, 1);
      Code : constant String := Field (Payload, 5);
   begin
      Ev := (others => <>);
      if Kind = "day" then
         Ev.Kind := Kind_Day;
         if Field (Payload, 2) = "none" then
            Ev.Input := No_Input;
            return Field (Payload, 3)'Length = 0;
         elsif Field (Payload, 2) = "tax" then
            Ev.Input := Tax_Input;
            Ev.Region := Positive'Value (Field (Payload, 3));
            Ev.Tax := Natural'Value (Field (Payload, 4));
            return Ev.Tax <= 100
              and then Field (Payload, 5)'Length = 0;
         end if;
         return False;
      elsif Kind = "region" then
         Ev.Kind := Kind_Region;
         Ev.Region := Positive'Value (Field (Payload, 2));
         Ev.Owner := Positive'Value (Field (Payload, 3));
         Ev.Tax := Natural'Value (Field (Payload, 4));
         Ev.Unrest := Natural'Value (Field (Payload, 5));
         Ev.Defence := Natural'Value (Field (Payload, 6));
         Ev.Tech := Natural'Value (Field (Payload, 7));
         Ev.Visited := Flag (Head (Field (Payload, 8)));
         return True;
      elsif Kind = "mission" then
         Ev.Kind := Kind_Mission;
         Ev.Region := Positive'Value (Field (Payload, 2));
         Ev.Outcome := Outcome_Of (Field (Payload, 3));
         Ev.Tick := Natural'Value (Field (Payload, 4));
         return True;
      elsif Kind = "patch" then
         Ev.Kind := Kind_Tile;
         Ev.Region := Positive'Value (Field (Payload, 2));
         Ev.X := Positive'Value (Field (Payload, 3));
         Ev.Y := Positive'Value (Field (Payload, 4));
         if Code'Length /= 1 then
            return False;
         end if;
         Ev.Terrain := Terrain_Of (Code (Code'First));
         Ev.Level := Map.Height_Level'Value (Field (Payload, 6));
         Ev.Walk := Flag (Head (Field (Payload, 7)));
         Ev.Drive := Flag (Head (Field (Payload, 8)));
         return True;
      elsif Kind = "squad" then
         Ev.Kind := Kind_Squad;
         Ev.Slot := Positive'Value (Field (Payload, 2));
         Ev.Health := Natural'Value (Field (Payload, 3));
         Ev.Ammo := Natural'Value (Field (Payload, 4));
         Ev.Region := Positive'Value (Field (Payload, 5));
         return True;
      elsif Kind = "reroll" then
         Ev.Kind := Kind_Reroll;
         Ev.Region := Positive'Value (Field (Payload, 2));
         Ev.City := RNG.Word'Value (Field (Payload, 3));
         return True;
      elsif Kind = "order" then
         Ev.Kind := Kind_Order;
         Ev.Code := Integer'Value (Field (Payload, 2));
         Ev.A := Integer'Value (Field (Payload, 3));
         Ev.B := Integer'Value (Field (Payload, 4));
         Ev.C := Integer'Value (Field (Payload, 5));
         Ev.D := Integer'Value (Field (Payload, 6));
         Ev.E := Integer'Value (Field (Payload, 7));
         return Field (Payload, 8)'Length = 0;
      elsif Kind = "ticks" then
         Ev.Kind := Kind_Ticks;
         Ev.Code := Integer'Value (Field (Payload, 2));
         return Ev.Code > 0 and then Ev.Code <= 32
           and then Field (Payload, 3)'Length = 0;
      end if;
      return False;
   exception
      when Constraint_Error | Save_Error =>
         return False;
   end Parse;

   function Seal (Snap : Snapshot) return RNG.Word is
   begin
      return Digest (Image (Snap));
   end Seal;

   function Header (Snap : Snapshot) return String is
      Seal_Text : constant String := Hex (Seal (Snap));
      Payload : constant String := "base " & Seal_Text;
   begin
      return "MGCD " & Trim (Format_Version)
        & LF
        & Payload & ' ' & Hex (Digest (Payload))
        & LF;
   end Header;

   function Line_Text (Ev : Event) return String is
      Payload : constant String := Wording (Ev);
   begin
      return Payload & ' ' & Hex (Digest (Payload)) & LF;
   end Line_Text;

   procedure Refuse (Snap : Snapshot; Region : Positive) is
   begin
      if Parameters.Region_May_Reroll
        (Snap.Play, Snap.Area (Region).Visited)
      then
         return;
      end if;
      if Snap.Play = Parameters.Scenario then
         raise Save_Error with "scenario refuses re-roll";
      end if;
      raise Save_Error with "visited region stays";
   end Refuse;

   procedure Guard (Snap : Snapshot; Ev : Event) is
   begin
      case Ev.Kind is
         when Kind_Day =>
            if Ev.Input = Tax_Input
              and then Ev.Region > Snap.Regions
            then
               raise Save_Error with "not a Megacorp delta";
            end if;
         when Kind_Region =>
            if Ev.Region > Snap.Regions
              or else Ev.Owner > Snap.Corps
            then
               raise Save_Error with "not a Megacorp delta";
            end if;
         when Kind_Mission | Kind_Tile =>
            if Ev.Region > Snap.Regions then
               raise Save_Error with "not a Megacorp delta";
            end if;
         when Kind_Squad =>
            if Ev.Slot > Snap.Squad then
               raise Save_Error with "not a Megacorp delta";
            end if;
         when Kind_Reroll =>
            if Ev.Region > Snap.Regions then
               raise Save_Error with "not a Megacorp delta";
            end if;
            Refuse (Snap, Ev.Region);
         when Kind_Order =>
            null;
         when Kind_Ticks =>
            if Ev.Code < 1 or else Ev.Code > 32 then
               raise Save_Error with "not a Megacorp delta";
            end if;
      end case;
   end Guard;

   procedure Apply
     (Snap : in out Snapshot;
      Item : in out World.Atlas;
      Ev : Event)
   is
   begin
      Guard (Snap, Ev);
      case Ev.Kind is
         when Kind_Day =>
            if Ev.Input = Tax_Input then
               Item.Area (Ev.Region).Tax := Ev.Tax;
               Snap.Area (Ev.Region).Tax := Ev.Tax;
            end if;
            World.Campaign.Advance (Item);
            Take (Snap, Item, Snap.Day + 1);
         when Kind_Region =>
            Item.Area (Ev.Region).Owner := Ev.Owner;
            Item.Area (Ev.Region).Tax := Ev.Tax;
            Item.Area (Ev.Region).Unrest := Ev.Unrest;
            Item.Area (Ev.Region).Defence := Ev.Defence;
            Item.Area (Ev.Region).Tech := Ev.Tech;
            Snap.Area (Ev.Region).Owner := Ev.Owner;
            Snap.Area (Ev.Region).Tax := Ev.Tax;
            Snap.Area (Ev.Region).Unrest := Ev.Unrest;
            Snap.Area (Ev.Region).Defence := Ev.Defence;
            Snap.Area (Ev.Region).Tech := Ev.Tech;
            Snap.Area (Ev.Region).Visited := Ev.Visited;
         when Kind_Mission =>
            if Snap.Missions >= Max_Missions then
               raise Save_Error with "not a Megacorp delta";
            end if;
            Snap.Missions := Snap.Missions + 1;
            Snap.Mission (Snap.Missions).Region := Ev.Region;
            Snap.Mission (Snap.Missions).Outcome := Ev.Outcome;
            Snap.Mission (Snap.Missions).Tick := Ev.Tick;
            Snap.Area (Ev.Region).Visited := True;
         when Kind_Tile =>
            declare
               Cell : Map.Tile;
            begin
               if Snap.Patches >= Max_Patches
                 and then not Already
                   (Snap, Ev.Region, Ev.X, Ev.Y)
               then
                  raise Save_Error with "not a Megacorp delta";
               end if;
               Cell.Kind := Ev.Terrain;
               Cell.Level := Ev.Level;
               Cell.Walkable := Ev.Walk;
               Cell.Drivable := Ev.Drive;
               Damage (Snap, Ev.Region, Ev.X, Ev.Y, Cell);
            end;
         when Kind_Squad =>
            Snap.Agent (Ev.Slot).Health := Ev.Health;
            Snap.Agent (Ev.Slot).Ammo := Ev.Ammo;
            Snap.Agent (Ev.Slot).Region := Ev.Region;
         when Kind_Reroll =>
            Item.Area (Ev.Region).City := Ev.City;
            Snap.Area (Ev.Region).Has_City := True;
            Snap.Area (Ev.Region).City := Ev.City;
         when Kind_Order =>
            Play.Handle (Ev.Code, Ev.A, Ev.B, Ev.C, Ev.D, Ev.E);
         when Kind_Ticks =>
            Play.Run (Positive (Ev.Code));
      end case;
   end Apply;

   function Count (Book : Journal) return Natural is
   begin
      return Book.Count;
   end Count;

   function Due (Book : Journal) return Boolean is
   begin
      return Book.Count >= Compact_After;
   end Due;

   function Notice (Book : Journal) return String is
   begin
      if Book.Dropped > 0 then
         return Torn_Note;
      elsif Book.Ignored then
         return Base_Note;
      end if;
      return "";
   end Notice;

   function Interesting (Ev : Event) return Boolean;
   function Headline_Of (Ev : Event) return String;

   function Interesting (Ev : Event) return Boolean is
   begin
      case Ev.Kind is
         when Kind_Region | Kind_Mission =>
            return True;
         when Kind_Day =>
            return Ev.Input = Tax_Input;
         when others =>
            return False;
      end case;
   end Interesting;

   function Headline_Of (Ev : Event) return String is
   begin
      case Ev.Kind is
         when Kind_Region =>
            return "Region " & Trim (Ev.Region)
              & " held by " & Trim (Ev.Owner);
         when Kind_Mission =>
            return "Mission " & Trim (Ev.Region)
              & " " & Outcome_Name (Ev.Outcome);
         when Kind_Day =>
            return "Tax on region " & Trim (Ev.Region)
              & " is " & Trim (Ev.Tax);
         when others =>
            return "";
      end case;
   end Headline_Of;

   function Headline_Count (Book : Journal) return Natural is
      Total : Natural := 0;
   begin
      for I in reverse 1 .. Book.Count loop
         if Interesting (Book.Item (I)) then
            Total := Total + 1;
            if Total = 8 then
               return Total;
            end if;
         end if;
      end loop;
      return Total;
   end Headline_Count;

   function Headline
     (Book : Journal;
      Index : Positive) return String
   is
      Seen : Natural := 0;
   begin
      for I in reverse 1 .. Book.Count loop
         if Interesting (Book.Item (I)) then
            Seen := Seen + 1;
            if Seen = Index then
               return Headline_Of (Book.Item (I));
            end if;
         end if;
      end loop;
      return "";
   end Headline;

   function Day_None return Event is
   begin
      return (Kind => Kind_Day, Input => No_Input, others => <>);
   end Day_None;

   function Day_Tax
     (Region : Positive;
      Rate : Natural) return Event
   is
   begin
      return
        (Kind => Kind_Day,
         Input => Tax_Input,
         Region => Region,
         Tax => Rate,
         others => <>);
   end Day_Tax;

   function Region_Set
     (Snap : Snapshot;
      Item : World.Atlas;
      Region : Positive) return Event
   is
   begin
      return
        (Kind => Kind_Region,
         Region => Region,
         Owner => Item.Area (Region).Owner,
         Tax => Item.Area (Region).Tax,
         Unrest => Item.Area (Region).Unrest,
         Defence => Item.Area (Region).Defence,
         Tech => Item.Area (Region).Tech,
         Visited => Snap.Area (Region).Visited,
         others => <>);
   end Region_Set;

   function Mission_Done
     (Region : Positive;
      Outcome : Mission_Outcome;
      Tick : Natural) return Event
   is
   begin
      return
        (Kind => Kind_Mission,
         Region => Region,
         Outcome => Outcome,
         Tick => Tick,
         others => <>);
   end Mission_Done;

   function Tile_Change
     (Region, X, Y : Positive;
      Cell : Map.Tile) return Event
   is
   begin
      return
        (Kind => Kind_Tile,
         Region => Region,
         X => X,
         Y => Y,
         Terrain => Cell.Kind,
         Level => Cell.Level,
         Walk => Cell.Walkable,
         Drive => Cell.Drivable,
         others => <>);
   end Tile_Change;

   function Squad_Change
     (Slot : Positive;
      Health, Ammo : Natural;
      Region : Positive) return Event
   is
   begin
      return
        (Kind => Kind_Squad,
         Slot => Slot,
         Health => Health,
         Ammo => Ammo,
         Region => Region,
         others => <>);
   end Squad_Change;

   function Reroll
     (Snap : Snapshot;
      Item : World.Atlas;
      Region : Positive) return Event
   is
      Current : constant RNG.Word := Item.Area (Region).City;
      Next : RNG.Word;
   begin
      Refuse (Snap, Region);
      Next := RNG.Derive (Current, Mix_A);
      if Next = Current then
         Next := RNG.Derive (Current, Mix_B);
      end if;
      return
        (Kind => Kind_Reroll,
         Region => Region,
         City => Next,
         others => <>);
   end Reroll;

   function Order
     (Code, A, B, C, D, E : Integer) return Event
   is
   begin
      return
        (Kind => Kind_Order,
         Code => Code,
         A => A,
         B => B,
         C => C,
         D => D,
         E => E,
         others => <>);
   end Order;

   function Ticks (Count : Positive) return Event is
   begin
      return (Kind => Kind_Ticks, Code => Count, others => <>);
   end Ticks;

   function Start
     (Disk : in out Data.Virtual_FS.Backend'Class;
      Path : String;
      Snap : Snapshot) return Journal
   is
      Book : Journal;
   begin
      Book.Base := Seal (Snap);
      Data.Virtual_FS.Write (Disk, Path, Header (Snap));
      return Book;
   end Start;

   function Load
     (Disk : Data.Virtual_FS.Backend'Class;
      Path : String) return Journal
   is
      Text : constant String :=
        Data.Virtual_FS.Read (Disk, Path);
      Book : Journal;
      Torn : Boolean := False;
      Last : Natural := 0;

      type Span is record
         Lo : Positive := 1;
         Hi : Natural := 0;
      end record;

      Lines : array (1 .. Max_Events + 4) of Span;
      Total : Natural := 0;
      Start_At : Positive := Text'First;

      function Slice (Index : Positive) return String;
      procedure Note_Torn;

      function Slice (Index : Positive) return String is
         Sp : constant Span := Lines (Index);
      begin
         if Sp.Hi < Sp.Lo then
            return "";
         end if;
         return Text (Sp.Lo .. Sp.Hi);
      end Slice;

      procedure Note_Torn is
      begin
         Torn := True;
         Book.Dropped := 1;
         Host.Log (Host.Warning, Torn_Note);
      end Note_Torn;
   begin
      if Text'Length = 0 then
         raise Save_Error with "not a Megacorp delta";
      end if;
      if Text (Text'Last) = ASCII.LF then
         Last := Text'Last;
      else
         Torn := True;
         for I in reverse Text'Range loop
            if Text (I) = ASCII.LF then
               Last := I;
               exit;
            end if;
         end loop;
      end if;
      if Last < Text'First then
         Note_Torn;
         return Book;
      end if;
      for I in Text'First .. Last loop
         if Text (I) = ASCII.LF then
            Total := Total + 1;
            if Total > Lines'Last then
               raise Save_Error with "not a Megacorp delta";
            end if;
            if I = Start_At then
               Lines (Total) := (Lo => Start_At, Hi => 0);
            else
               Lines (Total) := (Lo => Start_At, Hi => I - 1);
            end if;
            Start_At := I + 1;
         end if;
      end loop;
      if Total < 1
        or else Field (Slice (1), 1) /= "MGCD"
      then
         raise Save_Error with "not a Megacorp delta";
      end if;
      declare
         Listed : Natural;
      begin
         Listed := Natural'Value (Field (Slice (1), 2));
         if Listed /= Format_Version then
            raise Save_Error with "wrong format version";
         end if;
      exception
         when Constraint_Error =>
            raise Save_Error with "not a Megacorp delta";
      end;
      if Total < 2 then
         if Torn then
            Note_Torn;
            return Book;
         end if;
         raise Save_Error with "not a Megacorp delta";
      end if;
      declare
         Base_Line : constant String := Slice (2);
      begin
         if not Signed (Base_Line) then
            if Torn and then Total = 2 then
               Note_Torn;
               return Book;
            end if;
            raise Save_Error with "checksum mismatch";
         end if;
         declare
            Payload : constant String := Payload_Of (Base_Line);
         begin
            if Field (Payload, 1) /= "base" then
               raise Save_Error with "not a Megacorp delta";
            end if;
            Book.Base := From_Hex (Field (Payload, 2));
         end;
      end;
      for I in 3 .. Total loop
         declare
            Row : constant String := Slice (I);
            Ev : Event;
         begin
            if not Signed (Row)
              or else not Parse (Payload_Of (Row), Ev)
            then
               if I = Total then
                  Note_Torn;
                  exit;
               elsif not Signed (Row) then
                  raise Save_Error with "checksum mismatch";
               else
                  raise Save_Error with "not a Megacorp delta";
               end if;
            end if;
            Book.Count := Book.Count + 1;
            Book.Item (Book.Count) := Ev;
         end;
      end loop;
      if Torn and then Book.Dropped = 0 then
         Note_Torn;
      end if;
      return Book;
   end Load;

   procedure Rewrite
     (Disk : in out Data.Virtual_FS.Backend'Class;
      Path : String;
      Snap : Snapshot;
      Book : in out Journal)
   is
   begin
      if Book.Base /= 0
        and then Book.Base /= Seal (Snap)
        and then Book.Base /= Legacy_Seal (Snap)
      then
         return;
      end if;
      Data.Virtual_FS.Write (Disk, Path, Header (Snap));
      for I in 1 .. Book.Count loop
         Data.Virtual_FS.Append
           (Disk, Path, Line_Text (Book.Item (I)));
      end loop;
      Book.Dropped := 0;
      if Book.Count = 0 then
         Book.Base := Seal (Snap);
      end if;
   end Rewrite;

   procedure Commit
     (Disk : in out Data.Virtual_FS.Backend'Class;
      Path : String;
      Snap : in out Snapshot;
      Item : in out World.Atlas;
      Book : in out Journal;
      Ev : Event)
   is
   begin
      Guard (Snap, Ev);
      Data.Virtual_FS.Append (Disk, Path, Line_Text (Ev));
      Book.Count := Book.Count + 1;
      Book.Item (Book.Count) := Ev;
      Apply (Snap, Item, Ev);
   end Commit;

   procedure Replay
     (Snap : in out Snapshot;
      Item : in out World.Atlas;
      Book : in out Journal)
   is
   begin
      if Book.Count = 0 and then Book.Base = 0 then
         return;
      end if;
      if Book.Base /= Seal (Snap)
        and then Book.Base /= Legacy_Seal (Snap)
      then
         Book.Ignored := True;
         Host.Log (Host.Warning, Base_Note);
         return;
      end if;
      for I in 1 .. Book.Count loop
         Apply (Snap, Item, Book.Item (I));
      end loop;
   end Replay;

   procedure Compact
     (Disk : in out Data.Virtual_FS.Backend'Class;
      Snap_Path, Log_Path : String;
      Snap : Snapshot;
      Book : in out Journal)
   is
   begin
      Data.Virtual_FS.Write (Disk, Snap_Path, Image (Snap));
      Data.Virtual_FS.Write (Disk, Log_Path, Header (Snap));
      Book.Count := 0;
      Book.Dropped := 0;
      Book.Ignored := False;
      Book.Base := Seal (Snap);
   end Compact;

end Megacorp.Save.Log;
