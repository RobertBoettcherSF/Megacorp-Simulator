--  SPDX-License-Identifier: MIT
--  Copyright (c) 2026 Robert Boettcher

with Megacorp.Path;

package body Megacorp.Peds is
   use type Path.Status;

   function Facing_Of (From, To : Map.Point) return Map.Eight_Way;
   function Holds
     (P : Ped; X, Y : Positive) return Boolean;
   function Taken
     (Group : Crowd; Self : Positive; X, Y : Positive) return Boolean;
   function Blocker_Id
     (Group : Crowd; Self : Positive; X, Y : Positive) return Natural;
   procedure Repath
     (Group : in out Crowd; Index : Positive; M : Map.City);
   procedure Tick_One
     (Group : in out Crowd; Index : Positive; M : Map.City);
   function All_Arrived (Group : Crowd) return Boolean;
   procedure Append_Frames
     (Trace : in out Frame_Lists.Vector;
      Group : Crowd;
      At_Tick : Natural);

   function Facing_Of (From, To : Map.Point) return Map.Eight_Way is
      DX : constant Integer := To.X - From.X;
      DY : constant Integer := To.Y - From.Y;
   begin
      if DX = 0 and then DY = 0 then
         return Map.South;
      elsif DX = 0 and then DY < 0 then
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
      else
         return Map.North_West;
      end if;
   end Facing_Of;

   function Holds (P : Ped; X, Y : Positive) return Boolean is
   begin
      if P.X = X and then P.Y = Y then
         return True;
      end if;
      if P.Along > 0 and then P.Cursor < P.Route.Last_Index then
         return P.Route (P.Cursor + 1).X = X
           and then P.Route (P.Cursor + 1).Y = Y;
      end if;
      return False;
   end Holds;

   function Taken
     (Group : Crowd; Self : Positive; X, Y : Positive) return Boolean
   is
   begin
      for I in Group'Range loop
         if I /= Self and then Holds (Group (I), X, Y) then
            return True;
         end if;
      end loop;
      return False;
   end Taken;

   function Blocker_Id
     (Group : Crowd; Self : Positive; X, Y : Positive) return Natural
   is
      Found : Natural := 0;
   begin
      for I in Group'Range loop
         if I /= Self and then Holds (Group (I), X, Y) then
            if Found = 0 or else Group (I).Ident < Found then
               Found := Group (I).Ident;
            end if;
         end if;
      end loop;
      return Found;
   end Blocker_Id;

   procedure Repath
     (Group : in out Crowd; Index : Positive; M : Map.City)
   is
      Blocked : Path.Block_Lists.Vector;
      Here    : constant Map.Point :=
        (X => Group (Index).X, Y => Group (Index).Y);
      Goal    : constant Map.Point :=
        (X => Group (Index).Goal_X, Y => Group (Index).Goal_Y);
      Route   : Path.Result;
      Other   : Map.Point;
   begin
      for I in Group'Range loop
         if I /= Index then
            Blocked.Append
              ((X => Group (I).X, Y => Group (I).Y));
            if Group (I).Along > 0
              and then Group (I).Cursor < Group (I).Route.Last_Index
            then
               Other := Group (I).Route (Group (I).Cursor + 1);
               Blocked.Append (Other);
            end if;
         end if;
      end loop;
      Route := Path.Find
        (M, Here, Goal, Path.Walk, Path.Default_Budget, Blocked);
      if Path.Kind (Route) /= Path.Found then
         return;
      end if;
      pragma Assert (Path.Step (Route, 1) = Here);
      Group (Index).Route.Clear;
      for I in 1 .. Path.Length (Route) loop
         Group (Index).Route.Append (Path.Step (Route, I));
      end loop;
      Group (Index).Cursor := 1;
      Group (Index).Wait := 0;
      Group (Index).Along := 0;
      if Path.Length (Route) = 1 then
         Group (Index).State := Arrived;
      else
         Group (Index).Facing :=
           Facing_Of (Here, Path.Step (Route, 2));
      end if;
   end Repath;

   procedure Tick_One
     (Group : in out Crowd; Index : Positive; M : Map.City)
   is
      Next : Map.Point;
      Who  : Natural;
      Step : Natural;
   begin
      if not Group (Index).Alive
        or else Group (Index).State = Arrived
      then
         return;
      end if;
      --  A finished route stays as it is. Standing stays standing,
      --  so a halt is not turned into an arrival on the next tick.
      if Group (Index).Cursor >= Group (Index).Route.Last_Index then
         return;
      end if;
      Next := Group (Index).Route (Group (Index).Cursor + 1);
      Group (Index).Facing := Facing_Of
        ((X => Group (Index).X, Y => Group (Index).Y), Next);
      if Taken (Group, Index, Next.X, Next.Y) then
         Group (Index).State := Standing;
         Group (Index).Wait := Group (Index).Wait + 1;
         Who := Blocker_Id (Group, Index, Next.X, Next.Y);
         if Group (Index).Wait >= Wait_Limit
           and then Who > 0
           and then Group (Index).Ident > Who
         then
            Repath (Group, Index, M);
         end if;
         return;
      end if;
      Group (Index).Wait := 0;
      Group (Index).State := Walking;
      Step := Group (Index).Along + Group (Index).Speed;
      if Step >= Steps_Per_Tile then
         Group (Index).X := Next.X;
         Group (Index).Y := Next.Y;
         Group (Index).Along := 0;
         Group (Index).Cursor := Group (Index).Cursor + 1;
         if Group (Index).Cursor >= Group (Index).Route.Last_Index then
            Group (Index).State := Arrived;
         end if;
      else
         Group (Index).Along := Step;
      end if;
   end Tick_One;

   function All_Arrived (Group : Crowd) return Boolean is
   begin
      for I in Group'Range loop
         if Group (I).State /= Arrived then
            return False;
         end if;
      end loop;
      return True;
   end All_Arrived;

   procedure Append_Frames
     (Trace : in out Frame_Lists.Vector;
      Group : Crowd;
      At_Tick : Natural)
   is
   begin
      for I in Group'Range loop
         Trace.Append
           ((Tick => At_Tick,
             Ident => Group (I).Ident,
             X => Group (I).X,
             Y => Group (I).Y,
             Along => Group (I).Along,
             Facing => Group (I).Facing,
             State => Group (I).State));
      end loop;
   end Append_Frames;

   function Spawn
     (Who : Ped_Id;
      Start, Goal : Map.Point;
      M : Map.City;
      Speed : Positive := Default_Speed) return Ped
   is
      Route : constant Path.Result :=
        Path.Find (M, Start, Goal, Path.Walk);
      P : Ped;
   begin
      pragma Assert (Path.Kind (Route) = Path.Found);
      P.Ident := Who;
      P.X := Start.X;
      P.Y := Start.Y;
      P.Goal_X := Goal.X;
      P.Goal_Y := Goal.Y;
      P.Along := 0;
      P.Speed := Speed;
      P.Wait := 0;
      P.Cursor := 1;
      P.Facing := Map.South;
      for I in 1 .. Path.Length (Route) loop
         P.Route.Append (Path.Step (Route, I));
      end loop;
      if Path.Length (Route) = 1 then
         P.State := Arrived;
      else
         P.State := Standing;
         P.Facing := Facing_Of (Start, Path.Step (Route, 2));
      end if;
      return P;
   end Spawn;

   function Ident (P : Ped) return Ped_Id is
   begin
      return P.Ident;
   end Ident;

   function Tile_X (P : Ped) return Positive is
   begin
      return P.X;
   end Tile_X;

   function Tile_Y (P : Ped) return Positive is
   begin
      return P.Y;
   end Tile_Y;

   function Along (P : Ped) return Natural is
   begin
      return P.Along;
   end Along;

   function Facing (P : Ped) return Map.Eight_Way is
   begin
      return P.Facing;
   end Facing;

   function State_Of (P : Ped) return State_Kind is
   begin
      return P.State;
   end State_Of;

   function Speed_Of (P : Ped) return Positive is
   begin
      return P.Speed;
   end Speed_Of;

   function Health_Of (P : Ped) return Natural is
   begin
      return P.Health;
   end Health_Of;

   function Is_Alive (P : Ped) return Boolean is
   begin
      return P.Alive;
   end Is_Alive;

   function Ammo_Of (P : Ped) return Natural is
   begin
      return P.Ammo;
   end Ammo_Of;

   procedure Arm
     (P : in out Ped; Gun : Weapons.Kind; Rounds : Natural)
   is
      pragma Unreferenced (Gun);
   begin
      P.Ammo := Rounds;
   end Arm;

   procedure Spend_Round (P : in out Ped) is
   begin
      P.Ammo := P.Ammo - 1;
   end Spend_Round;

   procedure Hurt (P : in out Ped; Amount : Natural) is
   begin
      if not P.Alive then
         return;
      end if;
      if Amount >= P.Health then
         P.Health := 0;
         P.Alive := False;
         Halt (P);
      else
         P.Health := P.Health - Amount;
      end if;
   end Hurt;

   procedure Face_Toward (P : in out Ped; Target : Map.Point) is
   begin
      P.Facing := Facing_Of ((X => P.X, Y => P.Y), Target);
   end Face_Toward;

   function Place
     (Who : Ped_Id;
      At_Point : Map.Point;
      M : Map.City;
      Speed : Positive := Default_Speed) return Ped
   is
      pragma Unreferenced (M);
      P : Ped;
   begin
      P.Ident := Who;
      P.X := At_Point.X;
      P.Y := At_Point.Y;
      P.Goal_X := At_Point.X;
      P.Goal_Y := At_Point.Y;
      P.Along := 0;
      P.Speed := Speed;
      P.Wait := 0;
      P.Cursor := 1;
      P.Facing := Map.South;
      P.State := Standing;
      P.Route.Append (At_Point);
      return P;
   end Place;

   procedure Set_Facing (P : in out Ped; Dir : Map.Eight_Way) is
   begin
      P.Facing := Dir;
   end Set_Facing;

   procedure Halt (P : in out Ped) is
   begin
      P.Along := 0;
      P.Wait := 0;
      P.Cursor := 1;
      P.Goal_X := P.X;
      P.Goal_Y := P.Y;
      P.State := Standing;
      P.Route.Clear;
      P.Route.Append ((X => P.X, Y => P.Y));
   end Halt;

   procedure Command_Walk
     (Group : in out Crowd;
      Index : Positive;
      Goal : Map.Point;
      M : Map.City;
      Accepted : out Boolean)
   is
      Here  : constant Map.Point :=
        (X => Group (Index).X, Y => Group (Index).Y);
      Route : Path.Result;
   begin
      Group (Index).Along := 0;
      Group (Index).Wait := 0;
      Group (Index).Goal_X := Goal.X;
      Group (Index).Goal_Y := Goal.Y;
      if Here = Goal then
         Group (Index).Route.Clear;
         Group (Index).Route.Append (Here);
         Group (Index).Cursor := 1;
         Group (Index).State := Arrived;
         Accepted := True;
         return;
      end if;
      Route := Path.Find (M, Here, Goal, Path.Walk);
      if Path.Kind (Route) /= Path.Found then
         Accepted := False;
         return;
      end if;
      Group (Index).Route.Clear;
      for I in 1 .. Path.Length (Route) loop
         Group (Index).Route.Append (Path.Step (Route, I));
      end loop;
      Group (Index).Cursor := 1;
      if Path.Length (Route) = 1 then
         Group (Index).State := Arrived;
      else
         Group (Index).State := Standing;
         Group (Index).Facing :=
           Facing_Of (Here, Path.Step (Route, 2));
      end if;
      Accepted := True;
   end Command_Walk;

   function Ticks_To_Cross (Speed : Positive) return Positive is
      Progress : Natural := 0;
      Count    : Natural := 0;
   begin
      while Progress < Steps_Per_Tile loop
         Progress := Progress + Speed;
         Count := Count + 1;
      end loop;
      return Count;
   end Ticks_To_Cross;

   function Distinct_Ids (Group : Crowd) return Boolean is
   begin
      for I in Group'Range loop
         for J in Group'Range loop
            if I /= J and then Group (I).Ident = Group (J).Ident then
               return False;
            end if;
         end loop;
      end loop;
      return True;
   end Distinct_Ids;

   procedure Tick (Group : in out Crowd; M : Map.City) is
   begin
      for Wanted in Ped_Id loop
         for I in Group'Range loop
            if Group (I).Ident = Wanted then
               Tick_One (Group, I, M);
            end if;
         end loop;
      end loop;
   end Tick;

   function Run
     (M : Map.City;
      Start : Crowd;
      Max_Ticks : Natural) return Frame_Lists.Vector
   is
      Group : Crowd := Start;
      Trace : Frame_Lists.Vector;
   begin
      Append_Frames (Trace, Group, 0);
      for At_Tick in 1 .. Max_Ticks loop
         exit when All_Arrived (Group);
         Tick (Group, M);
         Append_Frames (Trace, Group, At_Tick);
      end loop;
      return Trace;
   end Run;

end Megacorp.Peds;
