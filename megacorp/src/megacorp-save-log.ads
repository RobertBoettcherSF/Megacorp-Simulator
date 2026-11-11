--  SPDX-License-Identifier: MIT
--  Copyright (c) 2026 Robert Boettcher

with Megacorp.Data.Virtual_FS;
with Megacorp.Map;
with Megacorp.RNG;
with Megacorp.World;

--  Item 18. An append-only log of what changed since a snapshot.
--  Loading is the snapshot plus a replay of this log. A torn
--  final record is dropped. See DESIGN.md.
package Megacorp.Save.Log is
   Format_Version : constant := 1;

   --  Fold the log into a new snapshot at this many records,
   --  or sooner when the caller asks.
   Compact_After : constant := 32;
   Max_Events    : constant := 64;

   type Journal is private;
   type Event is private;

   function Count (Book : Journal) return Natural;
   function Due (Book : Journal) return Boolean;
   function Notice (Book : Journal) return String;

   function Day_None return Event;

   function Day_Tax
     (Region : Positive;
      Rate : Natural) return Event
     with Pre => Rate <= 100;

   function Region_Set
     (Snap : Snapshot;
      Item : World.Atlas;
      Region : Positive) return Event
     with Pre =>
       Region <= Snap.Regions and then Region <= Item.Regions;

   function Mission_Done
     (Region : Positive;
      Outcome : Mission_Outcome;
      Tick : Natural) return Event;

   function Tile_Change
     (Region, X, Y : Positive;
      Cell : Map.Tile) return Event;

   function Squad_Change
     (Slot : Positive;
      Health, Ammo : Natural;
      Region : Positive) return Event
     with Pre => Slot <= Squad_Size;

   --  A new city seed for an unvisited region. Scenario play
   --  raises "scenario refuses re-roll". A visited region raises
   --  "visited region stays".
   function Reroll
     (Snap : Snapshot;
      Item : World.Atlas;
      Region : Positive) return Event
     with Pre =>
       Region <= Snap.Regions and then Region <= Item.Regions
       and then Snap.Seed = Item.Seed;

   --  A city command. Code, then five integers. See Play.Handle.
   function Order
     (Code, A, B, C, D, E : Integer) return Event;

   --  Count city ticks. The page batches a frame into one record.
   function Ticks (Count : Positive) return Event
     with Pre => Count <= 32;

   function Start
     (Disk : in out Data.Virtual_FS.Backend'Class;
      Path : String;
      Snap : Snapshot) return Journal
     with Pre =>
       Data.Virtual_FS.Is_Logical_Path (Path)
       and then Path'Length > 0;

   function Load
     (Disk : Data.Virtual_FS.Backend'Class;
      Path : String) return Journal
     with Pre => Data.Virtual_FS.Exists (Disk, Path);

   --  Write the records Load kept. Drops a torn tail from the file
   --  so the next append is not glued to it.
   procedure Rewrite
     (Disk : in out Data.Virtual_FS.Backend'Class;
      Path : String;
      Snap : Snapshot;
      Book : in out Journal)
     with Pre =>
       Data.Virtual_FS.Is_Logical_Path (Path)
       and then Path'Length > 0;

   procedure Commit
     (Disk : in out Data.Virtual_FS.Backend'Class;
      Path : String;
      Snap : in out Snapshot;
      Item : in out World.Atlas;
      Book : in out Journal;
      Ev : Event)
     with Pre =>
       Count (Book) < Max_Events
       and then Data.Virtual_FS.Is_Logical_Path (Path)
       and then Snap.Seed = Item.Seed;

   procedure Replay
     (Snap : in out Snapshot;
      Item : in out World.Atlas;
      Book : in out Journal)
     with Pre =>
       Snap.Seed = Item.Seed
       and then Snap.Regions = Item.Regions
       and then Snap.Corps = Item.Corps;

   procedure Compact
     (Disk : in out Data.Virtual_FS.Backend'Class;
      Snap_Path, Log_Path : String;
      Snap : Snapshot;
      Book : in out Journal)
     with Pre =>
       Data.Virtual_FS.Is_Logical_Path (Snap_Path)
       and then Data.Virtual_FS.Is_Logical_Path (Log_Path);

private
   type Input_Kind is (No_Input, Tax_Input);

   type Event_Kind is
     (Kind_Day,
      Kind_Region,
      Kind_Mission,
      Kind_Tile,
      Kind_Squad,
      Kind_Reroll,
      Kind_Order,
      Kind_Ticks);

   type Event is record
      Kind    : Event_Kind := Kind_Day;
      Input   : Input_Kind := No_Input;
      Region  : Positive := 1;
      Owner   : Positive := 1;
      Tax     : Natural := 0;
      Unrest  : Natural := 0;
      Defence : Natural := 0;
      Tech    : Natural := 0;
      Visited : Boolean := False;
      Outcome : Mission_Outcome := Won;
      Tick    : Natural := 0;
      X       : Positive := 1;
      Y       : Positive := 1;
      Terrain : Map.Terrain := Map.Open_Ground;
      Level   : Map.Height_Level := 0;
      Walk    : Boolean := False;
      Drive   : Boolean := False;
      Slot    : Positive := 1;
      Health  : Natural := 100;
      Ammo    : Natural := 12;
      City    : RNG.Word := 0;
      Code    : Integer := 0;
      A       : Integer := 0;
      B       : Integer := 0;
      C       : Integer := 0;
      D       : Integer := 0;
      E       : Integer := 0;
   end record;

   type Event_List is array (1 .. Max_Events) of Event;

   type Journal is record
      Count   : Natural := 0;
      Base    : RNG.Word := 0;
      Dropped : Natural := 0;
      Ignored : Boolean := False;
      Item    : Event_List;
   end record;
end Megacorp.Save.Log;
