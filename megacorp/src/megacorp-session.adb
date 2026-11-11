--  SPDX-License-Identifier: MIT
--  Copyright (c) 2026 Robert Boettcher

with Ada.Strings.Unbounded;
with Megacorp.Research;
with Megacorp.Weapons;

package body Megacorp.Session is
   use type Weapons.Kind;

   function Add
     (Left : Ada.Strings.Unbounded.Unbounded_String;
      Right : String)
     return Ada.Strings.Unbounded.Unbounded_String
     renames Ada.Strings.Unbounded."&";

   function Trim (Value : Integer) return String;
   procedure Bump (Value : in out Natural; By : Integer);
   function Gear_Cost (Item : Positive) return Natural;
   function Victim (Snap : Save.Snapshot) return Natural;

   function Trim (Value : Integer) return String is
      Image : constant String := Integer'Image (Value);
   begin
      if Image (Image'First) = ' ' then
         return Image (Image'First + 1 .. Image'Last);
      end if;
      return Image;
   end Trim;

   procedure Bump (Value : in out Natural; By : Integer) is
   begin
      if By >= 0 then
         if Value > 100 - By then
            Value := 100;
         else
            Value := Value + By;
         end if;
      elsif Value < -By then
         Value := 0;
      else
         Value := Value - Natural (-By);
      end if;
   end Bump;

   function Gear_Cost (Item : Positive) return Natural is
   begin
      case Item is
         when 1 =>
            return 180;
         when 2 =>
            return 420;
         when 3 =>
            return 90;
         when 4 =>
            return 140;
         when others =>
            return 0;
      end case;
   end Gear_Cost;

   function In_Debt (Snap : Save.Snapshot) return Boolean is
   begin
      return Snap.Funds < 0;
   end In_Debt;

   function Living (Snap : Save.Snapshot) return Natural is
      Total : Natural := 0;
   begin
      for I in 1 .. Snap.Roster_Count loop
         if Snap.Roster (I).Alive then
            Total := Total + 1;
         end if;
      end loop;
      return Total;
   end Living;

   function Upkeep (Snap : Save.Snapshot) return Natural is
   begin
      return Living (Snap) * Upkeep_Each;
   end Upkeep;

   function Income_Of (Item : World.Atlas) return Natural is
      Total : Natural := 0;
   begin
      for I in 1 .. Item.Regions loop
         if Item.Area (I).Owner = 1 then
            Total := Total + Purse_Scale * World.Campaign.Income
              (Item.Area (I).Population, Item.Area (I).Tax);
         end if;
      end loop;
      return Total;
   end Income_Of;

   function Can_Hire (Snap : Save.Snapshot) return Boolean is
   begin
      return Snap.Funds >= Hire_Price
        and then Snap.Roster_Count < Agents.Max_Roster;
   end Can_Hire;

   function Can_Fit
     (Snap : Save.Snapshot;
      Agent : Positive;
      Item : Positive) return Boolean
   is
      Who : Agents.Operative;
   begin
      if Agent > Snap.Roster_Count or else Item > 4 then
         return False;
      end if;
      if not Snap.Roster (Agent).Alive then
         return False;
      end if;
      if Snap.Funds < Integer (Gear_Cost (Item)) then
         return False;
      end if;
      Who := Snap.Roster (Agent);
      case Item is
         when 1 =>
            return Who.Gun = Weapons.Pistol
              and then Snap.Known (Research.SMG);
         when 2 =>
            return Who.Gun /= Weapons.Rifle
              and then Snap.Known (Research.Rifle);
         when 3 =>
            if Who.Augments = 0 then
               return Snap.Known (Research.Reflex);
            elsif Who.Augments = 1 then
               return Snap.Known (Research.Plate);
            end if;
            return False;
         when 4 =>
            return Who.Armour = 0 and then Snap.Known (Research.Vest);
         when others =>
            return False;
      end case;
   end Can_Fit;

   function Can_Assign
     (Snap : Save.Snapshot;
      Slot : Positive;
      Agent : Natural) return Boolean
   is
   begin
      if Slot > Agents.Squad_Slots then
         return False;
      end if;
      if Agent = 0 then
         return True;
      end if;
      if Agent > Snap.Roster_Count then
         return False;
      end if;
      if not Snap.Roster (Agent).Alive then
         return False;
      end if;
      for I in Snap.Pick'Range loop
         if I /= Slot and then Snap.Pick (I) = Agent then
            return False;
         end if;
      end loop;
      return True;
   end Can_Assign;

   function Victim (Snap : Save.Snapshot) return Natural is
      Choice : Natural := 0;
      Health : Natural := Natural'Last;
      Who : Natural;
   begin
      for Slot in Snap.Pick'Range loop
         Who := Snap.Pick (Slot);
         if Who > 0
           and then Who <= Snap.Roster_Count
           and then Snap.Roster (Who).Alive
           and then (Choice = 0
                     or else Snap.Roster (Who).Health < Health
                     or else (Snap.Roster (Who).Health = Health
                              and then Who < Choice))
         then
            Choice := Who;
            Health := Snap.Roster (Who).Health;
         end if;
      end loop;
      if Choice /= 0 then
         return Choice;
      end if;
      for I in 1 .. Snap.Roster_Count loop
         if Snap.Roster (I).Alive then
            return I;
         end if;
      end loop;
      return 0;
   end Victim;

   procedure Close_Day
     (Snap : in out Save.Snapshot;
      Pay : Natural)
   is
      Added : constant Natural := Snap.Grant;
   begin
      Snap.Funds :=
        Snap.Funds + Integer (Pay)
        - Integer (Upkeep (Snap))
        - Integer (Added);
      Snap.Company (1).Research :=
        Snap.Company (1).Research + Added;
      Research.Mark (Snap.Company (1).Research, Snap.Known);
   end Close_Day;

   procedure Play_Day
     (Snap : in out Save.Snapshot;
      Item : in out World.Atlas)
   is
      Pay : constant Natural := Income_Of (Item);
   begin
      World.Campaign.Advance (Item);
      Save.Take (Snap, Item, Snap.Day + 1);
      Close_Day (Snap, Pay);
   end Play_Day;

   procedure Hire (Snap : in out Save.Snapshot) is
   begin
      Snap.Roster_Count := Snap.Roster_Count + 1;
      Snap.Roster (Snap.Roster_Count) :=
        Agents.Person (Snap.Seed, Snap.Roster_Count);
      Snap.Funds := Snap.Funds - Hire_Price;
   end Hire;

   procedure Set_Grant
     (Snap : in out Save.Snapshot;
      Amount : Natural)
   is
   begin
      Snap.Grant := Amount;
   end Set_Grant;

   procedure Fit
     (Snap : in out Save.Snapshot;
      Agent : Positive;
      Item : Positive)
   is
   begin
      Snap.Funds := Snap.Funds - Integer (Gear_Cost (Item));
      if Item = 1 then
         Snap.Roster (Agent).Gun := Weapons.SMG;
      elsif Item = 2 then
         Snap.Roster (Agent).Gun := Weapons.Rifle;
      elsif Item = 3 then
         Snap.Roster (Agent).Augments :=
           Snap.Roster (Agent).Augments + 1;
      else
         Snap.Roster (Agent).Armour := 1;
      end if;
   end Fit;

   procedure Assign
     (Snap : in out Save.Snapshot;
      Slot : Positive;
      Agent : Natural)
   is
   begin
      Snap.Pick (Slot) := Agent;
   end Assign;

   procedure Debrief
     (Snap : in out Save.Snapshot;
      Item : World.Atlas;
      Region : Positive;
      Outcome : Save.Mission_Outcome)
   is
      Who : Natural;
      Bonus : Natural;
   begin
      case Outcome is
         when Save.Won =>
            Bonus := World.Campaign.Income
              (Item.Area (Region).Population,
               Item.Area (Region).Tax);
            Snap.Funds :=
              Snap.Funds + Loot_Base + Integer (Bonus);
            for I in 1 .. Snap.Roster_Count loop
               if Snap.Roster (I).Alive then
                  Bump (Snap.Roster (I).Morale, 4);
               end if;
            end loop;
         when Save.Lost =>
            Who := Victim (Snap);
            if Who /= 0 then
               Snap.Roster (Who).Alive := False;
            end if;
            for I in 1 .. Snap.Roster_Count loop
               if Snap.Roster (I).Alive then
                  Bump (Snap.Roster (I).Morale, -8);
               end if;
            end loop;
         when Save.Timed_Out =>
            for I in 1 .. Snap.Roster_Count loop
               if Snap.Roster (I).Alive then
                  Bump (Snap.Roster (I).Morale, -5);
               end if;
            end loop;
      end case;
   end Debrief;

   function Ledger (Snap : Save.Snapshot) return String is
      Text : Ada.Strings.Unbounded.Unbounded_String;
      Who : Agents.Operative;
   begin
      Text := Add (Text, Trim (Snap.Funds));
      Text := Add (Text, " ");
      Text := Add (Text, Trim (Snap.Company (1).Research));
      Text := Add (Text, " ");
      Text := Add (Text, Trim (Snap.Grant));
      Text := Add (Text, " ");
      Text := Add (Text, Trim (Snap.Roster_Count));
      for I in 1 .. Snap.Roster_Count loop
         Who := Snap.Roster (I);
         Text := Add (Text, " ");
         Text := Add (Text, Agents.Name_Of (Who));
         Text := Add (Text, " ");
         Text := Add (Text, Trim (Who.Health));
         Text := Add (Text, " ");
         Text := Add (Text, Trim (Who.Accuracy));
         Text := Add (Text, " ");
         Text := Add (Text, Trim (Who.Speed));
         Text := Add (Text, " ");
         Text := Add (Text, Trim (Who.Morale));
         Text := Add (Text, " ");
         Text := Add (Text, Trim (Who.Augments));
         Text := Add (Text, " ");
         Text := Add (Text, Weapons.Token (Who.Gun));
         Text := Add (Text, " ");
         Text := Add (Text, Trim (Who.Armour));
         if Who.Alive then
            Text := Add (Text, " 1");
         else
            Text := Add (Text, " 0");
         end if;
      end loop;
      for Item in Research.Branch loop
         if Snap.Known (Item) then
            Text := Add (Text, " 1");
         else
            Text := Add (Text, " 0");
         end if;
      end loop;
      return Ada.Strings.Unbounded.To_String (Text);
   end Ledger;
end Megacorp.Session;
