--  SPDX-License-Identifier: MIT
--  Copyright (c) 2026 Robert Boettcher

package body Megacorp.Vehicles is
   use type Path.Status;

   function Facing_Of (From, To : Map.Point) return Map.Eight_Way;
   function Listed
     (Blocked : Path.Block_Lists.Vector;
      X, Y : Positive) return Boolean;
   function Other_Id
     (Group : Fleet; Self : Positive; X, Y : Positive) return Natural;
   procedure Fill_Blocked
     (Group : Fleet;
      Self : Positive;
      Foot : Path.Block_Lists.Vector;
      Into : in out Path.Block_Lists.Vector);
   procedure Repath
     (Group : in out Fleet;
      Index : Positive;
      M : Map.City;
      Foot : Path.Block_Lists.Vector);
   procedure Settle (V : in out Vehicle);

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

   function Listed
     (Blocked : Path.Block_Lists.Vector;
      X, Y : Positive) return Boolean
   is
   begin
      for I in Blocked.First_Index .. Blocked.Last_Index loop
         if Blocked (I).X = X and then Blocked (I).Y = Y then
            return True;
         end if;
      end loop;
      return False;
   end Listed;

   function Health_Cap (Which : Kind) return Positive is
   begin
      if Which = Car then
         return Car_Health;
      end if;
      return Van_Health;
   end Health_Cap;

   function Step_Speed (Which : Kind) return Positive is
   begin
      if Which = Car then
         return Car_Speed;
      end if;
      return Van_Speed;
   end Step_Speed;

   function Seat_Cap (Which : Kind) return Positive is
   begin
      if Which = Car then
         return Car_Seats;
      end if;
      return Van_Seats;
   end Seat_Cap;

   function Kind_Token (Which : Kind) return String is
   begin
      case Which is
         when Car =>
            return "car";
         when Van =>
            return "van";
      end case;
   end Kind_Token;

   function State_Token (Motion : State_Kind) return String is
   begin
      case Motion is
         when Parked =>
            return "parked";
         when Driving =>
            return "driving";
         when Arrived =>
            return "arrived";
         when Wrecked =>
            return "wrecked";
      end case;
   end State_Token;

   procedure Settle (V : in out Vehicle) is
   begin
      V.Along := 0;
      V.Wait := 0;
      V.Cursor := 1;
      V.Goal_X := V.X;
      V.Goal_Y := V.Y;
      V.Route.Clear;
      V.Route.Append ((X => V.X, Y => V.Y));
   end Settle;

   function Park
     (Who : Vehicle_Id;
      Which : Kind;
      At_Point : Map.Point;
      M : Map.City;
      Dir : Map.Eight_Way := Map.South) return Vehicle
   is
      pragma Unreferenced (M);
      V : Vehicle;
   begin
      V.Ident := Who;
      V.Sort := Which;
      V.X := At_Point.X;
      V.Y := At_Point.Y;
      V.Facing := Dir;
      V.Speed := Step_Speed (Which);
      V.Health := Health_Cap (Which);
      V.Intact := True;
      V.Motion := Parked;
      V.Riders := 0;
      Settle (V);
      return V;
   end Park;

   function Ident (V : Vehicle) return Vehicle_Id is
   begin
      return V.Ident;
   end Ident;

   function Sort_Of (V : Vehicle) return Kind is
   begin
      return V.Sort;
   end Sort_Of;

   function Tile_X (V : Vehicle) return Positive is
   begin
      return V.X;
   end Tile_X;

   function Tile_Y (V : Vehicle) return Positive is
   begin
      return V.Y;
   end Tile_Y;

   function Along (V : Vehicle) return Natural is
   begin
      return V.Along;
   end Along;

   function Facing (V : Vehicle) return Map.Eight_Way is
   begin
      return V.Facing;
   end Facing;

   function State_Of (V : Vehicle) return State_Kind is
   begin
      return V.Motion;
   end State_Of;

   function Speed_Of (V : Vehicle) return Positive is
   begin
      return V.Speed;
   end Speed_Of;

   function Health_Of (V : Vehicle) return Natural is
   begin
      return V.Health;
   end Health_Of;

   function Is_Intact (V : Vehicle) return Boolean is
   begin
      return V.Intact;
   end Is_Intact;

   function Rider_Count (V : Vehicle) return Natural is
   begin
      return V.Riders;
   end Rider_Count;

   function Rider
     (V : Vehicle; Index : Positive) return Peds.Ped_Id
   is
   begin
      return V.Seat (Index);
   end Rider;

   function Aboard (V : Vehicle; Who : Peds.Ped_Id) return Boolean is
   begin
      for I in 1 .. V.Riders loop
         if V.Seat (I) = Who then
            return True;
         end if;
      end loop;
      return False;
   end Aboard;

   function Covers (V : Vehicle; X, Y : Positive) return Boolean is
   begin
      if V.X = X and then V.Y = Y then
         return True;
      end if;
      if V.Intact
        and then V.Along > 0
        and then V.Cursor < V.Route.Last_Index
      then
         return V.Route (V.Cursor + 1).X = X
           and then V.Route (V.Cursor + 1).Y = Y;
      end if;
      return False;
   end Covers;

   function Blocks_Walk (V : Vehicle; X, Y : Positive) return Boolean is
   begin
      return V.Intact and then Covers (V, X, Y);
   end Blocks_Walk;

   procedure Board
     (V : in out Vehicle;
      Who : Peds.Ped_Id;
      Accepted : out Boolean)
   is
   begin
      if not V.Intact
        or else Aboard (V, Who)
        or else V.Riders >= Seat_Cap (V.Sort)
      then
         Accepted := False;
         return;
      end if;
      V.Riders := V.Riders + 1;
      V.Seat (V.Riders) := Who;
      Accepted := True;
   end Board;

   procedure Alight
     (V : in out Vehicle;
      Who : Peds.Ped_Id;
      Accepted : out Boolean)
   is
      Slot : Natural := 0;
   begin
      for I in 1 .. V.Riders loop
         if V.Seat (I) = Who then
            Slot := I;
            exit;
         end if;
      end loop;
      if Slot = 0 then
         Accepted := False;
         return;
      end if;
      for I in Slot .. V.Riders - 1 loop
         V.Seat (I) := V.Seat (I + 1);
      end loop;
      V.Riders := V.Riders - 1;
      Accepted := True;
   end Alight;

   procedure Clear_Riders (V : in out Vehicle) is
   begin
      V.Riders := 0;
   end Clear_Riders;

   function Find_Ride
     (Group : Fleet; Who : Peds.Ped_Id) return Natural
   is
   begin
      for I in Group'Range loop
         if Aboard (Group (I), Who) then
            return I;
         end if;
      end loop;
      return 0;
   end Find_Ride;

   procedure Add_Blocks
     (Group : Fleet;
      Except : Natural;
      Walking : Boolean;
      Into : in out Path.Block_Lists.Vector)
   is
   begin
      for I in Group'Range loop
         if I /= Except
           and then (not Walking or else Group (I).Intact)
         then
            Into.Append ((X => Group (I).X, Y => Group (I).Y));
            if Group (I).Intact
              and then Group (I).Along > 0
              and then Group (I).Cursor < Group (I).Route.Last_Index
            then
               Into.Append (Group (I).Route (Group (I).Cursor + 1));
            end if;
         end if;
      end loop;
   end Add_Blocks;

   procedure Fill_Blocked
     (Group : Fleet;
      Self : Positive;
      Foot : Path.Block_Lists.Vector;
      Into : in out Path.Block_Lists.Vector)
   is
   begin
      for I in Foot.First_Index .. Foot.Last_Index loop
         Into.Append (Foot (I));
      end loop;
      Add_Blocks (Group, Self, False, Into);
   end Fill_Blocked;

   function Other_Id
     (Group : Fleet; Self : Positive; X, Y : Positive) return Natural
   is
      Found : Natural := 0;
   begin
      for I in Group'Range loop
         if I /= Self and then Covers (Group (I), X, Y) then
            if Found = 0 or else Group (I).Ident < Found then
               Found := Group (I).Ident;
            end if;
         end if;
      end loop;
      return Found;
   end Other_Id;

   procedure Repath
     (Group : in out Fleet;
      Index : Positive;
      M : Map.City;
      Foot : Path.Block_Lists.Vector)
   is
      Blocked : Path.Block_Lists.Vector;
      Here    : constant Map.Point :=
        (X => Group (Index).X, Y => Group (Index).Y);
      Goal    : constant Map.Point :=
        (X => Group (Index).Goal_X, Y => Group (Index).Goal_Y);
      Route   : Path.Result;
   begin
      Fill_Blocked (Group, Index, Foot, Blocked);
      Route := Path.Find
        (M, Here, Goal, Path.Drive, Path.Default_Budget, Blocked);
      if Path.Kind (Route) /= Path.Found then
         return;
      end if;
      pragma Assert (Path.Step (Route, 1) = Here);
      Group (Index).Route.Clear;
      for I in 1 .. Path.Length (Route) loop
         pragma Assert
           (Map.Tile_At
              (M, Path.Step (Route, I).X, Path.Step (Route, I).Y)
            .Drivable);
         Group (Index).Route.Append (Path.Step (Route, I));
      end loop;
      Group (Index).Cursor := 1;
      Group (Index).Wait := 0;
      Group (Index).Along := 0;
      if Path.Length (Route) = 1 then
         Group (Index).Motion := Arrived;
      else
         Group (Index).Motion := Driving;
         Group (Index).Facing :=
           Facing_Of (Here, Path.Step (Route, 2));
      end if;
   end Repath;

   procedure Command_Drive
     (Group : in out Fleet;
      Index : Positive;
      Goal : Map.Point;
      M : Map.City;
      Foot : Path.Block_Lists.Vector;
      Accepted : out Boolean)
   is
      Here    : constant Map.Point :=
        (X => Group (Index).X, Y => Group (Index).Y);
      Blocked : Path.Block_Lists.Vector;
      Route   : Path.Result;
   begin
      if not Group (Index).Intact then
         Accepted := False;
         return;
      end if;
      Group (Index).Along := 0;
      Group (Index).Wait := 0;
      Group (Index).Goal_X := Goal.X;
      Group (Index).Goal_Y := Goal.Y;
      if Here = Goal then
         Settle (Group (Index));
         Group (Index).Motion := Arrived;
         Accepted := True;
         return;
      end if;
      Fill_Blocked (Group, Index, Foot, Blocked);
      Route := Path.Find
        (M, Here, Goal, Path.Drive, Path.Default_Budget, Blocked);
      if Path.Kind (Route) /= Path.Found then
         Accepted := False;
         return;
      end if;
      Group (Index).Route.Clear;
      for I in 1 .. Path.Length (Route) loop
         pragma Assert
           (Map.Tile_At
              (M, Path.Step (Route, I).X, Path.Step (Route, I).Y)
            .Drivable);
         Group (Index).Route.Append (Path.Step (Route, I));
      end loop;
      Group (Index).Cursor := 1;
      if Path.Length (Route) = 1 then
         Group (Index).Motion := Arrived;
      else
         Group (Index).Motion := Driving;
         Group (Index).Facing :=
           Facing_Of (Here, Path.Step (Route, 2));
      end if;
      Accepted := True;
   end Command_Drive;

   procedure Advance
     (Group : in out Fleet;
      Index : Positive;
      M : Map.City;
      Foot : Path.Block_Lists.Vector)
   is
      Next    : Map.Point;
      Other   : Natural;
      On_Foot : Boolean;
      Step    : Natural;
   begin
      if not Group (Index).Intact
        or else Group (Index).Motion /= Driving
      then
         return;
      end if;
      if Group (Index).Cursor >= Group (Index).Route.Last_Index then
         Group (Index).Motion := Arrived;
         Group (Index).Along := 0;
         return;
      end if;
      Next := Group (Index).Route (Group (Index).Cursor + 1);
      Group (Index).Facing := Facing_Of
        ((X => Group (Index).X, Y => Group (Index).Y), Next);
      On_Foot := Listed (Foot, Next.X, Next.Y);
      Other := Other_Id (Group, Index, Next.X, Next.Y);
      if On_Foot or else Other > 0 then
         Group (Index).Wait := Group (Index).Wait + 1;
         if Group (Index).Wait >= Wait_Limit
           and then (On_Foot
                     or else (Other > 0
                              and then Group (Index).Ident > Other))
         then
            Repath (Group, Index, M, Foot);
         end if;
         return;
      end if;
      pragma Assert
        (Map.Tile_At (M, Next.X, Next.Y).Drivable);
      Group (Index).Wait := 0;
      Step := Group (Index).Along + Group (Index).Speed;
      if Step >= Peds.Steps_Per_Tile then
         Group (Index).X := Next.X;
         Group (Index).Y := Next.Y;
         Group (Index).Along := 0;
         Group (Index).Cursor := Group (Index).Cursor + 1;
         if Group (Index).Cursor >= Group (Index).Route.Last_Index then
            Group (Index).Motion := Arrived;
         end if;
      else
         Group (Index).Along := Step;
      end if;
   end Advance;

   procedure Stop (V : in out Vehicle) is
   begin
      Settle (V);
      if V.Intact then
         V.Motion := Parked;
      else
         V.Motion := Wrecked;
      end if;
   end Stop;

   procedure Hurt (V : in out Vehicle; Amount : Natural) is
   begin
      if not V.Intact then
         return;
      end if;
      if Amount >= V.Health then
         V.Health := 0;
         V.Intact := False;
         V.Motion := Wrecked;
         Settle (V);
      else
         V.Health := V.Health - Amount;
      end if;
   end Hurt;

end Megacorp.Vehicles;
