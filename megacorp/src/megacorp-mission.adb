--  SPDX-License-Identifier: MIT
--  Copyright (c) 2026 Robert Boettcher

with Megacorp.Weapons;

package body Megacorp.Mission is
   use type Actions.Item_Id;
   use type Behaviour.Mood;
   use type Behaviour.Role;

   function Word
     (Line : String; Index : Positive) return String;
   function To_Action (C : Command) return Actions.Action;
   function Find_Ped
     (Group : Behaviour.Crowd; Who : Peds.Ped_Id) return Natural;
   function Living_Agents (Group : Behaviour.Crowd) return Natural;
   function Goal_Met
     (Goal : Objective;
      Group : Behaviour.Crowd;
      Items : Actions.Bag) return Boolean;
   function Count_Met
     (Goals : Objective_List;
      Group : Behaviour.Crowd;
      Items : Actions.Bag) return Natural;
   function Judge
     (Group : Behaviour.Crowd;
      Items : Actions.Bag;
      Goals : Objective_List;
      At_Tick : Natural;
      Max_Ticks : Natural;
      Finished : Boolean) return Report;
   procedure Apply
     (Group : in out Behaviour.Crowd;
      Lines : Command_Lists.Vector;
      At_Tick : Positive);
   procedure Note
     (Rows : in out Goal_Lists.Vector;
      Goals : Objective_List;
      Group : Behaviour.Crowd;
      Items : Actions.Bag;
      At_Tick : Natural);
   function Open_Tile (M : Map.City; At_Point : Map.Point) return Boolean;
   function Fixture_Script
     (Plan : Fixture_Plan) return Command_Lists.Vector;
   function Dir_Of (Text : String) return Map.Eight_Way;
   function Parse (Line : String; C : out Command) return Boolean;

   function Word (Line : String; Index : Positive) return String is
      Seen : Natural := 0;
      Start : Positive;
      Cursor : Positive := Line'First;
   begin
      while Cursor <= Line'Last loop
         while Cursor <= Line'Last and then Line (Cursor) = ' ' loop
            Cursor := Cursor + 1;
         end loop;
         exit when Cursor > Line'Last;
         Seen := Seen + 1;
         Start := Cursor;
         while Cursor <= Line'Last and then Line (Cursor) /= ' ' loop
            Cursor := Cursor + 1;
         end loop;
         if Seen = Index then
            return Line (Start .. Cursor - 1);
         end if;
      end loop;
      return "";
   end Word;

   function To_Action (C : Command) return Actions.Action is
   begin
      case C.What is
         when Walk =>
            return Actions.Make_Walk ((X => C.X, Y => C.Y));
         when Wait =>
            return Actions.Make_Wait (C.Ticks);
         when Pick =>
            return Actions.Make_Pick (C.Item);
         when Shoot =>
            return Actions.Make_Shoot (C.Target, Weapons.Pistol);
         when Turn =>
            return Actions.Make_Turn (C.Dir);
      end case;
   end To_Action;

   function Find_Ped
     (Group : Behaviour.Crowd; Who : Peds.Ped_Id) return Natural
   is
   begin
      for I in Group'Range loop
         if Behaviour.Ident (Group (I)) = Who then
            return I;
         end if;
      end loop;
      return 0;
   end Find_Ped;

   function Living_Agents (Group : Behaviour.Crowd) return Natural is
      Total : Natural := 0;
   begin
      for I in Group'Range loop
         if Behaviour.Job_Of (Group (I)) = Behaviour.Agent
           and then Behaviour.Observe (Group (I)).Alive
         then
            Total := Total + 1;
         end if;
      end loop;
      return Total;
   end Living_Agents;

   function Goal_Met
     (Goal : Objective;
      Group : Behaviour.Crowd;
      Items : Actions.Bag) return Boolean
   is
      Slot : Natural;
      View : Behaviour.Frame;
   begin
      case Goal.Kind is
         when Eliminate =>
            Slot := Find_Ped (Group, Goal.Target);
            if Slot = 0 then
               return False;
            end if;
            return not Behaviour.Observe (Group (Slot)).Alive;
         when Acquire =>
            for I in Items'Range loop
               if Items (I).Ident = Goal.Item then
                  return not Items (I).Here;
               end if;
            end loop;
            return False;
         when Persuade =>
            Slot := Find_Ped (Group, Goal.Contact);
            if Slot = 0 then
               return False;
            end if;
            return Behaviour.Mood_Of (Group (Slot)) = Behaviour.Persuaded;
         when Evacuate =>
            for I in Group'Range loop
               View := Behaviour.Observe (Group (I));
               if Behaviour.Job_Of (Group (I)) = Behaviour.Agent
                 and then View.Alive
                 and then View.Along = 0
                 and then View.X = Goal.Zone_X
                 and then View.Y = Goal.Zone_Y
               then
                  return True;
               end if;
            end loop;
            return False;
      end case;
   end Goal_Met;

   function Count_Met
     (Goals : Objective_List;
      Group : Behaviour.Crowd;
      Items : Actions.Bag) return Natural
   is
      Total : Natural := 0;
   begin
      for I in Goals'Range loop
         if Goal_Met (Goals (I), Group, Items) then
            Total := Total + 1;
         end if;
      end loop;
      return Total;
   end Count_Met;

   function Judge
     (Group : Behaviour.Crowd;
      Items : Actions.Bag;
      Goals : Objective_List;
      At_Tick : Natural;
      Max_Ticks : Natural;
      Finished : Boolean) return Report
   is
      R : Report;
   begin
      R.Tick := At_Tick;
      R.Total := Goals'Length;
      R.Met := Count_Met (Goals, Group, Items);
      R.Agents_Alive := Living_Agents (Group);
      if R.Agents_Alive = 0 then
         R.Outcome := Lost;
         R.Why := Squad_Lost;
      elsif R.Met = R.Total then
         R.Outcome := Won;
         R.Why := Objectives_Met;
      elsif Finished or else At_Tick = Max_Ticks then
         R.Outcome := Timed_Out;
         R.Why := Time_Up;
         R.Tick := Max_Ticks;
      else
         R.Outcome := Running;
         R.Why := In_Progress;
      end if;
      return R;
   end Judge;

   procedure Apply
     (Group : in out Behaviour.Crowd;
      Lines : Command_Lists.Vector;
      At_Tick : Positive)
   is
      Acts : Actions.Action_Array (1 .. Actions.Capacity);
      Count : Natural;
   begin
      for I in Group'Range loop
         Count := 0;
         for C in Lines.First_Index .. Lines.Last_Index loop
            if Lines (C).At_Tick = At_Tick
              and then Lines (C).Who = Behaviour.Ident (Group (I))
              and then Count < Actions.Capacity
            then
               Count := Count + 1;
               Acts (Count) := To_Action (Lines (C));
            end if;
         end loop;
         if Count > 0 then
            Behaviour.Order
              (Group, I, Acts (1 .. Count), Actions.Replace);
         end if;
      end loop;
   end Apply;

   procedure Note
     (Rows : in out Goal_Lists.Vector;
      Goals : Objective_List;
      Group : Behaviour.Crowd;
      Items : Actions.Bag;
      At_Tick : Natural)
   is
      Row : Goal_Row;
      N : Natural := 0;
   begin
      Row.Tick := At_Tick;
      Row.Done := (others => False);
      for I in Goals'Range loop
         N := N + 1;
         Row.Done (N) := Goal_Met (Goals (I), Group, Items);
      end loop;
      Row.Met := Count_Met (Goals, Group, Items);
      Row.Item_Here := False;
      for I in Items'Range loop
         if Items (I).Here then
            Row.Item_Here := True;
         end if;
      end loop;
      Rows.Append (Row);
   end Note;

   function Play
     (M : Map.City;
      Group : in out Behaviour.Crowd;
      Items : in out Actions.Bag;
      Fleet : in out Vehicles.Fleet;
      Goals : Objective_List;
      Lines : Command_Lists.Vector;
      Max_Ticks : Natural) return Trace
   is
      Out_Trace : Trace;
      View : Behaviour.Frame;
   begin
      if Items'Length > 0 then
         Out_Trace.Has_Item := True;
         Out_Trace.Item_X := Items (Items'First).X;
         Out_Trace.Item_Y := Items (Items'First).Y;
      end if;
      Note (Out_Trace.Goals, Goals, Group, Items, 0);
      for I in Group'Range loop
         View := Behaviour.Observe (Group (I));
         View.Tick := 0;
         Out_Trace.Frames.Append (View);
      end loop;
      Out_Trace.Outcome :=
        Judge (Group, Items, Goals, 0, Max_Ticks, False);
      if Out_Trace.Outcome.Outcome /= Running then
         return Out_Trace;
      end if;
      for At_Tick in 1 .. Max_Ticks loop
         Apply (Group, Lines, At_Tick);
         Behaviour.Step (Group, M, Items, Fleet, At_Tick);
         Note (Out_Trace.Goals, Goals, Group, Items, At_Tick);
         for I in Group'Range loop
            View := Behaviour.Observe (Group (I));
            View.Tick := At_Tick;
            Out_Trace.Frames.Append (View);
         end loop;
         Out_Trace.Outcome :=
           Judge (Group, Items, Goals, At_Tick, Max_Ticks, False);
         exit when Out_Trace.Outcome.Outcome /= Running;
      end loop;
      if Out_Trace.Outcome.Outcome = Running then
         Out_Trace.Outcome :=
           Judge (Group, Items, Goals, Max_Ticks, Max_Ticks, True);
      end if;
      return Out_Trace;
   end Play;

   function Dir_Of (Text : String) return Map.Eight_Way is
   begin
      if Text = "north" then
         return Map.North;
      elsif Text = "east" then
         return Map.East;
      elsif Text = "south" then
         return Map.South;
      elsif Text = "west" then
         return Map.West;
      elsif Text = "north_east" then
         return Map.North_East;
      elsif Text = "south_east" then
         return Map.South_East;
      elsif Text = "south_west" then
         return Map.South_West;
      else
         return Map.North_West;
      end if;
   end Dir_Of;

   function Parse (Line : String; C : out Command) return Boolean is
      Kind : constant String := Word (Line, 3);
   begin
      if Word (Line, 1) = "" or else Word (Line, 2) = "" then
         return False;
      end if;
      C.At_Tick := Positive'Value (Word (Line, 1));
      C.Who := Peds.Ped_Id'Value (Word (Line, 2));
      if Kind = "walk" then
         C.What := Walk;
         C.X := Positive'Value (Word (Line, 4));
         C.Y := Positive'Value (Word (Line, 5));
      elsif Kind = "wait" then
         C.What := Wait;
         C.Ticks := Positive'Value (Word (Line, 4));
      elsif Kind = "pick" then
         C.What := Pick;
         C.Item := Actions.Item_Id'Value (Word (Line, 4));
      elsif Kind = "shoot" then
         C.What := Shoot;
         C.Target := Peds.Ped_Id'Value (Word (Line, 4));
      elsif Kind = "turn" then
         C.What := Turn;
         C.Dir := Dir_Of (Word (Line, 4));
      else
         return False;
      end if;
      return True;
   exception
      when Constraint_Error =>
         return False;
   end Parse;

   function Load (Path : String) return Command_Lists.Vector is
      File : Ada.Text_IO.File_Type;
      Lines : Command_Lists.Vector;
      C : Command;
   begin
      Ada.Text_IO.Open (File, Ada.Text_IO.In_File, Path);
      while not Ada.Text_IO.End_Of_File (File) loop
         declare
            Line : constant String := Ada.Text_IO.Get_Line (File);
         begin
            if Word (Line, 1) /= "" and then Parse (Line, C) then
               Lines.Append (C);
            end if;
         end;
      end loop;
      Ada.Text_IO.Close (File);
      return Lines;
   end Load;

   procedure Dump (Lines : Command_Lists.Vector; Path : String) is
      File : Ada.Text_IO.File_Type;
      C : Command;
   begin
      Ada.Text_IO.Create (File, Ada.Text_IO.Out_File, Path);
      for I in Lines.First_Index .. Lines.Last_Index loop
         C := Lines (I);
         Ada.Text_IO.Put (File, Positive'Image (C.At_Tick));
         Ada.Text_IO.Put (File, Peds.Ped_Id'Image (C.Who));
         case C.What is
            when Walk =>
               Ada.Text_IO.Put (File, " walk");
               Ada.Text_IO.Put (File, Positive'Image (C.X));
               Ada.Text_IO.Put (File, Positive'Image (C.Y));
            when Wait =>
               Ada.Text_IO.Put (File, " wait");
               Ada.Text_IO.Put (File, Positive'Image (C.Ticks));
            when Pick =>
               Ada.Text_IO.Put (File, " pick");
               Ada.Text_IO.Put (File, Actions.Item_Id'Image (C.Item));
            when Shoot =>
               Ada.Text_IO.Put (File, " shoot");
               Ada.Text_IO.Put (File, Peds.Ped_Id'Image (C.Target));
            when Turn =>
               Ada.Text_IO.Put (File, " turn south");
         end case;
         Ada.Text_IO.New_Line (File);
      end loop;
      Ada.Text_IO.Close (File);
   end Dump;

   procedure Put
     (File : Ada.Text_IO.File_Type;
      Seed : RNG.Word;
      R : Report)
   is
   begin
      declare
         Image : constant String := RNG.Word'Image (Seed);
      begin
         Ada.Text_IO.Put (File, "mission ");
         Ada.Text_IO.Put (File, Image (Image'First + 1 .. Image'Last));
         Ada.Text_IO.Put (File, ": ");
      end;
      Ada.Text_IO.Put_Line (File, Status_Token (R.Outcome));
      Ada.Text_IO.Put (File, "tick");
      Ada.Text_IO.Put_Line (File, Natural'Image (R.Tick));
      Ada.Text_IO.Put_Line (File, "why " & Cause_Token (R.Why));
      Ada.Text_IO.Put (File, "objectives");
      Ada.Text_IO.Put (File, Natural'Image (R.Met));
      Ada.Text_IO.Put (File, " of");
      Ada.Text_IO.Put_Line (File, Natural'Image (R.Total));
      Ada.Text_IO.Put (File, "agents alive");
      Ada.Text_IO.Put_Line (File, Natural'Image (R.Agents_Alive));
   end Put;

   function Status_Token (Which : Status) return String is
   begin
      case Which is
         when Running =>
            return "running";
         when Won =>
            return "won";
         when Lost =>
            return "lost";
         when Timed_Out =>
            return "timed_out";
      end case;
   end Status_Token;

   function Cause_Token (Which : Cause) return String is
   begin
      case Which is
         when In_Progress =>
            return "in_progress";
         when Objectives_Met =>
            return "objectives_met";
         when Squad_Lost =>
            return "squad_lost";
         when Time_Up =>
            return "time_up";
      end case;
   end Cause_Token;

   function Kind_Token (Which : Objective_Kind) return String is
   begin
      case Which is
         when Eliminate =>
            return "eliminate";
         when Acquire =>
            return "acquire";
         when Persuade =>
            return "persuade";
         when Evacuate =>
            return "evacuate";
      end case;
   end Kind_Token;

   function Open_Tile (M : Map.City; At_Point : Map.Point) return Boolean is
   begin
      return Map.In_Bounds (M, At_Point.X, At_Point.Y)
        and then Map.Tile_At (M, At_Point.X, At_Point.Y).Walkable;
   end Open_Tile;

   function Fixture_Of (M : Map.City) return Fixture_Plan is
      Plan : Fixture_Plan;
      Y : constant Positive := 50;
   begin
      Plan.Contact := (X => 1, Y => Y - 1);
      Plan.Agent := (X => 1, Y => Y);
      Plan.Case_At := (X => 1, Y => Y + 4);
      Plan.Stand := (X => 1, Y => Y + 7);
      Plan.Target := (X => 1, Y => Y + 8);
      Plan.Zone := Plan.Stand;
      pragma Assert (Open_Tile (M, Plan.Contact));
      pragma Assert (Open_Tile (M, Plan.Agent));
      pragma Assert (Open_Tile (M, Plan.Case_At));
      pragma Assert (Open_Tile (M, Plan.Stand));
      pragma Assert (Open_Tile (M, Plan.Target));
      pragma Assert (Open_Tile (M, Plan.Zone));
      return Plan;
   end Fixture_Of;

   function Fixture_Script
     (Plan : Fixture_Plan) return Command_Lists.Vector
   is
      Lines : Command_Lists.Vector;
      C : Command;
   begin
      C.At_Tick := 1;
      C.Who := 1;
      C.What := Wait;
      C.Ticks := 12;
      Lines.Append (C);
      C.What := Walk;
      C.X := Plan.Case_At.X;
      C.Y := Plan.Case_At.Y;
      Lines.Append (C);
      C.What := Pick;
      C.Item := 1;
      Lines.Append (C);
      C.What := Walk;
      C.X := Plan.Stand.X;
      C.Y := Plan.Stand.Y;
      Lines.Append (C);
      C.What := Shoot;
      C.Target := 3;
      Lines.Append (C);
      return Lines;
   end Fixture_Script;

   function Demonstration
     (M : Map.City;
      Seed : RNG.Word;
      Max_Ticks : Natural := 200) return Trace
   is
      Plan : constant Fixture_Plan := Fixture_Of (M);
      Group : Behaviour.Crowd (1 .. 3);
      Items : Actions.Bag (1 .. 1);
      Fleet : Vehicles.Fleet (1 .. 0);
      Goals : Objective_List (1 .. 4);
      Gun : constant Weapons.Kind := Weapons.Pistol;
      Result : Trace;
   begin
      Group (1) := Behaviour.Enlist (1, Behaviour.Agent, Plan.Agent, M, Seed);
      Group (2) :=
        Behaviour.Enlist (2, Behaviour.Civilian, Plan.Contact, M, Seed);
      Group (3) := Behaviour.Enlist
        (3, Behaviour.Guard, Plan.Target, M, Seed, Plan.Target, Plan.Target);
      Behaviour.Arm
        (Group, 1, Gun, Weapons.Profile (Gun).Magazine);
      Items (1) :=
        (Ident => 1, X => Plan.Case_At.X, Y => Plan.Case_At.Y, Here => True);
      Goals (1) := (Kind => Persuade, Contact => 2);
      Goals (2) := (Kind => Acquire, Item => 1);
      Goals (3) := (Kind => Eliminate, Target => 3);
      Goals (4) :=
        (Kind => Evacuate, Zone_X => Plan.Zone.X, Zone_Y => Plan.Zone.Y);
      Result := Play
        (M, Group, Items, Fleet, Goals, Fixture_Script (Plan), Max_Ticks);
      return Result;
   end Demonstration;

end Megacorp.Mission;
