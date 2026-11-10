--  SPDX-License-Identifier: MIT
--  Copyright (c) 2026 Robert Boettcher

with Megacorp.Data.Virtual_FS;
with Megacorp.Map;
with Megacorp.Parameters;
with Megacorp.RNG;
with Megacorp.World;
with Megacorp.World.Gen;
use type Megacorp.RNG.Word;

--  Item 17. The snapshot is the master seed plus the fields
--  play can change. Names, roads, and an untouched city are
--  rebuilt from the stamped generator algorithm.
--  Item 18 records the changes since this snapshot.
--  Item 19. Format version 2 adds research points. A v1 file
--  migrates forward. A newer file is refused.
package Megacorp.Save is
   Format_Version : constant := 2;

   Stamp_Max : constant := 24;

   --  A plain 40-region snapshot is about 1 KiB, including the
   --  missions line. One ruined tile adds one patch line.
   Budget : constant := 8192;

   Max_Patches : constant := 128;
   Squad_Size  : constant := 4;

   Save_Error : exception;

   --  A finished mission. A fight still in progress is not stored.
   type Mission_Outcome is (Won, Lost, Timed_Out);

   Max_Missions : constant := 64;

   type Region_State is record
      Owner    : Positive := 1;
      Tax      : Natural := 0;
      Unrest   : Natural := 0;
      Defence  : Natural := 0;
      Tech     : Natural := 0;
      Visited  : Boolean := False;
      Has_City : Boolean := False;
      City     : RNG.Word := 0;
   end record;

   type Mission_Mark is record
      Region  : Positive := 1;
      Outcome : Mission_Outcome := Won;
      Tick    : Natural := 0;
   end record;

   type Corp_State is record
      Cash       : Natural := 0;
      Earned     : Natural := 0;
      Spent      : Natural := 0;
      Eliminated : Boolean := False;
      Research   : Natural := 0;
   end record;

   type Patch is record
      Region : Positive := 1;
      X      : Positive := 1;
      Y      : Positive := 1;
      Kind   : Map.Terrain := Map.Open_Ground;
      Level  : Map.Height_Level := 0;
      Walk   : Boolean := False;
      Drive  : Boolean := False;
   end record;

   type Agent_State is record
      Health : Natural := 100;
      Ammo   : Natural := 12;
      Region : Positive := 1;
   end record;

   type Region_Table is
     array (1 .. Parameters.Max_Regions) of Region_State;
   type Corp_Table is
     array (1 .. Parameters.Max_Corporations) of Corp_State;
   type Patch_Table is array (1 .. Max_Patches) of Patch;
   type Squad_Table is array (1 .. Squad_Size) of Agent_State;
   type Mission_Table is array (1 .. Max_Missions) of Mission_Mark;

   type Snapshot is record
      Seed     : RNG.Word := 0;
      Day      : Natural := 0;
      Play     : Parameters.Play_Mode := Parameters.Auto_Play;
      Locked   : Boolean := False;
      Regions  : Positive := 1;
      Corps    : Positive := 1;
      Area     : Region_Table;
      Company  : Corp_Table;
      Patches  : Natural := 0;
      Patch    : Patch_Table;
      Squad    : Natural := Squad_Size;
      Agent    : Squad_Table;
      Missions  : Natural := 0;
      Mission   : Mission_Table;
      Algorithm : Positive := World.Gen.Current_Algorithm;
      Stamp_Len : Natural := 0;
      Stamp     : String (1 .. Stamp_Max) := (others => ' ');
   end record;

   function Capture
     (Item : World.Atlas;
      Day : Natural;
      Play : Parameters.Play_Mode;
      Algorithm : Positive := World.Gen.Current_Algorithm)
      return Snapshot
     with Pre => Algorithm <= World.Gen.Max_Algorithm;

   --  Copy the mutable world fields. Patches, the squad, and
   --  mission marks stay. A city seed that is not the generated
   --  one is kept; the generated seed is not stored.
   procedure Take
     (Snap : in out Snapshot;
      Item : World.Atlas;
      Day : Natural);

   procedure Restore
     (Snap : Snapshot;
      Item : in out World.Atlas)
     with Pre =>
       Snap.Seed = Item.Seed
       and then Snap.Regions = Item.Regions
       and then Snap.Corps = Item.Corps;

   procedure Damage
     (Snap : in out Snapshot;
      Region, X, Y : Positive;
      Cell : Map.Tile)
     with Pre =>
       Region <= Snap.Regions
       and then (Snap.Patches < Max_Patches
                 or else Already (Snap, Region, X, Y));

   function Already
     (Snap : Snapshot; Region, X, Y : Positive) return Boolean;

   procedure Apply_Patches
     (Snap : Snapshot;
      Region : Positive;
      City : in out Map.City)
     with Pre => Region <= Snap.Regions;

   procedure Store
     (Disk : in out Data.Virtual_FS.Backend'Class;
      Path : String;
      Snap : Snapshot)
     with Pre =>
       Data.Virtual_FS.Is_Logical_Path (Path)
       and then Path'Length > 0;

   function Load
     (Disk : Data.Virtual_FS.Backend'Class;
      Path : String) return Snapshot
     with Pre => Data.Virtual_FS.Exists (Disk, Path);

   function Image (Snap : Snapshot) return String;

   --  Checksum of the v1 bytes of this snapshot. A log written
   --  before migration still matches.
   function Legacy_Seal (Snap : Snapshot) return RNG.Word;

   function Digest (Text : String) return RNG.Word;

   --  Rebuild derived fields with the stamped algorithm, then
   --  copy the saved fields back.
   function Rebuild
     (Snap : Snapshot;
      Size : Parameters.Generator_Parameters) return World.Atlas
     with Pre =>
       Parameters.Region_Count (Size) = Snap.Regions
       and then Parameters.Corporation_Count (Size) = Snap.Corps,
       Post =>
         Rebuild'Result.Seed = Snap.Seed
         and then Rebuild'Result.Regions = Snap.Regions
         and then Rebuild'Result.Corps = Snap.Corps;

   function Same (Left, Right : Snapshot) return Boolean;

   function Bytes (Snap : Snapshot) return Natural;
end Megacorp.Save;
