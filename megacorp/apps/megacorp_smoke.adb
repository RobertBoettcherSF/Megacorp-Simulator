--  SPDX-License-Identifier: MIT
--  Copyright (c) 2026 Robert Boettcher

with Ada.Assertions;
with Ada.Command_Line;
with Ada.Text_IO;
with Ada.Containers;
with Ada.Strings.Fixed;
with Megacorp.Actions;
with Megacorp.Weapons;
with Megacorp.Assets.Placeholder;
with Megacorp.Data.Virtual_FS.Native;
with Megacorp.Host;
with Megacorp.Map;
with Megacorp.Path;
with Megacorp.Peds;
with Megacorp.Parameters;
with Megacorp.RNG;
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
     (Megacorp.Version = "0.8.0"
      and then Megacorp.Name = "Megacorp Simulator",
      "version 0.8.0");
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

   if Smoke_Check.Failure_Count = 0 then
      Ada.Text_IO.Put_Line ("smoke: PASS");
   else
      Ada.Text_IO.Put_Line ("smoke: FAIL");
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end Megacorp_Smoke;
