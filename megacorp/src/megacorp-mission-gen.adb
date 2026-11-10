--  SPDX-License-Identifier: MIT
--  Copyright (c) 2026 Robert Boettcher

with Megacorp.Actions;
with Megacorp.Behaviour;
with Megacorp.Path;
with Megacorp.Peds;
with Megacorp.Shots;
with Megacorp.Vehicles;
with Megacorp.Weapons;

package body Megacorp.Mission.Gen is
   use type Map.Point;
   use type Map.Terrain;
   use type Map.Gen.District;
   use type Path.Status;
   Gap : constant := 16;
   Run : constant := 6;
   Cast_N : constant := 8;

   type Stage is record
      X : Positive := 1;
      Y : Positive := 1;
      East : Boolean := True;
   end record;

   Max_List : constant := 16;

   type Stage_List is array (1 .. Max_List) of Stage;

   type Hold_List is array (1 .. 64) of Map.Point;

   type Bundle is record
      Plan   : Scene;
      Group  : Behaviour.Crowd (1 .. Cast_N);
      Items  : Actions.Bag (1 .. 2);
      Fleet  : Vehicles.Fleet (1 .. 3);
      Goal_N : Natural := 0;
      Goals  : Objective_List (1 .. 4);
      Lines  : Command_Lists.Vector;
   end record;

   function Is_Road (M : Map.City; X, Y : Integer) return Boolean;
   function Is_Walk (M : Map.City; X, Y : Integer) return Boolean;
   function Apart (A, B : Map.Point) return Natural;
   function Corp_Post
     (M : Map.City; Seed : RNG.Word; X, Y : Integer) return Boolean;
   function Zone_Of
     (M : Map.City; Seed : RNG.Word; X, Y : Integer)
     return Map.Gen.District;
   function Column_Road
     (M : Map.City; X, Y, Len : Positive) return Boolean;
   procedure Collect
     (M : Map.City;
      Seed : RNG.Word;
      List : out Stage_List;
      Total : out Natural);
   procedure Keep (Held : in out Hold_List; N : in out Natural; P : Map.Point);
   function Kept (Held : Hold_List; N : Natural; P : Map.Point) return Boolean;
   function Clear_Stage (Plan : Scene; P : Map.Point) return Boolean;
   function Slum_Run
     (M : Map.City;
      Seed : RNG.Word;
      Plan : Scene;
      Held : Hold_List;
      Used : Natural;
      Start, Goal : out Map.Point) return Boolean;
   function Road_Run
     (M : Map.City;
      Plan : Scene;
      Held : Hold_List;
      Used : Natural;
      Across : Boolean;
      Start, Goal : out Map.Point) return Boolean;
   function Spare_Road
     (M : Map.City;
      Plan : Scene;
      Held : Hold_List;
      Used : Natural;
      Spot : out Map.Point) return Boolean;
   function Spare_Walk
     (M : Map.City;
      Seed : RNG.Word;
      Plan : Scene;
      Held : Hold_List;
      Used : Natural;
      Which : Map.Gen.District;
      Spot : out Map.Point) return Boolean;
   function Other_Post
     (M : Map.City;
      Seed : RNG.Word;
      Plan : Scene;
      Held : Hold_List;
      Used : Natural;
      Spot : out Map.Point) return Boolean;
   procedure Place (M : Map.City; Seed : RNG.Word; Plan : out Scene);
   function Assemble (M : Map.City; Seed : RNG.Word) return Bundle;
   procedure Add_Wait
     (Lines : in out Command_Lists.Vector;
      Who : Peds.Ped_Id;
      Ticks : Positive);
   procedure Add_Walk
     (Lines : in out Command_Lists.Vector;
      Who : Peds.Ped_Id;
      Goal : Map.Point);
   procedure Add_Pick (Lines : in out Command_Lists.Vector);
   procedure Add_Shot (Lines : in out Command_Lists.Vector);

   function Is_Road (M : Map.City; X, Y : Integer) return Boolean is
   begin
      return Map.In_Bounds (M, X, Y)
        and then Map.Tile_At (M, X, Y).Drivable;
   end Is_Road;

   function Is_Walk (M : Map.City; X, Y : Integer) return Boolean is
   begin
      return Map.In_Bounds (M, X, Y)
        and then Map.Tile_At (M, X, Y).Walkable;
   end Is_Walk;

   function Apart (A, B : Map.Point) return Natural is
   begin
      return Natural'Max
        (abs (Integer (A.X) - Integer (B.X)),
         abs (Integer (A.Y) - Integer (B.Y)));
   end Apart;

   function Zone_Of
     (M : Map.City; Seed : RNG.Word; X, Y : Integer)
     return Map.Gen.District
   is
   begin
      return Map.Gen.District_At (Seed, M.Width, M.Height, X, Y);
   end Zone_Of;

   function Corp_Post
     (M : Map.City; Seed : RNG.Word; X, Y : Integer) return Boolean
   is
      Next : Map.Point;
   begin
      if not Is_Walk (M, X, Y) then
         return False;
      end if;
      for Dir in Map.Four_Way loop
         if Map.Has_Neighbour_4 (M, X, Y, Dir) then
            Next := Map.Neighbour_4 (M, X, Y, Dir);
            if Map.Tile_At (M, Next.X, Next.Y).Kind = Map.Building
              and then Zone_Of (M, Seed, Next.X, Next.Y)
                = Map.Gen.Corporate
            then
               return True;
            end if;
         end if;
      end loop;
      return False;
   end Corp_Post;

   function Column_Road
     (M : Map.City; X, Y, Len : Positive) return Boolean
   is
   begin
      if Y + Len - 1 > M.Height then
         return False;
      end if;
      for Step in 0 .. Len - 1 loop
         if not Is_Road (M, X, Y + Step) then
            return False;
         end if;
      end loop;
      return True;
   end Column_Road;

   procedure Collect
     (M : Map.City;
      Seed : RNG.Word;
      List : out Stage_List;
      Total : out Natural)
   is
      N : Natural := 0;
   begin
      List := (others => (X => 1, Y => 1, East => True));
      for Y in 1 .. M.Height - (Run - 1) loop
         for X in 1 .. M.Width loop
            exit when N = Max_List;
            if Column_Road (M, X, Y, Run) then
               if Corp_Post (M, Seed, X + 1, Y + Run - 1) then
                  N := N + 1;
                  List (N) := (X => X, Y => Y, East => True);
               elsif Corp_Post (M, Seed, X - 1, Y + Run - 1) then
                  N := N + 1;
                  List (N) := (X => X, Y => Y, East => False);
               end if;
            end if;
         end loop;
      end loop;
      Total := N;
   end Collect;

   procedure Keep
     (Held : in out Hold_List; N : in out Natural; P : Map.Point)
   is
   begin
      pragma Assert (N < Held'Last);
      N := N + 1;
      Held (N) := P;
   end Keep;

   function Kept
     (Held : Hold_List; N : Natural; P : Map.Point) return Boolean
   is
   begin
      for I in 1 .. N loop
         if Held (I).X = P.X and then Held (I).Y = P.Y then
            return True;
         end if;
      end loop;
      return False;
   end Kept;

   function Clear_Stage (Plan : Scene; P : Map.Point) return Boolean is
   begin
      return Apart (P, Plan.Contact) > Gap
        and then Apart (P, Plan.Agent) > Gap
        and then Apart (P, Plan.Stand) > Gap
        and then Apart (P, Plan.Target) > Gap;
   end Clear_Stage;

   function Slum_Run
     (M : Map.City;
      Seed : RNG.Word;
      Plan : Scene;
      Held : Hold_List;
      Used : Natural;
      Start, Goal : out Map.Point) return Boolean
   is
      Length : constant := 7;
      Fit : Boolean;
   begin
      Start := (X => 1, Y => 1);
      Goal := (X => 1, Y => 1);
      for Y in 1 .. M.Height loop
         for X in 1 .. M.Width - (Length - 1) loop
            Fit := True;
            for Step in 0 .. Length - 1 loop
               if not Is_Road (M, X + Step, Y)
                 or else Zone_Of (M, Seed, X + Step, Y) /= Map.Gen.Slums
                 or else not Clear_Stage (Plan, (X => X + Step, Y => Y))
                 or else Kept (Held, Used, (X => X + Step, Y => Y))
               then
                  Fit := False;
               end if;
            end loop;
            if Fit then
               Start := (X => X, Y => Y);
               Goal := (X => X + Length - 1, Y => Y);
               return True;
            end if;
         end loop;
      end loop;
      for X in 1 .. M.Width loop
         for Y in 1 .. M.Height - (Length - 1) loop
            Fit := True;
            for Step in 0 .. Length - 1 loop
               if not Is_Road (M, X, Y + Step)
                 or else Zone_Of (M, Seed, X, Y + Step) /= Map.Gen.Slums
                 or else not Clear_Stage (Plan, (X => X, Y => Y + Step))
                 or else Kept (Held, Used, (X => X, Y => Y + Step))
               then
                  Fit := False;
               end if;
            end loop;
            if Fit then
               Start := (X => X, Y => Y);
               Goal := (X => X, Y => Y + Length - 1);
               return True;
            end if;
         end loop;
      end loop;
      return False;
   end Slum_Run;

   function Road_Run
     (M : Map.City;
      Plan : Scene;
      Held : Hold_List;
      Used : Natural;
      Across : Boolean;
      Start, Goal : out Map.Point) return Boolean
   is
      Length : constant := 5;
      Fit : Boolean;
   begin
      Start := (X => 1, Y => 1);
      Goal := (X => 1, Y => 1);
      if Across then
         for Y in 1 .. M.Height loop
            for X in 1 .. M.Width - (Length - 1) loop
               Fit := True;
               for Step in 0 .. Length - 1 loop
                  if not Is_Road (M, X + Step, Y)
                    or else not Clear_Stage
                      (Plan, (X => X + Step, Y => Y))
                    or else Kept (Held, Used, (X => X + Step, Y => Y))
                  then
                     Fit := False;
                  end if;
               end loop;
               if Fit then
                  Start := (X => X, Y => Y);
                  Goal := (X => X + Length - 1, Y => Y);
                  return True;
               end if;
            end loop;
         end loop;
      else
         for X in 1 .. M.Width loop
            for Y in 1 .. M.Height - (Length - 1) loop
               Fit := True;
               for Step in 0 .. Length - 1 loop
                  if not Is_Road (M, X, Y + Step)
                    or else not Clear_Stage
                      (Plan, (X => X, Y => Y + Step))
                    or else Kept (Held, Used, (X => X, Y => Y + Step))
                  then
                     Fit := False;
                  end if;
               end loop;
               if Fit then
                  Start := (X => X, Y => Y);
                  Goal := (X => X, Y => Y + Length - 1);
                  return True;
               end if;
            end loop;
         end loop;
      end if;
      return False;
   end Road_Run;

   function Spare_Road
     (M : Map.City;
      Plan : Scene;
      Held : Hold_List;
      Used : Natural;
      Spot : out Map.Point) return Boolean
   is
   begin
      Spot := (X => 1, Y => 1);
      for Y in 1 .. M.Height loop
         for X in 1 .. M.Width loop
            if Is_Road (M, X, Y)
              and then Clear_Stage (Plan, (X => X, Y => Y))
              and then not Kept (Held, Used, (X => X, Y => Y))
            then
               Spot := (X => X, Y => Y);
               return True;
            end if;
         end loop;
      end loop;
      return False;
   end Spare_Road;

   function Spare_Walk
     (M : Map.City;
      Seed : RNG.Word;
      Plan : Scene;
      Held : Hold_List;
      Used : Natural;
      Which : Map.Gen.District;
      Spot : out Map.Point) return Boolean
   is
   begin
      Spot := (X => 1, Y => 1);
      for Y in 1 .. M.Height loop
         for X in 1 .. M.Width loop
            if Is_Walk (M, X, Y)
              and then Zone_Of (M, Seed, X, Y) = Which
              and then Clear_Stage (Plan, (X => X, Y => Y))
              and then not Kept (Held, Used, (X => X, Y => Y))
            then
               Spot := (X => X, Y => Y);
               return True;
            end if;
         end loop;
      end loop;
      return False;
   end Spare_Walk;

   function Other_Post
     (M : Map.City;
      Seed : RNG.Word;
      Plan : Scene;
      Held : Hold_List;
      Used : Natural;
      Spot : out Map.Point) return Boolean
   is
   begin
      Spot := (X => 1, Y => 1);
      for Y in 1 .. M.Height loop
         for X in 1 .. M.Width loop
            if Corp_Post (M, Seed, X, Y)
              and then (X /= Plan.Target.X or else Y /= Plan.Target.Y)
              and then (X /= Plan.Stand.X or else Y /= Plan.Stand.Y)
              and then not Kept (Held, Used, (X => X, Y => Y))
            then
               Spot := (X => X, Y => Y);
               return True;
            end if;
         end loop;
      end loop;
      return False;
   end Other_Post;

   procedure Place (M : Map.City; Seed : RNG.Word; Plan : out Scene) is
      Mission_G : RNG.Generator :=
        RNG.Child (RNG.Make (Seed), RNG.Mission, 1);
      Block_G : RNG.Generator :=
        RNG.Child (RNG.Make (Seed), RNG.Block, 1);
      List : Stage_List;
      Total : Natural;
      Pick : Integer;
      Chosen : Stage;
      Held : Hold_List := (others => (X => 1, Y => 1));
      Used : Natural := 0;
      Side : Integer;
      Found : Boolean;
      Here : Map.Point;
      There : Map.Point;
   begin
      Collect (M, Seed, List, Total);
      Pick := RNG.Pick (Mission_G, 0, 2);
      case Pick is
         when 0 =>
            Plan.Kind := Briefing;
            Plan.Level := Light;
            Plan.Cap := 100;
         when 1 =>
            Plan.Kind := Snatch;
            Plan.Level := Firm;
            Plan.Cap := 160;
         when others =>
            Plan.Kind := Contract;
            Plan.Level := Heavy;
            Plan.Cap := 200;
      end case;
      pragma Assert (Total > 0);
      Pick := RNG.Pick (Block_G, 1, Total);
      Chosen := List (Pick);
      Plan.Contact := (X => Chosen.X, Y => Chosen.Y);
      Plan.Agent := (X => Chosen.X, Y => Chosen.Y + 1);
      Plan.Case_At := (X => Chosen.X, Y => Chosen.Y + 3);
      Plan.Stand := (X => Chosen.X, Y => Chosen.Y + Run - 1);
      Plan.Zone := Plan.Stand;
      if Chosen.East then
         Side := 1;
      else
         Side := -1;
      end if;
      Plan.Target := (X => Chosen.X + Side, Y => Plan.Stand.Y);
      for Step in 0 .. Run - 1 loop
         Keep (Held, Used, (X => Chosen.X, Y => Chosen.Y + Step));
      end loop;
      Keep (Held, Used, Plan.Target);
      Found := Slum_Run (M, Seed, Plan, Held, Used, Here, There);
      pragma Assert (Found);
      Plan.Car := Here;
      Plan.Car_Goal := There;
      if Plan.Car.Y = Plan.Car_Goal.Y then
         for X in Plan.Car.X .. Plan.Car_Goal.X loop
            Keep (Held, Used, (X => X, Y => Plan.Car.Y));
         end loop;
      else
         for Y in Plan.Car.Y .. Plan.Car_Goal.Y loop
            Keep (Held, Used, (X => Plan.Car.X, Y => Y));
         end loop;
      end if;
      Plan.Driver := Plan.Car;
      Found := Road_Run (M, Plan, Held, Used, True, Here, There);
      pragma Assert (Found);
      Plan.Police_A := Here;
      Plan.Beat_A := There;
      for X in Plan.Police_A.X .. Plan.Beat_A.X loop
         Keep (Held, Used, (X => X, Y => Plan.Police_A.Y));
      end loop;
      Found := Road_Run (M, Plan, Held, Used, False, Here, There);
      pragma Assert (Found);
      Plan.Police_B := Here;
      Plan.Beat_B := There;
      for Y in Plan.Police_B.Y .. Plan.Beat_B.Y loop
         Keep (Held, Used, (X => Plan.Police_B.X, Y => Y));
      end loop;
      Found := Spare_Road (M, Plan, Held, Used, Here);
      pragma Assert (Found);
      Plan.Park_A := Here;
      Keep (Held, Used, Plan.Park_A);
      Found := Spare_Road (M, Plan, Held, Used, Here);
      pragma Assert (Found);
      Plan.Park_B := Here;
      Keep (Held, Used, Plan.Park_B);
      Found := Spare_Walk
        (M, Seed, Plan, Held, Used, Map.Gen.Residential, Here);
      pragma Assert (Found);
      Plan.Resident := Here;
      Keep (Held, Used, Plan.Resident);
      Found := Spare_Walk
        (M, Seed, Plan, Held, Used, Map.Gen.Residential, Here);
      pragma Assert (Found);
      Plan.Cache := Here;
      Keep (Held, Used, Plan.Cache);
      Found := Other_Post (M, Seed, Plan, Held, Used, Here);
      pragma Assert (Found);
      Plan.Guard := Here;
   end Place;

   function Build (M : Map.City; Seed : RNG.Word) return Scene is
      Plan : Scene;
   begin
      Place (M, Seed, Plan);
      return Plan;
   end Build;

   function Same (A, B : Scene) return Boolean is
   begin
      return A.Kind = B.Kind
        and then A.Level = B.Level
        and then A.Cap = B.Cap
        and then A.Contact = B.Contact
        and then A.Agent = B.Agent
        and then A.Case_At = B.Case_At
        and then A.Stand = B.Stand
        and then A.Target = B.Target
        and then A.Zone = B.Zone
        and then A.Guard = B.Guard
        and then A.Resident = B.Resident
        and then A.Driver = B.Driver
        and then A.Police_A = B.Police_A
        and then A.Beat_A = B.Beat_A
        and then A.Police_B = B.Police_B
        and then A.Beat_B = B.Beat_B
        and then A.Park_A = B.Park_A
        and then A.Park_B = B.Park_B
        and then A.Car = B.Car
        and then A.Car_Goal = B.Car_Goal
        and then A.Cache = B.Cache;
   end Same;

   function Reachable (M : Map.City; Plan : Scene) return Boolean is
      To_Case : constant Path.Result :=
        Path.Find (M, Plan.Agent, Plan.Case_At, Path.Walk);
      To_Zone : constant Path.Result :=
        Path.Find (M, Plan.Agent, Plan.Zone, Path.Walk);
      Drive : constant Path.Result :=
        Path.Find (M, Plan.Car, Plan.Car_Goal, Path.Drive);
      Beat_1 : constant Path.Result :=
        Path.Find (M, Plan.Police_A, Plan.Beat_A, Path.Walk);
      Beat_2 : constant Path.Result :=
        Path.Find (M, Plan.Police_B, Plan.Beat_B, Path.Walk);
   begin
      return Path.Kind (To_Case) = Path.Found
        and then Path.Kind (To_Zone) = Path.Found
        and then Path.Kind (Drive) = Path.Found
        and then Path.Kind (Beat_1) = Path.Found
        and then Path.Kind (Beat_2) = Path.Found
        and then not Shots.Blocked (M, Plan.Stand, Plan.Target)
        and then Shots.Distance (Plan.Stand, Plan.Target) = 1;
   end Reachable;

   function Civilians_In
     (M : Map.City;
      Plan : Scene;
      Which : Map.Gen.District) return Natural
   is
      Total : Natural := 0;
   begin
      if Zone_Of (M, Map.Layout_Seed (M), Plan.Contact.X, Plan.Contact.Y)
        = Which
      then
         Total := Total + 1;
      end if;
      if Zone_Of (M, Map.Layout_Seed (M), Plan.Resident.X, Plan.Resident.Y)
        = Which
      then
         Total := Total + 1;
      end if;
      if Zone_Of (M, Map.Layout_Seed (M), Plan.Driver.X, Plan.Driver.Y)
        = Which
      then
         Total := Total + 1;
      end if;
      return Total;
   end Civilians_In;

   function In_Band (M : Map.City; Plan : Scene) return Boolean is
   begin
      return Civilians_In (M, Plan, Map.Gen.Residential) in 1 .. 3
        and then Civilians_In (M, Plan, Map.Gen.Slums) in 1 .. 2
        and then Civilians_In (M, Plan, Map.Gen.Industrial) in 0 .. 1
        and then Civilians_In (M, Plan, Map.Gen.Corporate) in 0 .. 1
        and then Corp_Post
          (M, Map.Layout_Seed (M), Plan.Target.X, Plan.Target.Y)
        and then Corp_Post
          (M, Map.Layout_Seed (M), Plan.Guard.X, Plan.Guard.Y);
   end In_Band;

   procedure Add_Wait
     (Lines : in out Command_Lists.Vector;
      Who : Peds.Ped_Id;
      Ticks : Positive)
   is
      C : Command;
   begin
      C.At_Tick := 1;
      C.Who := Who;
      C.What := Wait;
      C.Ticks := Ticks;
      Lines.Append (C);
   end Add_Wait;

   procedure Add_Walk
     (Lines : in out Command_Lists.Vector;
      Who : Peds.Ped_Id;
      Goal : Map.Point)
   is
      C : Command;
   begin
      C.At_Tick := 1;
      C.Who := Who;
      C.What := Walk;
      C.X := Goal.X;
      C.Y := Goal.Y;
      Lines.Append (C);
   end Add_Walk;

   procedure Add_Pick (Lines : in out Command_Lists.Vector) is
      C : Command;
   begin
      C.At_Tick := 1;
      C.Who := 1;
      C.What := Pick;
      C.Item := 1;
      Lines.Append (C);
   end Add_Pick;

   procedure Add_Shot (Lines : in out Command_Lists.Vector) is
      C : Command;
   begin
      C.At_Tick := 1;
      C.Who := 1;
      C.What := Shoot;
      C.Target := 3;
      Lines.Append (C);
   end Add_Shot;

   function Assemble (M : Map.City; Seed : RNG.Word) return Bundle is
      Result : Bundle;
      Gun : constant Weapons.Kind := Weapons.Pistol;
   begin
      Place (M, Seed, Result.Plan);
      pragma Assert (Reachable (M, Result.Plan));
      Result.Group (1) := Behaviour.Enlist
        (1, Behaviour.Agent, Result.Plan.Agent, M, Seed);
      Result.Group (2) := Behaviour.Enlist
        (2, Behaviour.Civilian, Result.Plan.Contact, M, Seed);
      Result.Group (3) := Behaviour.Enlist
        (3, Behaviour.Guard, Result.Plan.Target, M, Seed,
         Result.Plan.Target, Result.Plan.Target);
      Result.Group (4) := Behaviour.Enlist
        (4, Behaviour.Guard, Result.Plan.Guard, M, Seed,
         Result.Plan.Guard, Result.Plan.Guard);
      Result.Group (5) := Behaviour.Enlist
        (5, Behaviour.Civilian, Result.Plan.Resident, M, Seed);
      Result.Group (6) := Behaviour.Enlist
        (6, Behaviour.Civilian, Result.Plan.Driver, M, Seed);
      Result.Group (7) := Behaviour.Enlist
        (7, Behaviour.Police, Result.Plan.Police_A, M, Seed);
      Result.Group (8) := Behaviour.Enlist
        (8, Behaviour.Police, Result.Plan.Police_B, M, Seed);
      Behaviour.Arm
        (Result.Group, 1, Gun, Weapons.Profile (Gun).Magazine);
      Behaviour.Arm
        (Result.Group, 3, Gun, Weapons.Profile (Gun).Magazine);
      Behaviour.Arm
        (Result.Group, 4, Gun, Weapons.Profile (Gun).Magazine);
      Result.Items (1) :=
        (Ident => 1,
         X => Result.Plan.Case_At.X,
         Y => Result.Plan.Case_At.Y,
         Here => True);
      Result.Items (2) :=
        (Ident => 2,
         X => Result.Plan.Cache.X,
         Y => Result.Plan.Cache.Y,
         Here => True);
      Result.Fleet (1) := Vehicles.Park
        (1, Vehicles.Car, Result.Plan.Park_A, M);
      Result.Fleet (2) := Vehicles.Park
        (2, Vehicles.Van, Result.Plan.Park_B, M);
      Result.Fleet (3) := Vehicles.Park
        (3, Vehicles.Car, Result.Plan.Car, M);
      Behaviour.Order
        (Result.Group, 6,
         (1 => Actions.Make_Enter (3),
          2 => Actions.Make_Drive (3, Result.Plan.Car_Goal),
          3 => Actions.Make_Exit (3)),
         Actions.Replace);
      Result.Goal_N := 0;
      if Result.Plan.Kind in Briefing | Contract then
         Result.Goal_N := Result.Goal_N + 1;
         Result.Goals (Result.Goal_N) :=
           (Kind => Persuade, Contact => 2);
      end if;
      if Result.Plan.Kind in Snatch | Contract then
         Result.Goal_N := Result.Goal_N + 1;
         Result.Goals (Result.Goal_N) := (Kind => Acquire, Item => 1);
         Result.Goal_N := Result.Goal_N + 1;
         Result.Goals (Result.Goal_N) := (Kind => Eliminate, Target => 3);
      end if;
      Result.Goal_N := Result.Goal_N + 1;
      Result.Goals (Result.Goal_N) :=
        (Kind => Evacuate,
         Zone_X => Result.Plan.Zone.X,
         Zone_Y => Result.Plan.Zone.Y);
      if Result.Plan.Kind in Briefing | Contract then
         Add_Wait (Result.Lines, 1, 12);
      end if;
      if Result.Plan.Kind in Snatch | Contract then
         Add_Walk (Result.Lines, 1, Result.Plan.Case_At);
         Add_Pick (Result.Lines);
      end if;
      Add_Walk (Result.Lines, 1, Result.Plan.Zone);
      if Result.Plan.Kind in Snatch | Contract then
         Add_Shot (Result.Lines);
      end if;
      Add_Wait (Result.Lines, 2, 100);
      Add_Wait (Result.Lines, 5, 100);
      Add_Walk (Result.Lines, 7, Result.Plan.Beat_A);
      Add_Walk (Result.Lines, 8, Result.Plan.Beat_B);
      return Result;
   end Assemble;

   function Play
     (M : Map.City;
      Seed : RNG.Word;
      Max_Ticks : Natural) return Trace
   is
      Ready : Bundle := Assemble (M, Seed);
   begin
      return Mission.Play
        (M, Ready.Group, Ready.Items, Ready.Fleet,
         Ready.Goals (1 .. Ready.Goal_N), Ready.Lines, Max_Ticks);
   end Play;

   function Solve (M : Map.City; Seed : RNG.Word) return Trace is
      Ready : Bundle := Assemble (M, Seed);
   begin
      return Mission.Play
        (M, Ready.Group, Ready.Items, Ready.Fleet,
         Ready.Goals (1 .. Ready.Goal_N), Ready.Lines, Ready.Plan.Cap);
   end Solve;

   function Car_Moved (M : Map.City; Seed : RNG.Word) return Boolean is
      Ready : Bundle := Assemble (M, Seed);
      Run : constant Trace := Mission.Play
        (M, Ready.Group, Ready.Items, Ready.Fleet,
         Ready.Goals (1 .. Ready.Goal_N), Ready.Lines, Ready.Plan.Cap);
   begin
      return Run.Outcome.Outcome = Won
        and then (Vehicles.Tile_X (Ready.Fleet (3)) /= Ready.Plan.Car.X
                  or else Vehicles.Tile_Y (Ready.Fleet (3))
                    /= Ready.Plan.Car.Y);
   end Car_Moved;

end Megacorp.Mission.Gen;
