--  SPDX-License-Identifier: MIT
--  Copyright (c) 2026 Robert Boettcher

with Megacorp.Path;
with Megacorp.Shots;

package body Megacorp.Behaviour is
   use type Map.Point;
   use type Path.Status;
   use type Peds.State_Kind;

   function Here_Of (A : Actions.Actor) return Map.Point;
   function Busy (A : Actions.Actor) return Boolean;
   function Dir_Of (From, To : Map.Point) return Map.Eight_Way;
   function Can_See
     (M : Map.City; From, To : Map.Point) return Boolean;
   function Hear_Shot
     (Bodies : Actions.Cast;
      Heard : out Map.Point) return Boolean;
   function Nearest
     (Group : Crowd;
      Bodies : Actions.Cast;
      Self : Positive;
      M : Map.City;
      Want : Role;
      Need_Range : Boolean) return Natural;
   function Beside
     (Group : Crowd;
      Bodies : Actions.Cast;
      Self : Positive) return Natural;
   function Fleer_Near
     (Group : Crowd;
      Bodies : Actions.Cast;
      Self : Positive;
      Threat : out Map.Point) return Boolean;
   function Refuge
     (M : Map.City; From, Threat : Map.Point) return Map.Point;
   function Neighbour
     (M : Map.City;
      From : Map.Point;
      Dice : in out RNG.Generator) return Map.Point;
   procedure Order_Walk
     (Bodies : in out Actions.Cast;
      Index : Positive;
      Goal : Map.Point);
   procedure Order_Shoot
     (Bodies : in out Actions.Cast;
      Index : Positive;
      Target : Peds.Ped_Id;
      Gun : Weapons.Kind);
   procedure Order_Turn
     (Bodies : in out Actions.Cast;
      Index : Positive;
      Dir : Map.Eight_Way);
   procedure Order_Follow
     (Bodies : in out Actions.Cast;
      Index : Positive;
      Target : Peds.Ped_Id);
   procedure Do_Civilian
     (Group : in out Crowd;
      Bodies : in out Actions.Cast;
      Index : Positive;
      M : Map.City;
      At_Tick : Natural;
      Heard : Boolean;
      Bang : Map.Point);
   procedure Do_Guard
     (Group : in out Crowd;
      Bodies : in out Actions.Cast;
      Index : Positive;
      M : Map.City);
   procedure Do_Police
     (Group : in out Crowd;
      Bodies : in out Actions.Cast;
      Index : Positive;
      M : Map.City;
      Heard : Boolean;
      Bang : Map.Point);
   procedure Do_Hostile
     (Group : in out Crowd;
      Bodies : in out Actions.Cast;
      Index : Positive;
      M : Map.City);
   procedure Do_Agent
     (Group : in out Crowd;
      Bodies : in out Actions.Cast;
      Index : Positive);
   procedure React
     (Group : in out Crowd;
      Bodies : in out Actions.Cast;
      M : Map.City;
      At_Tick : Natural);
   procedure Append
     (Trace : in out Frame_Lists.Vector;
      Group : Crowd;
      At_Tick : Natural);
   procedure Check_Street
     (Trace : Frame_Lists.Vector; Plan : Street_Plan);
   function Open_Tile (M : Map.City; At_Point : Map.Point) return Boolean;
   function Count_At
     (Trace : Frame_Lists.Vector;
      Who : Peds.Ped_Id;
      At_Point : Map.Point) return Natural;
   function Saw
     (Trace : Frame_Lists.Vector;
      Who : Peds.Ped_Id;
      Which : Mood) return Boolean;
   function Fired_At
     (Trace : Frame_Lists.Vector; Who : Peds.Ped_Id) return Natural;
   function Warned_At
     (Trace : Frame_Lists.Vector; Who : Peds.Ped_Id) return Natural;
   function Fled_From
     (Trace : Frame_Lists.Vector;
      Who : Peds.Ped_Id;
      Threat : Map.Point) return Boolean;

   function Here_Of (A : Actions.Actor) return Map.Point is
   begin
      return (X => Actions.Ped_X (A), Y => Actions.Ped_Y (A));
   end Here_Of;

   function Busy (A : Actions.Actor) return Boolean is
   begin
      return Actions.Length (A) > 0 or else Actions.Is_Pending (A);
   end Busy;

   function Dir_Of (From, To : Map.Point) return Map.Eight_Way is
      DX : constant Integer := To.X - From.X;
      DY : constant Integer := To.Y - From.Y;
   begin
      if DX = 0 and then DY < 0 then
         return Map.North;
      elsif DX > 0 and then DY < 0 then
         return Map.North_East;
      elsif DX > 0 and then DY = 0 then
         return Map.East;
      elsif DX > 0 and then DY > 0 then
         return Map.South_East;
      elsif DX = 0 and then DY > 0 then
         return Map.South;
      elsif DX < 0 and then DY > 0 then
         return Map.South_West;
      elsif DX < 0 and then DY = 0 then
         return Map.West;
      elsif DX < 0 and then DY < 0 then
         return Map.North_West;
      else
         return Map.South;
      end if;
   end Dir_Of;

   function Can_See
     (M : Map.City; From, To : Map.Point) return Boolean
   is
   begin
      return Shots.Distance (From, To) <= Sight_Radius
        and then not Shots.Blocked (M, From, To);
   end Can_See;

   function Hear_Shot
     (Bodies : Actions.Cast;
      Heard : out Map.Point) return Boolean
   is
      Found : Boolean := False;
      Who   : Peds.Ped_Id := Peds.Ped_Id'Last;
   begin
      Heard := (X => 1, Y => 1);
      for I in Bodies'Range loop
         if Actions.Shot_This_Tick (Bodies (I))
           and then (not Found
                     or else Actions.Ped_Ident (Bodies (I)) < Who)
         then
            Found := True;
            Who := Actions.Ped_Ident (Bodies (I));
            Heard := Here_Of (Bodies (I));
         end if;
      end loop;
      return Found;
   end Hear_Shot;

   function Nearest
     (Group : Crowd;
      Bodies : Actions.Cast;
      Self : Positive;
      M : Map.City;
      Want : Role;
      Need_Range : Boolean) return Natural
   is
      Best  : Natural := 0;
      Best_D : Natural := Natural'Last;
      Dist  : Natural;
      From  : constant Map.Point := Here_Of (Bodies (Self));
      There : Map.Point;
   begin
      for I in Group'Range loop
         if I /= Self
           and then Group (I).Job = Want
           and then Actions.Ped_Alive (Bodies (I))
         then
            There := Here_Of (Bodies (I));
            Dist := Shots.Distance (From, There);
            if Can_See (M, From, There)
              and then (not Need_Range
                        or else Shots.In_Range
                          (Group (Self).Gun, From, There))
              and then (Best = 0
                        or else Dist < Best_D
                        or else (Dist = Best_D
                                 and then Ident (Group (I))
                                   < Ident (Group (Best))))
            then
               Best := I;
               Best_D := Dist;
            end if;
         end if;
      end loop;
      return Best;
   end Nearest;

   function Beside
     (Group : Crowd;
      Bodies : Actions.Cast;
      Self : Positive) return Natural
   is
      Best : Natural := 0;
      From : constant Map.Point := Here_Of (Bodies (Self));
   begin
      for I in Group'Range loop
         if I /= Self
           and then Group (I).Job = Civilian
           and then Group (I).Temper in Calm | Wander
           and then Actions.Ped_Alive (Bodies (I))
           and then Shots.Distance (From, Here_Of (Bodies (I))) <= 1
           and then (Best = 0
                     or else Ident (Group (I)) < Ident (Group (Best)))
         then
            Best := I;
         end if;
      end loop;
      return Best;
   end Beside;

   function Fleer_Near
     (Group : Crowd;
      Bodies : Actions.Cast;
      Self : Positive;
      Threat : out Map.Point) return Boolean
   is
      From : constant Map.Point := Here_Of (Bodies (Self));
   begin
      Threat := From;
      for I in Group'Range loop
         if I /= Self
           and then Group (I).Job = Civilian
           and then Group (I).Temper = Flee
           and then Shots.Distance (From, Here_Of (Bodies (I)))
             <= Spread_Radius
         then
            Threat := Here_Of (Bodies (I));
            return True;
         end if;
      end loop;
      return False;
   end Fleer_Near;

   function Refuge
     (M : Map.City; From, Threat : Map.Point) return Map.Point
   is
      DX : Integer := 0;
      DY : Integer := 0;
      X  : Integer;
      Y  : Integer;
      Goal : Map.Point;
      Route : Path.Result;
   begin
      if abs (From.X - Threat.X) >= abs (From.Y - Threat.Y) then
         if From.X >= Threat.X then
            DX := 1;
         else
            DX := -1;
         end if;
      elsif From.Y >= Threat.Y then
         DY := 1;
      else
         DY := -1;
      end if;
      for K in reverse 1 .. 5 loop
         X := From.X + K * DX;
         Y := From.Y + K * DY;
         if Map.In_Bounds (M, X, Y)
           and then Map.Tile_At (M, X, Y).Walkable
         then
            Goal := (X => X, Y => Y);
            Route := Path.Find (M, From, Goal, Path.Walk);
            if Path.Kind (Route) = Path.Found then
               return Goal;
            end if;
         end if;
      end loop;
      return From;
   end Refuge;

   function Neighbour
     (M : Map.City;
      From : Map.Point;
      Dice : in out RNG.Generator) return Map.Point
   is
      type Step is record
         DX : Integer;
         DY : Integer;
      end record;
      Near : constant array (1 .. 4) of Step :=
        ((0, -1), (1, 0), (0, 1), (-1, 0));
      Spot : array (1 .. 4) of Map.Point;
      Count : Natural := 0;
      X : Integer;
      Y : Integer;
      Pick : Integer;
   begin
      for I in Near'Range loop
         X := From.X + Near (I).DX;
         Y := From.Y + Near (I).DY;
         if Map.In_Bounds (M, X, Y)
           and then Map.Tile_At (M, X, Y).Walkable
         then
            Count := Count + 1;
            Spot (Count) := (X => X, Y => Y);
         end if;
      end loop;
      if Count = 0 then
         return From;
      end if;
      Pick := RNG.Pick (Dice, 1, Count);
      return Spot (Pick);
   end Neighbour;

   procedure Order_Walk
     (Bodies : in out Actions.Cast;
      Index : Positive;
      Goal : Map.Point)
   is
   begin
      if Goal = Here_Of (Bodies (Index)) then
         return;
      end if;
      Actions.Order
        (Bodies, Index,
         (1 => Actions.Make_Walk (Goal)),
         Actions.Replace);
   end Order_Walk;

   procedure Order_Shoot
     (Bodies : in out Actions.Cast;
      Index : Positive;
      Target : Peds.Ped_Id;
      Gun : Weapons.Kind)
   is
   begin
      Actions.Order
        (Bodies, Index,
         (1 => Actions.Make_Shoot (Target, Gun)),
         Actions.Replace);
   end Order_Shoot;

   procedure Order_Turn
     (Bodies : in out Actions.Cast;
      Index : Positive;
      Dir : Map.Eight_Way)
   is
   begin
      Actions.Order
        (Bodies, Index,
         (1 => Actions.Make_Turn (Dir)),
         Actions.Replace);
   end Order_Turn;

   procedure Order_Follow
     (Bodies : in out Actions.Cast;
      Index : Positive;
      Target : Peds.Ped_Id)
   is
   begin
      Actions.Order
        (Bodies, Index,
         (1 => Actions.Make_Follow (Target)),
         Actions.Replace);
   end Order_Follow;

   procedure Do_Civilian
     (Group : in out Crowd;
      Bodies : in out Actions.Cast;
      Index : Positive;
      M : Map.City;
      At_Tick : Natural;
      Heard : Boolean;
      Bang : Map.Point)
   is
      Here   : constant Map.Point := Here_Of (Bodies (Index));
      Threat : Map.Point;
      Scared : Boolean;
   begin
      if not Actions.Ped_Alive (Bodies (Index)) then
         return;
      end if;
      if Group (Index).Temper = Persuaded then
         if Group (Index).Has_Focus
           and then not Busy (Bodies (Index))
         then
            Order_Follow
              (Bodies, Index, Group (Index).Focus);
         end if;
         return;
      end if;
      Scared := Heard
        and then Shots.Distance (Here, Bang) <= Hear_Radius;
      if not Scared then
         Scared := Fleer_Near (Group, Bodies, Index, Threat);
      else
         Threat := Bang;
      end if;
      if Scared then
         if Group (Index).Temper /= Flee
           or else not Busy (Bodies (Index))
         then
            Group (Index).Temper := Flee;
            Order_Walk (Bodies, Index, Refuge (M, Here, Threat));
         end if;
         return;
      end if;
      if Group (Index).Temper = Flee and then not Busy (Bodies (Index)) then
         Group (Index).Temper := Calm;
      end if;
      if Group (Index).Temper = Calm
        and then not Busy (Bodies (Index))
        and then At_Tick > 0
        and then At_Tick mod Wander_Every = 0
      then
         Group (Index).Temper := Wander;
         Order_Walk
           (Bodies, Index,
            Neighbour (M, Here, Group (Index).Dice));
      elsif Group (Index).Temper = Wander
        and then not Busy (Bodies (Index))
      then
         Group (Index).Temper := Calm;
      end if;
   end Do_Civilian;

   procedure Do_Guard
     (Group : in out Crowd;
      Bodies : in out Actions.Cast;
      Index : Positive;
      M : Map.City)
   is
      Foe : constant Natural :=
        Nearest (Group, Bodies, Index, M, Hostile, True);
      Goal : Map.Point;
   begin
      if not Actions.Ped_Alive (Bodies (Index)) then
         return;
      end if;
      if Foe /= 0 then
         Group (Index).Temper := Engage;
         Group (Index).Focus := Ident (Group (Foe));
         Group (Index).Has_Focus := True;
         if not Busy (Bodies (Index)) then
            Order_Shoot
              (Bodies, Index, Ident (Group (Foe)), Group (Index).Gun);
         end if;
         return;
      end if;
      if Group (Index).Temper = Engage then
         Group (Index).Temper := Patrol;
      end if;
      if not Busy (Bodies (Index)) then
         Group (Index).Temper := Patrol;
         if Group (Index).Go_B then
            Goal := Group (Index).Patrol_B;
         else
            Goal := Group (Index).Patrol_A;
         end if;
         Group (Index).Go_B := not Group (Index).Go_B;
         Order_Walk (Bodies, Index, Goal);
      end if;
   end Do_Guard;

   procedure Do_Police
     (Group : in out Crowd;
      Bodies : in out Actions.Cast;
      Index : Positive;
      M : Map.City;
      Heard : Boolean;
      Bang : Map.Point)
   is
      Foe  : constant Natural :=
        Nearest (Group, Bodies, Index, M, Hostile, False);
      Here : constant Map.Point := Here_Of (Bodies (Index));
   begin
      if not Actions.Ped_Alive (Bodies (Index)) then
         return;
      end if;
      if Group (Index).Temper = Warn then
         if Foe = 0
           or else Ident (Group (Foe)) /= Group (Index).Focus
         then
            Group (Index).Temper := Calm;
            Group (Index).Warn_Left := 0;
         elsif Group (Index).Warn_Left = 0 then
            Group (Index).Temper := Engage;
            if not Busy (Bodies (Index))
              and then Shots.In_Range
                (Group (Index).Gun, Here, Here_Of (Bodies (Foe)))
            then
               Order_Shoot
                 (Bodies, Index, Ident (Group (Foe)),
                  Group (Index).Gun);
            end if;
         else
            Group (Index).Warn_Left := Group (Index).Warn_Left - 1;
         end if;
      elsif Group (Index).Temper = Engage then
         if Foe = 0 then
            Group (Index).Temper := Calm;
         elsif not Busy (Bodies (Index))
           and then Shots.In_Range
             (Group (Index).Gun, Here, Here_Of (Bodies (Foe)))
         then
            Order_Shoot
              (Bodies, Index, Ident (Group (Foe)), Group (Index).Gun);
         end if;
      elsif Foe /= 0 then
         Group (Index).Temper := Warn;
         Group (Index).Warn_Left := Warn_Ticks;
         Group (Index).Focus := Ident (Group (Foe));
         Group (Index).Has_Focus := True;
         if not Busy (Bodies (Index)) then
            Order_Turn
              (Bodies, Index,
               Dir_Of (Here, Here_Of (Bodies (Foe))));
         end if;
      elsif Heard
        and then not Busy (Bodies (Index))
        and then Shots.Distance (Here, Bang) <= Hear_Radius
        and then not Can_See (M, Here, Bang)
      then
         Order_Walk (Bodies, Index, Bang);
      end if;
   end Do_Police;

   procedure Do_Hostile
     (Group : in out Crowd;
      Bodies : in out Actions.Cast;
      Index : Positive;
      M : Map.City)
   is
      Best : Natural := 0;
      Best_D : Natural := Natural'Last;
      From : constant Map.Point := Here_Of (Bodies (Index));
      Dist : Natural;
   begin
      if not Actions.Ped_Alive (Bodies (Index)) then
         return;
      end if;
      for I in Group'Range loop
         if I /= Index
           and then Group (I).Job /= Hostile
           and then Actions.Ped_Alive (Bodies (I))
         then
            Dist := Shots.Distance (From, Here_Of (Bodies (I)));
            if Can_See (M, From, Here_Of (Bodies (I)))
              and then Shots.In_Range
                (Group (Index).Gun, From, Here_Of (Bodies (I)))
              and then (Best = 0
                        or else Dist < Best_D
                        or else (Dist = Best_D
                                 and then Ident (Group (I))
                                   < Ident (Group (Best))))
            then
               Best := I;
               Best_D := Dist;
            end if;
         end if;
      end loop;
      if Best = 0 then
         if Group (Index).Temper = Engage then
            Group (Index).Temper := Calm;
         end if;
         return;
      end if;
      Group (Index).Temper := Engage;
      Group (Index).Focus := Ident (Group (Best));
      if not Busy (Bodies (Index)) then
         Order_Shoot
           (Bodies, Index, Ident (Group (Best)), Group (Index).Gun);
      end if;
   end Do_Hostile;

   procedure Do_Agent
     (Group : in out Crowd;
      Bodies : in out Actions.Cast;
      Index : Positive)
   is
      Who : constant Natural := Beside (Group, Bodies, Index);
   begin
      if not Actions.Ped_Alive (Bodies (Index)) or else Who = 0 then
         Group (Index).Has_Focus := False;
         Group (Index).Persuade_Left := 0;
         return;
      end if;
      if not Group (Index).Has_Focus
        or else Group (Index).Focus /= Ident (Group (Who))
      then
         Group (Index).Has_Focus := True;
         Group (Index).Focus := Ident (Group (Who));
         Group (Index).Persuade_Left := Persuade_Ticks;
         return;
      end if;
      if Group (Index).Persuade_Left > 0 then
         Group (Index).Persuade_Left :=
           Group (Index).Persuade_Left - 1;
      end if;
      if Group (Index).Persuade_Left = 0
        and then Group (Who).Temper in Calm | Wander
      then
         Group (Who).Temper := Persuaded;
         Group (Who).Has_Focus := True;
         Group (Who).Focus := Ident (Group (Index));
         Group (Index).Has_Focus := False;
      end if;
   end Do_Agent;

   procedure React
     (Group : in out Crowd;
      Bodies : in out Actions.Cast;
      M : Map.City;
      At_Tick : Natural)
   is
      Bang   : Map.Point;
      Heard  : constant Boolean := Hear_Shot (Bodies, Bang);
   begin
      declare
         type Rank is array (Positive range <>) of Positive;
         Order : Rank (Group'Range);
         Swap  : Positive;
      begin
         for I in Group'Range loop
            Order (I) := I;
         end loop;
         for I in Group'Range loop
            for J in I + 1 .. Group'Last loop
               if Ident (Group (Order (J))) < Ident (Group (Order (I))) then
                  Swap := Order (I);
                  Order (I) := Order (J);
                  Order (J) := Swap;
               end if;
            end loop;
         end loop;
         for K in Group'Range loop
            declare
               I : constant Positive := Order (K);
            begin
               case Group (I).Job is
                  when Civilian =>
                     Do_Civilian
                       (Group, Bodies, I, M, At_Tick, Heard, Bang);
                  when Guard =>
                     Do_Guard (Group, Bodies, I, M);
                  when Police =>
                     Do_Police (Group, Bodies, I, M, Heard, Bang);
                  when Hostile =>
                     Do_Hostile (Group, Bodies, I, M);
                  when Agent =>
                     Do_Agent (Group, Bodies, I);
               end case;
            end;
         end loop;
      end;
   end React;

   function Observe (Person : Mind) return Frame is
      Item : Frame;
   begin
      Item.Ident := Actions.Ped_Ident (Person.Person);
      Item.X := Actions.Ped_X (Person.Person);
      Item.Y := Actions.Ped_Y (Person.Person);
      Item.Along := Actions.Ped_Along (Person.Person);
      Item.Facing := Actions.Ped_Facing (Person.Person);
      Item.State := Actions.Ped_State (Person.Person);
      Item.Temper := Person.Temper;
      Item.Job := Person.Job;
      Item.Has_Action := Actions.Ran (Person.Person);
      if Item.Has_Action then
         Item.Action := Actions.Token_Strings.To_Bounded_String
           (Actions.Ran_Action (Person.Person));
      end if;
      Item.Health := Actions.Ped_Health (Person.Person);
      Item.Ammo := Actions.Ped_Ammo (Person.Person);
      Item.Alive := Actions.Ped_Alive (Person.Person);
      Item.Fired := Actions.Shot_This_Tick (Person.Person);
      Item.Landed := Actions.Shot_Landed (Person.Person);
      Item.At_X := Actions.Shot_X (Person.Person);
      Item.At_Y := Actions.Shot_Y (Person.Person);
      return Item;
   end Observe;

   procedure Append
     (Trace : in out Frame_Lists.Vector;
      Group : Crowd;
      At_Tick : Natural)
   is
      Item : Frame;
   begin
      for I in Group'Range loop
         Item := Observe (Group (I));
         Item.Tick := At_Tick;
         Trace.Append (Item);
      end loop;
   end Append;

   procedure Step
     (Group : in out Crowd;
      M : Map.City;
      Items : in out Actions.Bag;
      Fleet : in out Vehicles.Fleet;
      At_Tick : Positive)
   is
      Bodies : Actions.Cast (Group'Range);
   begin
      for I in Group'Range loop
         Bodies (I) := Group (I).Person;
      end loop;
      Actions.Tick (Bodies, M, Items, Fleet);
      for I in Group'Range loop
         Group (I).Person := Bodies (I);
      end loop;
      React (Group, Bodies, M, At_Tick);
      for I in Group'Range loop
         Group (I).Person := Bodies (I);
      end loop;
   end Step;

   procedure Order
     (Group : in out Crowd;
      Index : Positive;
      Planned : Actions.Action_Array;
      How : Actions.Mode)
   is
      Bodies : Actions.Cast (Group'Range);
   begin
      for I in Group'Range loop
         Bodies (I) := Group (I).Person;
      end loop;
      Actions.Order (Bodies, Index, Planned, How);
      Group (Index).Person := Bodies (Index);
   end Order;

   function Enlist
     (Who : Peds.Ped_Id;
      Job : Role;
      At_Point : Map.Point;
      M : Map.City;
      Seed : RNG.Word := 1;
      Patrol_A : Map.Point := (X => 1, Y => 1);
      Patrol_B : Map.Point := (X => 1, Y => 1)) return Mind
   is
      Result : Mind;
   begin
      Result.Person := Actions.Recruit (Who, At_Point, M, Seed);
      Result.Job := Job;
      Result.Seed := Seed;
      Result.Dice := RNG.Child
        (RNG.Make (Seed), RNG.Mission, RNG.Stream_Index (Who));
      Result.Patrol_A := Patrol_A;
      Result.Patrol_B := Patrol_B;
      Result.Go_B := True;
      if Job = Guard then
         Result.Temper := Patrol;
      else
         Result.Temper := Calm;
      end if;
      return Result;
   end Enlist;

   procedure Arm
     (Group : in out Crowd;
      Index : Positive;
      Gun : Weapons.Kind;
      Rounds : Natural)
   is
      Bodies : Actions.Cast (Index .. Index);
   begin
      Group (Index).Gun := Gun;
      Bodies (Index) := Group (Index).Person;
      Actions.Arm (Bodies, Index, Gun, Rounds);
      Group (Index).Person := Bodies (Index);
   end Arm;

   function Ident (M : Mind) return Peds.Ped_Id is
   begin
      return Actions.Ped_Ident (M.Person);
   end Ident;

   function Job_Of (M : Mind) return Role is
   begin
      return M.Job;
   end Job_Of;

   function Mood_Of (M : Mind) return Mood is
   begin
      return M.Temper;
   end Mood_Of;

   function Role_Token (Job : Role) return String is
   begin
      case Job is
         when Civilian =>
            return "civilian";
         when Guard =>
            return "guard";
         when Police =>
            return "police";
         when Hostile =>
            return "hostile";
         when Agent =>
            return "agent";
      end case;
   end Role_Token;

   function Mood_Token (Which : Mood) return String is
   begin
      case Which is
         when Calm =>
            return "calm";
         when Wander =>
            return "wander";
         when Patrol =>
            return "patrol";
         when Flee =>
            return "flee";
         when Warn =>
            return "warn";
         when Engage =>
            return "engage";
         when Persuaded =>
            return "persuaded";
      end case;
   end Mood_Token;

   function Distinct (Group : Crowd) return Boolean is
   begin
      for I in Group'Range loop
         for J in Group'Range loop
            if I /= J and then Ident (Group (I)) = Ident (Group (J)) then
               return False;
            end if;
         end loop;
      end loop;
      return True;
   end Distinct;

   function Run
     (M : Map.City;
      Start : Crowd;
      Max_Ticks : Natural) return Frame_Lists.Vector
   is
      Group : Crowd := Start;
      Items : Actions.Bag (1 .. 1);
      None : Vehicles.Fleet (1 .. 0);
      Trace : Frame_Lists.Vector;
   begin
      Items (1) := (Ident => 1, X => 1, Y => 1, Here => False);
      Append (Trace, Group, 0);
      for At_Tick in 1 .. Max_Ticks loop
         Step (Group, M, Items, None, At_Tick);
         Append (Trace, Group, At_Tick);
      end loop;
      return Trace;
   end Run;

   function Open_Tile (M : Map.City; At_Point : Map.Point) return Boolean is
   begin
      return Map.In_Bounds (M, At_Point.X, At_Point.Y)
        and then Map.Tile_At (M, At_Point.X, At_Point.Y).Walkable;
   end Open_Tile;

   function Street (M : Map.City) return Street_Plan is
      Plan : Street_Plan;
      Y : constant Positive := 4;
   begin
      Plan.Civ_B := (X => 1, Y => Y);
      Plan.Police_At := (X => 1, Y => Y + 2);
      Plan.Hostile_A := (X => 1, Y => Y + 5);
      Plan.Civ_A := (X => 1, Y => Y + 7);
      Plan.Patrol_A := (X => 1, Y => Y + 16);
      Plan.Patrol_B := (X => 1, Y => Y + 20);
      Plan.Hostile_B := (X => 1, Y => Y + 36);
      Plan.Guard_At := (X => 1, Y => Y + 40);
      pragma Assert (Open_Tile (M, Plan.Civ_B));
      pragma Assert (Open_Tile (M, Plan.Police_At));
      pragma Assert (Open_Tile (M, Plan.Hostile_A));
      pragma Assert (Open_Tile (M, Plan.Civ_A));
      pragma Assert (Open_Tile (M, Plan.Patrol_A));
      pragma Assert (Open_Tile (M, Plan.Patrol_B));
      pragma Assert (Open_Tile (M, Plan.Hostile_B));
      pragma Assert (Open_Tile (M, Plan.Guard_At));
      pragma Assert
        (not Shots.Blocked (M, Plan.Police_At, Plan.Hostile_A));
      pragma Assert
        (not Shots.Blocked (M, Plan.Guard_At, Plan.Hostile_B));
      return Plan;
   end Street;

   function Count_At
     (Trace : Frame_Lists.Vector;
      Who : Peds.Ped_Id;
      At_Point : Map.Point) return Natural
   is
      Total : Natural := 0;
   begin
      for I in Trace.First_Index .. Trace.Last_Index loop
         if Trace (I).Ident = Who
           and then Trace (I).State = Peds.Arrived
           and then Trace (I).X = At_Point.X
           and then Trace (I).Y = At_Point.Y
         then
            Total := Total + 1;
         end if;
      end loop;
      return Total;
   end Count_At;

   function Saw
     (Trace : Frame_Lists.Vector;
      Who : Peds.Ped_Id;
      Which : Mood) return Boolean
   is
   begin
      for I in Trace.First_Index .. Trace.Last_Index loop
         if Trace (I).Ident = Who and then Trace (I).Temper = Which then
            return True;
         end if;
      end loop;
      return False;
   end Saw;

   function Fired_At
     (Trace : Frame_Lists.Vector; Who : Peds.Ped_Id) return Natural
   is
   begin
      for I in Trace.First_Index .. Trace.Last_Index loop
         if Trace (I).Ident = Who and then Trace (I).Fired then
            return Trace (I).Tick;
         end if;
      end loop;
      return 0;
   end Fired_At;

   function Warned_At
     (Trace : Frame_Lists.Vector; Who : Peds.Ped_Id) return Natural
   is
   begin
      for I in Trace.First_Index .. Trace.Last_Index loop
         if Trace (I).Ident = Who and then Trace (I).Temper = Warn then
            return Trace (I).Tick;
         end if;
      end loop;
      return 0;
   end Warned_At;

   function Fled_From
     (Trace : Frame_Lists.Vector;
      Who : Peds.Ped_Id;
      Threat : Map.Point) return Boolean
   is
      Start : Natural := 0;
      Later : Natural;
   begin
      for I in Trace.First_Index .. Trace.Last_Index loop
         if Trace (I).Ident = Who then
            if Start = 0 then
               Start := Shots.Distance
                 ((X => Trace (I).X, Y => Trace (I).Y), Threat);
            end if;
            Later := Shots.Distance
              ((X => Trace (I).X, Y => Trace (I).Y), Threat);
            if Trace (I).Temper = Flee and then Later > Start then
               return True;
            end if;
         end if;
      end loop;
      return False;
   end Fled_From;

   procedure Check_Street
     (Trace : Frame_Lists.Vector; Plan : Street_Plan)
   is
      Warn_Tick : constant Natural := Warned_At (Trace, 7);
      Fire_Tick : constant Natural := Fired_At (Trace, 7);
   begin
      pragma Assert (Saw (Trace, 2, Flee));
      pragma Assert (Fled_From (Trace, 2, Plan.Hostile_A));
      pragma Assert (Saw (Trace, 3, Flee));
      pragma Assert (Fled_From (Trace, 3, Plan.Hostile_A));
      pragma Assert (Saw (Trace, 5, Engage));
      pragma Assert (Fired_At (Trace, 5) > 0);
      pragma Assert (Count_At (Trace, 4, Plan.Patrol_A) >= 2);
      pragma Assert (Count_At (Trace, 4, Plan.Patrol_B) >= 2);
      pragma Assert (Warn_Tick > 0);
      pragma Assert (Fire_Tick >= Warn_Tick + Warn_Ticks);
   end Check_Street;

   function Run_Street
     (M : Map.City; Seed : RNG.Word) return Frame_Lists.Vector
   is
      Plan  : constant Street_Plan := Street (M);
      Group : Crowd (1 .. 7);
      Gun   : constant Weapons.Kind := Weapons.Pistol;
      Rounds : constant Natural := Weapons.Profile (Gun).Magazine;
      Trace : Frame_Lists.Vector;
   begin
      Group (1) := Enlist (1, Hostile, Plan.Hostile_A, M, Seed);
      Group (2) := Enlist (2, Civilian, Plan.Civ_A, M, Seed);
      Group (3) := Enlist (3, Civilian, Plan.Civ_B, M, Seed);
      Group (4) := Enlist
        (4, Guard, Plan.Patrol_A, M, Seed, Plan.Patrol_A, Plan.Patrol_B);
      Group (5) := Enlist
        (5, Guard, Plan.Guard_At, M, Seed,
         Plan.Guard_At, Plan.Guard_At);
      Group (6) := Enlist (6, Hostile, Plan.Hostile_B, M, Seed);
      Group (7) := Enlist (7, Police, Plan.Police_At, M, Seed);
      Arm (Group, 1, Gun, Rounds);
      Arm (Group, 4, Gun, Rounds);
      Arm (Group, 5, Gun, Rounds);
      Arm (Group, 6, Gun, Rounds);
      Arm (Group, 7, Gun, Rounds);
      Trace := Run (M, Group, 160);
      Check_Street (Trace, Plan);
      return Trace;
   end Run_Street;

end Megacorp.Behaviour;
