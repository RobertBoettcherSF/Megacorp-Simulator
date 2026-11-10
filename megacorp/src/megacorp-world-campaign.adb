--  SPDX-License-Identifier: MIT
--  Copyright (c) 2026 Robert Boettcher

with Megacorp.World.Gen;

package body Megacorp.World.Campaign is
   Player : constant := 1;

   function Add (Left, Right : Natural) return Natural;
   function Holdings_Of
     (Item : Atlas; Corp : Positive) return Natural;
   function Adjacent
     (Item : Atlas; Left, Right : Positive) return Boolean;
   function Foreign_Neighbour
     (Item : Atlas; Region : Positive) return Boolean;
   procedure Mark (Item : in out Atlas);
   procedure Collect (Item : in out Atlas; Corp : Positive);
   procedure Pressure (Item : in out Atlas; Corp : Positive);
   procedure Fortify (Item : in out Atlas; Corp : Positive);
   procedure Study (Item : in out Atlas; Corp : Positive);
   procedure Strike (Item : in out Atlas; Corp : Positive);
   procedure Revolt (Item : in out Atlas);
   function Attack_Cost (Kind : Trait) return Natural;
   function Guard_Cost (Kind : Trait) return Natural;
   function Aim_Tax (Kind : Trait) return Natural;
   function Edge_Tech
     (Item : Atlas; Corp, Region : Positive) return Natural;
   function Score
     (Kind : Trait; Region : World.Region) return Integer;
   procedure Pay
     (Item : in out Atlas; Corp : Positive; Cost : Natural);
   function Bonus (Kind : Trait) return Natural;
   function Adjacent_To_Corp
     (Item : Atlas; Corp, Region : Positive) return Boolean;
   function Trim (Value : Integer) return String;
   function Trim_Word (Value : RNG.Word) return String;
   procedure Write_Owners
     (File : Ada.Text_IO.File_Type;
      Item : Atlas;
      Day : Natural;
      Last : Boolean);

   function Add (Left, Right : Natural) return Natural is
   begin
      if Right > Natural'Last - Left then
         return Natural'Last;
      end if;
      return Left + Right;
   end Add;

   function Holdings (Item : Atlas; Corp : Positive) return Natural is
   begin
      return Holdings_Of (Item, Corp);
   end Holdings;

   function Holdings_Of
     (Item : Atlas; Corp : Positive) return Natural
   is
      Total : Natural := 0;
   begin
      for I in 1 .. Item.Regions loop
         if Item.Area (I).Owner = Corp then
            Total := Total + 1;
         end if;
      end loop;
      return Total;
   end Holdings_Of;

   function Adjacent
     (Item : Atlas; Left, Right : Positive) return Boolean
   is
   begin
      for I in 1 .. Item.Links loop
         if (Item.Road (I).Left = Left and then Item.Road (I).Right = Right)
           or else (Item.Road (I).Left = Right
                    and then Item.Road (I).Right = Left)
         then
            return True;
         end if;
      end loop;
      return False;
   end Adjacent;

   function Foreign_Neighbour
     (Item : Atlas; Region : Positive) return Boolean
   is
      Owner : constant Positive := Item.Area (Region).Owner;
   begin
      for I in 1 .. Item.Links loop
         declare
            Other : Natural := 0;
         begin
            if Item.Road (I).Left = Region then
               Other := Item.Road (I).Right;
            elsif Item.Road (I).Right = Region then
               Other := Item.Road (I).Left;
            end if;
            if Other in 1 .. Item.Regions
              and then Item.Area (Other).Owner /= Owner
            then
               return True;
            end if;
         end;
      end loop;
      return False;
   end Foreign_Neighbour;

   function Coherent (Item : Atlas) return Boolean is
      Total : Natural := 0;
   begin
      for I in 1 .. Item.Regions loop
         if Item.Area (I).Owner > Item.Corps then
            return False;
         end if;
         Total := Total + 1;
      end loop;
      if Total /= Item.Regions then
         return False;
      end if;
      for C in 1 .. Item.Corps loop
         if Item.Company (C).Eliminated
           and then Holdings_Of (Item, C) /= 0
         then
            return False;
         end if;
         if not Item.Company (C).Eliminated
           and then Holdings_Of (Item, C) = 0
         then
            return False;
         end if;
      end loop;
      return True;
   end Coherent;

   function Books_Balance
     (Opening, Now : Atlas) return Boolean
   is
   begin
      if Opening.Corps /= Now.Corps then
         return False;
      end if;
      for C in 1 .. Now.Corps loop
         declare
            Expected : constant Natural :=
              Add (Opening.Company (C).Cash, Now.Company (C).Earned);
         begin
            if Now.Company (C).Spent > Expected
              or else Now.Company (C).Cash
                /= Expected - Now.Company (C).Spent
            then
               return False;
            end if;
         end;
      end loop;
      return True;
   end Books_Balance;

   procedure Mark (Item : in out Atlas) is
   begin
      for C in 1 .. Item.Corps loop
         if Holdings_Of (Item, C) = 0 then
            Item.Company (C).Eliminated := True;
         end if;
      end loop;
   end Mark;

   procedure Collect (Item : in out Atlas; Corp : Positive) is
      Gain : Natural := 0;
   begin
      if Item.Company (Corp).Eliminated then
         return;
      end if;
      for I in 1 .. Item.Regions loop
         if Item.Area (I).Owner = Corp then
            Gain := Add
              (Gain,
               Item.Area (I).Population * Item.Area (I).Tax / 1000);
         end if;
      end loop;
      Item.Company (Corp).Cash :=
        Add (Item.Company (Corp).Cash, Gain);
      Item.Company (Corp).Earned :=
        Add (Item.Company (Corp).Earned, Gain);
   end Collect;

   function Aim_Tax (Kind : Trait) return Natural is
   begin
      case Kind is
         when Aggressive =>
            return 12;
         when Mercantile =>
            return 28;
         when Scientific =>
            return 16;
         when Secretive =>
            return 10;
      end case;
   end Aim_Tax;

   procedure Pressure (Item : in out Atlas; Corp : Positive) is
      Shift : Integer;
      Next : Integer;
      Toward : Natural;
   begin
      if Item.Company (Corp).Eliminated then
         return;
      end if;
      for I in 1 .. Item.Regions loop
         if Item.Area (I).Owner = Corp then
            Shift := Integer (Item.Area (I).Tax) / 8
              - Integer (Item.Area (I).Tech) / 25;
            Next := Integer (Item.Area (I).Unrest) + Shift;
            if Next < 0 then
               Next := 0;
            elsif Next > 100 then
               Next := 100;
            end if;
            Item.Area (I).Unrest := Natural (Next);
            if Corp /= Player then
               if Item.Area (I).Unrest > 70
                 and then Item.Area (I).Tax > 0
               then
                  Item.Area (I).Tax := Item.Area (I).Tax - 1;
               else
                  Toward := Aim_Tax (Item.Company (Corp).Kind);
                  if Item.Area (I).Tax < Toward then
                     Item.Area (I).Tax := Item.Area (I).Tax + 1;
                  elsif Item.Area (I).Tax > Toward
                    and then Item.Area (I).Tax > 0
                  then
                     Item.Area (I).Tax := Item.Area (I).Tax - 1;
                  end if;
               end if;
            end if;
         end if;
      end loop;
   end Pressure;

   function Guard_Cost (Kind : Trait) return Natural is
   begin
      case Kind is
         when Aggressive =>
            return 150;
         when Mercantile =>
            return 250;
         when Scientific =>
            return 200;
         when Secretive =>
            return 400;
      end case;
   end Guard_Cost;

   procedure Pay
     (Item : in out Atlas; Corp : Positive; Cost : Natural)
   is
   begin
      Item.Company (Corp).Cash := Item.Company (Corp).Cash - Cost;
      Item.Company (Corp).Spent :=
        Add (Item.Company (Corp).Spent, Cost);
   end Pay;

   procedure Fortify (Item : in out Atlas; Corp : Positive) is
      Cost : constant Natural :=
        Guard_Cost (Item.Company (Corp).Kind);
      Choice : Natural := 0;
      Worry : Natural := 0;
   begin
      if Item.Company (Corp).Eliminated
        or else Corp = Player
        or else Item.Company (Corp).Cash < Cost
      then
         return;
      end if;
      for I in 1 .. Item.Regions loop
         if Item.Area (I).Owner = Corp
           and then Foreign_Neighbour (Item, I)
           and then (Choice = 0
                     or else Item.Area (I).Unrest > Worry
                     or else (Item.Area (I).Unrest = Worry
                              and then I < Choice))
         then
            Choice := I;
            Worry := Item.Area (I).Unrest;
         end if;
      end loop;
      if Choice = 0 then
         return;
      end if;
      Pay (Item, Corp, Cost);
      Item.Area (Choice).Defence :=
        Add (Item.Area (Choice).Defence, Cost / 2);
      if Item.Area (Choice).Defence > 2000 then
         Item.Area (Choice).Defence := 2000;
      end if;
      if Item.Area (Choice).Unrest >= 3 then
         Item.Area (Choice).Unrest := Item.Area (Choice).Unrest - 3;
      else
         Item.Area (Choice).Unrest := 0;
      end if;
   end Fortify;

   procedure Study (Item : in out Atlas; Corp : Positive) is
      Cost : constant := 150;
      Choice : Natural := 0;
      Low : Natural := Natural'Last;
   begin
      if Item.Company (Corp).Eliminated
        or else Corp = Player
        or else Item.Company (Corp).Kind /= Scientific
        or else Item.Company (Corp).Cash < Cost
      then
         return;
      end if;
      for I in 1 .. Item.Regions loop
         if Item.Area (I).Owner = Corp
           and then Item.Area (I).Tech < 100
           and then (Choice = 0 or else Item.Area (I).Tech < Low)
         then
            Choice := I;
            Low := Item.Area (I).Tech;
         end if;
      end loop;
      if Choice = 0 then
         return;
      end if;
      Pay (Item, Corp, Cost);
      Item.Area (Choice).Tech := Item.Area (Choice).Tech + 1;
   end Study;

   function Attack_Cost (Kind : Trait) return Natural is
   begin
      case Kind is
         when Aggressive =>
            return 600;
         when Mercantile =>
            return 400;
         when Scientific =>
            return 350;
         when Secretive =>
            return 250;
      end case;
   end Attack_Cost;

   function Score
     (Kind : Trait; Region : World.Region) return Integer
   is
   begin
      case Kind is
         when Aggressive =>
            return 500 + Integer (Region.Unrest)
              - Integer (Region.Defence);
         when Mercantile =>
            return Integer (Region.Population) / 2
              - Integer (Region.Defence);
         when Scientific =>
            return Integer (Region.Tech) * 3
              - Integer (Region.Defence) / 2;
         when Secretive =>
            return 300 - Integer (Region.Defence) * 2;
      end case;
   end Score;

   function Edge_Tech
     (Item : Atlas; Corp, Region : Positive) return Natural
   is
      Best : Natural := 0;
   begin
      for I in 1 .. Item.Regions loop
         if Item.Area (I).Owner = Corp
           and then Adjacent (Item, I, Region)
           and then Item.Area (I).Tech > Best
         then
            Best := Item.Area (I).Tech;
         end if;
      end loop;
      return Best;
   end Edge_Tech;

   function Bonus (Kind : Trait) return Natural is
   begin
      case Kind is
         when Aggressive =>
            return 80;
         when Mercantile =>
            return 20;
         when Scientific =>
            return 40;
         when Secretive =>
            return 50;
      end case;
   end Bonus;

   procedure Strike (Item : in out Atlas; Corp : Positive) is
      Kind : constant Trait := Item.Company (Corp).Kind;
      Cost : constant Natural := Attack_Cost (Kind);
      Choice : Natural := 0;
      Best : Integer := Integer'First;
      Value : Integer;
      Power : Natural;
      Hold : Natural;
   begin
      if Item.Company (Corp).Eliminated
        or else Corp = Player
        or else Item.Company (Corp).Cash < Cost
      then
         return;
      end if;
      for I in 1 .. Item.Regions loop
         if Item.Area (I).Owner /= Corp
           and then Foreign_Neighbour (Item, I)
           and then Adjacent_To_Corp (Item, Corp, I)
         then
            Value := Score (Kind, Item.Area (I));
            if Kind = Secretive and then Value < 80 then
               Value := Integer'First;
            end if;
            if Value > Best
              or else (Value = Best and then Value /= Integer'First
                       and then (Choice = 0 or else I < Choice))
            then
               Best := Value;
               Choice := I;
            end if;
         end if;
      end loop;
      if Choice = 0 or else Best = Integer'First then
         return;
      end if;
      if Best <= 0 and then Kind /= Aggressive then
         return;
      end if;
      Pay (Item, Corp, Cost);
      Power := Cost + Bonus (Kind) + Edge_Tech (Item, Corp, Choice) / 5;
      Hold := Item.Area (Choice).Defence
        + Item.Area (Choice).Tech / 5 + 40;
      if Power > Hold then
         Item.Area (Choice).Owner := Corp;
         Item.Area (Choice).Defence := Cost / 4;
         Item.Area (Choice).Unrest := 25;
      else
         Item.Area (Choice).Defence :=
           Add (Item.Area (Choice).Defence, Cost / 5);
         if Item.Area (Choice).Defence > 2000 then
            Item.Area (Choice).Defence := 2000;
         end if;
         if Item.Area (Choice).Unrest <= 96 then
            Item.Area (Choice).Unrest := Item.Area (Choice).Unrest + 4;
         else
            Item.Area (Choice).Unrest := 100;
         end if;
      end if;
   end Strike;

   function Adjacent_To_Corp
     (Item : Atlas; Corp, Region : Positive) return Boolean
   is
   begin
      for I in 1 .. Item.Regions loop
         if Item.Area (I).Owner = Corp
           and then Adjacent (Item, I, Region)
         then
            return True;
         end if;
      end loop;
      return False;
   end Adjacent_To_Corp;

   procedure Revolt (Item : in out Atlas) is
      Best : Natural;
      Best_Cash : Natural;
      Other : Natural;
   begin
      for I in 1 .. Item.Regions loop
         if Item.Area (I).Unrest >= 100 then
            Best := 0;
            Best_Cash := 0;
            for Link in 1 .. Item.Links loop
               Other := 0;
               if Item.Road (Link).Left = I then
                  Other := Item.Road (Link).Right;
               elsif Item.Road (Link).Right = I then
                  Other := Item.Road (Link).Left;
               end if;
               if Other in 1 .. Item.Regions
                 and then Item.Area (Other).Owner /= Item.Area (I).Owner
                 and then not Item.Company (Item.Area (Other).Owner).Eliminated
               then
                  if Best = 0
                    or else Item.Company (Item.Area (Other).Owner).Cash
                      > Best_Cash
                    or else (Item.Company (Item.Area (Other).Owner).Cash
                             = Best_Cash
                             and then Item.Area (Other).Owner < Best)
                  then
                     Best := Item.Area (Other).Owner;
                     Best_Cash := Item.Company (Best).Cash;
                  end if;
               end if;
            end loop;
            if Best /= 0 then
               Item.Area (I).Owner := Best;
               Item.Area (I).Unrest := 35;
               Item.Area (I).Defence := 0;
            else
               Item.Area (I).Unrest := 70;
               if Item.Area (I).Tax > 8 then
                  Item.Area (I).Tax := 8;
               end if;
            end if;
         end if;
      end loop;
   end Revolt;

   procedure Advance (Item : in out Atlas) is
      Cash_Before : Natural;
      Earned_Before : Natural;
      Spent_Before : Natural;
   begin
      Mark (Item);
      for C in 1 .. Item.Corps loop
         Cash_Before := Item.Company (C).Cash;
         Earned_Before := Item.Company (C).Earned;
         Spent_Before := Item.Company (C).Spent;
         Collect (Item, C);
         Pressure (Item, C);
         Fortify (Item, C);
         Study (Item, C);
         Strike (Item, C);
         pragma Assert
           (Item.Company (C).Cash
            = Add (Cash_Before,
                   Item.Company (C).Earned - Earned_Before)
              - (Item.Company (C).Spent - Spent_Before));
      end loop;
      Revolt (Item);
      Mark (Item);
   end Advance;

   procedure Run (Item : in out Atlas; Days : Natural) is
   begin
      for Day in 1 .. Days loop
         Advance (Item);
      end loop;
   end Run;

   function Play
     (Seed : RNG.Word;
      Size : Parameters.Generator_Parameters;
      Days : Natural) return Atlas
   is
      Item : Atlas := Gen.Generate (Seed, Size);
   begin
      Run (Item, Days);
      return Item;
   end Play;

   function Trim (Value : Integer) return String is
      Image : constant String := Integer'Image (Value);
   begin
      return Image (Image'First + 1 .. Image'Last);
   end Trim;

   function Trim_Word (Value : RNG.Word) return String is
      Image : constant String := RNG.Word'Image (Value);
   begin
      return Image (Image'First + 1 .. Image'Last);
   end Trim_Word;

   procedure Put_Day
     (File : Ada.Text_IO.File_Type;
      Item : Atlas;
      Day : Natural)
   is
   begin
      Ada.Text_IO.Put (File, "day" & Integer'Image (Day) & ":");
      for C in 1 .. Item.Corps loop
         Ada.Text_IO.Put
           (File,
            Integer'Image (C) & "="
            & Trim (Integer (Holdings (Item, C))));
         if Item.Company (C).Eliminated then
            Ada.Text_IO.Put (File, "*");
         end if;
      end loop;
      Ada.Text_IO.New_Line (File);
   end Put_Day;

   procedure Write_Owners
     (File : Ada.Text_IO.File_Type; Item : Atlas; Day : Natural;
      Last : Boolean)
   is
   begin
      Ada.Text_IO.Put (File, "    {""day"": ");
      Ada.Text_IO.Put (File, Trim (Day));
      Ada.Text_IO.Put (File, ", ""owner"": [");
      for I in 1 .. Item.Regions loop
         if I > 1 then
            Ada.Text_IO.Put (File, ",");
         end if;
         Ada.Text_IO.Put
           (File, Trim (Integer (Item.Area (I).Owner)));
      end loop;
      Ada.Text_IO.Put (File, "], ""cash"": [");
      for C in 1 .. Item.Corps loop
         if C > 1 then
            Ada.Text_IO.Put (File, ",");
         end if;
         Ada.Text_IO.Put (File, Trim (Integer (Item.Company (C).Cash)));
      end loop;
      Ada.Text_IO.Put (File, "]}");
      if Last then
         Ada.Text_IO.New_Line (File);
      else
         Ada.Text_IO.Put_Line (File, ",");
      end if;
   end Write_Owners;

   procedure Write
     (Path : String;
      Seed : RNG.Word;
      Size : Parameters.Generator_Parameters;
      Days : Natural;
      Version : String)
   is
      File : Ada.Text_IO.File_Type;
      Item : Atlas := Gen.Generate (Seed, Size);
   begin
      Ada.Text_IO.Create (File, Ada.Text_IO.Out_File, Path);
      Ada.Text_IO.Put_Line (File, "{");
      Ada.Text_IO.Put_Line
        (File, "  ""version"": """ & Version & """,");
      Ada.Text_IO.Put_Line
        (File, "  ""seed"": " & Trim_Word (Seed) & ",");
      Ada.Text_IO.Put_Line
        (File, "  ""days"": " & Trim (Days) & ",");
      Ada.Text_IO.Put_Line (File, "  ""frames"": [");
      Write_Owners (File, Item, 0, Days = 0);
      for Day in 1 .. Days loop
         Advance (Item);
         Write_Owners (File, Item, Day, Day = Days);
      end loop;
      Ada.Text_IO.Put_Line (File, "  ]");
      Ada.Text_IO.Put_Line (File, "}");
      Ada.Text_IO.Close (File);
   exception
      when others =>
         if Ada.Text_IO.Is_Open (File) then
            Ada.Text_IO.Close (File);
         end if;
         raise;
   end Write;

end Megacorp.World.Campaign;
