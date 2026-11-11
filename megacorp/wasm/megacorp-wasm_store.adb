--  SPDX-License-Identifier: MIT
--  Copyright (c) 2026 Robert Boettcher

with Megacorp.API;
with Megacorp.Assets.Import;
with Megacorp.Data.Virtual_FS;
with Megacorp.Data.Virtual_FS.Browser;
with Megacorp.Parameters;
with Megacorp.RNG;
with Megacorp.Save;
with Megacorp.Save.Log;
with Megacorp.World.Gen;

package body Megacorp.Wasm_Store is
   package Host_Files renames Megacorp.Data.Virtual_FS.Browser;

   Files : Host_Files.Disk := Host_Files.Open;
   Snap  : Save.Snapshot;
   Globe : World.Atlas;
   Book  : Save.Log.Journal;

   Cap : constant := 65536;
   type Octet is new Interfaces.Unsigned_8;
   Import_Buf : array (1 .. Cap) of Octet := (others => 0);

   procedure Fresh (Seed : Interfaces.Unsigned_32);
   function Base_Name (Name : String) return String;

   procedure Fresh (Seed : Interfaces.Unsigned_32) is
   begin
      Globe := World.Gen.Generate
        (RNG.Word (Seed), Parameters.Defaults);
      Snap := Save.Capture
        (Globe, 0, Parameters.Auto_Play);
      Save.Store (Files, "slot.mgc", Snap);
      Book := Save.Log.Start (Files, "slot.log", Snap);
      API.Install (Globe, Snap.Day);
   end Fresh;

   procedure Boot (Seed : Interfaces.Unsigned_32) is
   begin
      if Host_Files.Exists (Files, "slot.mgc") then
         begin
            Snap := Save.Load (Files, "slot.mgc");
            Globe := Save.Rebuild (Snap, Parameters.Defaults);
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
         Save.Log.Commit
           (Files, "slot.log", Snap, Globe, Book, Save.Log.Day_None);
         if Save.Log.Due (Book) then
            Save.Log.Compact
              (Files, "slot.mgc", "slot.log", Snap, Book);
         end if;
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
end Megacorp.Wasm_Store;
