--  SPDX-License-Identifier: MIT
--  Copyright (c) 2026 Robert Boettcher

with Megacorp.Path;
with Megacorp.Shots;

package body Megacorp.Actions is
   use type Map.Eight_Way;
   use type Map.Point;
   use type Path.Status;
   use type Peds.State_Kind;
   use type Vehicles.Kind;
   use type Vehicles.State_Kind;

   function Trim (Image : String) return String;
   function Facing_Token (Dir : Map.Eight_Way) return String;
   function Find_Actor (Group : Cast; Who : Peds.Ped_Id) return Natural;
   function Find_Item (Items : Bag; Id : Item_Id) return Natural;
   function Close (P : Peds.Ped; Goal : Map.Point) return Boolean;
   procedure Drop_Front (A : in out Actor);
   procedure Clear_Queue (A : in out Actor);
   procedure Apply_Pending (A : in out Actor);
   procedure Prepare
     (Group : in out Cast;
      Index : Positive;
      Bodies : in out Peds.Crowd;
      Fleet : in out Vehicles.Fleet;
      M : Map.City;
      Foot : Path.Block_Lists.Vector;
      Walk_Blocks : Path.Block_Lists.Vector);
   procedure Resolve
     (Group : in out Cast;
      Index : Positive;
      M : Map.City;
      Items : in out Bag;
      Fleet : in out Vehicles.Fleet);
   procedure Shoot_Step
     (Group : in out Cast;
      Index : Positive;
      M : Map.City);
   procedure Shoot_Rig
     (Group : in out Cast;
      Index : Positive;
      M : Map.City;
      Fleet : in out Vehicles.Fleet);
   function Exit_Spot
     (M : Map.City;
      Fleet : Vehicles.Fleet;
      Group : Cast;
      Self : Peds.Ped_Id;
      From : Map.Point) return Map.Point;
   procedure Eject
     (Group : in out Cast;
      Fleet : in out Vehicles.Fleet;
      Slot : Positive;
      M : Map.City);
   procedure Add_Foot
     (Group : Cast;
      Into : in out Path.Block_Lists.Vector);
   function Occupied
     (Group : Cast; Self : Peds.Ped_Id; X, Y : Positive) return Boolean;
   function Driving
     (Group : Cast; Fleet : Vehicles.Fleet; Slot : Positive)
     return Boolean;
   function Face_Of (From, To : Map.Point) return Map.Eight_Way;
   function On_Route
     (Route : Path.Result; At_Point : Map.Point) return Boolean;
   function Clear_Of
     (Route : Path.Result; At_Point : Map.Point; Gap : Natural)
     return Boolean;
   function Side_Walk
     (M : Map.City; At_Point : Map.Point; Spot : out Map.Point)
     return Boolean;
   function Drive_Goal
     (M : Map.City;
      From : Map.Point;
      Goal : out Map.Point;
      Route : out Path.Result) return Boolean;
   function Same_Spot (A : Snapshot; B : Ride_Frame) return Boolean;
   function Neighbour_Drives
     (M : Map.City; Frame : Ride_Frame) return Boolean;
   procedure Check_Outing (M : Map.City; Trace : Outing);
   procedure Append_Rides
     (Trace : in out Ride_Lists.Vector;
      Fleet : Vehicles.Fleet;
      At_Tick : Natural);
   procedure Remember (A : in out Actor; Had : Boolean; Old : Natural);
   function Any_Here (Items : Bag) return Boolean;
   function Idle (Group : Cast) return Boolean;
   procedure Append_Shots
     (Trace : in out Shot_Lists.Vector;
      Group : Cast;
      Items : Bag;
      At_Tick : Natural);

   function Trim (Image : String) return String is
   begin
      if Image'Length > 0 and then Image (Image'First) = ' ' then
         return Image (Image'First + 1 .. Image'Last);
      end if;
      return Image;
   end Trim;

   function Facing_Token (Dir : Map.Eight_Way) return String is
   begin
      case Dir is
         when Map.North =>
            return "north";
         when Map.East =>
            return "east";
         when Map.South =>
            return "south";
         when Map.West =>
            return "west";
         when Map.North_East =>
            return "north_east";
         when Map.South_East =>
            return "south_east";
         when Map.South_West =>
            return "south_west";
         when Map.North_West =>
            return "north_west";
      end case;
   end Facing_Token;

   function Make_Walk (Goal : Map.Point) return Action is
   begin
      return (Which => Walk_To, Goal => Goal);
   end Make_Walk;

   function Make_Wait (Ticks : Positive) return Action is
   begin
      return (Which => Wait, Total => Ticks, Left => Ticks);
   end Make_Wait;

   function Make_Turn (Dir : Map.Eight_Way) return Action is
   begin
      return (Which => Turn_To, Dir => Dir);
   end Make_Turn;

   function Make_Follow (Target : Peds.Ped_Id) return Action is
   begin
      return (Which => Follow, Target => Target);
   end Make_Follow;

   function Make_Pick (Item : Item_Id) return Action is
   begin
      return (Which => Pick_Up, Item => Item);
   end Make_Pick;

   function Token (A : Action) return String is
   begin
      case A.Which is
         when Walk_To =>
            return "walk_to "
              & Trim (Integer'Image (A.Goal.X)) & ","
              & Trim (Integer'Image (A.Goal.Y));
         when Wait =>
            return "wait " & Trim (Integer'Image (A.Total));
         when Turn_To =>
            return "turn_to " & Facing_Token (A.Dir);
         when Follow =>
            return "follow "
              & Trim (Integer'Image (Integer (A.Target)));
         when Pick_Up =>
            return "pick_up "
              & Trim (Integer'Image (Integer (A.Item)));
         when Shoot_At =>
            return "shoot_at "
              & Trim (Integer'Image (Integer (A.Foe)))
              & " " & Weapons.Token (A.Gun);
         when Enter_Vehicle =>
            return "enter_vehicle "
              & Trim (Integer'Image (Integer (A.Board)));
         when Exit_Vehicle =>
            return "exit_vehicle "
              & Trim (Integer'Image (Integer (A.Leave)));
         when Drive_To =>
            return "drive_to "
              & Trim (Integer'Image (A.Drive_Goal.X)) & ","
              & Trim (Integer'Image (A.Drive_Goal.Y));
         when Shoot_Vehicle =>
            return "shoot_vehicle "
              & Trim (Integer'Image (Integer (A.Rig)))
              & " " & Weapons.Token (A.Rig_Gun);
      end case;
   end Token;

   function Make_Enter (Which : Vehicles.Vehicle_Id) return Action is
   begin
      return (Which => Enter_Vehicle, Board => Which);
   end Make_Enter;

   function Make_Exit (Which : Vehicles.Vehicle_Id) return Action is
   begin
      return (Which => Exit_Vehicle, Leave => Which);
   end Make_Exit;

   function Make_Drive
     (Which : Vehicles.Vehicle_Id; Goal : Map.Point) return Action
   is
   begin
      return (Which => Drive_To, Ride => Which, Drive_Goal => Goal);
   end Make_Drive;

   function Make_Shoot_Vehicle
     (Which : Vehicles.Vehicle_Id; Gun : Weapons.Kind) return Action
   is
   begin
      return
        (Which => Shoot_Vehicle,
         Rig => Which,
         Rig_Gun => Gun,
         Rig_Aim => 1,
         Rig_Gap => 0);
   end Make_Shoot_Vehicle;

   function Make_Shoot
     (Target : Peds.Ped_Id; Gun : Weapons.Kind) return Action
   is
   begin
      return
        (Which => Shoot_At,
         Foe => Target,
         Gun => Gun,
         Aim_Left => 1,
         Gap => 0);
   end Make_Shoot;

   function Recruit
     (Who : Peds.Ped_Id;
      At_Point : Map.Point;
      M : Map.City;
      Seed : RNG.Word := 1) return Actor
   is
      A : Actor;
   begin
      A.Walker := Peds.Place (Who, At_Point, M);
      A.Seed := Seed;
      return A;
   end Recruit;

   procedure Arm
     (Group : in out Cast;
      Index : Positive;
      Gun : Weapons.Kind;
      Rounds : Natural)
   is
   begin
      Peds.Arm (Group (Index).Walker, Gun, Rounds);
   end Arm;

   function Length (A : Actor) return Natural is
   begin
      return A.Live_Count;
   end Length;

   function Is_Pending (A : Actor) return Boolean is
   begin
      return A.Has_Pending;
   end Is_Pending;

   function Room (A : Actor; How : Mode) return Natural is
      Used : Natural;
   begin
      if How = Replace then
         return Capacity;
      end if;
      Used := A.Live_Count;
      if A.Has_Pending and then A.Pending_Mode = Append then
         Used := Used + A.Pending_Count;
      end if;
      if Used >= Capacity then
         return 0;
      end if;
      return Capacity - Used;
   end Room;

   function Front (A : Actor) return Action is
   begin
      return A.Live (1);
   end Front;

   function At_Queue (A : Actor; Index : Positive) return Action is
   begin
      return A.Live (Index);
   end At_Queue;

   function Ped_Ident (A : Actor) return Peds.Ped_Id is
   begin
      return Peds.Ident (A.Walker);
   end Ped_Ident;

   function Ped_X (A : Actor) return Positive is
   begin
      return Peds.Tile_X (A.Walker);
   end Ped_X;

   function Ped_Y (A : Actor) return Positive is
   begin
      return Peds.Tile_Y (A.Walker);
   end Ped_Y;

   function Ped_Along (A : Actor) return Natural is
   begin
      return Peds.Along (A.Walker);
   end Ped_Along;

   function Ped_Facing (A : Actor) return Map.Eight_Way is
   begin
      return Peds.Facing (A.Walker);
   end Ped_Facing;

   function Ped_State (A : Actor) return Peds.State_Kind is
   begin
      return Peds.State_Of (A.Walker);
   end Ped_State;

   function Ped_Health (A : Actor) return Natural is
   begin
      return Peds.Health_Of (A.Walker);
   end Ped_Health;

   function Ped_Alive (A : Actor) return Boolean is
   begin
      return Peds.Is_Alive (A.Walker);
   end Ped_Alive;

   function Ped_Ammo (A : Actor) return Natural is
   begin
      return Peds.Ammo_Of (A.Walker);
   end Ped_Ammo;

   function Ran (A : Actor) return Boolean is
   begin
      return A.Has_Action;
   end Ran;

   function Ran_Action (A : Actor) return String is
   begin
      if not A.Has_Action then
         return "";
      end if;
      return Token_Strings.To_String (A.Action);
   end Ran_Action;

   function Shot_This_Tick (A : Actor) return Boolean is
   begin
      return A.Fired_Now;
   end Shot_This_Tick;

   function Shot_Landed (A : Actor) return Boolean is
   begin
      return A.Fired_Hit;
   end Shot_Landed;

   function Shot_X (A : Actor) return Positive is
   begin
      return A.Fired_X;
   end Shot_X;

   function Shot_Y (A : Actor) return Positive is
   begin
      return A.Fired_Y;
   end Shot_Y;

   function Distinct (Group : Cast) return Boolean is
   begin
      for I in Group'Range loop
         for J in Group'Range loop
            if I /= J
              and then Peds.Ident (Group (I).Walker)
                = Peds.Ident (Group (J).Walker)
            then
               return False;
            end if;
         end loop;
      end loop;
      return True;
   end Distinct;

   function Find_Actor (Group : Cast; Who : Peds.Ped_Id) return Natural is
   begin
      for I in Group'Range loop
         if Peds.Ident (Group (I).Walker) = Who then
            return I;
         end if;
      end loop;
      return 0;
   end Find_Actor;

   function Find_Item (Items : Bag; Id : Item_Id) return Natural is
   begin
      for I in Items'Range loop
         if Items (I).Ident = Id then
            return I;
         end if;
      end loop;
      return 0;
   end Find_Item;

   function Close (P : Peds.Ped; Goal : Map.Point) return Boolean is
   begin
      return abs (Peds.Tile_X (P) - Goal.X) <= 1
        and then abs (Peds.Tile_Y (P) - Goal.Y) <= 1;
   end Close;

   procedure Drop_Front (A : in out Actor) is
   begin
      if A.Live_Count = 0 then
         return;
      end if;
      for I in 1 .. A.Live_Count - 1 loop
         A.Live (I) := A.Live (I + 1);
      end loop;
      A.Live_Count := A.Live_Count - 1;
      A.Commanded := False;
      A.Settled := False;
   end Drop_Front;

   procedure Clear_Queue (A : in out Actor) is
   begin
      A.Live_Count := 0;
      A.Pending_Count := 0;
      A.Has_Pending := False;
      A.Commanded := False;
      A.Settled := False;
      A.Failed := False;
      if Peds.State_Of (A.Walker) /= Peds.Riding then
         Peds.Halt (A.Walker);
      end if;
   end Clear_Queue;

   procedure Apply_Pending (A : in out Actor) is
   begin
      if not A.Has_Pending then
         return;
      end if;
      if A.Pending_Mode = Replace then
         A.Live_Count := 0;
         A.Commanded := False;
         A.Settled := False;
         if Peds.State_Of (A.Walker) /= Peds.Riding then
            Peds.Halt (A.Walker);
         end if;
      end if;
      for I in 1 .. A.Pending_Count loop
         A.Live_Count := A.Live_Count + 1;
         A.Live (A.Live_Count) := A.Pending (I);
      end loop;
      A.Has_Pending := False;
      A.Pending_Count := 0;
   end Apply_Pending;

   procedure Embark
     (Group : in out Cast;
      Index : Positive;
      Fleet : in out Vehicles.Fleet;
      Slot : Positive;
      Accepted : out Boolean)
   is
   begin
      Vehicles.Board
        (Fleet (Slot), Peds.Ident (Group (Index).Walker), Accepted);
      if Accepted then
         Peds.Mount
           (Group (Index).Walker,
            (X => Vehicles.Tile_X (Fleet (Slot)),
             Y => Vehicles.Tile_Y (Fleet (Slot))),
            Vehicles.Facing (Fleet (Slot)),
            Vehicles.Along (Fleet (Slot)));
      end if;
   end Embark;

   procedure Order
     (Group : in out Cast;
      Index : Positive;
      Actions : Action_Array;
      How : Mode)
   is
   begin
      if How = Append
        and then Group (Index).Has_Pending
        and then Group (Index).Pending_Mode = Append
      then
         for I in Actions'Range loop
            Group (Index).Pending_Count :=
              Group (Index).Pending_Count + 1;
            Group (Index).Pending (Group (Index).Pending_Count) :=
              Actions (I);
         end loop;
         return;
      end if;
      Group (Index).Pending_Count := 0;
      for I in Actions'Range loop
         Group (Index).Pending_Count := Group (Index).Pending_Count + 1;
         Group (Index).Pending (Group (Index).Pending_Count) :=
           Actions (I);
      end loop;
      Group (Index).Pending_Mode := How;
      Group (Index).Has_Pending := Group (Index).Pending_Count > 0;
   end Order;

   procedure Prepare
     (Group : in out Cast;
      Index : Positive;
      Bodies : in out Peds.Crowd;
      Fleet : in out Vehicles.Fleet;
      M : Map.City;
      Foot : Path.Block_Lists.Vector;
      Walk_Blocks : Path.Block_Lists.Vector)
   is
      Accepted : Boolean;
      Leader   : Natural;
      Goal     : Map.Point;
      Slot     : Natural;
   begin
      Group (Index).Failed := False;
      Group (Index).Settled := False;
      if Group (Index).Live_Count = 0 then
         return;
      end if;
      case Group (Index).Live (1).Which is
         when Walk_To =>
            if not Group (Index).Commanded then
               Peds.Command_Walk
                 (Bodies, Index, Group (Index).Live (1).Goal,
                  M, Walk_Blocks, Accepted);
               if not Accepted then
                  Group (Index).Failed := True;
               else
                  Group (Index).Commanded := True;
               end if;
            end if;
         when Follow =>
            Leader := Find_Actor
              (Group, Group (Index).Live (1).Target);
            if Leader = 0 then
               Group (Index).Failed := True;
            elsif Peds.Along (Bodies (Index)) = 0 then
               Goal :=
                 (X => Peds.Tile_X (Bodies (Leader)),
                  Y => Peds.Tile_Y (Bodies (Leader)));
               if Close (Bodies (Index), Goal)
                 and then Peds.State_Of (Bodies (Leader)) = Peds.Arrived
               then
                  Peds.Halt (Bodies (Index));
                  Group (Index).Settled := True;
               elsif not Group (Index).Commanded
                 or else Goal.X /= Group (Index).Command_X
                 or else Goal.Y /= Group (Index).Command_Y
               then
                  Peds.Command_Walk
                    (Bodies, Index, Goal, M, Walk_Blocks, Accepted);
                  if not Accepted then
                     if not Close (Bodies (Index), Goal) then
                        Group (Index).Failed := True;
                     end if;
                  else
                     Group (Index).Commanded := True;
                     Group (Index).Command_X := Goal.X;
                     Group (Index).Command_Y := Goal.Y;
                  end if;
               end if;
            end if;
         when Drive_To =>
            if not Group (Index).Commanded then
               Slot := Vehicles.Find_Ride
                 (Fleet, Peds.Ident (Bodies (Index)));
               Goal := Group (Index).Live (1).Drive_Goal;
               if Slot = 0
                 or else Vehicles.Ident (Fleet (Slot))
                   /= Group (Index).Live (1).Ride
                 or else not Map.In_Bounds (M, Goal.X, Goal.Y)
               then
                  Group (Index).Failed := True;
               else
                  Vehicles.Command_Drive
                    (Fleet, Slot, Goal, M, Foot, Accepted);
                  if not Accepted then
                     Group (Index).Failed := True;
                  else
                     Group (Index).Commanded := True;
                  end if;
               end if;
            end if;
         when Wait | Turn_To | Pick_Up | Shoot_At
            | Enter_Vehicle | Exit_Vehicle | Shoot_Vehicle =>
            null;
      end case;
   end Prepare;

   procedure Shoot_Step
     (Group : in out Cast;
      Index : Positive;
      M : Map.City)
   is
      Gun    : Weapons.Kind;
      Slot   : Natural;
      From_P : Map.Point;
      To_P   : Map.Point;
      Dice   : RNG.Generator;
      Landed : Boolean;
      Stats  : Weapons.Stats;
   begin
      Group (Index).Fired_Now := False;
      if Group (Index).Live_Count = 0
        or else Group (Index).Live (1).Which /= Shoot_At
      then
         return;
      end if;
      Gun := Group (Index).Live (1).Gun;
      Stats := Weapons.Profile (Gun);
      Slot := Find_Actor (Group, Group (Index).Live (1).Foe);
      if Slot = 0 or else not Peds.Is_Alive (Group (Slot).Walker) then
         Group (Index).Failed := True;
         return;
      end if;
      From_P :=
        (X => Peds.Tile_X (Group (Index).Walker),
         Y => Peds.Tile_Y (Group (Index).Walker));
      To_P :=
        (X => Peds.Tile_X (Group (Slot).Walker),
         Y => Peds.Tile_Y (Group (Slot).Walker));
      Peds.Face_Toward (Group (Index).Walker, To_P);
      if Group (Index).Live (1).Aim_Left > 0 then
         Group (Index).Live (1).Aim_Left :=
           Group (Index).Live (1).Aim_Left - 1;
         return;
      end if;
      if Group (Index).Live (1).Gap > 0 then
         Group (Index).Live (1).Gap := Group (Index).Live (1).Gap - 1;
         return;
      end if;
      if not Shots.In_Range (Gun, From_P, To_P)
        or else Shots.Blocked (M, From_P, To_P)
        or else Peds.Ammo_Of (Group (Index).Walker) = 0
      then
         Group (Index).Failed := True;
         return;
      end if;
      Peds.Spend_Round (Group (Index).Walker);
      Group (Index).Shots_Fired := Group (Index).Shots_Fired + 1;
      Dice := RNG.Child
        (RNG.Make (Group (Index).Seed),
         RNG.Mission,
         RNG.Stream_Index
           (Peds.Ident (Group (Index).Walker) * 1000
            + Group (Index).Shots_Fired));
      Landed := Shots.Lands (Gun, From_P, To_P, Dice);
      Group (Index).Fired_Now := True;
      Group (Index).Fired_Hit := Landed;
      Group (Index).Fired_X := To_P.X;
      Group (Index).Fired_Y := To_P.Y;
      if Landed then
         Peds.Hurt (Group (Slot).Walker, Stats.Damage);
         if not Peds.Is_Alive (Group (Slot).Walker) then
            Clear_Queue (Group (Slot));
            Drop_Front (Group (Index));
            return;
         end if;
      end if;
      if Peds.Ammo_Of (Group (Index).Walker) = 0 then
         Group (Index).Failed := True;
         return;
      end if;
      Group (Index).Live (1).Gap := Stats.Rate - 1;
   end Shoot_Step;

   procedure Add_Foot
     (Group : Cast;
      Into : in out Path.Block_Lists.Vector)
   is
      At_X : Integer;
      At_Y : Integer;
   begin
      for I in Group'Range loop
         if Peds.Is_Alive (Group (I).Walker)
           and then Peds.State_Of (Group (I).Walker) /= Peds.Riding
         then
            Into.Append
              ((X => Peds.Tile_X (Group (I).Walker),
                Y => Peds.Tile_Y (Group (I).Walker)));
            if Peds.Along (Group (I).Walker) > 0 then
               case Peds.Facing (Group (I).Walker) is
                  when Map.North =>
                     At_X := Peds.Tile_X (Group (I).Walker);
                     At_Y := Peds.Tile_Y (Group (I).Walker) - 1;
                  when Map.East =>
                     At_X := Peds.Tile_X (Group (I).Walker) + 1;
                     At_Y := Peds.Tile_Y (Group (I).Walker);
                  when Map.South =>
                     At_X := Peds.Tile_X (Group (I).Walker);
                     At_Y := Peds.Tile_Y (Group (I).Walker) + 1;
                  when Map.West =>
                     At_X := Peds.Tile_X (Group (I).Walker) - 1;
                     At_Y := Peds.Tile_Y (Group (I).Walker);
                  when Map.North_East =>
                     At_X := Peds.Tile_X (Group (I).Walker) + 1;
                     At_Y := Peds.Tile_Y (Group (I).Walker) - 1;
                  when Map.South_East =>
                     At_X := Peds.Tile_X (Group (I).Walker) + 1;
                     At_Y := Peds.Tile_Y (Group (I).Walker) + 1;
                  when Map.South_West =>
                     At_X := Peds.Tile_X (Group (I).Walker) - 1;
                     At_Y := Peds.Tile_Y (Group (I).Walker) + 1;
                  when Map.North_West =>
                     At_X := Peds.Tile_X (Group (I).Walker) - 1;
                     At_Y := Peds.Tile_Y (Group (I).Walker) - 1;
               end case;
               if At_X > 0 and then At_Y > 0 then
                  Into.Append ((X => At_X, Y => At_Y));
               end if;
            end if;
         end if;
      end loop;
   end Add_Foot;

   function Occupied
     (Group : Cast; Self : Peds.Ped_Id; X, Y : Positive) return Boolean
   is
   begin
      for I in Group'Range loop
         if Peds.Ident (Group (I).Walker) /= Self
           and then Peds.Is_Alive (Group (I).Walker)
           and then Peds.Claims (Group (I).Walker, X, Y)
         then
            return True;
         end if;
      end loop;
      return False;
   end Occupied;

   function Exit_Spot
     (M : Map.City;
      Fleet : Vehicles.Fleet;
      Group : Cast;
      Self : Peds.Ped_Id;
      From : Map.Point) return Map.Point
   is
      type Shift is record
         DX : Integer;
         DY : Integer;
      end record;
      Near : constant array (1 .. 8) of Shift :=
        ((0, -1), (1, 0), (0, 1), (-1, 0),
         (1, -1), (1, 1), (-1, 1), (-1, -1));
      X : Integer;
      Y : Integer;
      Blocked : Boolean;
   begin
      for I in Near'Range loop
         X := From.X + Near (I).DX;
         Y := From.Y + Near (I).DY;
         if Map.In_Bounds (M, X, Y)
           and then Map.Tile_At (M, X, Y).Walkable
           and then not Occupied (Group, Self, X, Y)
         then
            Blocked := False;
            for V in Fleet'Range loop
               if Vehicles.Blocks_Walk (Fleet (V), X, Y) then
                  Blocked := True;
               end if;
            end loop;
            if not Blocked then
               return (X => X, Y => Y);
            end if;
         end if;
      end loop;
      for DY in -2 .. 2 loop
         for DX in -2 .. 2 loop
            if Integer'Max (abs DX, abs DY) = 2 then
               X := From.X + DX;
               Y := From.Y + DY;
               if Map.In_Bounds (M, X, Y)
                 and then Map.Tile_At (M, X, Y).Walkable
                 and then not Occupied (Group, Self, X, Y)
               then
                  Blocked := False;
                  for V in Fleet'Range loop
                     if Vehicles.Blocks_Walk (Fleet (V), X, Y) then
                        Blocked := True;
                     end if;
                  end loop;
                  if not Blocked then
                     return (X => X, Y => Y);
                  end if;
               end if;
            end if;
         end loop;
      end loop;
      return From;
   end Exit_Spot;

   procedure Eject
     (Group : in out Cast;
      Fleet : in out Vehicles.Fleet;
      Slot : Positive;
      M : Map.City)
   is
      Count : constant Natural :=
        Vehicles.Rider_Count (Fleet (Slot));
      Who   : array (1 .. Vehicles.Max_Seats) of Peds.Ped_Id;
      Taken : Boolean;
      Spot  : Map.Point;
      Actor : Natural;
   begin
      for I in 1 .. Count loop
         Who (I) := Vehicles.Rider (Fleet (Slot), I);
      end loop;
      for I in 1 .. Count loop
         Vehicles.Alight (Fleet (Slot), Who (I), Taken);
         Actor := Find_Actor (Group, Who (I));
         if Actor > 0 then
            Spot := Exit_Spot
              (M, Fleet, Group, Who (I),
               (X => Vehicles.Tile_X (Fleet (Slot)),
                Y => Vehicles.Tile_Y (Fleet (Slot))));
            Peds.Relocate (Group (Actor).Walker, Spot);
            Clear_Queue (Group (Actor));
         end if;
      end loop;
   end Eject;

   procedure Shoot_Rig
     (Group : in out Cast;
      Index : Positive;
      M : Map.City;
      Fleet : in out Vehicles.Fleet)
   is
      Gun    : Weapons.Kind;
      Slot   : Natural;
      From_P : Map.Point;
      To_P   : Map.Point;
      Dice   : RNG.Generator;
      Landed : Boolean;
      Stats  : Weapons.Stats;
   begin
      Group (Index).Fired_Now := False;
      if Group (Index).Live_Count = 0
        or else Group (Index).Live (1).Which /= Shoot_Vehicle
      then
         return;
      end if;
      Gun := Group (Index).Live (1).Rig_Gun;
      Stats := Weapons.Profile (Gun);
      Slot := 0;
      for I in Fleet'Range loop
         if Vehicles.Ident (Fleet (I)) = Group (Index).Live (1).Rig then
            Slot := I;
            exit;
         end if;
      end loop;
      if Slot = 0 or else not Vehicles.Is_Intact (Fleet (Slot)) then
         Group (Index).Failed := True;
         return;
      end if;
      From_P :=
        (X => Peds.Tile_X (Group (Index).Walker),
         Y => Peds.Tile_Y (Group (Index).Walker));
      To_P :=
        (X => Vehicles.Tile_X (Fleet (Slot)),
         Y => Vehicles.Tile_Y (Fleet (Slot)));
      Peds.Face_Toward (Group (Index).Walker, To_P);
      if Group (Index).Live (1).Rig_Aim > 0 then
         Group (Index).Live (1).Rig_Aim :=
           Group (Index).Live (1).Rig_Aim - 1;
         return;
      end if;
      if Group (Index).Live (1).Rig_Gap > 0 then
         Group (Index).Live (1).Rig_Gap :=
           Group (Index).Live (1).Rig_Gap - 1;
         return;
      end if;
      if not Shots.In_Range (Gun, From_P, To_P)
        or else Shots.Blocked (M, From_P, To_P)
        or else Peds.Ammo_Of (Group (Index).Walker) = 0
      then
         Group (Index).Failed := True;
         return;
      end if;
      Peds.Spend_Round (Group (Index).Walker);
      Group (Index).Shots_Fired := Group (Index).Shots_Fired + 1;
      Dice := RNG.Child
        (RNG.Make (Group (Index).Seed),
         RNG.Mission,
         RNG.Stream_Index
           (Peds.Ident (Group (Index).Walker) * 1000
            + Group (Index).Shots_Fired));
      Landed := Shots.Lands (Gun, From_P, To_P, Dice);
      Group (Index).Fired_Now := True;
      Group (Index).Fired_Hit := Landed;
      Group (Index).Fired_X := To_P.X;
      Group (Index).Fired_Y := To_P.Y;
      if Landed then
         Vehicles.Hurt (Fleet (Slot), Stats.Damage);
         if not Vehicles.Is_Intact (Fleet (Slot)) then
            Eject (Group, Fleet, Slot, M);
            Drop_Front (Group (Index));
            return;
         end if;
      end if;
      if Peds.Ammo_Of (Group (Index).Walker) = 0 then
         Group (Index).Failed := True;
         return;
      end if;
      Group (Index).Live (1).Rig_Gap := Stats.Rate - 1;
   end Shoot_Rig;

   procedure Resolve
     (Group : in out Cast;
      Index : Positive;
      M : Map.City;
      Items : in out Bag;
      Fleet : in out Vehicles.Fleet)
   is
      Slot     : Natural;
      Accepted : Boolean;
      Spot     : Map.Point;
   begin
      if Group (Index).Live_Count = 0 then
         return;
      end if;
      if Group (Index).Failed then
         Clear_Queue (Group (Index));
         return;
      end if;
      case Group (Index).Live (1).Which is
         when Walk_To =>
            if Peds.State_Of (Group (Index).Walker) = Peds.Arrived
              and then Peds.Tile_X (Group (Index).Walker)
                = Group (Index).Live (1).Goal.X
              and then Peds.Tile_Y (Group (Index).Walker)
                = Group (Index).Live (1).Goal.Y
            then
               Drop_Front (Group (Index));
            end if;
         when Wait =>
            if Group (Index).Live (1).Left > 0 then
               Group (Index).Live (1).Left :=
                 Group (Index).Live (1).Left - 1;
            end if;
            if Group (Index).Live (1).Left = 0 then
               Drop_Front (Group (Index));
            end if;
         when Turn_To =>
            Peds.Set_Facing
              (Group (Index).Walker, Group (Index).Live (1).Dir);
            Drop_Front (Group (Index));
         when Follow =>
            if Group (Index).Settled then
               Drop_Front (Group (Index));
            end if;
         when Pick_Up =>
            Slot := Find_Item (Items, Group (Index).Live (1).Item);
            if Slot = 0
              or else not Items (Slot).Here
              or else Items (Slot).X /= Peds.Tile_X (Group (Index).Walker)
              or else Items (Slot).Y /= Peds.Tile_Y (Group (Index).Walker)
              or else Peds.Along (Group (Index).Walker) /= 0
            then
               Clear_Queue (Group (Index));
            else
               Items (Slot).Here := False;
               Drop_Front (Group (Index));
            end if;
         when Shoot_At =>
            Shoot_Step (Group, Index, M);
            if Group (Index).Failed then
               Clear_Queue (Group (Index));
            end if;
         when Enter_Vehicle =>
            Slot := 0;
            for I in Fleet'Range loop
               if Vehicles.Ident (Fleet (I))
                 = Group (Index).Live (1).Board
               then
                  Slot := I;
                  exit;
               end if;
            end loop;
            if Slot = 0
              or else Peds.Along (Group (Index).Walker) /= 0
              or else abs
                (Peds.Tile_X (Group (Index).Walker)
                 - Vehicles.Tile_X (Fleet (Slot))) > 1
              or else abs
                (Peds.Tile_Y (Group (Index).Walker)
                 - Vehicles.Tile_Y (Fleet (Slot))) > 1
            then
               Clear_Queue (Group (Index));
            else
               Vehicles.Board
                 (Fleet (Slot),
                  Peds.Ident (Group (Index).Walker),
                  Accepted);
               if not Accepted then
                  Clear_Queue (Group (Index));
               else
                  Peds.Mount
                    (Group (Index).Walker,
                     (X => Vehicles.Tile_X (Fleet (Slot)),
                      Y => Vehicles.Tile_Y (Fleet (Slot))),
                     Vehicles.Facing (Fleet (Slot)),
                     Vehicles.Along (Fleet (Slot)));
                  Drop_Front (Group (Index));
               end if;
            end if;
         when Exit_Vehicle =>
            Slot := Vehicles.Find_Ride
              (Fleet, Peds.Ident (Group (Index).Walker));
            if Slot = 0
              or else Vehicles.Ident (Fleet (Slot))
                /= Group (Index).Live (1).Leave
            then
               Clear_Queue (Group (Index));
            elsif Vehicles.Along (Fleet (Slot)) /= 0 then
               null;
            else
               Spot := Exit_Spot
                 (M, Fleet, Group,
                  Peds.Ident (Group (Index).Walker),
                  (X => Vehicles.Tile_X (Fleet (Slot)),
                   Y => Vehicles.Tile_Y (Fleet (Slot))));
               Vehicles.Alight
                 (Fleet (Slot),
                  Peds.Ident (Group (Index).Walker),
                  Accepted);
               if not Accepted then
                  Clear_Queue (Group (Index));
               else
                  Peds.Relocate (Group (Index).Walker, Spot);
                  Drop_Front (Group (Index));
               end if;
            end if;
         when Drive_To =>
            Slot := Vehicles.Find_Ride
              (Fleet, Peds.Ident (Group (Index).Walker));
            if Group (Index).Failed
              or else Slot = 0
              or else Vehicles.Ident (Fleet (Slot))
                /= Group (Index).Live (1).Ride
            then
               if Slot > 0
                 and then Vehicles.Is_Intact (Fleet (Slot))
               then
                  Vehicles.Stop (Fleet (Slot));
               end if;
               Clear_Queue (Group (Index));
            elsif Vehicles.State_Of (Fleet (Slot)) = Vehicles.Arrived
              and then Vehicles.Tile_X (Fleet (Slot))
                = Group (Index).Live (1).Drive_Goal.X
              and then Vehicles.Tile_Y (Fleet (Slot))
                = Group (Index).Live (1).Drive_Goal.Y
            then
               Drop_Front (Group (Index));
            end if;
         when Shoot_Vehicle =>
            Shoot_Rig (Group, Index, M, Fleet);
            if Group (Index).Failed then
               Clear_Queue (Group (Index));
            end if;
      end case;
   end Resolve;

   procedure Remember (A : in out Actor; Had : Boolean; Old : Natural) is
   begin
      if not Had then
         A.Has_Action := False;
         A.Rest_Count := 0;
         return;
      end if;
      A.Has_Action := True;
      if A.Live_Count = 0 or else A.Live_Count < Old then
         if A.Live_Count = 0 then
            A.Rest_Count := 0;
         else
            A.Rest_Count := A.Live_Count;
            for I in 1 .. A.Live_Count loop
               A.Rest (I) := Token_Strings.To_Bounded_String
                 (Token (A.Live (I)));
            end loop;
         end if;
      else
         A.Rest_Count := A.Live_Count - 1;
         for I in 1 .. A.Rest_Count loop
            A.Rest (I) := Token_Strings.To_Bounded_String
              (Token (A.Live (I + 1)));
         end loop;
      end if;
   end Remember;

   function Driving
     (Group : Cast; Fleet : Vehicles.Fleet; Slot : Positive)
     return Boolean
   is
   begin
      for I in Group'Range loop
         if Group (I).Live_Count > 0
           and then not Group (I).Failed
           and then Group (I).Live (1).Which = Drive_To
           and then Group (I).Live (1).Ride = Vehicles.Ident (Fleet (Slot))
           and then Vehicles.Aboard
             (Fleet (Slot), Peds.Ident (Group (I).Walker))
         then
            return True;
         end if;
      end loop;
      return False;
   end Driving;

   procedure Tick
     (Group : in out Cast;
      M : Map.City;
      Items : in out Bag;
      Fleet : in out Vehicles.Fleet)
   is
      Bodies      : Peds.Crowd (Group'Range);
      Foot        : Path.Block_Lists.Vector;
      Walk_Blocks : Path.Block_Lists.Vector;
      Had         : Boolean;
      Old         : Natural;
      Slot        : Natural;
   begin
      for I in Group'Range loop
         Apply_Pending (Group (I));
         Bodies (I) := Group (I).Walker;
      end loop;
      Add_Foot (Group, Foot);
      Vehicles.Add_Blocks (Fleet, 0, True, Walk_Blocks);
      for I in Group'Range loop
         Prepare (Group, I, Bodies, Fleet, M, Foot, Walk_Blocks);
      end loop;
      declare
         type Rank is array (Positive range <>) of Positive;
         Order : Rank (Fleet'Range);
         Swap  : Positive;
      begin
         for I in Fleet'Range loop
            Order (I) := I;
         end loop;
         for I in Fleet'Range loop
            for J in I + 1 .. Fleet'Last loop
               if Vehicles.Ident (Fleet (Order (J)))
                 < Vehicles.Ident (Fleet (Order (I)))
               then
                  Swap := Order (I);
                  Order (I) := Order (J);
                  Order (J) := Swap;
               end if;
            end loop;
         end loop;
         for K in Fleet'Range loop
            if Driving (Group, Fleet, Order (K)) then
               Vehicles.Advance (Fleet, Order (K), M, Foot);
            end if;
         end loop;
      end;
      Walk_Blocks.Clear;
      Vehicles.Add_Blocks (Fleet, 0, True, Walk_Blocks);
      for I in Group'Range loop
         Slot := Vehicles.Find_Ride
           (Fleet, Peds.Ident (Bodies (I)));
         if Slot > 0 then
            Peds.Carry
              (Bodies (I),
               (X => Vehicles.Tile_X (Fleet (Slot)),
                Y => Vehicles.Tile_Y (Fleet (Slot))),
               Vehicles.Facing (Fleet (Slot)),
               Vehicles.Along (Fleet (Slot)));
         end if;
      end loop;
      Peds.Tick (Bodies, M, Walk_Blocks);
      for I in Group'Range loop
         Group (I).Walker := Bodies (I);
         Group (I).Fired_Now := False;
      end loop;
      for I in Group'Range loop
         Had := Group (I).Live_Count > 0;
         Old := Group (I).Live_Count;
         if Had then
            Group (I).Action := Token_Strings.To_Bounded_String
              (Token (Group (I).Live (1)));
         end if;
         Resolve (Group, I, M, Items, Fleet);
         Remember (Group (I), Had, Old);
      end loop;
   end Tick;

   procedure Tick
     (Group : in out Cast;
      M : Map.City;
      Items : in out Bag)
   is
      None : Vehicles.Fleet (1 .. 0);
   begin
      Tick (Group, M, Items, None);
   end Tick;

   function Any_Here (Items : Bag) return Boolean is
   begin
      for I in Items'Range loop
         if Items (I).Here then
            return True;
         end if;
      end loop;
      return False;
   end Any_Here;

   function Idle (Group : Cast) return Boolean is
   begin
      for I in Group'Range loop
         if Group (I).Live_Count > 0 or else Group (I).Has_Pending then
            return False;
         end if;
      end loop;
      return True;
   end Idle;

   procedure Append_Shots
     (Trace : in out Shot_Lists.Vector;
      Group : Cast;
      Items : Bag;
      At_Tick : Natural)
   is
      Here : constant Boolean := Any_Here (Items);
      Shot : Snapshot;
   begin
      for I in Group'Range loop
         Shot.Tick := At_Tick;
         Shot.Ident := Peds.Ident (Group (I).Walker);
         Shot.X := Peds.Tile_X (Group (I).Walker);
         Shot.Y := Peds.Tile_Y (Group (I).Walker);
         Shot.Along := Peds.Along (Group (I).Walker);
         Shot.Facing := Peds.Facing (Group (I).Walker);
         Shot.State := Peds.State_Of (Group (I).Walker);
         Shot.Has_Action := Group (I).Has_Action;
         Shot.Action := Group (I).Action;
         Shot.Rest_Count := Group (I).Rest_Count;
         Shot.Rest := Group (I).Rest;
         Shot.Item_Here := Here;
         Shot.Health := Peds.Health_Of (Group (I).Walker);
         Shot.Ammo := Peds.Ammo_Of (Group (I).Walker);
         Shot.Alive := Peds.Is_Alive (Group (I).Walker);
         Shot.Fired := Group (I).Fired_Now;
         Shot.Landed := Group (I).Fired_Hit;
         Shot.At_X := Group (I).Fired_X;
         Shot.At_Y := Group (I).Fired_Y;
         Trace.Append (Shot);
      end loop;
   end Append_Shots;

   function Run
     (M : Map.City;
      Start : Cast;
      Items : Bag;
      Max_Ticks : Natural) return Shot_Lists.Vector
   is
      Group : Cast := Start;
      Stuff : Bag := Items;
      Trace : Shot_Lists.Vector;
   begin
      Append_Shots (Trace, Group, Stuff, 0);
      for At_Tick in 1 .. Max_Ticks loop
         exit when Idle (Group);
         Tick (Group, M, Stuff);
         Append_Shots (Trace, Group, Stuff, At_Tick);
      end loop;
      return Trace;
   end Run;

   procedure Append_Rides
     (Trace : in out Ride_Lists.Vector;
      Fleet : Vehicles.Fleet;
      At_Tick : Natural)
   is
      Frame : Ride_Frame;
   begin
      for I in Fleet'Range loop
         Frame.Tick := At_Tick;
         Frame.Ident := Vehicles.Ident (Fleet (I));
         Frame.Sort := Vehicles.Sort_Of (Fleet (I));
         Frame.X := Vehicles.Tile_X (Fleet (I));
         Frame.Y := Vehicles.Tile_Y (Fleet (I));
         Frame.Along := Vehicles.Along (Fleet (I));
         Frame.Facing := Vehicles.Facing (Fleet (I));
         Frame.Motion := Vehicles.State_Of (Fleet (I));
         Frame.Health := Vehicles.Health_Of (Fleet (I));
         Frame.Cap := Vehicles.Health_Cap (Frame.Sort);
         Frame.Intact := Vehicles.Is_Intact (Fleet (I));
         Frame.Riders := Vehicles.Rider_Count (Fleet (I));
         Frame.Rider := (others => 0);
         for R in 1 .. Frame.Riders loop
            Frame.Rider (R) :=
              Integer (Vehicles.Rider (Fleet (I), R));
         end loop;
         Trace.Append (Frame);
      end loop;
   end Append_Rides;

   function Play
     (M : Map.City;
      Start : Cast;
      Items : Bag;
      Fleet : Vehicles.Fleet;
      Max_Ticks : Natural) return Outing
   is
      Group : Cast := Start;
      Stuff : Bag := Items;
      Cars  : Vehicles.Fleet := Fleet;
      Trace : Outing;
   begin
      Append_Shots (Trace.Peds, Group, Stuff, 0);
      Append_Rides (Trace.Cars, Cars, 0);
      for At_Tick in 1 .. Max_Ticks loop
         exit when Idle (Group);
         Tick (Group, M, Stuff, Cars);
         Append_Shots (Trace.Peds, Group, Stuff, At_Tick);
         Append_Rides (Trace.Cars, Cars, At_Tick);
      end loop;
      return Trace;
   end Play;

   function Face_Of (From, To : Map.Point) return Map.Eight_Way is
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
   end Face_Of;

   function On_Route
     (Route : Path.Result; At_Point : Map.Point) return Boolean
   is
   begin
      if Path.Kind (Route) /= Path.Found then
         return False;
      end if;
      for I in 1 .. Path.Length (Route) loop
         if Path.Step (Route, I) = At_Point then
            return True;
         end if;
      end loop;
      return False;
   end On_Route;

   function Clear_Of
     (Route : Path.Result; At_Point : Map.Point; Gap : Natural)
     return Boolean
   is
      Dist : Natural;
   begin
      if Path.Kind (Route) /= Path.Found then
         return False;
      end if;
      for I in 1 .. Path.Length (Route) loop
         Dist := Natural'Max
           (abs (Path.Step (Route, I).X - At_Point.X),
            abs (Path.Step (Route, I).Y - At_Point.Y));
         if Dist < Gap then
            return False;
         end if;
      end loop;
      return True;
   end Clear_Of;

   function Side_Walk
     (M : Map.City; At_Point : Map.Point; Spot : out Map.Point)
     return Boolean
   is
      type Shift is record
         DX : Integer;
         DY : Integer;
      end record;
      Near : constant array (1 .. 4) of Shift :=
        ((0, -1), (1, 0), (0, 1), (-1, 0));
      X : Integer;
      Y : Integer;
   begin
      for I in Near'Range loop
         X := At_Point.X + Near (I).DX;
         Y := At_Point.Y + Near (I).DY;
         if Map.In_Bounds (M, X, Y)
           and then Map.Tile_At (M, X, Y).Walkable
         then
            Spot := (X => X, Y => Y);
            return True;
         end if;
      end loop;
      Spot := At_Point;
      return False;
   end Side_Walk;

   function Drive_Goal
     (M : Map.City;
      From : Map.Point;
      Goal : out Map.Point;
      Route : out Path.Result) return Boolean
   is
      type Offset is record
         DX : Integer;
         DY : Integer;
      end record;
      Tries : constant array (1 .. 8) of Offset :=
        ((8, 0), (0, 8), (-8, 0), (0, -8),
         (12, 0), (0, 12), (6, 0), (0, 6));
      X : Integer;
      Y : Integer;
   begin
      for I in Tries'Range loop
         X := From.X + Tries (I).DX;
         Y := From.Y + Tries (I).DY;
         if Map.In_Bounds (M, X, Y)
           and then Map.Tile_At (M, X, Y).Drivable
         then
            Route := Path.Find
              (M, From, (X => X, Y => Y), Path.Drive);
            if Path.Kind (Route) = Path.Found
              and then Path.Length (Route) in 6 .. 14
            then
               Goal := (X => X, Y => Y);
               return True;
            end if;
         end if;
      end loop;
      Goal := From;
      Route := Path.Find (M, From, From, Path.Drive);
      return False;
   end Drive_Goal;

   function Vehicle_Demo (M : Map.City) return Road_Plan is
      Plan    : Road_Plan;
      Route   : Path.Result;
      Found   : Boolean := False;
      Board   : Map.Point;
      Have    : Boolean;
      X       : Integer;
      Y       : Integer;
      Spot    : Map.Point;
      Walk    : Path.Result;
   begin
      for Row in 1 .. M.Height loop
         for Column in 1 .. M.Width loop
            if not Found
              and then Map.Tile_At (M, Column, Row).Drivable
              and then Side_Walk (M, (X => Column, Y => Row), Board)
              and then Drive_Goal
                (M, (X => Column, Y => Row), Plan.Goal, Route)
            then
               Plan.Car_At := (X => Column, Y => Row);
               Plan.Board := Board;
               Found := True;
            end if;
         end loop;
      end loop;
      pragma Assert (Found);
      Found := False;
      for Row in 1 .. M.Height loop
         for Column in 1 .. M.Width loop
            Spot := (X => Column, Y => Row);
            if not Found
              and then Map.Tile_At (M, Column, Row).Drivable
              and then not On_Route (Route, Spot)
              and then Clear_Of (Route, Spot, 5)
              and then Side_Walk (M, Spot, Board)
              and then not On_Route (Route, Board)
            then
               Plan.Van_At := Spot;
               Plan.Shooter_At := Board;
               Found := True;
            end if;
         end loop;
      end loop;
      pragma Assert (Found);
      Found := False;
      for Radius in 4 .. 12 loop
         exit when Found;
         for DY in -Radius .. Radius loop
            exit when Found;
            for DX in -Radius .. Radius loop
               if Integer'Max (abs DX, abs DY) = Radius then
                  X := Plan.Board.X + DX;
                  Y := Plan.Board.Y + DY;
                  if Map.In_Bounds (M, X, Y)
                    and then Map.Tile_At (M, X, Y).Walkable
                  then
                     Spot := (X => X, Y => Y);
                     if Spot /= Plan.Car_At
                       and then Spot /= Plan.Van_At
                       and then Spot /= Plan.Shooter_At
                       and then Spot /= Plan.Board
                       and then not On_Route (Route, Spot)
                     then
                        Walk := Path.Find (M, Spot, Plan.Board, Path.Walk);
                        if Path.Kind (Walk) = Path.Found
                          and then Path.Length (Walk) in 4 .. 12
                        then
                           Plan.Ped_At := Spot;
                           Found := True;
                        end if;
                     end if;
                  end if;
               end if;
            end loop;
         end loop;
      end loop;
      pragma Assert (Found);
      Have := Plan.Car_At /= Plan.Van_At;
      pragma Assert (Have);
      return Plan;
   end Vehicle_Demo;

   function Same_Spot (A : Snapshot; B : Ride_Frame) return Boolean is
   begin
      return A.X = B.X
        and then A.Y = B.Y
        and then A.Along = B.Along
        and then A.Facing = B.Facing
        and then A.State = Peds.Riding;
   end Same_Spot;

   function Neighbour_Drives
     (M : Map.City; Frame : Ride_Frame) return Boolean
   is
      X : Integer := Frame.X;
      Y : Integer := Frame.Y;
   begin
      case Frame.Facing is
         when Map.North =>
            Y := Y - 1;
         when Map.East =>
            X := X + 1;
         when Map.South =>
            Y := Y + 1;
         when Map.West =>
            X := X - 1;
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
      return Map.In_Bounds (M, X, Y)
        and then Map.Tile_At (M, X, Y).Drivable;
   end Neighbour_Drives;

   procedure Check_Outing (M : Map.City; Trace : Outing) is
      Saw_Ride : Boolean := False;
      Saw_Exit : Boolean := False;
      Van_Down : Boolean := False;
      Thrown   : Boolean := False;
      Followed : Boolean := True;
      On_Road  : Boolean := True;
      Ped      : Snapshot;
      Frame    : Ride_Frame;
   begin
      pragma Assert (not Trace.Peds.Is_Empty);
      pragma Assert (not Trace.Cars.Is_Empty);
      for I in Trace.Peds.First_Index .. Trace.Peds.Last_Index loop
         Ped := Trace.Peds (I);
         if Ped.Ident = 1 and then Ped.State = Peds.Riding then
            Saw_Ride := True;
         elsif Ped.Ident = 1
           and then Saw_Ride
           and then Ped.State = Peds.Standing
         then
            Saw_Exit := True;
         end if;
         if Ped.Ident = 3
           and then Ped.Tick = Trace.Peds (Trace.Peds.Last_Index).Tick
           and then Ped.State = Peds.Standing
           and then Ped.Alive
         then
            Thrown := True;
         end if;
      end loop;
      for I in Trace.Cars.First_Index .. Trace.Cars.Last_Index loop
         Frame := Trace.Cars (I);
         if not Map.Tile_At (M, Frame.X, Frame.Y).Drivable then
            On_Road := False;
         end if;
         if Frame.Along > 0 and then not Neighbour_Drives (M, Frame) then
            On_Road := False;
         end if;
         if Frame.Sort = Vehicles.Van
           and then Frame.Tick
             = Trace.Cars (Trace.Cars.Last_Index).Tick
           and then not Frame.Intact
           and then Frame.Riders = 0
           and then Frame.Motion = Vehicles.Wrecked
         then
            Van_Down := True;
         end if;
         for R in 1 .. Frame.Riders loop
            for P in Trace.Peds.First_Index .. Trace.Peds.Last_Index loop
               Ped := Trace.Peds (P);
               if Ped.Tick = Frame.Tick
                 and then Integer (Ped.Ident) = Frame.Rider (R)
                 and then not Same_Spot (Ped, Frame)
               then
                  Followed := False;
               end if;
            end loop;
         end loop;
      end loop;
      pragma Assert (Saw_Ride);
      pragma Assert (Saw_Exit);
      pragma Assert (Van_Down);
      pragma Assert (Thrown);
      pragma Assert (Followed);
      pragma Assert (On_Road);
   end Check_Outing;

   function Run_Vehicles
     (M : Map.City; Seed : RNG.Word) return Outing
   is
      Plan  : constant Road_Plan := Vehicle_Demo (M);
      Group : Cast (1 .. 4);
      Items : Bag (1 .. 1);
      Fleet : Vehicles.Fleet (1 .. 2);
      Gun   : constant Weapons.Kind := Weapons.Rifle;
      Taken : Boolean;
      Trace : Outing;
   begin
      Group (1) := Recruit (1, Plan.Ped_At, M, Seed);
      Group (2) := Recruit (2, Plan.Shooter_At, M, Seed);
      Group (3) := Recruit (3, Plan.Van_At, M, Seed);
      Group (4) := Recruit (4, Plan.Car_At, M, Seed);
      Fleet (1) := Vehicles.Park
        (1, Vehicles.Car, Plan.Car_At, M, Face_Of (Plan.Car_At, Plan.Goal));
      Fleet (2) := Vehicles.Park
        (2, Vehicles.Van, Plan.Van_At, M, Map.South);
      Vehicles.Board (Fleet (1), 4, Taken);
      pragma Assert (Taken);
      Vehicles.Board (Fleet (2), 3, Taken);
      pragma Assert (Taken);
      Peds.Mount
        (Group (4).Walker, Plan.Car_At,
         Vehicles.Facing (Fleet (1)), 0);
      Peds.Mount
        (Group (3).Walker, Plan.Van_At,
         Vehicles.Facing (Fleet (2)), 0);
      Arm (Group, 2, Gun, Weapons.Profile (Gun).Magazine);
      Order
        (Group, 1,
         (1 => Make_Walk (Plan.Board),
          2 => Make_Enter (1),
          3 => Make_Drive (1, Plan.Goal),
          4 => Make_Exit (1)),
         Replace);
      Order
        (Group, 2,
         (1 => Make_Shoot_Vehicle (2, Gun)),
         Replace);
      Items (1) := (Ident => 1, X => 1, Y => 1, Here => False);
      Trace := Play (M, Group, Items, Fleet, 800);
      Check_Outing (M, Trace);
      return Trace;
   end Run_Vehicles;

end Megacorp.Actions;
