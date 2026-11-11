--  SPDX-License-Identifier: MIT
--  Copyright (c) 2026 Robert Boettcher

with Megacorp.Agents;
with Megacorp.API;
with Megacorp.Assets.Import;
with Megacorp.Data.Virtual_FS;
with Megacorp.Data.Virtual_FS.Browser;
with Megacorp.Menu;
with Megacorp.Mission.Gen;
with Megacorp.Parameters;
with Megacorp.Play;
with Megacorp.Research;
with Megacorp.RNG;
with Megacorp.Save;
with Megacorp.Save.Log;
with Megacorp.Session;
with Megacorp.Sound;
with Megacorp.Weapons;
with Megacorp.World.Campaign;
with Megacorp.World.Gen;

package body Megacorp.Wasm_Store is
   use type RNG.Word;
   use type Parameters.Play_Mode;
   use type Menu.Screen;
   use type Menu.Action;

   package Host_Files renames Megacorp.Data.Virtual_FS.Browser;

   Files : Host_Files.Disk := Host_Files.Open;
   Snap  : Save.Snapshot;
   Globe : World.Atlas;
   Book  : Save.Log.Journal;

   Cap : constant := 65536;
   Brief_Max : constant := 2048;
   Office_Max : constant := 1024;
   type Octet is new Interfaces.Unsigned_8;
   Import_Buf : array (1 .. Cap) of Octet := (others => 0);
   Brief_Buf : array (0 .. Brief_Max - 1) of Octet := (others => 0);
   Brief_Used : Natural := 0;
   Office_Buf : array (0 .. Office_Max - 1) of Octet := (others => 0);
   Office_Used : Natural := 0;
   Menu_Max : constant := 1024;
   Menu_Buf : array (0 .. Menu_Max - 1) of Octet := (others => 0);
   Menu_Used : Natural := 0;
   Sound_Max : constant := 512;
   Sound_Buf : array (0 .. Sound_Max - 1) of Octet := (others => 0);
   Sound_Used : Natural := 0;
   Sound_Seq : Natural := 0;
   Extra_Max : constant := 8;
   Extra : array (1 .. Extra_Max) of Natural := (others => 0);
   Extra_N : Natural := 0;
   Card : Menu.Card;
   World_Ready : Boolean := False;

   procedure Fresh
     (Seed : Interfaces.Unsigned_32;
      Mode : Parameters.Play_Mode);
   procedure Write_Menu;
   procedure Write_Sound;
   procedure Push_Extra (Code : Natural);
   procedure Save_Game;
   procedure Load_Game;
   procedure Launch_Mission;
   procedure Try_Reroll;
   procedure Apply_Menu (Act : Menu.Action; Arg : Integer);
   procedure Load_Prefs;
   procedure Store_Prefs;
   function Roster_Alive return Natural;
   procedure Note (Ev : Save.Log.Event);
   procedure Refresh;
   procedure Put_B (Value : Natural);
   procedure Put_I16 (Value : Integer);
   procedure Put_Name (Item : String);
   procedure Put_O (Value : Natural);
   procedure Put_U16 (Value : Natural);
   procedure Put_I32 (Value : Integer);
   procedure Put_Fixed (Item : String; Width : Natural);
   procedure Write_Office;

   procedure Put_B (Value : Natural) is
   begin
      if Brief_Used >= Brief_Max then
         return;
      end if;
      Brief_Buf (Brief_Used) := Octet (Value mod 256);
      Brief_Used := Brief_Used + 1;
   end Put_B;

   procedure Put_I16 (Value : Integer) is
      Bits : Integer := Value;
      Stored : Natural;
   begin
      if Bits > 32767 then
         Bits := 32767;
      elsif Bits < -32768 then
         Bits := -32768;
      end if;
      if Bits < 0 then
         Stored := 65536 + Bits;
      else
         Stored := Bits;
      end if;
      Put_B (Stored mod 256);
      Put_B (Stored / 256);
   end Put_I16;

   procedure Put_O (Value : Natural) is
   begin
      if Office_Used >= Office_Max then
         return;
      end if;
      Office_Buf (Office_Used) := Octet (Value mod 256);
      Office_Used := Office_Used + 1;
   end Put_O;

   procedure Put_U16 (Value : Natural) is
      Stored : Natural := Value;
   begin
      if Stored > 65535 then
         Stored := 65535;
      end if;
      Put_O (Stored mod 256);
      Put_O (Stored / 256);
   end Put_U16;

   procedure Put_I32 (Value : Integer) is
      Bits : Interfaces.Unsigned_32;
      use type Interfaces.Unsigned_32;
   begin
      if Value >= 0 then
         Bits := Interfaces.Unsigned_32 (Value);
      else
         Bits := 0 - Interfaces.Unsigned_32 (-Value);
      end if;
      for Drop in 1 .. 4 loop
         Put_O (Natural (Bits and 16#FF#));
         Bits := Bits / 256;
      end loop;
   end Put_I32;

   procedure Put_Fixed (Item : String; Width : Natural) is
      Last : Natural := Item'Length;
   begin
      if Last > Width then
         Last := Width;
      end if;
      Put_O (Last);
      for I in 1 .. Width loop
         if I <= Last then
            Put_O (Character'Pos (Item (Item'First + I - 1)));
         else
            Put_O (0);
         end if;
      end loop;
   end Put_Fixed;

   procedure Write_Office is
      Next : Agents.Operative;
   begin
      Office_Used := 0;
      Put_O (1);
      Put_I32 (Snap.Funds);
      Put_U16 (Snap.Company (1).Research);
      Put_U16 (Snap.Grant);
      if Session.In_Debt (Snap) then
         Put_O (1);
      else
         Put_O (0);
      end if;
      Put_O (Snap.Roster_Count);
      if Session.Can_Hire (Snap) then
         Put_O (1);
      else
         Put_O (0);
      end if;
      Put_U16 (Session.Hire_Price);
      Put_U16 (Session.Upkeep (Snap));
      Put_U16 (Session.Income_Of (Globe));
      for Item in Research.Branch loop
         if Snap.Known (Item) then
            Put_O (1);
         else
            Put_O (0);
         end if;
         Put_U16 (Research.Cost (Item));
         Put_Fixed (Research.Token (Item), 8);
      end loop;
      for I in 1 .. Snap.Roster_Count loop
         if Snap.Roster (I).Alive then
            Put_O (1);
         else
            Put_O (0);
         end if;
         Put_O (Snap.Roster (I).Health);
         Put_O (Snap.Roster (I).Accuracy);
         Put_O (Snap.Roster (I).Speed);
         Put_O (Snap.Roster (I).Morale);
         Put_O (Snap.Roster (I).Augments);
         Put_O (Weapons.Kind'Pos (Snap.Roster (I).Gun));
         Put_O (Snap.Roster (I).Armour);
         Put_Fixed (Agents.Name_Of (Snap.Roster (I)), 12);
         Put_Fixed (Weapons.Token (Snap.Roster (I).Gun), 6);
      end loop;
      for I in Snap.Pick'Range loop
         Put_O (Snap.Pick (I));
      end loop;
      if Snap.Roster_Count < Agents.Max_Roster then
         Put_O (1);
         Next := Agents.Person
           (Snap.Seed, Snap.Roster_Count + 1);
         Put_Fixed (Agents.Name_Of (Next), 12);
         Put_O (Next.Health);
         Put_O (Next.Accuracy);
         Put_O (Next.Speed);
         Put_O (Next.Morale);
      else
         Put_O (0);
         Put_Fixed ("", 12);
         Put_O (0);
         Put_O (0);
         Put_O (0);
         Put_O (0);
      end if;
   end Write_Office;

   procedure Put_M (Value : Natural) is
   begin
      if Menu_Used >= Menu_Max then
         return;
      end if;
      Menu_Buf (Menu_Used) := Octet (Value mod 256);
      Menu_Used := Menu_Used + 1;
   end Put_M;

   procedure Put_M16 (Value : Natural) is
      Stored : Natural := Value;
   begin
      if Stored > 65535 then
         Stored := 65535;
      end if;
      Put_M (Stored mod 256);
      Put_M (Stored / 256);
   end Put_M16;

   procedure Put_M32 (Value : Integer) is
      Bits : Interfaces.Unsigned_32;
      use type Interfaces.Unsigned_32;
   begin
      if Value >= 0 then
         Bits := Interfaces.Unsigned_32 (Value);
      else
         Bits := 0 - Interfaces.Unsigned_32 (-Value);
      end if;
      for Drop in 1 .. 4 loop
         Put_M (Natural (Bits and 16#FF#));
         Bits := Bits / 256;
      end loop;
   end Put_M32;

   procedure Put_M_Text (Item : String; Width : Natural) is
      Last : Natural := Item'Length;
   begin
      if Last > Width then
         Last := Width;
      end if;
      Put_M (Last);
      for I in 1 .. Width loop
         if I <= Last then
            Put_M (Character'Pos (Item (Item'First + I - 1)));
         else
            Put_M (0);
         end if;
      end loop;
   end Put_M_Text;

   function Roster_Alive return Natural is
      Total : Natural := 0;
   begin
      for I in 1 .. Snap.Roster_Count loop
         if Snap.Roster (I).Alive then
            Total := Total + 1;
         end if;
      end loop;
      return Total;
   end Roster_Alive;

   procedure Write_Menu is
      Kind : Mission.Gen.Recipe_Kind;
      Reward : Natural := 0;
      Region_Name : String (1 .. 24) := (others => ' ');
      Name_Len : Natural := 0;
   begin
      Menu_Used := 0;
      Put_M (1);
      Put_M (Menu.Screen'Pos (Card.Where));
      Put_M (Card.Cursor);
      if Card.Saved then
         Put_M (1);
      else
         Put_M (0);
      end if;
      Put_M (Card.Speed);
      Put_M (Card.Volume);
      Put_M (Card.Effects);
      Put_M (Card.Music);
      if World_Ready and then Snap.Play = Parameters.Scenario then
         Put_M (0);
      elsif World_Ready and then Snap.Play = Parameters.Free_Play then
         Put_M (1);
      else
         Put_M (2);
      end if;
      if World_Ready and then Snap.Locked then
         Put_M (1);
      else
         Put_M (0);
      end if;
      Put_M16 (Card.Region);
      Put_M32 (Card.Typed);
      Put_M (Card.Scenario);
      Put_M (Card.Outcome);
      Put_M (Card.Dead);
      Put_M32 (Card.Loot);
      Put_M32 (Card.Before);
      Put_M32 (Card.After);
      if World_Ready
        and then Card.Region >= 1
        and then Card.Region <= Globe.Regions
      then
         Kind := Mission.Gen.Preview (Globe.Area (Card.Region).City);
         Reward := Session.Loot_Base + World.Campaign.Income
           (Globe.Area (Card.Region).Population,
            Globe.Area (Card.Region).Tax);
         Name_Len := Globe.Area (Card.Region).Title.Length;
         if Name_Len > 24 then
            Name_Len := 24;
         end if;
         if Name_Len > 0 then
            Region_Name (1 .. Name_Len) :=
              Globe.Area (Card.Region).Title.Text (1 .. Name_Len);
         end if;
         Put_M16 (Reward);
         Put_M_Text (Mission.Gen.Objective (Kind), 64);
         Put_M_Text (Mission.Gen.Estimate (Kind), 32);
         Put_M_Text (Region_Name (1 .. Name_Len), 24);
      else
         Put_M16 (0);
         Put_M_Text ("", 64);
         Put_M_Text ("", 32);
         Put_M_Text ("", 24);
      end if;
      Put_M (Menu.Scenario_Count);
      for I in 1 .. Menu.Scenario_Count loop
         Put_M32 (Menu.Scenario_Seed (I));
         Put_M_Text (Menu.Scenario_Name (I), 16);
      end loop;
      Put_M (3);
      Put_M_Text ("Source code is MIT.", 72);
      Put_M_Text
        ("AdaWebPack libgnat is GPL-3.0 with the GCC Runtime", 72);
      Put_M_Text
        ("Library Exception 3.1, so this project stays MIT.", 72);
      Put_M (Card.Trouble);
   end Write_Menu;

   procedure Put_S (Value : Natural) is
   begin
      if Sound_Used >= Sound_Max then
         return;
      end if;
      Sound_Buf (Sound_Used) := Octet (Value mod 256);
      Sound_Used := Sound_Used + 1;
   end Put_S;

   procedure Put_S16 (Value : Natural) is
   begin
      Put_S (Value mod 256);
      Put_S (Value / 256);
   end Put_S16;

   procedure Push_Extra (Code : Natural) is
   begin
      if Extra_N < Extra_Max then
         Extra_N := Extra_N + 1;
         Extra (Extra_N) := Code;
      end if;
   end Push_Extra;

   function Ambient_Code return Natural is
   begin
      if Card.Where = Menu.Field
        or else (Card.Where = Menu.Paused
                 and then Card.Under = Menu.Field)
      then
         return Sound.Scene'Pos (Sound.City);
      elsif Card.Where = Menu.Atlas
        or else Card.Where = Menu.Briefing
        or else Card.Where = Menu.Debrief
        or else Card.Where = Menu.Paused
      then
         return Sound.Scene'Pos (Sound.Map);
      end if;
      return Sound.Scene'Pos (Sound.Title);
   end Ambient_Code;

   procedure Write_Sound is
      Total : Natural := 0;
      Voice : Sound.Voice;
      Phrase : Sound.Bar;
   begin
      if Sound_Seq < 255 then
         Sound_Seq := Sound_Seq + 1;
      else
         Sound_Seq := 1;
      end if;
      Sound_Used := 0;
      Put_S (1);
      Put_S (Sound_Seq);
      Put_S (Ambient_Code);
      Put_S (Card.Volume);
      Put_S (Card.Effects);
      Put_S (Card.Music);
      Total := Play.Sound_Count + Extra_N;
      if Total > Sound.Max_Events then
         Total := Sound.Max_Events;
      end if;
      Put_S (Total);
      for I in 1 .. Play.Sound_Count loop
         if I <= Total then
            Put_S (Play.Sound_Code (I));
         end if;
      end loop;
      for I in 1 .. Extra_N loop
         if Play.Sound_Count + I <= Total then
            Put_S (Extra (I));
         end if;
      end loop;
      for Kind in Sound.Click .. Sound.Blip loop
         Voice := Sound.Tone (Kind);
         Put_S (Sound.Wave'Pos (Voice.Shape));
         Put_S16 (Voice.Freq);
         Put_S16 (Voice.Ms);
         Put_S (Voice.Attack);
         Put_S (Voice.Gain);
      end loop;
      for Place in Sound.Scene loop
         Phrase := Sound.Loop_Of (Place);
         for I in Phrase'Range loop
            Put_S16 (Phrase (I).Freq);
            Put_S16 (Phrase (I).Ms);
         end loop;
      end loop;
      Extra_N := 0;
      Play.Clear_Sounds;
   end Write_Sound;

   procedure Put_Name (Item : String) is
      Last : Natural;
   begin
      Last := Item'Length;
      if Last > 16 then
         Last := 16;
      end if;
      Put_B (Last);
      for I in 1 .. 16 loop
         if I <= Last then
            Put_B (Character'Pos (Item (Item'First + I - 1)));
         else
            Put_B (0);
         end if;
      end loop;
   end Put_Name;

   function Recipe_Name (Seed : RNG.Word) return String is
      Kind : constant Natural :=
        Mission.Gen.Recipe_Kind'Pos (Mission.Gen.Preview (Seed));
   begin
      case Kind is
         when 0 =>
            return "Briefing";
         when 1 =>
            return "Snatch";
         when others =>
            return "Contract";
      end case;
   end Recipe_Name;

   procedure Refresh is
      Lines : constant Natural := Save.Log.Headline_Count (Book);
      Line : String (1 .. 79);
      Count : Natural;
   begin
      Brief_Used := 0;
      Put_B (1);
      Put_B (Globe.Regions);
      Put_B (Globe.Corps);
      Put_B (Lines);
      for I in 1 .. Globe.Regions loop
         if Snap.Area (I).Visited then
            Put_B (1);
         else
            Put_B (0);
         end if;
         Put_B (World.Campaign.Income
           (Globe.Area (I).Population, Globe.Area (I).Tax) mod 256);
         Put_B (World.Campaign.Income
           (Globe.Area (I).Population, Globe.Area (I).Tax) / 256);
         Put_B (World.Campaign.Influence
           (Globe.Area (I).Defence, Globe.Area (I).Tech));
         Put_I16 (World.Campaign.Threat (Globe, I));
         Put_B (Mission.Gen.Recipe_Kind'Pos
           (Mission.Gen.Preview (Globe.Area (I).City)));
         Put_Name (Recipe_Name (Globe.Area (I).City));
      end loop;
      for C in 1 .. Globe.Corps loop
         Put_B (World.Campaign.Holdings (Globe, C));
         Put_B (World.Campaign.Strength (Globe, C) mod 256);
         Put_B (World.Campaign.Strength (Globe, C) / 256);
         Put_B (0);
      end loop;
      for N in 1 .. Lines loop
         declare
            Text : constant String := Save.Log.Headline (Book, N);
         begin
            Count := Text'Length;
            if Count > 79 then
               Count := 79;
            end if;
            Line (1 .. Count) := Text (Text'First .. Text'First + Count - 1);
            Put_B (Count);
            for I in 1 .. 79 loop
               if I <= Count then
                  Put_B (Character'Pos (Line (I)));
               else
                  Put_B (0);
               end if;
            end loop;
         end;
      end loop;
      Write_Office;
   end Refresh;
   procedure Open_City;
   function Base_Name (Name : String) return String;

   procedure Open_City is
      Home : constant Positive := Globe.Company (1).Home;
      Kept : Boolean;
   begin
      Play.Open (Globe.Area (Home).City);
      if Host_Files.Exists (Files, "city.mgc") then
         Kept := Play.Read (Files, "city.mgc");
         if not Kept then
            Play.Open (Globe.Area (Home).City);
         end if;
      end if;
   end Open_City;

   procedure Note (Ev : Save.Log.Event) is
      Result : Save.Mission_Outcome;
   begin
      Save.Log.Commit
        (Files, "slot.log", Snap, Globe, Book, Ev);
      if Play.Needs_Settle then
         declare
            Funds_Before : constant Integer := Snap.Funds;
            Alive_Before : constant Natural := Roster_Alive;
         begin
         Play.Settle (Globe, Snap);
         if Play.Mission_Ending = 2 then
            Result := Save.Mission_Outcome'First;
         elsif Play.Mission_Ending = 4 then
            Result := Save.Mission_Outcome'Last;
         else
            Result := Save.Mission_Outcome'Succ
              (Save.Mission_Outcome'First);
         end if;
         Save.Log.Commit
           (Files, "slot.log", Snap, Globe, Book,
            Save.Log.Mission_Done
              (Positive (Play.Mission_Region), Result, Play.Clock));
         Save.Log.Commit
           (Files, "slot.log", Snap, Globe, Book,
            Save.Log.Region_Set
              (Snap, Globe, Positive (Play.Mission_Region)));
         Save.Log.Commit
           (Files, "slot.log", Snap, Globe, Book,
            Save.Log.Payoff
              (Positive (Play.Mission_Region), Result));
         API.Install (Globe, Snap.Day);
         Menu.Note_Result
           (Card, Play.Mission_Ending,
            Alive_Before - Roster_Alive,
            Funds_Before, Snap.Funds);
         end;
      end if;
      Refresh;
      Write_Menu;
      if Save.Log.Due (Book) then
         if Play.Ready then
            Play.Write (Files, "city.mgc");
         end if;
         Save.Log.Compact
           (Files, "slot.mgc", "slot.log", Snap, Book);
      end if;
   end Note;

   procedure Fresh
     (Seed : Interfaces.Unsigned_32;
      Mode : Parameters.Play_Mode)
   is
   begin
      Globe := World.Gen.Generate
        (RNG.Word (Seed), Parameters.Defaults);
      Snap := Save.Capture (Globe, 0, Mode);
      Save.Store (Files, "slot.mgc", Snap);
      Book := Save.Log.Start (Files, "slot.log", Snap);
      Play.Open (Globe.Area (Globe.Company (1).Home).City);
      Play.Write (Files, "city.mgc");
      API.Install (Globe, Snap.Day);
      World_Ready := True;
      Card.Saved := True;
      Refresh;
      Write_Menu;
   end Fresh;

   procedure Save_Game is
   begin
      if not World_Ready then
         return;
      end if;
      if Play.Ready then
         Play.Write (Files, "city.mgc");
      end if;
      Save.Log.Compact
        (Files, "slot.mgc", "slot.log", Snap, Book);
      Store_Prefs;
      Card.Saved := True;
   end Save_Game;

   procedure Load_Game is
      Text : constant String := Host_Files.Read (Files, "slot.mgc");
   begin
      if not Save.Looks_Saved (Text) then
         Menu.Note_Trouble (Card, 1);
         Card.Where := Menu.Title;
         World_Ready := False;
         return;
      end if;
      Snap := Save.Load (Files, "slot.mgc");
      Globe := Save.Rebuild (Snap, Parameters.Defaults);
      Open_City;
      if Host_Files.Exists (Files, "slot.log") then
         Book := Save.Log.Load (Files, "slot.log");
         Save.Log.Replay (Snap, Globe, Book);
      else
         Book := Save.Log.Start (Files, "slot.log", Snap);
      end if;
      API.Install (Globe, Snap.Day);
      World_Ready := True;
      Card.Saved := True;
      Menu.Arrive (Card, Menu.Atlas);
      Refresh;
      Write_Menu;
   end Load_Game;

   procedure Launch_Mission is
      Region : Positive;
      Seed : RNG.Word;
      Lo : Integer;
      Hi : Integer;
   begin
      if not World_Ready
        or else Card.Region < 1
        or else Card.Region > Globe.Regions
      then
         return;
      end if;
      Region := Card.Region;
      Seed := Globe.Area (Region).City;
      Lo := Integer (Seed and 16#7FFF_FFFF#);
      Hi := Integer ((Seed / 2 ** 31) and 16#7FFF_FFFF#);
      Note (Save.Log.Order (6, Region, Lo, Hi, 0, 0));
      Menu.Arrive (Card, Menu.Field);
   end Launch_Mission;

   procedure Try_Reroll is
   begin
      if not World_Ready
        or else Card.Region < 1
        or else Card.Region > Globe.Regions
      then
         return;
      end if;
      if Parameters.Region_May_Reroll
        (Snap.Play, Snap.Area (Card.Region).Visited)
      then
         Note (Save.Log.Reroll (Snap, Globe, Card.Region));
      end if;
   end Try_Reroll;

   procedure Load_Prefs is
      function Number_After (Text, Key : String) return Integer;
      function Number_After (Text, Key : String) return Integer is
         Mark : Natural := Text'First;
         Start : Natural;
         Value : Natural := 0;
         Found : Boolean := False;
      begin
         while Mark + Key'Length - 1 <= Text'Last loop
            if Text (Mark .. Mark + Key'Length - 1) = Key then
               Start := Mark + Key'Length;
               while Start <= Text'Last
                 and then Text (Start) = ' '
               loop
                  Start := Start + 1;
               end loop;
               while Start <= Text'Last
                 and then Text (Start) in '0' .. '9'
               loop
                  Value := Value * 10
                    + (Character'Pos (Text (Start))
                       - Character'Pos ('0'));
                  Found := True;
                  Start := Start + 1;
               end loop;
               if Found then
                  return Integer (Value);
               end if;
            end if;
            Mark := Mark + 1;
         end loop;
         return -1;
      end Number_After;
      Text : constant String :=
        (if Host_Files.Exists (Files, "prefs.txt")
         then Host_Files.Read (Files, "prefs.txt")
         else "");
      Speed : constant Integer := Number_After (Text, "speed");
      Volume : constant Integer := Number_After (Text, "volume");
      Effects : constant Integer := Number_After (Text, "effects");
      Music : constant Integer := Number_After (Text, "music");
   begin
      if Speed = 0 or else Speed = 1 or else Speed = 2
        or else Speed = 4
      then
         Card.Speed := Speed;
      end if;
      if Volume >= 0 and then Volume <= 100 then
         Card.Volume := Volume;
      end if;
      if Effects >= 0 and then Effects <= 100 then
         Card.Effects := Effects;
      end if;
      if Music >= 0 and then Music <= 100 then
         Card.Music := Music;
      end if;
   end Load_Prefs;

   procedure Store_Prefs is
      function Trim (Value : Natural) return String;
      function Trim (Value : Natural) return String is
         Image : constant String := Natural'Image (Value);
      begin
         return Image (Image'First + 1 .. Image'Last);
      end Trim;
      Text : constant String :=
        "speed " & Trim (Card.Speed) & ASCII.LF
        & "volume " & Trim (Card.Volume) & ASCII.LF
        & "effects " & Trim (Card.Effects) & ASCII.LF
        & "music " & Trim (Card.Music) & ASCII.LF;
   begin
      Host_Files.Write (Files, "prefs.txt", Text);
   end Store_Prefs;

   procedure Apply_Menu (Act : Menu.Action; Arg : Integer) is
      Effect : constant Menu.Effect := Menu.Handle (Card, Act, Arg);
   begin
      case Effect is
         when Menu.Stay =>
            null;
         when Menu.Make_Scenario =>
            Fresh
              (Interfaces.Unsigned_32
                 (Menu.Scenario_Seed (Card.Scenario)),
               Parameters.Scenario);
            Menu.Arrive (Card, Menu.Atlas);
         when Menu.Make_Free =>
            Fresh
              (Interfaces.Unsigned_32 (Menu.Free_Seed (Card)),
               Parameters.Free_Play);
            Menu.Arrive (Card, Menu.Atlas);
         when Menu.Load_Continue =>
            begin
               Load_Game;
            exception
               when others =>
                  Menu.Note_Trouble (Card, 1);
                  Card.Where := Menu.Title;
                  World_Ready := False;
            end;
         when Menu.Launch =>
            Launch_Mission;
         when Menu.Write_Disk =>
            Save_Game;
         when Menu.Leave_Game =>
            Save_Game;
            Menu.Arrive (Card, Menu.Title);
         when Menu.Reroll =>
            Try_Reroll;
      end case;
      if Act = Menu.Set_Speed or else Act = Menu.Set_Volume
        or else Act = Menu.Set_Effects or else Act = Menu.Set_Music
      then
         Store_Prefs;
      end if;
      if Act /= Menu.Up and then Act /= Menu.Down
        and then Act /= Menu.Set_Speed
        and then Act /= Menu.Set_Volume
        and then Act /= Menu.Set_Effects
        and then Act /= Menu.Set_Music
        and then Act /= Menu.Type_Digit
      then
         Push_Extra (Sound.Kind'Pos (Sound.Click));
      end if;
      Write_Menu;
      Write_Sound;
   end Apply_Menu;

   procedure Boot (Seed : Interfaces.Unsigned_32) is
      pragma Unreferenced (Seed);
   begin
      Load_Prefs;
      Card.Saved := Host_Files.Exists (Files, "slot.mgc");
      Card.Where := Menu.Title;
      Card.Cursor := 0;
      World_Ready := False;
      Write_Menu;
      Write_Sound;
   end Boot;

   procedure Advance (Days : Interfaces.Unsigned_32) is
      type Owner_List is array (1 .. Parameters.Max_Regions) of Positive;
      Old : Owner_List := (others => 1);
   begin
      if not World_Ready or else Card.Where /= Menu.Atlas then
         return;
      end if;
      for Drop in 1 .. Natural (Days) loop
         for I in 1 .. Globe.Regions loop
            Old (I) := Globe.Area (I).Owner;
         end loop;
         Note (Save.Log.Day_None);
         for I in 1 .. Globe.Regions loop
            if Globe.Area (I).Owner /= Old (I) then
               Note (Save.Log.Region_Set (Snap, Globe, I));
               Push_Extra (Sound.Kind'Pos (Sound.Blip));
            end if;
         end loop;
      end loop;
      API.Install (Globe, Snap.Day);
      Write_Sound;
   end Advance;

   procedure Reset (Seed : Interfaces.Unsigned_32) is
   begin
      Fresh (Seed, Parameters.Auto_Play);
      Menu.Arrive (Card, Menu.Atlas);
      Write_Menu;
      Write_Sound;
   end Reset;

   function Import_Buffer return System.Address is
   begin
      return Import_Buf'Address;
   end Import_Buffer;

   function Import_Capacity return Interfaces.Unsigned_32 is
   begin
      return Interfaces.Unsigned_32 (Cap);
   end Import_Capacity;

   function Base_Name (Name : String) return String is
      Last : Natural := Name'Last;
   begin
      while Last >= Name'First and then Name (Last) /= '/' loop
         Last := Last - 1;
      end loop;
      return Name (Last + 1 .. Name'Last);
   end Base_Name;

   function Commit_Asset
     (Name : System.Address;
      Name_Len : Interfaces.Unsigned_32;
      Data_Len : Interfaces.Unsigned_32) return Interfaces.Unsigned_32
   is
      Length : constant Natural := Natural (Name_Len);
      Bytes : constant Natural := Natural (Data_Len);
      Title : String (1 .. Length);
      for Title'Address use Name;
      Data : String (1 .. Bytes);
   begin
      if Length = 0 or else Bytes = 0 or else Bytes > Cap then
         return 0;
      end if;
      for I in 1 .. Bytes loop
         Data (I) := Character'Val (Octet'Pos (Import_Buf (I)));
      end loop;
      declare
         Leaf : constant String := Base_Name (Title);
         Path : constant String := "assets/" & Leaf;
      begin
         if not Assets.Import.Accepts (Leaf, Data) then
            return 0;
         end if;
         if not Megacorp.Data.Virtual_FS.Is_Logical_Path (Path) then
            return 0;
         end if;
         Host_Files.Write (Files, Path, Data);
         return 1;
      end;
   end Commit_Asset;

   procedure Command (Code, A, B, C, D, E : Integer) is
      Region : Positive;
      Seed : RNG.Word;
      Lo : Integer;
      Hi : Integer;
   begin
      if Code = 12 then
         if A >= 0
           and then A <= Menu.Action'Pos (Menu.Action'Last)
         then
            Apply_Menu (Menu.Action'Val (A), B);
         end if;
         return;
      end if;
      if not World_Ready then
         return;
      end if;
      if Code = 6 then
         if Card.Where = Menu.Briefing then
            Launch_Mission;
            Write_Menu;
         end if;
         return;
      end if;
      if Code = 7 then
         if Session.Can_Hire (Snap) then
            Note (Save.Log.Hire_Agent (Snap));
         end if;
         return;
      elsif Code = 8 then
         if A = 0 or else A = Session.Grant_Low
           or else A = Session.Grant_High
         then
            Note (Save.Log.Set_Grant (Natural (A)));
         end if;
         return;
      elsif Code = 9 then
         if A >= 1 and then B >= 1 and then B <= 4
           and then Session.Can_Fit
             (Snap, Positive (A), Positive (B))
         then
            Note (Save.Log.Fit_Gear (Positive (A), Positive (B)));
         end if;
         return;
      elsif Code = 10 then
         if A >= 1 and then A <= Agents.Squad_Slots and then B >= 0
           and then Session.Can_Assign
             (Snap, Positive (A), Natural (B))
         then
            Note (Save.Log.Pick_Squad (Positive (A), Natural (B)));
         end if;
         return;
      end if;
      if Code = 6
        and then A >= 1
        and then A <= Globe.Regions
      then
         Region := Positive (A);
         Seed := Globe.Area (Region).City;
         Lo := Integer (Seed and 16#7FFF_FFFF#);
         Hi := Integer
           ((Seed / 2 ** 31) and 16#7FFF_FFFF#);
         Note (Save.Log.Order (6, Region, Lo, Hi, 0, 0));
      else
         Note (Save.Log.Order (Code, A, B, C, D, E));
      end if;
   end Command;

   procedure Play_Ticks (Count : Interfaces.Unsigned_32) is
      use type Interfaces.Unsigned_32;
   begin
      if not World_Ready or else Card.Where /= Menu.Field then
         return;
      end if;
      if Count < 1 or else Count > 32 then
         return;
      end if;
      Note (Save.Log.Ticks (Positive (Count)));
      Write_Sound;
   end Play_Ticks;

   function City_State return System.Address is
   begin
      return Play.City_State;
   end City_State;

   function City_State_Size return Interfaces.Unsigned_32 is
   begin
      return Play.City_State_Size;
   end City_State_Size;

   function Brief return System.Address is
   begin
      return Brief_Buf'Address;
   end Brief;

   function Brief_Size return Interfaces.Unsigned_32 is
   begin
      return Interfaces.Unsigned_32 (Brief_Used);
   end Brief_Size;

   function Office return System.Address is
   begin
      return Office_Buf'Address;
   end Office;

   function Office_Size return Interfaces.Unsigned_32 is
   begin
      return Interfaces.Unsigned_32 (Office_Used);
   end Office_Size;

   function Menu_State return System.Address is
   begin
      return Menu_Buf'Address;
   end Menu_State;

   function Menu_State_Size return Interfaces.Unsigned_32 is
   begin
      return Interfaces.Unsigned_32 (Menu_Used);
   end Menu_State_Size;

   function Sound_State return System.Address is
   begin
      return Sound_Buf'Address;
   end Sound_State;

   function Sound_State_Size return Interfaces.Unsigned_32 is
   begin
      return Interfaces.Unsigned_32 (Sound_Used);
   end Sound_State_Size;
end Megacorp.Wasm_Store;
