--  SPDX-License-Identifier: MIT
--  Copyright (c) 2026 Robert Boettcher

with Megacorp.Agents;
with Megacorp.RNG;
with Megacorp.Save;
with Megacorp.World;
with Megacorp.World.Campaign;
use type Megacorp.RNG.Word;

--  Item 25. The player's books. Income is the item 24 formula
--  on regions owned by corporation 1. Upkeep, research funding,
--  and shopping come off that purse. The purse is an integer,
--  so a thin day can leave it negative. Campaign cash on the
--  atlas is a different number and is not touched.
package Megacorp.Session is
   Opening_Funds : constant Integer := 1500;
   Hire_Price    : constant := 400;
   Upkeep_Each   : constant := 30;
   Loot_Base     : constant := 250;
   Grant_Low     : constant := 40;
   Grant_High    : constant := 80;

   function In_Debt (Snap : Save.Snapshot) return Boolean;

   function Living (Snap : Save.Snapshot) return Natural;

   function Upkeep (Snap : Save.Snapshot) return Natural;

   function Income_Of (Item : World.Atlas) return Natural;

   function Can_Hire (Snap : Save.Snapshot) return Boolean
     with Post =>
       Can_Hire'Result =
         (Snap.Funds >= Hire_Price
          and then Snap.Roster_Count < Agents.Max_Roster);

   function Can_Fit
     (Snap : Save.Snapshot;
      Agent : Positive;
      Item : Positive) return Boolean;

   function Can_Assign
     (Snap : Save.Snapshot;
      Slot : Positive;
      Agent : Natural) return Boolean;

   procedure Close_Day
     (Snap : in out Save.Snapshot;
      Pay : Natural)
     with Pre =>
       Pay <= 100_000
       and then Snap.Grant <= Grant_High
       and then Snap.Company (1).Research
         <= Natural'Last - Snap.Grant,
       Post =>
         Snap.Funds =
           Snap'Old.Funds + Integer (Pay)
           - Integer (Upkeep (Snap'Old))
           - Integer (Snap'Old.Grant)
         and then Snap.Company (1).Research =
           Snap'Old.Company (1).Research + Snap'Old.Grant
         and then Snap.Roster_Count = Snap'Old.Roster_Count;

   procedure Play_Day
     (Snap : in out Save.Snapshot;
      Item : in out World.Atlas)
     with Pre =>
       Snap.Seed = Item.Seed
       and then Snap.Regions = Item.Regions
       and then Snap.Corps = Item.Corps
       and then Snap.Grant <= Grant_High,
       Post =>
         Snap.Day = Snap'Old.Day + 1
         and then World.Campaign.Coherent (Item);

   procedure Hire (Snap : in out Save.Snapshot)
     with Pre => Can_Hire (Snap),
          Post =>
            Snap.Roster_Count = Snap'Old.Roster_Count + 1
            and then Snap.Funds = Snap'Old.Funds - Hire_Price
            and then Snap.Roster (Snap.Roster_Count).Alive;

   procedure Set_Grant
     (Snap : in out Save.Snapshot;
      Amount : Natural)
     with Pre =>
       Amount = 0
       or else Amount = Grant_Low
       or else Amount = Grant_High,
       Post => Snap.Grant = Amount;

   procedure Fit
     (Snap : in out Save.Snapshot;
      Agent : Positive;
      Item : Positive)
     with Pre => Can_Fit (Snap, Agent, Item),
          Post =>
            Snap.Funds < Snap'Old.Funds
            and then Snap.Roster_Count = Snap'Old.Roster_Count;

   procedure Assign
     (Snap : in out Save.Snapshot;
      Slot : Positive;
      Agent : Natural)
     with Pre => Can_Assign (Snap, Slot, Agent),
          Post => Snap.Pick (Slot) = Agent;

   procedure Debrief
     (Snap : in out Save.Snapshot;
      Item : World.Atlas;
      Region : Positive;
      Outcome : Save.Mission_Outcome)
     with Pre =>
       Region <= Item.Regions and then Region <= Snap.Regions,
       Post => Snap.Roster_Count = Snap'Old.Roster_Count;

   function Ledger (Snap : Save.Snapshot) return String;
end Megacorp.Session;
