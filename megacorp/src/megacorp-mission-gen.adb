--  SPDX-License-Identifier: MIT
--  Copyright (c) 2026 Robert Boettcher

with Megacorp.Actions;
with Megacorp.Path;
with Megacorp.Peds;
with Megacorp.Shots;
with Megacorp.Vehicles;
with Megacorp.Weapons;

package body Megacorp.Mission.Gen is
   use type Map.Point;
   use type Map.Terrain;
   use type Map.Gen.District;
   use type Behaviour.Role;
   use type Path.Status;
   Gap : constant := 16;
   Run : constant := 6;

   type Stage is record
      X : Positive := 1;
      Y : Positive := 1;
      East : Boolean := True;
   end record;

   Max_List : constant := 16;

   type Stage_List is array (1 .. Max_List) of Stage;

   type Hold_List is array (1 .. 400) of Map.Point;

   type Bundle (People, Motors : Positive) is record
      Plan   : Scene;
      Group  : Behaviour.Crowd (1 .. People);
      Items  : Actions.Bag (1 .. 2);
      Fleet  : Vehicles.Fleet (1 .. Motors);
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
   function District_Run
     (M : Map.City;
      Seed : RNG.Word;
      Plan : Scene;
      Held : Hold_List;
      Used : Natural;
      Which : Map.Gen.District;
      Start, Goal : out Map.Point) return Boolean;
   function Tiles_Of
     (M : Map.City; Seed : RNG.Word; Which : Map.Gen.District)
     return Natural;
   function Quota (Tiles, Rate, Low, High : Natural) return Natural;
   procedure Add_Seat
     (Plan : in out Scene;
      Here : Map.Point;
      Job : Behaviour.Role;
      Work : Duty;
      Aim : Map.Point;
      Motor : Positive);
   procedure Add_Motor
     (Plan : in out Scene;
      Here, Aim : Map.Point;
      Moves, Van : Boolean);
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
   procedure Add_Shot
     (Lines : in out Command_Lists.Vector; Target : Peds.Ped_Id);

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

   function District_Run
     (M : Map.City;
      Seed : RNG.Word;
      Plan : Scene;
      Held : Hold_List;
      Used : Natural;
      Which : Map.Gen.District;
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
                 or else Zone_Of (M, Seed, X + Step, Y) /= Which
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
                 or else Zone_Of (M, Seed, X, Y + Step) /= Which
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
   end District_Run;

   function Tiles_Of
     (M : Map.City; Seed : RNG.Word; Which : Map.Gen.District)
     return Natural
   is
      Total : Natural := 0;
   begin
      for Y in 1 .. M.Height loop
         for X in 1 .. M.Width loop
            if Zone_Of (M, Seed, X, Y) = Which then
               Total := Total + 1;
            end if;
         end loop;
      end loop;
      return Total;
   end Tiles_Of;

   function Quota (Tiles, Rate, Low, High : Natural) return Natural is
      Raw : Natural := (Tiles * Rate) / 1024;
   begin
      if Raw < Low then
         Raw := Low;
      end if;
      if Raw > High then
         Raw := High;
      end if;
      return Raw;
   end Quota;

   procedure Add_Seat
     (Plan : in out Scene;
      Here : Map.Point;
      Job : Behaviour.Role;
      Work : Duty;
      Aim : Map.Point;
      Motor : Positive)
   is
   begin
      pragma Assert (Plan.People < Max_People);
      Plan.People := Plan.People + 1;
      Plan.Seat (Plan.People) :=
        (Spot => Here, Job => Job, Work => Work,
         Aim => Aim, Motor => Motor);
   end Add_Seat;

   procedure Add_Motor
     (Plan : in out Scene;
      Here, Aim : Map.Point;
      Moves, Van : Boolean)
   is
   begin
      pragma Assert (Plan.Motors < Max_Motors);
      Plan.Motors := Plan.Motors + 1;
      Plan.Motor (Plan.Motors) :=
        (Spot => Here, Aim => Aim, Moves => Moves, Van => Van);
   end Add_Motor;

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
      Plan := (others => <>);
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
      Plan.People := 0;
      Plan.Motors := 0;
      Plan.Squad := RNG.Pick (Mission_G, 1, 4);
      declare
         Lead_At : constant Map.Point := Plan.Agent;
         Talk_At : constant Map.Point := Plan.Contact;
         Watch : constant Map.Point := Plan.Target;
      begin
         Add_Seat
           (Plan, Lead_At, Behaviour.Agent, Lead, Lead_At, 1);
         Add_Seat
           (Plan, Talk_At, Behaviour.Civilian, Contact, Talk_At, 1);
         Add_Seat
           (Plan, Watch, Behaviour.Guard, Sentry, Watch, 1);
      end;
      declare
         Placed : Natural := 0;
         Ax : Integer;
         Ay : Integer;
      begin
         for Step in 0 .. Run - 1 loop
            for Offset in -1 .. 1 loop
               if Offset /= 0 and then Placed < Plan.Squad - 1 then
                  Ax := Chosen.X + Offset;
                  Ay := Chosen.Y + Step;
                  if Is_Walk (M, Ax, Ay)
                    and then not Kept (Held, Used, (X => Ax, Y => Ay))
                    and then (Ax /= Plan.Target.X
                              or else Ay /= Plan.Target.Y)
                  then
                     Add_Seat
                       (Plan, (X => Ax, Y => Ay), Behaviour.Agent, Ally,
                        (X => Ax, Y => Ay), 1);
                     Keep (Held, Used, (X => Ax, Y => Ay));
                     Placed := Placed + 1;
                  end if;
               end if;
            end loop;
         end loop;
         Plan.Squad := Placed + 1;
      end;
      declare
         Need : constant Natural :=
           Quota (Tiles_Of (M, Seed, Map.Gen.Corporate), 4, 3, 8);
         Got : Natural := 1;
      begin
         while Got < Need loop
            Found := Other_Post (M, Seed, Plan, Held, Used, Here);
            exit when not Found;
            if Got = 1 then
               Plan.Guard := Here;
            end if;
            Add_Seat
              (Plan, Here, Behaviour.Guard, Post, Here, 1);
            Keep (Held, Used, Here);
            Got := Got + 1;
         end loop;
         if Plan.Guard = (X => 1, Y => 1) then
            Plan.Guard := Plan.Target;
         end if;
      end;
      for Which in Map.Gen.District loop
         declare
            Rate : Natural := 2;
            Low : Natural := 2;
            High : Natural := 8;
            Need : Natural;
            Have : Natural := 0;
         begin
            case Which is
               when Map.Gen.Residential =>
                  Rate := 3;
                  Low := 12;
                  High := 28;
               when Map.Gen.Slums =>
                  Rate := 3;
                  Low := 4;
                  High := 14;
               when Map.Gen.Industrial =>
                  Rate := 2;
                  Low := 4;
                  High := 12;
               when Map.Gen.Corporate =>
                  Rate := 2;
                  Low := 2;
                  High := 8;
            end case;
            if Which = Map.Gen.Industrial or else Which = Map.Gen.Slums
            then
               Found := District_Run
                 (M, Seed, Plan, Held, Used, Which, Here, There);
               pragma Assert (Found);
               if Here.Y = There.Y then
                  for X in Here.X .. There.X loop
                     Keep (Held, Used, (X => X, Y => Here.Y));
                  end loop;
               else
                  for Y in Here.Y .. There.Y loop
                     Keep (Held, Used, (X => Here.X, Y => Y));
                  end loop;
               end if;
               Add_Motor (Plan, Here, There, True, Which = Map.Gen.Slums);
               Add_Seat
                 (Plan, Here, Behaviour.Civilian, Driver, There,
                  Plan.Motors);
               if Which = Map.Gen.Industrial then
                  Plan.Car := Here;
                  Plan.Car_Goal := There;
                  Plan.Driver := Here;
               end if;
            end if;
            Need := Quota (Tiles_Of (M, Seed, Which), Rate, Low, High);
            for I in 1 .. Plan.People loop
               if Plan.Seat (I).Job = Behaviour.Civilian
                 and then Zone_Of
                   (M, Seed, Plan.Seat (I).Spot.X, Plan.Seat (I).Spot.Y)
                   = Which
               then
                  Have := Have + 1;
               end if;
            end loop;
            while Have < Need loop
               Found := Spare_Walk
                 (M, Seed, Plan, Held, Used, Which, Here);
               pragma Assert (Found);
               if Which = Map.Gen.Residential
                 and then Plan.Resident = (X => 1, Y => 1)
               then
                  Plan.Resident := Here;
               end if;
               Add_Seat
                 (Plan, Here, Behaviour.Civilian, Citizen, Here, 1);
               Keep (Held, Used, Here);
               Have := Have + 1;
            end loop;
         end;
      end loop;
      Found := Spare_Walk
        (M, Seed, Plan, Held, Used, Map.Gen.Residential, Here);
      pragma Assert (Found);
      Plan.Cache := Here;
      Keep (Held, Used, Here);
      for Beat in 1 .. 4 loop
         Found := Road_Run
           (M, Plan, Held, Used, Beat mod 2 = 1, Here, There);
         pragma Assert (Found);
         if Here.Y = There.Y then
            for X in Here.X .. There.X loop
               Keep (Held, Used, (X => X, Y => Here.Y));
            end loop;
         else
            for Y in Here.Y .. There.Y loop
               Keep (Held, Used, (X => Here.X, Y => Y));
            end loop;
         end if;
         if Beat = 1 then
            Plan.Police_A := Here;
            Plan.Beat_A := There;
         elsif Beat = 2 then
            Plan.Police_B := Here;
            Plan.Beat_B := There;
         end if;
         Add_Seat (Plan, Here, Behaviour.Police, Officer, There, 1);
      end loop;
      for Park in 1 .. 6 loop
         Found := Spare_Road (M, Plan, Held, Used, Here);
         pragma Assert (Found);
         if Park = 1 then
            Plan.Park_A := Here;
         elsif Park = 2 then
            Plan.Park_B := Here;
         end if;
         Add_Motor (Plan, Here, Here, False, Park mod 2 = 0);
         Keep (Held, Used, Here);
      end loop;
   end Place;

   function Objective (Kind : Recipe_Kind) return String is
   begin
      case Kind is
         when Briefing =>
            return "Meet the contact, then the zone.";
         when Snatch =>
            return "Carry the case to the zone.";
         when Contract =>
            return "Sabotage the marked building.";
      end case;
   end Objective;

   function Estimate (Kind : Recipe_Kind) return String is
   begin
      case Kind is
         when Briefing =>
            return "one guard";
         when Snatch =>
            return "guard and police";
         when Contract =>
            return "heavy guard and police";
      end case;
   end Estimate;

   function Preview (Seed : RNG.Word) return Recipe_Kind is
      Mission_G : RNG.Generator :=
        RNG.Child (RNG.Make (Seed), RNG.Mission, 1);
      Pick : constant Integer := RNG.Pick (Mission_G, 0, 2);
   begin
      case Pick is
         when 0 =>
            return Briefing;
         when 1 =>
            return Snatch;
         when others =>
            return Contract;
      end case;
   end Preview;

   function Build (M : Map.City; Seed : RNG.Word) return Scene is
      Plan : Scene;
   begin
      Place (M, Seed, Plan);
      return Plan;
   end Build;

   function Same (A, B : Scene) return Boolean is
      Match : Boolean;
   begin
      Match := A.Kind = B.Kind
        and then A.Level = B.Level
        and then A.Cap = B.Cap
        and then A.Squad = B.Squad
        and then A.People = B.People
        and then A.Motors = B.Motors
        and then A.Contact = B.Contact
        and then A.Agent = B.Agent
        and then A.Case_At = B.Case_At
        and then A.Stand = B.Stand
        and then A.Target = B.Target
        and then A.Zone = B.Zone
        and then A.Car = B.Car
        and then A.Car_Goal = B.Car_Goal
        and then A.Cache = B.Cache;
      if not Match then
         return False;
      end if;
      for I in 1 .. A.People loop
         if A.Seat (I).Spot /= B.Seat (I).Spot
           or else A.Seat (I).Job /= B.Seat (I).Job
           or else A.Seat (I).Work /= B.Seat (I).Work
         then
            return False;
         end if;
      end loop;
      for I in 1 .. A.Motors loop
         if A.Motor (I).Spot /= B.Motor (I).Spot
           or else A.Motor (I).Moves /= B.Motor (I).Moves
         then
            return False;
         end if;
      end loop;
      return True;
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
      for I in 1 .. Plan.People loop
         if Plan.Seat (I).Job = Behaviour.Civilian
           and then Zone_Of
             (M, Map.Layout_Seed (M),
              Plan.Seat (I).Spot.X, Plan.Seat (I).Spot.Y) = Which
         then
            Total := Total + 1;
         end if;
      end loop;
      return Total;
   end Civilians_In;

   function In_Band (M : Map.City; Plan : Scene) return Boolean is
      Guards : Natural := 0;
      Police : Natural := 0;
      Agents : Natural := 0;
      Moving : Natural := 0;
      Parked : Natural := 0;
   begin
      for I in 1 .. Plan.People loop
         case Plan.Seat (I).Job is
            when Behaviour.Guard =>
               Guards := Guards + 1;
            when Behaviour.Police =>
               Police := Police + 1;
            when Behaviour.Agent =>
               Agents := Agents + 1;
            when others =>
               null;
         end case;
      end loop;
      for I in 1 .. Plan.Motors loop
         if Plan.Motor (I).Moves then
            Moving := Moving + 1;
         else
            Parked := Parked + 1;
         end if;
      end loop;
      return Civilians_In (M, Plan, Map.Gen.Residential) in 12 .. 32
        and then Civilians_In (M, Plan, Map.Gen.Slums) in 4 .. 16
        and then Civilians_In (M, Plan, Map.Gen.Industrial) in 4 .. 14
        and then Civilians_In (M, Plan, Map.Gen.Corporate) in 1 .. 10
        and then Guards in 3 .. 10
        and then Police = 4
        and then Agents in 1 .. 4
        and then Moving = 2
        and then Parked = 6
        and then Corp_Post
          (M, Map.Layout_Seed (M), Plan.Target.X, Plan.Target.Y);
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

   procedure Add_Shot
     (Lines : in out Command_Lists.Vector; Target : Peds.Ped_Id)
   is
      C : Command;
   begin
      C.At_Tick := 1;
      C.Who := 1;
      C.What := Shoot;
      C.Target := Target;
      Lines.Append (C);
   end Add_Shot;

   function Assemble (M : Map.City; Seed : RNG.Word) return Bundle is
      Draft : Scene;
      Gun : constant Weapons.Kind := Weapons.Pistol;
   begin
      Place (M, Seed, Draft);
      pragma Assert (Draft.People > 0 and then Draft.Motors > 0);
      pragma Assert (Reachable (M, Draft));
      declare
         Result : Bundle (Draft.People, Draft.Motors);
         Who : Peds.Ped_Id;
         Sort : Vehicles.Kind;
      begin
         Result.Plan := Draft;
         for I in 1 .. Draft.People loop
            Who := Peds.Ped_Id (I);
            if Draft.Seat (I).Work in Sentry | Post then
               Result.Group (I) := Behaviour.Enlist
                 (Who, Draft.Seat (I).Job, Draft.Seat (I).Spot, M, Seed,
                  Draft.Seat (I).Spot, Draft.Seat (I).Spot);
            else
               Result.Group (I) := Behaviour.Enlist
                 (Who, Draft.Seat (I).Job, Draft.Seat (I).Spot, M, Seed);
            end if;
            if Draft.Seat (I).Job in Behaviour.Agent | Behaviour.Guard
            then
               Behaviour.Arm
                 (Result.Group, I, Gun, Weapons.Profile (Gun).Magazine);
            end if;
         end loop;
         Result.Items (1) :=
           (Ident => 1,
            X => Draft.Case_At.X,
            Y => Draft.Case_At.Y,
            Here => True);
         Result.Items (2) :=
           (Ident => 2,
            X => Draft.Cache.X,
            Y => Draft.Cache.Y,
            Here => True);
         for I in 1 .. Draft.Motors loop
            if Draft.Motor (I).Van then
               Sort := Vehicles.Van;
            else
               Sort := Vehicles.Car;
            end if;
            Result.Fleet (I) := Vehicles.Park
              (I, Sort, Draft.Motor (I).Spot, M);
         end loop;
         for I in 1 .. Draft.People loop
            Who := Peds.Ped_Id (I);
            case Draft.Seat (I).Work is
               when Lead =>
                  null;
               when Driver =>
                  Behaviour.Order
                    (Result.Group, I,
                     (1 => Actions.Make_Enter
                        (Vehicles.Vehicle_Id (Draft.Seat (I).Motor)),
                      2 => Actions.Make_Drive
                        (Vehicles.Vehicle_Id (Draft.Seat (I).Motor),
                         Draft.Seat (I).Aim),
                      3 => Actions.Make_Exit
                        (Vehicles.Vehicle_Id (Draft.Seat (I).Motor)),
                      4 => Actions.Make_Wait (100)),
                     Actions.Replace);
               when Officer =>
                  Add_Walk (Result.Lines, Who, Draft.Seat (I).Aim);
                  Add_Wait (Result.Lines, Who, 100);
                  Add_Wait (Result.Lines, Who, 100);
               when Ally | Contact | Citizen =>
                  Add_Wait (Result.Lines, Who, 100);
                  Add_Wait (Result.Lines, Who, 100);
               when Sentry | Post =>
                  null;
            end case;
         end loop;
         Result.Goal_N := 0;
         if Draft.Kind in Briefing | Contract then
            Result.Goal_N := Result.Goal_N + 1;
            Result.Goals (Result.Goal_N) :=
              (Kind => Persuade, Contact => 2);
         end if;
         if Draft.Kind in Snatch | Contract then
            Result.Goal_N := Result.Goal_N + 1;
            Result.Goals (Result.Goal_N) :=
              (Kind => Acquire, Item => 1);
            Result.Goal_N := Result.Goal_N + 1;
            Result.Goals (Result.Goal_N) :=
              (Kind => Eliminate, Target => 3);
         end if;
         Result.Goal_N := Result.Goal_N + 1;
         Result.Goals (Result.Goal_N) :=
           (Kind => Evacuate,
            Zone_X => Draft.Zone.X,
            Zone_Y => Draft.Zone.Y);
         if Draft.Kind in Briefing | Contract then
            Add_Wait (Result.Lines, 1, 12);
         end if;
         if Draft.Kind in Snatch | Contract then
            Add_Walk (Result.Lines, 1, Draft.Case_At);
            Add_Pick (Result.Lines);
         end if;
         Add_Walk (Result.Lines, 1, Draft.Zone);
         if Draft.Kind in Snatch | Contract then
            Add_Shot (Result.Lines, 3);
         end if;
         return Result;
      end;
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
        and then (Vehicles.Tile_X (Ready.Fleet (1))
                  /= Ready.Plan.Motor (1).Spot.X
                  or else Vehicles.Tile_Y (Ready.Fleet (1))
                    /= Ready.Plan.Motor (1).Spot.Y);
   end Car_Moved;

end Megacorp.Mission.Gen;
