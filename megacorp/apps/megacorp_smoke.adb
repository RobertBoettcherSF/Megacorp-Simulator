--  SPDX-License-Identifier: MIT
--  Copyright (c) 2026 Robert Boettcher

with Ada.Assertions;
with Ada.Command_Line;
with Ada.Directories;
with Ada.Exceptions;
with Ada.Text_IO;
with Ada.Containers;
with Ada.Strings.Fixed;
with Megacorp.Actions;
with Megacorp.Behaviour;
with Megacorp.Mission;
with Megacorp.Mission.Gen;
with Megacorp.Vehicles;
with Megacorp.Weapons;
with Megacorp.World.Campaign;
with Megacorp.World.Gen;
with Megacorp.Assets.Placeholder;
with Megacorp.Data.Virtual_FS.Native;
with Megacorp.Host;
with Megacorp.Map;
with Megacorp.Map.Gen;
with Megacorp.Path;
with Megacorp.Peds;
with Megacorp.Parameters;
with Megacorp.RNG;
with Megacorp.Save;
with Megacorp.Save.Log;
with Megacorp.Save.Migrate;
with Megacorp.API;
with Megacorp.Assets.Import;
with Megacorp.Play;
with Smoke_Check;

procedure Megacorp_Smoke is
   package Params renames Megacorp.Parameters;
   package RNG renames Megacorp.RNG;
   use type RNG.Word;
   use type Megacorp.Map.City;
   use type Megacorp.Map.Point;
   use type Megacorp.Map.Terrain;
   use type Megacorp.Path.Result;
   use type Megacorp.Path.Status;

   type Sample is array (Positive range <>) of Integer;
   procedure Shuffle_Sample is new RNG.Shuffle
     (Item => Integer, Index => Positive, Collection => Sample);

   Defaults : constant Params.Generator_Parameters := Params.Defaults;
   Custom   : Params.Generator_Parameters;
   Rejected : Params.Generator_Parameters;
   Raised   : Boolean;
   Earlier  : Megacorp.Host.Milliseconds;
   Later    : Megacorp.Host.Milliseconds;
begin
   Smoke_Check.Expect
     (Megacorp.Version = "0.23.0"
      and then Megacorp.Name = "Megacorp Simulator",
      "version 0.23.0");
   declare
      package Globe renames Megacorp.World.Gen;
      package Camp renames Megacorp.World.Campaign;
      Opened : Megacorp.World.Atlas :=
        Globe.Generate (42, Defaults);
   begin
      Megacorp.API.Init (42);
      Smoke_Check.Expect
        (Megacorp.API.Digest
           = Megacorp.API.Fingerprint (Opened, 0),
         "engine matches native day 0");
      Megacorp.API.Step (10);
      Camp.Run (Opened, 10);
      Smoke_Check.Expect
        (Megacorp.API.Digest
           = Megacorp.API.Fingerprint (Opened, 10),
         "engine matches native day 10");
   end;
   declare
      package Native renames Megacorp.Data.Virtual_FS.Native;
      Store : constant Native.Disk := Native.Open ("../web");
      Text : constant String :=
        Native.Read (Store, "assets/tiles.json");
      Png : constant String :=
        Character'Val (16#89#) & "PNG"
        & Character'Val (13) & Character'Val (10)
        & Character'Val (16#1A#) & Character'Val (10);
   begin
      Smoke_Check.Expect
        (Megacorp.Assets.Import.Accepts ("tiles.json", Text)
         and then not Megacorp.Assets.Import.Accepts
           ("notes.json", "hello")
         and then Megacorp.Assets.Import.Accepts ("sprite.png", Png)
         and then not Megacorp.Assets.Import.Accepts
           ("sprite.png", "PNG"),
         "imported assets are checked");
   end;
   Ada.Directories.Create_Path ("/tmp/megacorp-play");
   declare
      package Native renames Megacorp.Data.Virtual_FS.Native;
      package Globe renames Megacorp.World.Gen;
      Root : Native.Disk :=
        Native.Open ("/tmp/megacorp-play");
      World : Megacorp.World.Atlas;
      Home : Positive;
      City : Megacorp.RNG.Word;
      Snap : Megacorp.Save.Snapshot;
      Book : Megacorp.Save.Log.Journal;
      Start_X : Positive;
      Start_Y : Positive;
      End_X : Positive;
      End_Y : Positive;
      Goal : Megacorp.Map.Point;
      First : Megacorp.RNG.Word;
      Again : Megacorp.RNG.Word;
   begin
      World := Globe.Generate (42, Defaults);
      Home := World.Company (1).Home;
      City := World.Area (Home).City;
      Megacorp.Play.Open (City);
      Start_X := Megacorp.Play.Actor_X (1);
      Start_Y := Megacorp.Play.Actor_Y (1);
      Goal := Megacorp.Play.Goal_Near (1);
      Snap := Megacorp.Save.Capture
        (World, 0, Megacorp.Parameters.Auto_Play);
      Book := Megacorp.Save.Log.Start (Root, "slot.log", Snap);
      Megacorp.Save.Log.Commit
        (Root, "slot.log", Snap, World, Book,
         Megacorp.Save.Log.Order
           (1,
            Megacorp.Play.Pixel_X (Start_X),
            Megacorp.Play.Pixel_Y (Start_Y),
            0, 0, 0));
      Megacorp.Save.Log.Commit
        (Root, "slot.log", Snap, World, Book,
         Megacorp.Save.Log.Order
           (1,
            Megacorp.Play.Pixel_X (Goal.X),
            Megacorp.Play.Pixel_Y (Goal.Y),
            0, 0, 0));
      Megacorp.Save.Log.Commit
        (Root, "slot.log", Snap, World, Book,
         Megacorp.Save.Log.Ticks (24));
      Smoke_Check.Expect
        (Megacorp.Play.Clock = 24
         and then (Megacorp.Play.Actor_X (1) /= Start_X
                   or else Megacorp.Play.Actor_Y (1) /= Start_Y),
         "a move order walks the selected ped");
      End_X := Megacorp.Play.Actor_X (1);
      End_Y := Megacorp.Play.Actor_Y (1);
      First := Megacorp.Play.Digest;
      Megacorp.Play.Write (Root, "city.mgc");
      Megacorp.Play.Open (City);
      Smoke_Check.Expect
        (Megacorp.Play.Read (Root, "city.mgc")
         and then Megacorp.Play.Clock = 24
         and then Megacorp.Play.Actor_X (1) = End_X
         and then Megacorp.Play.Actor_Y (1) = End_Y,
         "a city checkpoint reloads");
      Megacorp.Play.Open (City);
      Megacorp.Save.Log.Replay (Snap, World, Book);
      Again := Megacorp.Play.Digest;
      Smoke_Check.Expect
        (Again = First,
         "a replayed command sequence gives the same digest");
   end;
   declare
      package Native renames Megacorp.Data.Virtual_FS.Native;
      package Globe renames Megacorp.World.Gen;

      function Low (Value : Megacorp.RNG.Word) return Integer;
      function High (Value : Megacorp.RNG.Word) return Integer;
      function Low (Value : Megacorp.RNG.Word) return Integer is
      begin
         return Integer (Value and 16#7FFF_FFFF#);
      end Low;
      function High (Value : Megacorp.RNG.Word) return Integer is
      begin
         return Integer ((Value / 2 ** 31) and 16#7FFF_FFFF#);
      end High;

      Root : Native.Disk := Native.Open ("/tmp/megacorp-play");
      World : Megacorp.World.Atlas;
      Again : Megacorp.World.Atlas;
      Snap : Megacorp.Save.Snapshot;
      Book : Megacorp.Save.Log.Journal;
      Region : Positive;
      City : Megacorp.RNG.Word;
      First : Megacorp.RNG.Word;
      Second : Megacorp.RNG.Word;
   begin
      World := Globe.Generate (42, Defaults);
      Region := 1;
      for I in 1 .. World.Regions loop
         if World.Area (I).Owner /= 1 then
            Region := I;
            exit;
         end if;
      end loop;
      City := World.Area (Region).City;
      Snap := Megacorp.Save.Capture
        (World, 0, Megacorp.Parameters.Auto_Play);
      Book := Megacorp.Save.Log.Start (Root, "mission.log", Snap);
      Megacorp.Save.Log.Commit
        (Root, "mission.log", Snap, World, Book,
         Megacorp.Save.Log.Order
           (6, Region, Low (City), High (City), 0, 0));
      Megacorp.Save.Log.Commit
        (Root, "mission.log", Snap, World, Book,
         Megacorp.Save.Log.Order
           (1,
            Megacorp.Play.Pixel_X (Megacorp.Play.Actor_X (1)),
            Megacorp.Play.Pixel_Y (Megacorp.Play.Actor_Y (1)),
            0, 0, 0));
      Megacorp.Save.Log.Commit
        (Root, "mission.log", Snap, World, Book,
         Megacorp.Save.Log.Order
           (1,
            Megacorp.Play.Pixel_X (Megacorp.Play.Zone_X),
            Megacorp.Play.Pixel_Y (Megacorp.Play.Zone_Y),
            0, 0, 0));
      Megacorp.Save.Log.Commit
        (Root, "mission.log", Snap, World, Book,
         Megacorp.Save.Log.Ticks (32));
      Megacorp.Save.Log.Commit
        (Root, "mission.log", Snap, World, Book,
         Megacorp.Save.Log.Ticks (16));
      Smoke_Check.Expect
        (Megacorp.Play.Mission_Ending = 2,
         "a scripted walk wins the mission");
      First := Megacorp.Play.Digest;
      Megacorp.Play.Settle (World, Snap);
      Megacorp.Save.Log.Commit
        (Root, "mission.log", Snap, World, Book,
         Megacorp.Save.Log.Mission_Done
           (Region, Megacorp.Save.Mission_Outcome'First,
            Megacorp.Play.Clock));
      Megacorp.Save.Log.Commit
        (Root, "mission.log", Snap, World, Book,
         Megacorp.Save.Log.Region_Set (Snap, World, Region));
      Smoke_Check.Expect
        (World.Area (Region).Owner = 1
         and then Snap.Area (Region).Visited,
         "a win takes the region and marks it visited");
      Again := Globe.Generate (42, Defaults);
      Snap := Megacorp.Save.Capture
        (Again, 0, Megacorp.Parameters.Auto_Play);
      Megacorp.Save.Log.Replay (Snap, Again, Book);
      Second := Megacorp.Play.Digest;
      Smoke_Check.Expect
        (Second = First
         and then Again.Area (Region).Owner = 1
         and then Snap.Area (Region).Visited,
         "a scripted win replays to the same digest");
      declare
         Base : Megacorp.Save.Snapshot := Snap;
      begin
         Book := Megacorp.Save.Log.Start (Root, "loss.log", Base);
         Megacorp.Save.Log.Commit
           (Root, "loss.log", Snap, Again, Book,
            Megacorp.Save.Log.Order
              (6, Region, Low (City), High (City), 0, 0));
         Megacorp.Save.Log.Commit
           (Root, "loss.log", Snap, Again, Book,
            Megacorp.Save.Log.Ticks (32));
         Megacorp.Save.Log.Commit
           (Root, "loss.log", Snap, Again, Book,
            Megacorp.Save.Log.Ticks (16));
         Smoke_Check.Expect
           (Megacorp.Play.Mission_Ending = 4,
            "standing still loses the mission");
         First := Megacorp.Play.Digest;
         Again := Globe.Generate (42, Defaults);
         Megacorp.Save.Restore (Base, Again);
         Megacorp.Save.Log.Replay (Base, Again, Book);
         Smoke_Check.Expect
           (Megacorp.Play.Digest = First
            and then Again.Area (Region).Owner = Base.Area (Region).Owner,
            "a scripted loss replays to the same digest");
      end;
   end;
   Smoke_Check.Expect
     (Params.Corporation_Count (Defaults) = 4
      and then Params.Region_Count (Defaults) = 40
      and then Params.City_Map_Width (Defaults) = 128
      and then Params.City_Map_Height (Defaults) = 128,
      "default parameters");
   Custom := Params.Make (2, 10, 64, 96);
   Smoke_Check.Expect
     (Params.Corporation_Count (Custom) = 2
      and then Params.Region_Count (Custom) = 10
      and then Params.City_Map_Width (Custom) = 64
      and then Params.City_Map_Height (Custom) = 96,
      "parameters are not fixed constants");
   Smoke_Check.Expect
     (not Params.Region_May_Reroll (Params.Scenario, False)
      and then not Params.Region_May_Reroll (Params.Scenario, True)
      and then Params.Region_May_Reroll (Params.Free_Play, False)
      and then Params.Region_May_Reroll (Params.Auto_Play, False)
      and then not Params.Region_May_Reroll (Params.Free_Play, True)
      and then not Params.Region_May_Reroll (Params.Auto_Play, True),
      "re-roll rule");

   Raised := False;
   begin
      Rejected :=
        Params.Make
          (0,
           Params.Default_Regions,
           Params.Default_City_Map_Width,
           Params.Default_City_Map_Height);
      Smoke_Check.Discard (Params.Corporation_Count (Rejected));
   exception
      when Ada.Assertions.Assertion_Error =>
         Raised := True;
   end;
   Smoke_Check.Expect (Raised, "make rejects 0 corporations");

   Raised := False;
   begin
      Rejected :=
        Params.Make
          (Params.Default_Corporations,
           Params.Default_Regions,
           Params.Max_City_Map_Edge + 1,
           Params.Default_City_Map_Height);
      Smoke_Check.Discard (Params.City_Map_Width (Rejected));
   exception
      when Ada.Assertions.Assertion_Error =>
         Raised := True;
   end;
   Smoke_Check.Expect (Raised, "make rejects an oversized map");

   Earlier := Megacorp.Host.Monotonic_Milliseconds;
   delay 0.01;
   Later := Megacorp.Host.Monotonic_Milliseconds;
   Smoke_Check.Expect (Later >= Earlier, "clock does not go backwards");

   Megacorp.Host.Log (Megacorp.Host.Info, "smoke");
   Smoke_Check.Expect (True, "log accepts a message");

   Raised := False;
   begin
      Megacorp.Host.Log (Megacorp.Host.Info, "");
   exception
      when Ada.Assertions.Assertion_Error =>
         Raised := True;
   end;
   Smoke_Check.Expect (Raised, "log rejects an empty message");

   declare
      Published : RNG.Generator := RNG.Restore (0, 1, 2, 3, 4);
      Seeded    : RNG.Generator := RNG.Make (0);
      Left      : RNG.Generator := RNG.Make (99);
      Right     : RNG.Generator := RNG.Make (99);
      Other     : RNG.Generator := RNG.Make (100);
      World     : RNG.Generator := RNG.Make (42);
      Region_1  : RNG.Generator :=
        RNG.Child (World, RNG.Region, 1);
      Region_2  : RNG.Generator :=
        RNG.Child (World, RNG.Region, 2);
      City_1    : RNG.Generator :=
        RNG.Child (World, RNG.City, 1);
      Again     : RNG.Generator;
      Again_2   : RNG.Generator;
      Bounds    : RNG.Generator := RNG.Make (7);
      Deck      : Sample (1 .. 5) := (1, 2, 3, 4, 5);
      Seen      : array (1 .. 5) of Boolean := (others => False);
      Same      : Boolean;
      In_Bounds : Boolean := True;
      Shuffled  : Boolean := True;
      First_L   : RNG.Word;
      First_R   : RNG.Word;
      First_O   : RNG.Word;
      First_R1  : RNG.Word;
      First_R2  : RNG.Word;
      First_C1  : RNG.Word;
      Drawn     : Long_Long_Integer;
      Picked    : Integer;
      Remaining : Natural;
   begin
      Smoke_Check.Expect
        (RNG.Next (Published) = 16#0000_0000_0000_2D00#
         and then RNG.Next (Published) = 0
         and then RNG.Next (Published) = 16#0000_0000_5A00_7080#
         and then RNG.Next (Published) = 16#10E0_0000_0000_9D80#,
         "xoshiro256** reference vector");
      Smoke_Check.Expect
        (RNG.State_Word (Seeded, 1) = 16#E220_A839_7B1D_CDAF#
         and then RNG.State_Word (Seeded, 2) = 16#6E78_9E6A_A1B9_65F4#
         and then RNG.State_Word (Seeded, 3) = 16#06C4_5D18_8009_454F#
         and then RNG.State_Word (Seeded, 4) = 16#F88B_B8A8_724C_81EC#
         and then RNG.Next (Seeded) = 16#99EC_5F36_CB75_F2B4#
         and then RNG.Next (Seeded) = 16#BF6E_1F78_4956_452A#
         and then RNG.Next (Seeded) = 16#1A5F_849D_4933_E6E0#
         and then RNG.Next (Seeded) = 16#6AA5_94F1_262D_2D2C#,
         "Make(0) reference vector");

      First_L := RNG.Next (Left);
      First_R := RNG.Next (Right);
      First_O := RNG.Next (Other);
      Same := First_L = First_R and then First_O /= First_L;
      Remaining := 3;
      while Remaining > 0 loop
         Same := Same and then RNG.Next (Left) = RNG.Next (Right);
         Remaining := Remaining - 1;
      end loop;
      Smoke_Check.Expect (Same, "same seed gives the same sequence");

      First_R1 := RNG.Next (Region_1);
      First_R2 := RNG.Next (Region_2);
      First_C1 := RNG.Next (City_1);
      Smoke_Check.Discard (Integer (RNG.Next (World) mod 16));
      Smoke_Check.Discard (Integer (RNG.Next (Region_2) mod 16));
      Again := RNG.Child (World, RNG.Region, 1);
      Again_2 := RNG.Child (World, RNG.Region, 2);
      Smoke_Check.Expect
        (RNG.Next (Again) = First_R1
         and then RNG.Next (Again_2) = First_R2
         and then First_R1 /= First_R2
         and then First_R1 /= First_C1
         and then First_R2 /= First_C1,
         "child streams stay independent");

      Remaining := 16;
      while Remaining > 0 loop
         Picked := RNG.Pick (Bounds, -3, 5);
         Drawn := RNG.Uniform (Bounds, -20, 20);
         In_Bounds :=
           In_Bounds
           and then Picked in -3 .. 5
           and then Drawn in -20 .. 20
           and then RNG.Pick (Bounds, 0, 7) in 0 .. 7;
         Remaining := Remaining - 1;
      end loop;
      Smoke_Check.Expect
        (In_Bounds
         and then not RNG.Chance (Bounds, 0, 4)
         and then RNG.Chance (Bounds, 4, 4),
         "ranges stay in bounds");

      Shuffle_Sample (Bounds, Deck);
      for Value of Deck loop
         if Value in 1 .. 5 then
            Seen (Value) := True;
         else
            Shuffled := False;
         end if;
      end loop;
      Smoke_Check.Expect
        (Shuffled
         and then Seen (1) and then Seen (2) and then Seen (3)
         and then Seen (4) and then Seen (5),
         "shuffle keeps every value");
   end;

   declare
      package Map renames Megacorp.Map;

      Small   : constant Map.City := Map.Test_Layout (1, 5, 5);
      Layout  : constant Map.City := Map.Test_Layout (42, 24, 24);
      Repeat  : constant Map.City := Map.Test_Layout (42, 24, 24);
      Other   : constant Map.City := Map.Test_Layout (99, 24, 24);
      Full    : constant Map.City :=
        Map.Test_Layout (42, Defaults);
      Here    : Map.Point;
      Cell    : Map.Tile;
      Seen_Water    : Boolean := False;
      Seen_Road     : Boolean := False;
      Seen_Building : Boolean := False;
      Rules         : Boolean := True;
   begin
      Raised := False;
      begin
         if Map.Tile_At (Small, 0, 1).Kind = Map.Water then
            Raised := False;
         end if;
      exception
         when Ada.Assertions.Assertion_Error =>
            Raised := True;
      end;
      Smoke_Check.Expect
        (Raised
         and then Small.Width = 5
         and then Map.Tile_At (Small, 1, 1).Kind = Map.Open_Ground,
         "map bounds");

      Here := Map.Neighbour_4 (Small, 3, 3, Map.North);
      Smoke_Check.Expect
        (not Map.Has_Neighbour_4 (Small, 1, 1, Map.North)
         and then not Map.Has_Neighbour_4 (Small, 1, 1, Map.West)
         and then Map.Neighbour_4 (Small, 1, 1, Map.East).X = 2
         and then Map.Neighbour_4 (Small, 1, 1, Map.East).Y = 1
         and then Map.Neighbour_4 (Small, 1, 1, Map.South).Y = 2
         and then Here.X = 3
         and then Here.Y = 2
         and then Map.Has_Neighbour_8 (Small, 3, 3, Map.South_East)
         and then Map.Neighbour_8 (Small, 3, 3, Map.South_East).X = 4
         and then Map.Neighbour_8 (Small, 3, 3, Map.South_East).Y = 4
         and then not Map.Has_Neighbour_8 (Small, 1, 1, Map.North_West),
         "map neighbours");

      for Y in 1 .. Layout.Height loop
         for X in 1 .. Layout.Width loop
            Cell := Map.Tile_At (Layout, X, Y);
            case Cell.Kind is
               when Map.Water =>
                  Seen_Water := True;
                  Rules := Rules
                    and then not Cell.Walkable
                    and then not Cell.Drivable
                    and then Cell.Level = 0;
               when Map.Road =>
                  Seen_Road := True;
                  Rules := Rules
                    and then Cell.Walkable
                    and then Cell.Drivable;
               when Map.Building =>
                  Seen_Building := True;
                  Rules := Rules
                    and then not Cell.Walkable
                    and then not Cell.Drivable;
               when Map.Open_Ground | Map.Pavement =>
                  Rules := Rules
                    and then Cell.Walkable
                    and then not Cell.Drivable;
            end case;
         end loop;
      end loop;
      Smoke_Check.Expect
        (Rules and then Seen_Water and then Seen_Road
         and then Seen_Building,
         "test layout walkability");
      Smoke_Check.Expect
        (Layout = Repeat
         and then Layout /= Other
         and then Full.Width = 128
         and then Full.Height = 128
         and then Map.Layout_Seed (Full) = 42,
         "test layout follows the seed");
   end;

   declare
      package Map renames Megacorp.Map;
      package Gen renames Megacorp.Map.Gen;

      Seed_A : constant Map.City := Gen.Generate (1, Defaults);
      Seed_B : constant Map.City := Gen.Generate (42, Defaults);
      Again  : constant Map.City := Gen.Generate (42, Defaults);
      Seed_C : constant Map.City := Gen.Generate (100, Defaults);

      function Shares_Ok (M : Map.City) return Boolean;
      function Heights_Ok (M : Map.City) return Boolean;

      function Shares_Ok (M : Map.City) return Boolean is
         type Counts is array (Gen.District) of Natural;
         Tally : Counts := (others => 0);
         Total : constant Natural := M.Width * M.Height;
         Zone  : Gen.District;

         function Pct (Which : Gen.District) return Natural;
         function Pct (Which : Gen.District) return Natural is
         begin
            return (Tally (Which) * 100) / Total;
         end Pct;
      begin
         for Y in 1 .. M.Height loop
            for X in 1 .. M.Width loop
               Zone := Gen.District_At
                 (Map.Layout_Seed (M), M.Width, M.Height, X, Y);
               Tally (Zone) := Tally (Zone) + 1;
            end loop;
         end loop;
         return Pct (Gen.Corporate) in 8 .. 16
           and then Pct (Gen.Industrial) in 12 .. 25
           and then Pct (Gen.Slums) in 12 .. 22
           and then Pct (Gen.Residential) in 45 .. 65;
      end Shares_Ok;

      function Heights_Ok (M : Map.City) return Boolean is
         type Seen is array (Gen.District) of Boolean;
         Found : Seen := (others => False);
         Cell  : Map.Tile;
         Zone  : Gen.District;
         Ok    : Boolean := True;
      begin
         for Y in 1 .. M.Height loop
            for X in 1 .. M.Width loop
               Cell := Map.Tile_At (M, X, Y);
               if Cell.Kind = Map.Building then
                  Zone := Gen.District_At
                    (Map.Layout_Seed (M), M.Width, M.Height, X, Y);
                  Ok := Ok
                    and then Cell.Level >= Gen.Min_Storey (Zone)
                    and then Cell.Level <= Gen.Max_Storey (Zone);
                  Found (Zone) := True;
               end if;
            end loop;
         end loop;
         return Ok
           and then Found (Gen.Corporate)
           and then Found (Gen.Residential)
           and then Found (Gen.Industrial)
           and then Found (Gen.Slums);
      end Heights_Ok;

      Drive : constant Megacorp.Path.Result :=
        Megacorp.Path.Find
          (Seed_B,
           (X => 1, Y => 1),
           (X => Seed_B.Width, Y => Seed_B.Height),
           Megacorp.Path.Drive);
   begin
      Smoke_Check.Expect
        (Gen.Roads_Connected (Seed_A)
         and then Gen.Roads_Connected (Seed_B)
         and then Gen.Roads_Connected (Seed_C)
         and then Gen.Foot_Connected (Seed_A)
         and then Gen.Foot_Connected (Seed_B)
         and then Gen.Foot_Connected (Seed_C)
         and then Megacorp.Path.Kind (Drive) = Megacorp.Path.Found,
         "generated roads and sidewalks connect");
      Smoke_Check.Expect
        (Seed_B = Again
         and then Seed_A /= Seed_B
         and then Seed_B /= Seed_C
         and then Map.Layout_Seed (Seed_A) = 1
         and then Map.Layout_Seed (Seed_C) = 100,
         "generated city follows the seed");
      Smoke_Check.Expect
        (Shares_Ok (Seed_A)
         and then Shares_Ok (Seed_B)
         and then Shares_Ok (Seed_C)
         and then Heights_Ok (Seed_A)
         and then Heights_Ok (Seed_B)
         and then Heights_Ok (Seed_C),
         "districts and storeys stay in bounds");
   end;

   declare
      package Map renames Megacorp.Map;
      package Gen renames Megacorp.Mission.Gen;
      use type Ada.Containers.Count_Type;
      use type Megacorp.Mission.Status;

      function Won_Set (Seed : RNG.Word) return Boolean;
      function Won_Set (Seed : RNG.Word) return Boolean is
         City : constant Map.City :=
           Map.Gen.Generate (Seed, Defaults);
         Plan : constant Gen.Scene := Gen.Build (City, Seed);
         Run  : constant Megacorp.Mission.Trace :=
           Gen.Solve (City, Seed);
      begin
         return Run.Outcome.Outcome = Megacorp.Mission.Won
           and then Gen.In_Band (City, Plan)
           and then Gen.Reachable (City, Plan)
           and then Gen.Car_Moved (City, Seed);
      end Won_Set;

      Seen_Light : Boolean := False;
      Seen_Firm  : Boolean := False;
      Seen_Heavy : Boolean := False;
      Sweep : Boolean := True;
      City : constant Map.City :=
        Map.Gen.Generate (42, Defaults);
      First : constant Gen.Scene := Gen.Build (City, 42);
      Again : constant Gen.Scene := Gen.Build (City, 42);
      Run_A : constant Megacorp.Mission.Trace :=
        Gen.Solve (City, 42);
      Run_B : constant Megacorp.Mission.Trace :=
        Gen.Solve (City, 42);
   begin
      for Seed in 1 .. 50 loop
         declare
            Sample : constant Map.City :=
              Map.Gen.Generate (RNG.Word (Seed), Defaults);
            Plan : constant Gen.Scene :=
              Gen.Build (Sample, RNG.Word (Seed));
         begin
            Sweep := Sweep and then Won_Set (RNG.Word (Seed));
            case Plan.Level is
               when Gen.Light =>
                  Seen_Light := True;
               when Gen.Firm =>
                  Seen_Firm := True;
               when Gen.Heavy =>
                  Seen_Heavy := True;
            end case;
         end;
      end loop;
      Smoke_Check.Expect
        (Sweep and then Seen_Light and then Seen_Firm and then Seen_Heavy,
         "generated missions are solvable");
      Smoke_Check.Expect
        (Gen.Same (First, Again)
         and then Run_A.Outcome.Tick = Run_B.Outcome.Tick
         and then Run_A.Frames.Length = Run_B.Frames.Length
         and then Gen.In_Band (City, First)
         and then Gen.Reachable (City, First)
         and then Gen.Car_Moved (City, 42),
         "population and recipe repeat");
   end;

   declare
      package Globe renames Megacorp.World.Gen;
      Home : constant Megacorp.World.Atlas :=
        Globe.Generate (42, Defaults);
      Again : constant Megacorp.World.Atlas :=
        Globe.Generate (42, Defaults);
      Other : constant Megacorp.World.Atlas :=
        Globe.Generate (1, Defaults);
   begin
      Smoke_Check.Expect
        (Home.Regions = 40
         and then Home.Corps = 4
         and then Home.Links > 0
         and then Globe.Connected (Home)
         and then Globe.Distinct_Homes (Home),
         "world has 40 linked regions and 4 corporations");
      Smoke_Check.Expect
        (Globe.Same (Home, Again)
         and then not Globe.Same (Home, Other),
         "world follows the seed");
   end;

   declare
      package Camp renames Megacorp.World.Campaign;
      package Globe renames Megacorp.World.Gen;

      function Owners (Item : Megacorp.World.Atlas) return Boolean;
      function Owners (Item : Megacorp.World.Atlas) return Boolean is
         Total : Natural := 0;
      begin
         for C in 1 .. Item.Corps loop
            Total := Total + Camp.Holdings (Item, C);
         end loop;
         return Total = Item.Regions and then Camp.Coherent (Item);
      end Owners;

      Opened : constant Megacorp.World.Atlas :=
        Globe.Generate (42, Defaults);
      Once : Megacorp.World.Atlas := Opened;
      Twice : Megacorp.World.Atlas := Opened;
      Gone : Megacorp.World.Atlas := Opened;
      Year : Megacorp.World.Atlas;
      Steady : Boolean := True;
   begin
      Camp.Run (Once, 30);
      Camp.Run (Twice, 30);
      for I in 1 .. Gone.Regions loop
         if Gone.Area (I).Owner = 4 then
            Gone.Area (I).Owner := 2;
         end if;
      end loop;
      Camp.Advance (Gone);
      for Seed in 1 .. 20 loop
         Year := Globe.Generate (RNG.Word (Seed), Defaults);
         Camp.Run (Year, 365);
         Steady := Steady
           and then Camp.Coherent (Year)
           and then Camp.Books_Balance
             (Globe.Generate (RNG.Word (Seed), Defaults), Year);
      end loop;
      Smoke_Check.Expect
        (Camp.Books_Balance (Opened, Once)
         and then Camp.Coherent (Once)
         and then Once.Company (1).Cash = Twice.Company (1).Cash
         and then Once.Area (1).Owner = Twice.Area (1).Owner
         and then Once.Company (3).Spent = Twice.Company (3).Spent,
         "campaign books repeat");
      Smoke_Check.Expect
        (Gone.Company (4).Eliminated
         and then Camp.Holdings (Gone, 4) = 0
         and then Owners (Once)
         and then Steady,
         "empty corporations are eliminated");
   end;

   declare
      package Native renames Megacorp.Data.Virtual_FS.Native;
      package Camp renames Megacorp.World.Campaign;
      package Globe renames Megacorp.World.Gen;

      function Match
        (Left, Right : Megacorp.World.Atlas) return Boolean;
      function Match
        (Left, Right : Megacorp.World.Atlas) return Boolean
      is
      begin
         for C in 1 .. Left.Corps loop
            if Left.Company (C).Cash /= Right.Company (C).Cash
              or else Left.Company (C).Eliminated
                /= Right.Company (C).Eliminated
            then
               return False;
            end if;
         end loop;
         for I in 1 .. Left.Regions loop
            if Left.Area (I).Owner /= Right.Area (I).Owner
              or else Left.Area (I).Tax /= Right.Area (I).Tax
              or else Left.Area (I).Unrest /= Right.Area (I).Unrest
              or else Left.Area (I).Defence /= Right.Area (I).Defence
              or else Left.Area (I).Tech /= Right.Area (I).Tech
            then
               return False;
            end if;
         end loop;
         return True;
      end Match;

      function Failed (Name, Expect : String) return Boolean;
      function Failed (Name, Expect : String) return Boolean is
         Root : constant Native.Disk :=
           Native.Open ("/tmp/megacorp-save");
      begin
         declare
            Back : constant Megacorp.Save.Snapshot :=
              Megacorp.Save.Load (Root, Name);
            pragma Unreferenced (Back);
         begin
            return False;
         end;
      exception
         when Error : Megacorp.Save.Save_Error =>
            return Ada.Exceptions.Exception_Message (Error) = Expect;
      end Failed;

      Opened : constant Megacorp.World.Atlas :=
        Globe.Generate (42, Defaults);
      Played : Megacorp.World.Atlas := Opened;
      Fresh : Megacorp.World.Atlas := Opened;
      Whole : Megacorp.World.Atlas := Opened;
      Snap : Megacorp.Save.Snapshot;
      Back : Megacorp.Save.Snapshot;
   begin
      Camp.Run (Played, 5);
      Snap := Megacorp.Save.Capture
        (Played, 5, Params.Auto_Play);
      Snap.Agent (1).Health := 80;
      declare
         City : Megacorp.Map.City :=
           Megacorp.Map.Gen.Generate (Opened.Area (1).City, Defaults);
         Cell : Megacorp.Map.Tile :=
           Megacorp.Map.Tile_At (City, 2, 2);
      begin
         Cell.Kind := Megacorp.Map.Open_Ground;
         Cell.Level := 0;
         Cell.Walkable := True;
         Cell.Drivable := False;
         Megacorp.Save.Damage (Snap, 1, 2, 2, Cell);
         Megacorp.Save.Apply_Patches (Snap, 1, City);
         Smoke_Check.Expect
           (Megacorp.Map.Tile_At (City, 2, 2).Kind
              = Megacorp.Map.Open_Ground
            and then Snap.Area (1).Visited
            and then Megacorp.Save.Bytes (Snap) <= Megacorp.Save.Budget,
            "a ruined tile is a patch under the budget");
      end;
      Ada.Directories.Create_Path ("/tmp/megacorp-save");
      declare
         Root : Native.Disk := Native.Open ("/tmp/megacorp-save");
      begin
         Megacorp.Save.Store (Root, "slot.mgc", Snap);
         Back := Megacorp.Save.Load (Root, "slot.mgc");
      end;
      Smoke_Check.Expect
        (Megacorp.Save.Same (Snap, Back),
         "save round trip");
      declare
         Root : Native.Disk := Native.Open ("/tmp/megacorp-save");
         Raw : constant String := Native.Read (Root, "slot.mgc");
         Mark : Natural := Raw'First;
         Bad : String := Raw;
         Next : String := Raw;
      begin
         while Mark < Raw'Last
           and then Raw (Mark .. Mark + 1) /= "r "
         loop
            Mark := Mark + 1;
         end loop;
         if Bad (Mark + 2) = '1' then
            Bad (Mark + 2) := '2';
         else
            Bad (Mark + 2) := '1';
         end if;
         Native.Write (Root, "bad.mgc", Bad);
         Mark := Raw'First;
         while Mark <= Raw'Last and then Raw (Mark) /= ' ' loop
            Mark := Mark + 1;
         end loop;
         Next (Mark + 1) := '3';
         Native.Write (Root, "next.mgc", Next);
      end;
      Smoke_Check.Expect
        (Failed ("bad.mgc", "checksum mismatch")
         and then Failed ("next.mgc", "wrong format version"),
         "bad saves are rejected");
      Megacorp.Save.Restore (Back, Fresh);
      Camp.Run (Fresh, 5);
      Camp.Run (Whole, 10);
      Smoke_Check.Expect
        (Match (Fresh, Whole),
         "load then continue matches one play");
   end;

   declare
      package Native renames Megacorp.Data.Virtual_FS.Native;
      package Camp renames Megacorp.World.Campaign;
      package Globe renames Megacorp.World.Gen;
      package Journal renames Megacorp.Save.Log;
      use type Megacorp.Save.Mission_Outcome;

      function Match
        (Left, Right : Megacorp.World.Atlas) return Boolean;
      function Match
        (Left, Right : Megacorp.World.Atlas) return Boolean
      is
      begin
         for C in 1 .. Left.Corps loop
            if Left.Company (C).Cash /= Right.Company (C).Cash
              or else Left.Company (C).Eliminated
                /= Right.Company (C).Eliminated
            then
               return False;
            end if;
         end loop;
         for I in 1 .. Left.Regions loop
            if Left.Area (I).Owner /= Right.Area (I).Owner
              or else Left.Area (I).Tax /= Right.Area (I).Tax
              or else Left.Area (I).Unrest /= Right.Area (I).Unrest
              or else Left.Area (I).Defence /= Right.Area (I).Defence
              or else Left.Area (I).Tech /= Right.Area (I).Tech
              or else Left.Area (I).City /= Right.Area (I).City
            then
               return False;
            end if;
         end loop;
         return True;
      end Match;

      function Refused
        (Snap : Megacorp.Save.Snapshot;
         Item : Megacorp.World.Atlas;
         Region : Positive;
         Expect : String) return Boolean;
      function Refused
        (Snap : Megacorp.Save.Snapshot;
         Item : Megacorp.World.Atlas;
         Region : Positive;
         Expect : String) return Boolean
      is
      begin
         declare
            Ev : constant Journal.Event :=
              Journal.Reroll (Snap, Item, Region);
            pragma Unreferenced (Ev);
         begin
            return False;
         end;
      exception
         when Error : Megacorp.Save.Save_Error =>
            return Ada.Exceptions.Exception_Message (Error) = Expect;
      end Refused;

      function Bad_Checksum return Boolean;
      function Bad_Checksum return Boolean is
         Root : constant Native.Disk :=
           Native.Open ("/tmp/megacorp-log");
         Book : Journal.Journal;
      begin
         Book := Journal.Load (Root, "bad.log");
         return Journal.Notice (Book) = "checksum mismatch";
      exception
         when Error : Megacorp.Save.Save_Error =>
            return Ada.Exceptions.Exception_Message (Error)
              = "checksum mismatch";
      end Bad_Checksum;

      Home : Megacorp.World.Atlas := Globe.Generate (42, Defaults);
      Locked : constant Megacorp.Save.Snapshot :=
        Megacorp.Save.Capture (Home, 0, Params.Scenario);
      City_2 : constant RNG.Word := Home.Area (2).City;
      Free : Megacorp.Save.Snapshot :=
        Megacorp.Save.Capture (Home, 0, Params.Free_Play);
      City_8 : constant RNG.Word := Home.Area (8).City;
      Auto : Megacorp.Save.Snapshot :=
        Megacorp.Save.Capture (Home, 0, Params.Auto_Play);
      City_9 : constant RNG.Word := Home.Area (9).City;
      Root : Native.Disk := Native.Open ("/tmp/megacorp-log");
      Book : Journal.Journal;
      Cell : constant Megacorp.Map.Tile :=
        (Kind => Megacorp.Map.Open_Ground,
         Level => 0,
         Walkable => True,
         Drivable => False);
   begin
      Ada.Directories.Create_Path ("/tmp/megacorp-log");
      Smoke_Check.Expect
        (Refused (Locked, Home, 2, "scenario refuses re-roll")
         and then Home.Area (2).City = City_2,
         "a scenario refuses re-roll");

      Book := Journal.Start (Root, "roll.log", Auto);
      Journal.Commit
        (Root, "roll.log", Auto, Home, Book,
         Journal.Reroll (Auto, Home, 9));
      Smoke_Check.Expect
        (Home.Area (9).City /= City_9
         and then Auto.Area (9).Has_City,
         "auto-play re-rolls an unvisited region");
      Journal.Commit
        (Root, "roll.log", Auto, Home, Book,
         Journal.Tile_Change (9, 2, 2, Cell));
      declare
         Kept : constant RNG.Word := Home.Area (9).City;
      begin
         Smoke_Check.Expect
           (Auto.Area (9).Visited
            and then Refused
              (Auto, Home, 9, "visited region stays")
            and then Home.Area (9).City = Kept,
            "a visited region stays as left");
      end;

      Book := Journal.Start (Root, "free.log", Free);
      Journal.Commit
        (Root, "free.log", Free, Home, Book,
         Journal.Reroll (Free, Home, 8));
      Smoke_Check.Expect
        (Home.Area (8).City /= City_8
         and then Free.Area (8).Has_City
         and then not Free.Area (8).Visited,
         "free play re-rolls only an unvisited region");
      Journal.Commit
        (Root, "free.log", Free, Home, Book,
         Journal.Tile_Change (8, 3, 3, Cell));
      declare
         Kept : constant RNG.Word := Home.Area (8).City;
         City : Megacorp.Map.City :=
           Megacorp.Map.Gen.Generate (Kept, Defaults);
      begin
         Megacorp.Save.Apply_Patches (Free, 8, City);
         Smoke_Check.Expect
           (Free.Area (8).Visited
            and then Refused
              (Free, Home, 8, "visited region stays")
            and then Home.Area (8).City = Kept
            and then Megacorp.Map.Tile_At (City, 3, 3).Kind
              = Megacorp.Map.Open_Ground,
            "a visited region keeps its patch");
      end;

      declare
         Left : Megacorp.World.Atlas :=
           Globe.Generate (42, Defaults);
         Right : Megacorp.World.Atlas := Left;
         Snap : Megacorp.Save.Snapshot :=
           Megacorp.Save.Capture
             (Right, 0, Params.Auto_Play);
      begin
         Left.Area (1).Tax := 40;
         Camp.Advance (Left);
         Book := Journal.Start (Root, "tax.log", Snap);
         Journal.Commit
           (Root, "tax.log", Snap, Right, Book,
            Journal.Day_Tax (1, 40));
         Smoke_Check.Expect
           (Match (Left, Right) and then Snap.Day = 1,
            "a day tick carries its tax input");
      end;

      declare
         Marked : Megacorp.World.Atlas :=
           Globe.Generate (42, Defaults);
         Again : Megacorp.World.Atlas :=
           Globe.Generate (42, Defaults);
         Snap : Megacorp.Save.Snapshot :=
           Megacorp.Save.Capture (Marked, 0, Params.Free_Play);
         Back : Megacorp.Save.Snapshot :=
           Megacorp.Save.Capture (Again, 0, Params.Free_Play);
      begin
         Marked.Area (2).Tax := 15;
         Book := Journal.Start (Root, "mark.log", Snap);
         Journal.Commit
           (Root, "mark.log", Snap, Marked, Book,
            Journal.Region_Set (Snap, Marked, 2));
         Journal.Commit
           (Root, "mark.log", Snap, Marked, Book,
            Journal.Mission_Done (4, Megacorp.Save.Won, 83));
         Journal.Commit
           (Root, "mark.log", Snap, Marked, Book,
            Journal.Squad_Change (1, 70, 9, 1));
         Book := Journal.Load (Root, "mark.log");
         Journal.Replay (Back, Again, Book);
         Smoke_Check.Expect
           (Megacorp.Save.Same (Snap, Back)
            and then Again.Area (2).Tax = 15
            and then Back.Area (4).Visited
            and then Back.Mission (1).Outcome = Megacorp.Save.Won
            and then Back.Agent (1).Health = 70,
            "region, mission, and squad records replay");
      end;

      declare
         Lived : Megacorp.World.Atlas :=
           Globe.Generate (42, Defaults);
         Straight : Megacorp.World.Atlas := Lived;
         Again : Megacorp.World.Atlas :=
           Globe.Generate (42, Defaults);
         Snap : Megacorp.Save.Snapshot :=
           Megacorp.Save.Capture (Lived, 0, Params.Auto_Play);
         Back : Megacorp.Save.Snapshot :=
           Megacorp.Save.Capture (Again, 0, Params.Auto_Play);
      begin
         Book := Journal.Start (Root, "play.log", Snap);
         for Step in 1 .. 6 loop
            Journal.Commit
              (Root, "play.log", Snap, Lived, Book,
               Journal.Day_None);
         end loop;
         Camp.Run (Straight, 6);
         Book := Journal.Load (Root, "play.log");
         Journal.Replay (Back, Again, Book);
         Smoke_Check.Expect
           (Match (Lived, Straight)
            and then Match (Again, Straight)
            and then Megacorp.Save.Same (Snap, Back)
            and then Snap.Day = 6,
            "snapshot plus log equals continuous play");
      end;

      declare
         Lived : Megacorp.World.Atlas :=
           Globe.Generate (3, Defaults);
         Again : Megacorp.World.Atlas :=
           Globe.Generate (3, Defaults);
         Straight : Megacorp.World.Atlas := Again;
         Snap : Megacorp.Save.Snapshot :=
           Megacorp.Save.Capture (Lived, 0, Params.Auto_Play);
         Back : Megacorp.Save.Snapshot :=
           Megacorp.Save.Capture (Again, 0, Params.Auto_Play);
      begin
         Book := Journal.Start (Root, "torn.log", Snap);
         for Step in 1 .. 3 loop
            Journal.Commit
              (Root, "torn.log", Snap, Lived, Book,
               Journal.Day_None);
         end loop;
         Native.Append (Root, "torn.log", "day none");
         Book := Journal.Load (Root, "torn.log");
         Smoke_Check.Expect
           (Journal.Notice (Book) = "torn delta record dropped"
            and then Journal.Count (Book) = 3,
            "a torn tail is reported");
         Journal.Rewrite (Root, "torn.log", Back, Book);
         Book := Journal.Load (Root, "torn.log");
         Journal.Replay (Back, Again, Book);
         Camp.Run (Straight, 3);
         Smoke_Check.Expect
           (Journal.Notice (Book) = ""
            and then Match (Again, Straight)
            and then Megacorp.Save.Same (Snap, Back),
            "a torn tail is recovered");
      end;

      declare
         Raw : constant String := Native.Read (Root, "torn.log");
         Bad : String := Raw;
         Mark : Natural := Raw'First;
      begin
         while Mark < Raw'Last - 3
           and then Raw (Mark .. Mark + 3) /= "day "
         loop
            Mark := Mark + 1;
         end loop;
         Bad (Mark) := 'D';
         Native.Write (Root, "bad.log", Bad);
      end;
      Smoke_Check.Expect
        (Bad_Checksum, "a bad middle checksum is rejected");

      declare
         Lived : Megacorp.World.Atlas :=
           Globe.Generate (5, Defaults);
         Straight : Megacorp.World.Atlas :=
           Globe.Generate (5, Defaults);
         Again : Megacorp.World.Atlas := Straight;
         Snap : Megacorp.Save.Snapshot :=
           Megacorp.Save.Capture (Lived, 0, Params.Auto_Play);
         Cash : Natural;
      begin
         Megacorp.Save.Store (Root, "fold.mgc", Snap);
         Book := Journal.Start (Root, "fold.log", Snap);
         for Step in 1 .. 5 loop
            Journal.Commit
              (Root, "fold.log", Snap, Lived, Book,
               Journal.Day_None);
         end loop;
         Camp.Run (Straight, 5);
         declare
            Old : constant String := Native.Read (Root, "fold.log");
         begin
            Journal.Compact
              (Root, "fold.mgc", "fold.log", Snap, Book);
            Smoke_Check.Expect
              (Journal.Count (Book) = 0 and then Snap.Day = 5,
               "compaction clears the log");
            Snap := Megacorp.Save.Load (Root, "fold.mgc");
            Megacorp.Save.Restore (Snap, Again);
            Smoke_Check.Expect
              (Match (Again, Straight) and then Match (Lived, Straight),
               "compaction matches continuous play");
            Native.Write (Root, "fold.log", Old);
            Book := Journal.Load (Root, "fold.log");
            Cash := Again.Company (1).Cash;
            Journal.Replay (Snap, Again, Book);
            Smoke_Check.Expect
              (Journal.Notice (Book) = "delta base mismatch"
               and then Again.Company (1).Cash = Cash,
               "a log for an older snapshot is not replayed");
         end;
      end;

      declare
         Lived : Megacorp.World.Atlas :=
           Globe.Generate (9, Defaults);
         Straight : Megacorp.World.Atlas :=
           Globe.Generate (9, Defaults);
         Again : Megacorp.World.Atlas := Straight;
         Snap : Megacorp.Save.Snapshot :=
           Megacorp.Save.Capture (Lived, 0, Params.Auto_Play);
      begin
         Book := Journal.Start (Root, "year.log", Snap);
         for Step in 1 .. Journal.Compact_After loop
            Journal.Commit
              (Root, "year.log", Snap, Lived, Book,
               Journal.Day_None);
            if Journal.Due (Book) then
               Journal.Compact
                 (Root, "year.mgc", "year.log", Snap, Book);
            end if;
         end loop;
         Camp.Run (Straight, Journal.Compact_After);
         Snap := Megacorp.Save.Load (Root, "year.mgc");
         Megacorp.Save.Restore (Snap, Again);
         Smoke_Check.Expect
           (Journal.Count (Book) = 0
            and then Snap.Day = Journal.Compact_After
            and then Match (Lived, Straight)
            and then Match (Again, Straight),
            "a full log compacts to the same world");
      end;
   end;

   declare
      package Native renames Megacorp.Data.Virtual_FS.Native;
      package Camp renames Megacorp.World.Campaign;
      package Globe renames Megacorp.World.Gen;
      package Journal renames Megacorp.Save.Log;
      package Move renames Megacorp.Save.Migrate;

      function Match
        (Left, Right : Megacorp.World.Atlas) return Boolean;
      function Match
        (Left, Right : Megacorp.World.Atlas) return Boolean
      is
      begin
         for C in 1 .. Left.Corps loop
            if Left.Company (C).Cash /= Right.Company (C).Cash
              or else Left.Company (C).Eliminated
                /= Right.Company (C).Eliminated
            then
               return False;
            end if;
         end loop;
         for I in 1 .. Left.Regions loop
            if Left.Area (I).Owner /= Right.Area (I).Owner
              or else Left.Area (I).Tax /= Right.Area (I).Tax
              or else Left.Area (I).Unrest /= Right.Area (I).Unrest
              or else Left.Area (I).Defence /= Right.Area (I).Defence
              or else Left.Area (I).Tech /= Right.Area (I).Tech
              or else Left.Area (I).City /= Right.Area (I).City
            then
               return False;
            end if;
         end loop;
         return True;
      end Match;

      function Rejected (Name, Expect : String) return Boolean;
      function Rejected (Name, Expect : String) return Boolean is
         Root : constant Native.Disk :=
           Native.Open ("/tmp/megacorp-migrate");
         Back : Megacorp.Save.Snapshot;
      begin
         Back := Megacorp.Save.Load (Root, Name);
         return Back.Day = Natural'Last;
      exception
         when Error : Megacorp.Save.Save_Error =>
            return Ada.Exceptions.Exception_Message (Error) = Expect;
      end Rejected;

      Root : constant Native.Disk := Native.Open ("tests");
      Snap : Megacorp.Save.Snapshot;
   begin
      Ada.Directories.Create_Path ("/tmp/megacorp-migrate");
      Smoke_Check.Expect
        (Move.Note (1, 2) = "migrated save from version 1 to 2",
         "migration note");
      declare
         Raw : constant String := Native.Read (Root, "v1-slot.mgc");
         Next : constant String := Move.To_Current (Raw);
         Study : Boolean := True;
      begin
         Snap := Megacorp.Save.Load (Root, "v1-slot.mgc");
         for C in 1 .. Snap.Corps loop
            Study := Study and then Snap.Company (C).Research = 0;
         end loop;
         Smoke_Check.Expect
           (Move.Listed_Version (Raw) = 1
            and then Move.Listed_Version (Next) = 2
            and then Move.Sum_Ok (Next)
            and then Move.To_Current (Next) = Next
            and then Ada.Strings.Fixed.Index (Next, "algorithm 1") > 0
            and then Snap.Algorithm = Globe.Current_Algorithm
            and then Snap.Day = 0
            and then Snap.Stamp (1 .. Snap.Stamp_Len) = "0.18.0"
            and then Study,
            "a v1 fixture migrates to v2");
      end;
      declare
         Played : Megacorp.World.Atlas :=
           Megacorp.Save.Rebuild (Snap, Defaults);
         Straight : Megacorp.World.Atlas :=
           Globe.Generate (42, Defaults);
         Book : Journal.Journal :=
           Journal.Load (Root, "v1-slot.log");
      begin
         Journal.Replay (Snap, Played, Book);
         Camp.Run (Straight, 4);
         Smoke_Check.Expect
           (Journal.Notice (Book) = ""
            and then Snap.Day = 4
            and then Match (Played, Straight),
            "a v1 log replays after migration");
      end;
      declare
         World : constant Megacorp.World.Atlas :=
           Globe.Generate (42, Defaults);
         Disk : Native.Disk :=
           Native.Open ("/tmp/megacorp-migrate");
         Back : Megacorp.Save.Snapshot;
         Raw : String (1 .. 8192);
         Last : Natural;
         Mark : Natural;
      begin
         Snap := Megacorp.Save.Capture
           (World, 0, Params.Auto_Play);
         Snap.Company (1).Research := 5;
         Megacorp.Save.Store (Disk, "v2.mgc", Snap);
         Back := Megacorp.Save.Load (Disk, "v2.mgc");
         Smoke_Check.Expect
           (Megacorp.Save.Same (Snap, Back)
            and then Back.Company (1).Research = 5
            and then Back.Algorithm = 1,
            "a v2 snapshot round-trips");
         declare
            Text : constant String := Native.Read (Disk, "v2.mgc");
         begin
            Last := Text'Length;
            Raw (1 .. Last) := Text;
         end;
         Mark := Raw'First;
         while Mark <= Last and then Raw (Mark) /= ' ' loop
            Mark := Mark + 1;
         end loop;
         Raw (Mark + 1) := '3';
         Native.Write (Disk, "future.mgc", Raw (1 .. Last));
         Smoke_Check.Expect
           (Rejected ("future.mgc", "wrong format version"),
            "a future format version is refused");
      end;
      declare
         Old : constant Megacorp.World.Atlas :=
           Globe.Generate (42, Defaults, 1);
         Next : constant Megacorp.World.Atlas :=
           Globe.Generate (42, Defaults, 2);
         Held : Megacorp.Save.Snapshot :=
           Megacorp.Save.Capture (Next, 0, Params.Auto_Play, 2);
         Built : constant Megacorp.World.Atlas :=
           Megacorp.Save.Rebuild (Held, Defaults);
         Raised : Boolean := False;
      begin
         Smoke_Check.Expect
           (Old.Area (1).City /= Next.Area (1).City
            and then not Held.Area (1).Has_City
            and then Built.Area (1).City = Next.Area (1).City
            and then Built.Area (1).City /= Old.Area (1).City,
            "the stamped generator version is honoured");
         Held.Algorithm := 9;
         begin
            declare
               Ignored : constant Megacorp.World.Atlas :=
                 Megacorp.Save.Rebuild (Held, Defaults);
               pragma Unreferenced (Ignored);
            begin
               Raised := False;
            end;
         exception
            when Error : Megacorp.Save.Save_Error =>
               Raised :=
                 Ada.Exceptions.Exception_Message (Error)
                   = "unknown generator version";
         end;
         Smoke_Check.Expect
           (Raised, "an unknown generator version is refused");
      end;
   end;

   declare
      package Native renames Megacorp.Data.Virtual_FS.Native;
      package Tiles renames Megacorp.Assets.Placeholder;
      use type Ada.Containers.Count_Type;

      Store : constant Native.Disk := Native.Open ("../web");
      Names : constant Megacorp.Data.Virtual_FS.Name_Lists.Vector :=
        Native.List (Store, "assets");
      Text  : constant String :=
        Native.Read (Store, "assets/tiles.json");
      Set   : constant Tiles.Tileset := Tiles.Load (Store);
      Listed_Index : Boolean := False;
      Listed_Atlas : Boolean := False;
      Ids_Ok : Boolean := True;
   begin
      if Names.Length > 0 then
         for I in 1 .. Positive (Names.Length) loop
            if Names.Element (I) = "tiles.json" then
               Listed_Index := True;
            elsif Names.Element (I) = "atlas.png" then
               Listed_Atlas := True;
            end if;
         end loop;
      end if;
      Smoke_Check.Expect
        (Native.Exists (Store, "assets/tiles.json")
         and then Ada.Strings.Fixed.Index (Text, """tile_width""") > 0
         and then Listed_Index
         and then Listed_Atlas
         and then not Native.Exists (Store, "assets/missing.txt")
         and then not Native.Exists (Store, "../secret"),
         "virtual file system");
      Raised := False;
      begin
         declare
            Ignored : constant String :=
              Native.Read (Store, "assets/missing.txt");
         begin
            Smoke_Check.Discard (Ignored'Length);
         end;
      exception
         when Ada.Assertions.Assertion_Error =>
            Raised := True;
      end;
      Smoke_Check.Expect (Raised, "missing file is not readable");
      for Kind in Megacorp.Map.Terrain loop
         for Level in Megacorp.Map.Height_Level loop
            Ids_Ok := Ids_Ok
              and then Tiles.Tile_Id (Set, Kind, Level)
                = Megacorp.Map.Terrain'Pos (Kind) * 16 + Level;
         end loop;
      end loop;
      Smoke_Check.Expect
        (Tiles.Complete (Set) and then Ids_Ok,
         "placeholder tile index");
   end;

   declare
      package Map renames Megacorp.Map;
      package Route renames Megacorp.Path;

      Road_Tile : constant Map.Tile :=
        (Kind => Map.Road, Level => 1,
         Walkable => True, Drivable => True);
      Block_Tile : constant Map.Tile :=
        (Kind => Map.Building, Level => 2,
         Walkable => False, Drivable => False);
      Water_Tile : constant Map.Tile :=
        (Kind => Map.Water, Level => 0,
         Walkable => False, Drivable => False);

      Straight : constant Map.City := Map.Blank (1, 6);
      Around   : Map.City := Map.Blank (5, 5);
      River    : Map.City := Map.Blank (5, 3);
      Roads    : Map.City := Map.Blank (5, 5);
      Line     : Route.Result;
      Again    : Route.Result;
      Detour   : Route.Result;
      Blocked  : Route.Result;
      Driven   : Route.Result;
      Tight    : Route.Result;
      On_Road  : Boolean := True;
      Goes_Around : Boolean := False;
   begin
      Line := Route.Find
        (Straight, (X => 1, Y => 1), (X => 1, Y => 6),
         Route.Walk, 100);
      Again := Route.Find
        (Straight, (X => 1, Y => 1), (X => 1, Y => 6),
         Route.Walk, 100);
      Smoke_Check.Expect
        (Route.Kind (Line) = Route.Found
         and then Route.Length (Line) = 6
         and then Route.Step (Line, 1) = (X => 1, Y => 1)
         and then Route.Step (Line, 6) = (X => 1, Y => 6)
         and then Line = Again,
         "straight path is stable");

      for Y in 1 .. 4 loop
         Map.Set_Tile (Around, 3, Y, Block_Tile);
      end loop;
      Detour := Route.Find
        (Around, (X => 2, Y => 2), (X => 4, Y => 2),
         Route.Walk, 100);
      if Route.Kind (Detour) = Route.Found then
         for I in 1 .. Route.Length (Detour) loop
            if Route.Step (Detour, I).Y = 5 then
               Goes_Around := True;
            end if;
         end loop;
      end if;
      Smoke_Check.Expect
        (Route.Kind (Detour) = Route.Found and then Goes_Around,
         "walk routes around buildings");

      for Y in 1 .. 3 loop
         Map.Set_Tile (River, 3, Y, Water_Tile);
      end loop;
      Blocked := Route.Find
        (River, (X => 1, Y => 2), (X => 5, Y => 2),
         Route.Walk, 100);
      Smoke_Check.Expect
        (Route.Kind (Blocked) = Route.No_Path,
         "no walk path across water");

      for I in 1 .. 5 loop
         Map.Set_Tile (Roads, I, 1, Road_Tile);
         Map.Set_Tile (Roads, I, 5, Road_Tile);
         Map.Set_Tile (Roads, 1, I, Road_Tile);
         Map.Set_Tile (Roads, 5, I, Road_Tile);
      end loop;
      Driven := Route.Find
        (Roads, (X => 1, Y => 1), (X => 5, Y => 5),
         Route.Drive, 100);
      if Route.Kind (Driven) = Route.Found then
         for I in 1 .. Route.Length (Driven) loop
            On_Road := On_Road
              and then Map.Tile_At
                (Roads,
                 Route.Step (Driven, I).X,
                 Route.Step (Driven, I).Y).Drivable;
         end loop;
      else
         On_Road := False;
      end if;
      Smoke_Check.Expect (On_Road, "drive stays on roads");

      Tight := Route.Find
        (Straight, (X => 1, Y => 1), (X => 1, Y => 6),
         Route.Walk, 2);
      Smoke_Check.Expect
        (Route.Kind (Tight) = Route.Budget_Exceeded,
         "search stops at the budget");
   end;

   declare
      package Map renames Megacorp.Map;
      package Peds renames Megacorp.Peds;
      use type Ada.Containers.Count_Type;
      use type Peds.Frame_Lists.Vector;
      use type Peds.State_Kind;

      Lane : constant Map.City := Map.Blank (1, 6);
      Hall : constant Map.City := Map.Blank (5, 3);
      One  : constant Peds.Ped :=
        Peds.Spawn
          (1, (X => 1, Y => 1), (X => 1, Y => 6), Lane);
      Due  : constant Natural :=
        5 * Peds.Ticks_To_Cross (Peds.Default_Speed);
      First : constant Peds.Frame_Lists.Vector :=
        Peds.Run (Lane, (1 => One), Due);
      Again : constant Peds.Frame_Lists.Vector :=
        Peds.Run (Lane, (1 => One), Due);
      East : constant Peds.Ped :=
        Peds.Spawn
          (1, (X => 1, Y => 2), (X => 5, Y => 2), Hall);
      West : constant Peds.Ped :=
        Peds.Spawn
          (2, (X => 5, Y => 2), (X => 1, Y => 2), Hall);
      Meet : constant Peds.Frame_Lists.Vector :=
        Peds.Run (Hall, (1 => East, 2 => West), 400);
      Same : constant Peds.Frame_Lists.Vector :=
        Peds.Run (Hall, (1 => East, 2 => West), 400);
      On_Time : Boolean := False;
      Still_Going : Boolean := False;
      Shared : Boolean := False;
      East_Home : Boolean := False;
      West_Home : Boolean := False;
   begin
      for I in First.First_Index .. First.Last_Index loop
         if First (I).Tick = Due
           and then First (I).State = Peds.Arrived
           and then First (I).X = 1
           and then First (I).Y = 6
         then
            On_Time := True;
         end if;
         if First (I).Tick = Due - 1
           and then First (I).State /= Peds.Arrived
         then
            Still_Going := True;
         end if;
      end loop;
      Smoke_Check.Expect
        (First.Length = Ada.Containers.Count_Type (Due + 1)
         and then On_Time
         and then Still_Going
         and then First = Again,
         "ped arrives on the expected tick");

      for I in Meet.First_Index .. Meet.Last_Index loop
         for J in I + 1 .. Meet.Last_Index loop
            if Meet (I).Tick = Meet (J).Tick
              and then Meet (I).X = Meet (J).X
              and then Meet (I).Y = Meet (J).Y
            then
               Shared := True;
            end if;
         end loop;
         if Meet (I).Ident = 1
           and then Meet (I).State = Peds.Arrived
           and then Meet (I).X = 5
           and then Meet (I).Y = 2
         then
            East_Home := True;
         end if;
         if Meet (I).Ident = 2
           and then Meet (I).State = Peds.Arrived
           and then Meet (I).X = 1
           and then Meet (I).Y = 2
         then
            West_Home := True;
         end if;
      end loop;
      Smoke_Check.Expect
        (not Shared
         and then East_Home
         and then West_Home
         and then Meet = Same,
         "two peds pass and both arrive");
   end;

   declare
      package Map renames Megacorp.Map;
      package Peds renames Megacorp.Peds;
      package Act renames Megacorp.Actions;
      use type Act.Kind;
      use type Act.Shot_Lists.Vector;
      use type Map.Eight_Way;
      use type Peds.State_Kind;

      Lane : constant Map.City := Map.Blank (1, 6);
      Open : constant Map.City := Map.Blank (3, 3);
      Hall : constant Map.City := Map.Blank (6, 3);
      Wall : Map.City := Map.Blank (5, 3);
      Water_Tile : constant Map.Tile :=
        (Kind => Map.Water, Level => 0,
         Walkable => False, Drivable => False);
      Solo : Act.Cast (1 .. 1);
      Pair : Act.Cast (1 .. 2);
      Waiter : Act.Cast (1 .. 1);
      Extra : Act.Cast (1 .. 1);
      Blocked : Act.Cast (1 .. 1);
      Case_Item : Act.Bag (1 .. 1);
      Gear : Act.Bag (1 .. 1);
      First : Act.Shot_Lists.Vector;
      Again : Act.Shot_Lists.Vector;
      Meet : Act.Shot_Lists.Vector;
      Same : Act.Shot_Lists.Vector;
      Phase : Natural := 0;
      Ordered : Boolean := True;
      Picked : Boolean := False;
      At_Case : Boolean := False;
      Saw_Follow : Boolean := False;
   begin
      Case_Item (1) := (Ident => 1, X => 1, Y => 4, Here => True);
      Solo (1) := Act.Recruit (1, (X => 1, Y => 1), Lane);
      Act.Order
        (Solo, 1,
         (1 => Act.Make_Walk ((X => 1, Y => 2)),
          2 => Act.Make_Wait (2),
          3 => Act.Make_Turn (Map.North),
          4 => Act.Make_Walk ((X => 1, Y => 4)),
          5 => Act.Make_Pick (1)),
         Act.Replace);
      First := Act.Run (Lane, Solo, Case_Item, 80);
      Again := Act.Run (Lane, Solo, Case_Item, 80);
      for I in First.First_Index .. First.Last_Index loop
         if First (I).Has_Action then
            declare
               Text : constant String :=
                 Act.Token_Strings.To_String (First (I).Action);
            begin
               if Text'Length >= 7
                 and then Text (Text'First .. Text'First + 6) = "walk_to"
               then
                  if Phase = 0 then
                     Phase := 1;
                  elsif Phase = 3 then
                     Phase := 4;
                  elsif Phase /= 1 and then Phase /= 4 then
                     Ordered := False;
                  end if;
               elsif Text'Length >= 4
                 and then Text (Text'First .. Text'First + 3) = "wait"
               then
                  if Phase = 1 then
                     Phase := 2;
                  elsif Phase /= 2 then
                     Ordered := False;
                  end if;
               elsif Text'Length >= 7
                 and then Text (Text'First .. Text'First + 6) = "turn_to"
               then
                  if Phase = 2 then
                     Phase := 3;
                  elsif Phase /= 3 then
                     Ordered := False;
                  end if;
               elsif Text'Length >= 7
                 and then Text (Text'First .. Text'First + 6) = "pick_up"
               then
                  if Phase = 4 then
                     Phase := 5;
                  else
                     Ordered := False;
                  end if;
               end if;
            end;
         end if;
         if not First (I).Item_Here
           and then First (I).X = 1
           and then First (I).Y = 4
         then
            Picked := True;
         end if;
      end loop;
      Smoke_Check.Expect
        (Ordered and then Phase = 5 and then Picked
         and then First = Again,
         "actions run in order");

      for Y in 1 .. 3 loop
         Map.Set_Tile (Wall, 3, Y, Water_Tile);
      end loop;
      Blocked (1) := Act.Recruit (1, (X => 1, Y => 2), Wall);
      Act.Order
        (Blocked, 1,
         (1 => Act.Make_Walk ((X => 5, Y => 2)),
          2 => Act.Make_Wait (3)),
         Act.Replace);
      Smoke_Check.Expect
        (Act.Length (Blocked (1)) = 0
         and then Act.Is_Pending (Blocked (1)),
         "order waits for the next tick");
      Act.Tick (Blocked, Wall, Case_Item);
      Smoke_Check.Expect
        (Act.Length (Blocked (1)) = 0
         and then not Act.Is_Pending (Blocked (1))
         and then Act.Ped_State (Blocked (1)) = Peds.Standing
         and then Act.Ped_X (Blocked (1)) = 1
         and then Act.Ped_Y (Blocked (1)) = 2,
         "failed walk clears the queue");

      Waiter (1) := Act.Recruit (1, (X => 2, Y => 2), Open);
      Act.Order
        (Waiter, 1,
         (1 => Act.Make_Wait (5),
          2 => Act.Make_Turn (Map.South)),
         Act.Replace);
      Act.Tick (Waiter, Open, Case_Item);
      Act.Order
        (Waiter, 1,
         (1 => Act.Make_Turn (Map.North)),
         Act.Replace);
      Smoke_Check.Expect
        (Act.Is_Pending (Waiter (1))
         and then Act.Length (Waiter (1)) = 2
         and then Act.Front (Waiter (1)).Which = Act.Wait
         and then Act.Ped_Facing (Waiter (1)) = Map.South,
         "replace is still pending");
      Act.Tick (Waiter, Open, Case_Item);
      Smoke_Check.Expect
        (not Act.Is_Pending (Waiter (1))
         and then Act.Length (Waiter (1)) = 0
         and then Act.Ped_Facing (Waiter (1)) = Map.North,
         "replace takes effect on the next tick");

      Extra (1) := Act.Recruit (1, (X => 2, Y => 2), Open);
      Act.Order
        (Extra, 1, (1 => Act.Make_Wait (4)), Act.Replace);
      Act.Tick (Extra, Open, Case_Item);
      Act.Order
        (Extra, 1, (1 => Act.Make_Turn (Map.East)), Act.Append);
      Smoke_Check.Expect
        (Act.Is_Pending (Extra (1))
         and then Act.Length (Extra (1)) = 1
         and then Act.Front (Extra (1)).Which = Act.Wait,
         "append waits for the next tick");
      Act.Tick (Extra, Open, Case_Item);
      Smoke_Check.Expect
        (not Act.Is_Pending (Extra (1))
         and then Act.Length (Extra (1)) = 2
         and then Act.Front (Extra (1)).Which = Act.Wait
         and then Act.At_Queue (Extra (1), 2).Which = Act.Turn_To,
         "append adds to the queue");

      Gear (1) := (Ident => 1, X => 6, Y => 2, Here => True);
      Pair (1) := Act.Recruit (1, (X => 1, Y => 2), Hall);
      Pair (2) := Act.Recruit (2, (X => 1, Y => 1), Hall);
      Act.Order
        (Pair, 1,
         (1 => Act.Make_Walk ((X => 4, Y => 2))),
         Act.Replace);
      Act.Order
        (Pair, 2,
         (1 => Act.Make_Walk ((X => 1, Y => 3)),
          2 => Act.Make_Wait (1),
          3 => Act.Make_Turn (Map.East),
          4 => Act.Make_Follow (1),
          5 => Act.Make_Walk ((X => 6, Y => 2)),
          6 => Act.Make_Pick (1)),
         Act.Replace);
      Meet := Act.Run (Hall, Pair, Gear, 400);
      Same := Act.Run (Hall, Pair, Gear, 400);
      for I in Meet.First_Index .. Meet.Last_Index loop
         if Meet (I).Has_Action then
            declare
               Text : constant String :=
                 Act.Token_Strings.To_String (Meet (I).Action);
            begin
               if Text'Length >= 6
                 and then Text (Text'First .. Text'First + 5) = "follow"
               then
                  Saw_Follow := True;
               end if;
            end;
         end if;
         if not Meet (I).Item_Here
           and then Meet (I).X = 6
           and then Meet (I).Y = 2
         then
            At_Case := True;
         end if;
      end loop;
      Smoke_Check.Expect
        (Saw_Follow and then At_Case and then Meet = Same,
         "follow then pick up, traces match");
   end;

   declare
      package Map renames Megacorp.Map;
      package Peds renames Megacorp.Peds;
      package Act renames Megacorp.Actions;
      package Guns renames Megacorp.Weapons;
      use type Act.Shot_Lists.Vector;

      Lane : constant Map.City := Map.Blank (3, 1);
      Far  : constant Map.City := Map.Blank (30, 1);
      Wall : Map.City := Map.Blank (5, 3);
      Brick : constant Map.Tile :=
        (Kind => Map.Building, Level => 3,
         Walkable => False, Drivable => False);
      Pair : Act.Cast (1 .. 2);
      Empty : Act.Bag (1 .. 1);
      First : Act.Shot_Lists.Vector;
      Again : Act.Shot_Lists.Vector;
      Target_Hp : Natural;
      Shooter_Ammo : Natural;
      Target_Alive : Boolean;
      Saw_Wait : Boolean;
   begin
      Empty (1) := (Ident => 1, X => 1, Y => 1, Here => False);
      for Y in 1 .. 3 loop
         Map.Set_Tile (Wall, 3, Y, Brick);
      end loop;
      Pair (1) := Act.Recruit (1, (X => 1, Y => 2), Wall, 9);
      Pair (2) := Act.Recruit (2, (X => 5, Y => 2), Wall, 9);
      Act.Arm (Pair, 1, Guns.Pistol, Guns.Profile (Guns.Pistol).Magazine);
      Act.Order
        (Pair, 1, (1 => Act.Make_Shoot (2, Guns.Pistol)), Act.Replace);
      First := Act.Run (Wall, Pair, Empty, 30);
      Again := Act.Run (Wall, Pair, Empty, 30);
      Target_Hp := 0;
      Shooter_Ammo := 0;
      for I in First.First_Index .. First.Last_Index loop
         if First (I).Ident = 2 then
            Target_Hp := First (I).Health;
         elsif First (I).Ident = 1 then
            Shooter_Ammo := First (I).Ammo;
         end if;
      end loop;
      Smoke_Check.Expect
        (Target_Hp = Peds.Full_Health
         and then Shooter_Ammo = Guns.Profile (Guns.Pistol).Magazine
         and then First = Again,
         "a wall blocks the shot");

      Pair (1) := Act.Recruit (1, (X => 1, Y => 1), Far, 9);
      Pair (2) := Act.Recruit (2, (X => 25, Y => 1), Far, 9);
      Act.Arm (Pair, 1, Guns.Pistol, Guns.Profile (Guns.Pistol).Magazine);
      Act.Order
        (Pair, 1,
         (1 => Act.Make_Shoot (2, Guns.Pistol),
          2 => Act.Make_Wait (4)),
         Act.Replace);
      First := Act.Run (Far, Pair, Empty, 20);
      Target_Hp := 0;
      Saw_Wait := False;
      for I in First.First_Index .. First.Last_Index loop
         if First (I).Ident = 2 then
            Target_Hp := First (I).Health;
         end if;
         if First (I).Ident = 1 and then First (I).Has_Action then
            declare
               Text : constant String :=
                 Act.Token_Strings.To_String (First (I).Action);
            begin
               if Text'Length >= 4
                 and then Text (Text'First .. Text'First + 3) = "wait"
               then
                  Saw_Wait := True;
               end if;
            end;
         end if;
      end loop;
      Smoke_Check.Expect
        (Target_Hp = Peds.Full_Health and then not Saw_Wait,
         "out of range fails and clears the queue");

      Pair (1) := Act.Recruit (1, (X => 1, Y => 1), Lane, 9);
      Pair (2) := Act.Recruit (2, (X => 2, Y => 1), Lane, 9);
      Act.Arm (Pair, 1, Guns.Pistol, 2);
      Act.Order
        (Pair, 2, (1 => Act.Make_Wait (30)), Act.Replace);
      Act.Order
        (Pair, 1, (1 => Act.Make_Shoot (2, Guns.Pistol)), Act.Replace);
      First := Act.Run (Lane, Pair, Empty, 40);
      Again := Act.Run (Lane, Pair, Empty, 40);
      Target_Hp := 0;
      Shooter_Ammo := 99;
      Target_Alive := False;
      for I in First.First_Index .. First.Last_Index loop
         if First (I).Ident = 2 then
            Target_Hp := First (I).Health;
            Target_Alive := First (I).Alive;
         elsif First (I).Ident = 1 then
            Shooter_Ammo := First (I).Ammo;
         end if;
      end loop;
      Smoke_Check.Expect
        (Shooter_Ammo = 0
         and then Target_Hp = Peds.Full_Health - 2 * 25
         and then Target_Alive
         and then First = Again,
         "running out of ammo stops firing");

      Act.Arm (Pair, 1, Guns.Pistol, Guns.Profile (Guns.Pistol).Magazine);
      Act.Order
        (Pair, 1, (1 => Act.Make_Shoot (2, Guns.Pistol)), Act.Replace);
      Act.Order
        (Pair, 2, (1 => Act.Make_Wait (40)), Act.Replace);
      First := Act.Run (Lane, Pair, Empty, 80);
      Again := Act.Run (Lane, Pair, Empty, 80);
      Target_Hp := 99;
      Target_Alive := True;
      for I in First.First_Index .. First.Last_Index loop
         if First (I).Ident = 2 then
            Target_Hp := First (I).Health;
            Target_Alive := First (I).Alive;
         end if;
      end loop;
      Smoke_Check.Expect
        (Target_Hp = 0 and then not Target_Alive and then First = Again,
         "damage totals bring the target down");
   end;

   declare
      package Map renames Megacorp.Map;
      package Act renames Megacorp.Actions;
      package Peds renames Megacorp.Peds;
      package Cars renames Megacorp.Vehicles;
      use type Act.Outing;
      use type Map.Eight_Way;
      use type Peds.State_Kind;
      use type Cars.State_Kind;

      Road : constant Map.Tile :=
        (Kind => Map.Road, Level => 1,
         Walkable => True, Drivable => True);
      City : Map.City := Map.Blank (16, 5);
      Hall : Map.City := Map.Blank (10, 3);
      Group : Act.Cast (1 .. 4);
      Pair : Act.Cast (1 .. 1);
      Items : Act.Bag (1 .. 1);
      Fleet : Cars.Fleet (1 .. 2);
      Parked : Cars.Fleet (1 .. 1);
      First : Act.Outing;
      Again : Act.Outing;
      Taken : Boolean;
      On_Road : Boolean;
      Entered : Boolean;
      Exited : Boolean;
      Followed : Boolean;
      Ejected : Boolean;
      Wrecked : Boolean;
      Blocked : Boolean;
      Arrived : Boolean;
      Frame : Act.Ride_Frame;
      Ped : Act.Snapshot;
      X : Integer;
      Y : Integer;
   begin
      for Column in 1 .. 16 loop
         Map.Set_Tile (City, Column, 3, Road);
      end loop;
      Map.Set_Tile (City, 16, 1, Road);
      for Column in 1 .. 10 loop
         Map.Set_Tile (Hall, Column, 2, Road);
      end loop;
      Items (1) := (Ident => 1, X => 1, Y => 1, Here => False);
      Group (1) := Act.Recruit (1, (X => 6, Y => 1), City, 9);
      Group (2) := Act.Recruit (2, (X => 15, Y => 1), City, 9);
      Group (3) := Act.Recruit (3, (X => 16, Y => 1), City, 9);
      Group (4) := Act.Recruit (4, (X => 2, Y => 3), City, 9);
      Fleet (1) := Cars.Park
        (1, Cars.Car, (X => 2, Y => 3), City, Map.East);
      Fleet (2) := Cars.Park
        (2, Cars.Van, (X => 16, Y => 1), City, Map.South);
      Act.Embark (Group, 4, Fleet, 1, Taken);
      Act.Embark (Group, 3, Fleet, 2, Taken);
      Act.Arm
        (Group, 2, Megacorp.Weapons.Rifle,
         Megacorp.Weapons.Profile (Megacorp.Weapons.Rifle).Magazine);
      Act.Order
        (Group, 1,
         (1 => Act.Make_Walk ((X => 2, Y => 2)),
          2 => Act.Make_Enter (1),
          3 => Act.Make_Drive (1, (X => 12, Y => 3)),
          4 => Act.Make_Exit (1)),
         Act.Replace);
      Act.Order
        (Group, 2,
         (1 => Act.Make_Shoot_Vehicle (2, Megacorp.Weapons.Rifle)),
         Act.Replace);
      First := Act.Play (City, Group, Items, Fleet, 800);
      Again := Act.Play (City, Group, Items, Fleet, 800);
      On_Road := True;
      Entered := False;
      Exited := False;
      Followed := True;
      Ejected := False;
      Wrecked := False;
      for I in First.Cars.First_Index .. First.Cars.Last_Index loop
         Frame := First.Cars (I);
         if not Map.Tile_At (City, Frame.X, Frame.Y).Drivable then
            On_Road := False;
         end if;
         if Frame.Along > 0 then
            X := Frame.X;
            Y := Frame.Y;
            case Frame.Facing is
               when Map.East =>
                  X := X + 1;
               when Map.West =>
                  X := X - 1;
               when Map.North =>
                  Y := Y - 1;
               when Map.South =>
                  Y := Y + 1;
               when Map.North_East =>
                  X := X + 1;
                  Y := Y - 1;
               when Map.South_East =>
                  X := X + 1;
                  Y := Y + 1;
               when Map.South_West =>
                  X := X - 1;
                  Y := Y + 1;
               when Map.North_West =>
                  X := X - 1;
                  Y := Y - 1;
            end case;
            if not Map.In_Bounds (City, X, Y)
              or else not Map.Tile_At (City, X, Y).Drivable
            then
               On_Road := False;
            end if;
         end if;
         if Frame.Ident = 2
           and then Frame.Tick = First.Cars (First.Cars.Last_Index).Tick
           and then not Frame.Intact
           and then Frame.Motion = Cars.Wrecked
           and then Frame.Riders = 0
         then
            Wrecked := True;
         end if;
         for R in 1 .. Frame.Riders loop
            for P in First.Peds.First_Index .. First.Peds.Last_Index loop
               Ped := First.Peds (P);
               if Ped.Tick = Frame.Tick
                 and then Integer (Ped.Ident) = Frame.Rider (R)
                 and then (Ped.X /= Frame.X
                           or else Ped.Y /= Frame.Y
                           or else Ped.Along /= Frame.Along
                           or else Ped.Facing /= Frame.Facing
                           or else Ped.State /= Peds.Riding)
               then
                  Followed := False;
               end if;
            end loop;
         end loop;
      end loop;
      for I in First.Peds.First_Index .. First.Peds.Last_Index loop
         Ped := First.Peds (I);
         if Ped.Ident = 1 and then Ped.State = Peds.Riding then
            Entered := True;
         elsif Ped.Ident = 1
           and then Entered
           and then Ped.State = Peds.Standing
         then
            Exited := True;
         end if;
         if Ped.Ident = 3
           and then Ped.Tick = First.Peds (First.Peds.Last_Index).Tick
           and then Ped.State = Peds.Standing
           and then Ped.Alive
           and then Ped.X = 16
           and then Ped.Y = 2
         then
            Ejected := True;
         end if;
      end loop;
      Smoke_Check.Expect (On_Road, "vehicle stays on the road");
      Smoke_Check.Expect
        (Entered and then Exited, "ped enters and exits");
      Smoke_Check.Expect (Followed, "passengers follow the vehicle");
      Smoke_Check.Expect
        (Wrecked and then Ejected, "a wreck ejects its riders");
      Smoke_Check.Expect (First = Again, "vehicle trace repeats");

      Pair (1) := Act.Recruit (1, (X => 1, Y => 2), Hall, 3);
      Parked (1) := Cars.Park
        (1, Cars.Car, (X => 5, Y => 2), Hall, Map.East);
      Act.Order
        (Pair, 1,
         (1 => Act.Make_Walk ((X => 9, Y => 2))),
         Act.Replace);
      First := Act.Play (Hall, Pair, Items, Parked, 400);
      Blocked := True;
      Arrived := False;
      for I in First.Peds.First_Index .. First.Peds.Last_Index loop
         Ped := First.Peds (I);
         if Ped.X = 5 and then Ped.Y = 2 then
            Blocked := False;
         end if;
         if Ped.X = 9 and then Ped.Y = 2
           and then Ped.State = Peds.Arrived
         then
            Arrived := True;
         end if;
      end loop;
      Smoke_Check.Expect
        (Blocked and then Arrived, "a vehicle blocks its tile");

      for Seed of Map.Export_Seeds loop
         declare
            Layout : constant Map.City :=
              Map.Gen.Generate (Seed, Defaults);
            One : constant Act.Outing :=
              Act.Run_Vehicles (Layout, Seed);
            Two : constant Act.Outing :=
              Act.Run_Vehicles (Layout, Seed);
         begin
            Smoke_Check.Expect
              (One = Two, "seeded vehicle demo repeats");
         end;
      end loop;
   end;

   declare
      package Map renames Megacorp.Map;
      package Beh renames Megacorp.Behaviour;
      package Guns renames Megacorp.Weapons;
      use type Beh.Frame_Lists.Vector;
      use type Beh.Mood;
      use type Megacorp.Peds.State_Kind;

      function Saw
        (Trace : Beh.Frame_Lists.Vector;
         Who : Megacorp.Peds.Ped_Id;
         Which : Beh.Mood) return Boolean;
      function Moved_Away
        (Trace : Beh.Frame_Lists.Vector;
         Who : Megacorp.Peds.Ped_Id;
         Threat : Map.Point) return Boolean;
      function Fired
        (Trace : Beh.Frame_Lists.Vector;
         Who : Megacorp.Peds.Ped_Id) return Boolean;

      function Saw
        (Trace : Beh.Frame_Lists.Vector;
         Who : Megacorp.Peds.Ped_Id;
         Which : Beh.Mood) return Boolean
      is
      begin
         for I in Trace.First_Index .. Trace.Last_Index loop
            if Trace (I).Ident = Who
              and then Trace (I).Temper = Which
            then
               return True;
            end if;
         end loop;
         return False;
      end Saw;

      function Moved_Away
        (Trace : Beh.Frame_Lists.Vector;
         Who : Megacorp.Peds.Ped_Id;
         Threat : Map.Point) return Boolean
      is
         Start : Natural := 0;
         Later : Natural;
      begin
         for I in Trace.First_Index .. Trace.Last_Index loop
            if Trace (I).Ident = Who then
               Later := Natural'Max
                 (abs (Trace (I).X - Threat.X),
                  abs (Trace (I).Y - Threat.Y));
               if Start = 0 then
                  Start := Later;
               end if;
               if Trace (I).Temper = Beh.Flee and then Later > Start then
                  return True;
               end if;
            end if;
         end loop;
         return False;
      end Moved_Away;

      function Fired
        (Trace : Beh.Frame_Lists.Vector;
         Who : Megacorp.Peds.Ped_Id) return Boolean
      is
      begin
         for I in Trace.First_Index .. Trace.Last_Index loop
            if Trace (I).Ident = Who and then Trace (I).Fired then
               return True;
            end if;
         end loop;
         return False;
      end Fired;

      Yard : constant Map.City := Map.Blank (12, 16);
      Lane : constant Map.City := Map.Blank (8, 8);
      Road : constant Map.City := Map.Blank (12, 4);
      Room : constant Map.City := Map.Blank (6, 4);
      Gun  : constant Guns.Kind := Guns.Pistol;
      Rounds : constant Natural := Guns.Profile (Gun).Magazine;
      Crowd : Beh.Crowd (1 .. 3);
      Pair : Beh.Crowd (1 .. 2);
      One : Beh.Crowd (1 .. 1);
      Trace : Beh.Frame_Lists.Vector;
      Again : Beh.Frame_Lists.Vector;
      Visits_A : Natural;
      Visits_B : Natural;
      Closer : Boolean;
      Warned : Natural;
      Shot : Natural;
   begin
      Crowd (1) := Beh.Enlist (1, Beh.Hostile, (X => 2, Y => 2), Yard, 3);
      Crowd (2) := Beh.Enlist (2, Beh.Civilian, (X => 2, Y => 8), Yard, 3);
      Crowd (3) := Beh.Enlist (3, Beh.Civilian, (X => 6, Y => 11), Yard, 3);
      Beh.Arm (Crowd, 1, Gun, Rounds);
      Trace := Beh.Run (Yard, Crowd, 40);
      Again := Beh.Run (Yard, Crowd, 40);
      Smoke_Check.Expect
        (Saw (Trace, 2, Beh.Flee)
         and then Moved_Away (Trace, 2, (X => 2, Y => 2))
         and then Saw (Trace, 3, Beh.Flee)
         and then Trace = Again,
         "civilians flee and panic spreads");

      Pair (1) := Beh.Enlist (1, Beh.Guard, (X => 2, Y => 2), Lane, 4);
      Pair (2) := Beh.Enlist (2, Beh.Hostile, (X => 2, Y => 6), Lane, 4);
      Beh.Arm (Pair, 1, Gun, Rounds);
      Beh.Arm (Pair, 2, Gun, Rounds);
      Trace := Beh.Run (Lane, Pair, 24);
      Smoke_Check.Expect
        (Saw (Trace, 1, Beh.Engage) and then Fired (Trace, 1),
         "a guard engages a hostile in sight");

      One (1) := Beh.Enlist
        (1, Beh.Guard, (X => 2, Y => 2), Lane, 5,
         (X => 2, Y => 2), (X => 2, Y => 6));
      Beh.Arm (One, 1, Gun, Rounds);
      Trace := Beh.Run (Lane, One, 160);
      Visits_A := 0;
      Visits_B := 0;
      for I in Trace.First_Index .. Trace.Last_Index loop
         if Trace (I).State = Megacorp.Peds.Arrived
           and then Trace (I).X = 2
           and then Trace (I).Y = 2
         then
            Visits_A := Visits_A + 1;
         elsif Trace (I).State = Megacorp.Peds.Arrived
           and then Trace (I).X = 2
           and then Trace (I).Y = 6
         then
            Visits_B := Visits_B + 1;
         end if;
      end loop;
      Smoke_Check.Expect
        (Visits_A >= 2 and then Visits_B >= 2,
         "a guard patrols a loop");

      Crowd (1) := Beh.Enlist (1, Beh.Police, (X => 2, Y => 2), Road, 6);
      Crowd (2) := Beh.Enlist (2, Beh.Hostile, (X => 6, Y => 2), Road, 6);
      Crowd (3) := Beh.Enlist (3, Beh.Civilian, (X => 7, Y => 2), Road, 6);
      Beh.Arm (Crowd, 1, Gun, Rounds);
      Beh.Arm (Crowd, 2, Gun, Rounds);
      Trace := Beh.Run (Road, Crowd, 40);
      Warned := 0;
      Shot := 0;
      for I in Trace.First_Index .. Trace.Last_Index loop
         if Trace (I).Ident = 1 and then Trace (I).Temper = Beh.Warn
           and then Warned = 0
         then
            Warned := Trace (I).Tick;
         end if;
         if Trace (I).Ident = 1 and then Trace (I).Fired and then Shot = 0
         then
            Shot := Trace (I).Tick;
         end if;
      end loop;
      Smoke_Check.Expect
        (Warned > 0 and then Shot >= Warned + Beh.Warn_Ticks,
         "police warn before they fire");

      Crowd (1) := Beh.Enlist (1, Beh.Police, (X => 2, Y => 2), Yard, 7);
      Crowd (2) := Beh.Enlist (2, Beh.Hostile, (X => 9, Y => 2), Yard, 7);
      Crowd (3) := Beh.Enlist (3, Beh.Civilian, (X => 10, Y => 2), Yard, 7);
      Beh.Arm (Crowd, 2, Gun, Rounds);
      Trace := Beh.Run (Yard, Crowd, 20);
      Closer := False;
      for I in Trace.First_Index .. Trace.Last_Index loop
         if Trace (I).Ident = 1 and then Trace (I).X > 2 then
            Closer := True;
         end if;
      end loop;
      Smoke_Check.Expect (Closer, "police walk toward a heard shot");

      Pair (1) := Beh.Enlist (1, Beh.Agent, (X => 2, Y => 2), Room, 8);
      Pair (2) := Beh.Enlist (2, Beh.Civilian, (X => 3, Y => 2), Room, 8);
      Trace := Beh.Run (Room, Pair, 16);
      Smoke_Check.Expect
        (Saw (Trace, 2, Beh.Persuaded),
         "an agent persuades a neighbour");

      One (1) := Beh.Enlist (1, Beh.Civilian, (X => 3, Y => 3), Lane, 9);
      Trace := Beh.Run (Lane, One, 16);
      Smoke_Check.Expect
        (Saw (Trace, 1, Beh.Wander),
         "a calm civilian wanders");

      for Seed of Map.Export_Seeds loop
         declare
            Layout : constant Map.City :=
              Map.Gen.Generate (Seed, Defaults);
            First : constant Beh.Frame_Lists.Vector :=
              Beh.Run_Street (Layout, Seed);
            Second : constant Beh.Frame_Lists.Vector :=
              Beh.Run_Street (Layout, Seed);
         begin
            Smoke_Check.Expect
              (First = Second, "seeded behaviour demo repeats");
         end;
      end loop;
   end;

   declare
      package Map renames Megacorp.Map;
      package Act renames Megacorp.Actions;
      package Beh renames Megacorp.Behaviour;
      package Cars renames Megacorp.Vehicles;
      package Job renames Megacorp.Mission;
      package Guns renames Megacorp.Weapons;
      use type Job.Cause;
      use type Job.Command_Lists.Vector;
      use type Job.Report;
      use type Job.Status;
      use type Beh.Frame_Lists.Vector;

      Yard : constant Map.City := Map.Blank (10, 4);
      Gun : constant Guns.Kind := Guns.Pistol;
      Rounds : constant Natural := Guns.Profile (Gun).Magazine;
      Group : Beh.Crowd (1 .. 2);
      Trio : Beh.Crowd (1 .. 3);
      Items : Act.Bag (1 .. 1);
      Spare : Act.Bag (1 .. 1);
      Fleet : Cars.Fleet (1 .. 0);
      Goals : Job.Objective_List (1 .. 1);
      Lines : Job.Command_Lists.Vector;
      Loaded : Job.Command_Lists.Vector;
      One : Job.Trace;
      Two : Job.Trace;
      C : Job.Command;
   begin
      Items (1) := (Ident => 1, X => 1, Y => 1, Here => False);
      Group (1) := Beh.Enlist (1, Beh.Agent, (X => 1, Y => 1), Yard, 4);
      Group (2) := Beh.Enlist
        (2, Beh.Guard, (X => 2, Y => 1), Yard, 4,
         (X => 2, Y => 1), (X => 2, Y => 1));
      Beh.Arm (Group, 1, Gun, Rounds);
      Goals (1) := (Kind => Job.Eliminate, Target => 2);
      C.At_Tick := 1;
      C.Who := 1;
      C.What := Job.Shoot;
      C.Target := 2;
      Lines.Append (C);
      One := Job.Play (Yard, Group, Items, Fleet, Goals, Lines, 40);
      Smoke_Check.Expect
        (One.Outcome.Outcome = Job.Won
         and then One.Outcome.Why = Job.Objectives_Met,
         "eliminate objective can win");

      Lines.Clear;
      Group (1) := Beh.Enlist (1, Beh.Agent, (X => 1, Y => 2), Yard, 5);
      Group (2) := Beh.Enlist (2, Beh.Civilian, (X => 4, Y => 2), Yard, 5);
      Items (1) := (Ident => 1, X => 3, Y => 2, Here => True);
      Spare := Items;
      Goals (1) := (Kind => Job.Acquire, Item => 1);
      C.What := Job.Walk;
      C.X := 3;
      C.Y := 2;
      Lines.Append (C);
      C.What := Job.Pick;
      C.Item := 1;
      Lines.Append (C);
      One := Job.Play (Yard, Group, Items, Fleet, Goals, Lines, 40);
      Group (1) := Beh.Enlist (1, Beh.Agent, (X => 1, Y => 2), Yard, 5);
      Group (2) := Beh.Enlist (2, Beh.Civilian, (X => 4, Y => 2), Yard, 5);
      Two := Job.Play (Yard, Group, Spare, Fleet, Goals, Lines, 40);
      Smoke_Check.Expect
        (One.Outcome.Outcome = Job.Won
         and then One.Outcome = Two.Outcome
         and then One.Frames = Two.Frames,
         "acquire objective can win");

      Lines.Clear;
      Group (1) := Beh.Enlist (1, Beh.Agent, (X => 2, Y => 2), Yard, 6);
      Group (2) := Beh.Enlist (2, Beh.Civilian, (X => 3, Y => 2), Yard, 6);
      Goals (1) := (Kind => Job.Persuade, Contact => 2);
      One := Job.Play (Yard, Group, Items, Fleet, Goals, Lines, 20);
      Smoke_Check.Expect
        (One.Outcome.Outcome = Job.Won, "persuade objective can win");

      Lines.Clear;
      Group (1) := Beh.Enlist (1, Beh.Agent, (X => 1, Y => 1), Yard, 7);
      Group (2) := Beh.Enlist (2, Beh.Civilian, (X => 1, Y => 4), Yard, 7);
      Goals (1) := (Kind => Job.Evacuate, Zone_X => 1, Zone_Y => 4);
      C.What := Job.Walk;
      C.X := 1;
      C.Y := 4;
      Lines.Append (C);
      One := Job.Play (Yard, Group, Items, Fleet, Goals, Lines, 40);
      Smoke_Check.Expect
        (One.Outcome.Outcome = Job.Won, "evacuate objective can win");
      declare
         File_Lines : Job.Command_Lists.Vector;
         Clean : Job.Command;
      begin
         Clean.At_Tick := 1;
         Clean.Who := 1;
         Clean.What := Job.Walk;
         Clean.X := 2;
         Clean.Y := 3;
         File_Lines.Append (Clean);
         Job.Dump (File_Lines, "/tmp/mission_script.txt");
         Loaded := Job.Load ("/tmp/mission_script.txt");
         Smoke_Check.Expect
           (File_Lines = Loaded, "a script file reloads");
      end;

      Trio (1) := Beh.Enlist (1, Beh.Agent, (X => 2, Y => 2), Yard, 8);
      Trio (2) := Beh.Enlist (2, Beh.Hostile, (X => 3, Y => 2), Yard, 8);
      Trio (3) := Beh.Enlist (3, Beh.Civilian, (X => 10, Y => 2), Yard, 8);
      Beh.Arm (Trio, 2, Gun, Rounds);
      Goals (1) := (Kind => Job.Eliminate, Target => 3);
      Lines.Clear;
      One := Job.Play (Yard, Trio, Items, Fleet, Goals, Lines, 40);
      Smoke_Check.Expect
        (One.Outcome.Outcome = Job.Lost
         and then One.Outcome.Why = Job.Squad_Lost
         and then One.Outcome.Agents_Alive = 0,
         "squad death loses the mission");

      Lines.Clear;
      Group (1) := Beh.Enlist (1, Beh.Agent, (X => 1, Y => 1), Yard, 9);
      Group (2) := Beh.Enlist (2, Beh.Civilian, (X => 8, Y => 1), Yard, 9);
      Goals (1) := (Kind => Job.Evacuate, Zone_X => 8, Zone_Y => 1);
      One := Job.Play (Yard, Group, Items, Fleet, Goals, Lines, 4);
      Smoke_Check.Expect
        (One.Outcome.Outcome = Job.Timed_Out
         and then One.Outcome.Tick = 4
         and then One.Outcome.Why = Job.Time_Up,
         "a short cap times out");

      declare
         City : constant Map.City :=
           Map.Gen.Generate (42, Defaults);
         Shown : constant Job.Trace :=
           Job.Demonstration (City, 42, 200);
      begin
         Smoke_Check.Expect
           (Shown.Outcome.Outcome = Job.Won
            and then Shown.Outcome.Met = 4,
            "the fixture mission wins");
      end;
   end;

   if Smoke_Check.Failure_Count = 0 then
      Ada.Text_IO.Put_Line ("smoke: PASS");
   else
      Ada.Text_IO.Put_Line ("smoke: FAIL");
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end Megacorp_Smoke;
