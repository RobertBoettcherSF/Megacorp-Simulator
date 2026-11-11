--  SPDX-License-Identifier: MIT
--  Copyright (c) 2026 Robert Boettcher

with Megacorp.Agents;
with Megacorp.API;
with Megacorp.Assets.Import;
with Megacorp.Data.Virtual_FS;
with Megacorp.Data.Virtual_FS.Browser;
with Megacorp.Mission.Gen;
with Megacorp.Parameters;
with Megacorp.Play;
with Megacorp.Research;
with Megacorp.RNG;
with Megacorp.Save;
with Megacorp.Save.Log;
with Megacorp.Session;
with Megacorp.Weapons;
with Megacorp.World.Campaign;
with Megacorp.World.Gen;

package body Megacorp.Wasm_Store is
   use type RNG.Word;

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

   procedure Fresh (Seed : Interfaces.Unsigned_32);
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
      end if;
      Refresh;
      if Save.Log.Due (Book) then
         if Play.Ready then
            Play.Write (Files, "city.mgc");
         end if;
         Save.Log.Compact
           (Files, "slot.mgc", "slot.log", Snap, Book);
      end if;
   end Note;

   procedure Fresh (Seed : Interfaces.Unsigned_32) is
   begin
      Globe := World.Gen.Generate
        (RNG.Word (Seed), Parameters.Defaults);
      Snap := Save.Capture
        (Globe, 0, Parameters.Auto_Play);
      Save.Store (Files, "slot.mgc", Snap);
      Book := Save.Log.Start (Files, "slot.log", Snap);
      Play.Open (Globe.Area (Globe.Company (1).Home).City);
      Play.Write (Files, "city.mgc");
      API.Install (Globe, Snap.Day);
      Refresh;
   end Fresh;

   procedure Boot (Seed : Interfaces.Unsigned_32) is
   begin
      if Host_Files.Exists (Files, "slot.mgc") then
         begin
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
      Refresh;
         exception
            when others =>
               Fresh (Seed);
         end;
      else
         Fresh (Seed);
      end if;
   end Boot;

   procedure Advance (Days : Interfaces.Unsigned_32) is
      type Owner_List is array (1 .. Parameters.Max_Regions) of Positive;
      Old : Owner_List := (others => 1);
   begin
      for Drop in 1 .. Natural (Days) loop
         for I in 1 .. Globe.Regions loop
            Old (I) := Globe.Area (I).Owner;
         end loop;
         Note (Save.Log.Day_None);
         for I in 1 .. Globe.Regions loop
            if Globe.Area (I).Owner /= Old (I) then
               Note (Save.Log.Region_Set (Snap, Globe, I));
            end if;
         end loop;
      end loop;
      API.Install (Globe, Snap.Day);
   end Advance;

   procedure Reset (Seed : Interfaces.Unsigned_32) is
   begin
      Fresh (Seed);
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
      if Count < 1 or else Count > 32 then
         return;
      end if;
      Note (Save.Log.Ticks (Positive (Count)));
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
end Megacorp.Wasm_Store;
