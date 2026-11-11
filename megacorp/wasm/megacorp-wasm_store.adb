--  SPDX-License-Identifier: MIT
--  Copyright (c) 2026 Robert Boettcher

with Megacorp.API;
with Megacorp.Assets.Import;
with Megacorp.Data.Virtual_FS;
with Megacorp.Data.Virtual_FS.Browser;
with Megacorp.Parameters;
with Megacorp.Play;
with Megacorp.RNG;
with Megacorp.Save;
with Megacorp.Save.Log;
with Megacorp.World.Gen;

package body Megacorp.Wasm_Store is
   use type RNG.Word;

   package Host_Files renames Megacorp.Data.Virtual_FS.Browser;

   Files : Host_Files.Disk := Host_Files.Open;
   Snap  : Save.Snapshot;
   Globe : World.Atlas;
   Book  : Save.Log.Journal;

   Cap : constant := 65536;
   type Octet is new Interfaces.Unsigned_8;
   Import_Buf : array (1 .. Cap) of Octet := (others => 0);

   procedure Fresh (Seed : Interfaces.Unsigned_32);
   procedure Note (Ev : Save.Log.Event);
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
         API.Install (Globe, Snap.Day);
      end if;
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
         exception
            when others =>
               Fresh (Seed);
         end;
      else
         Fresh (Seed);
      end if;
   end Boot;

   procedure Advance (Days : Interfaces.Unsigned_32) is
   begin
      for Drop in 1 .. Natural (Days) loop
         Note (Save.Log.Day_None);
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
end Megacorp.Wasm_Store;
