--  SPDX-License-Identifier: MIT
--  Copyright (c) 2026 Robert Boettcher

with Ada.Command_Line;
with Ada.Exceptions;
with Ada.Text_IO;
with Megacorp.Host;
with Megacorp.Map;
with Megacorp.Map.Gen;
with Megacorp.Mission;
with Megacorp.Mission.Gen;
with Megacorp.Data.Virtual_FS.Native;
with Megacorp.Parameters;
with Megacorp.RNG;
with Megacorp.Save;
with Megacorp.Save.Log;
with Megacorp.World.Campaign;
with Megacorp.World.Gen;

procedure Megacorp_Main is
   package Params renames Megacorp.Parameters;

   P : constant Params.Generator_Parameters := Params.Defaults;

   Visited_Stays : constant Boolean :=
     not Params.Region_May_Reroll (Params.Scenario, True)
     and then not Params.Region_May_Reroll (Params.Free_Play, True)
     and then not Params.Region_May_Reroll (Params.Auto_Play, True);
begin
   Megacorp.Host.Log (Megacorp.Host.Info, "start " & Megacorp.Version);
   Ada.Text_IO.Put_Line (Megacorp.Name & " " & Megacorp.Version);
   Ada.Text_IO.Put_Line
     ("corporations:" & Params.Corporation_Count (P)'Image);
   Ada.Text_IO.Put_Line ("regions:" & Params.Region_Count (P)'Image);
   Ada.Text_IO.Put_Line
     ("city map:"
      & Params.City_Map_Width (P)'Image
      & " x"
      & Params.City_Map_Height (P)'Image);
   Ada.Text_IO.Put ("scenario: ");
   if Params.Unvisited_Regions_May_Reroll (Params.Scenario) then
      Ada.Text_IO.Put_Line ("unvisited regions may be re-rolled");
   else
      Ada.Text_IO.Put_Line ("locked once generated");
   end if;
   Ada.Text_IO.Put ("free play: ");
   if Params.Unvisited_Regions_May_Reroll (Params.Free_Play) then
      Ada.Text_IO.Put_Line ("unvisited regions may be re-rolled");
   else
      Ada.Text_IO.Put_Line ("locked once generated");
   end if;
   Ada.Text_IO.Put ("auto-play: ");
   if Params.Unvisited_Regions_May_Reroll (Params.Auto_Play) then
      Ada.Text_IO.Put_Line ("unvisited regions may be re-rolled");
   else
      Ada.Text_IO.Put_Line ("locked once generated");
   end if;
   if Visited_Stays then
      Ada.Text_IO.Put_Line ("visited regions stay as left");
   end if;

   if Ada.Command_Line.Argument_Count = 2
     and then Ada.Command_Line.Argument (1) = "--export"
   then
      Megacorp.Map.Export_Maps
        (Ada.Command_Line.Argument (2), Megacorp.Version);
      Ada.Text_IO.Put_Line
        ("exported maps to " & Ada.Command_Line.Argument (2));
   elsif Ada.Command_Line.Argument_Count >= 4
     and then Ada.Command_Line.Argument (1) = "--campaign"
   then
      declare
         use type Megacorp.RNG.Word;
         function Parent (Path : String) return String;
         function Base (Path : String) return String;
         function Parent (Path : String) return String is
            Last : Natural := Path'Last;
         begin
            while Last >= Path'First and then Path (Last) /= '/' loop
               Last := Last - 1;
            end loop;
            if Last < Path'First then
               return ".";
            end if;
            if Last = Path'First then
               return "/";
            end if;
            return Path (Path'First .. Last - 1);
         end Parent;
         function Base (Path : String) return String is
            Last : Natural := Path'Last;
         begin
            while Last >= Path'First and then Path (Last) /= '/' loop
               Last := Last - 1;
            end loop;
            return Path (Last + 1 .. Path'Last);
         end Base;

         procedure Keep
           (Text : String;
            Into : in out String;
            Len : out Natural);
         procedure Keep
           (Text : String;
            Into : in out String;
            Len : out Natural)
         is
         begin
            if Text'Length > Into'Length or else Text'Length = 0 then
               raise Constraint_Error;
            end if;
            Len := Text'Length;
            Into (Into'First .. Into'First + Len - 1) := Text;
         end Keep;

         Seed : Megacorp.RNG.Word;
         Days : Natural := 0;
         Have_Days : Boolean := False;
         Do_Compact : Boolean := False;
         Save_Path : String (1 .. 256) := (others => ' ');
         Load_Path : String (1 .. 256) := (others => ' ');
         Log_Path : String (1 .. 256) := (others => ' ');
         Save_Len : Natural := 0;
         Load_Len : Natural := 0;
         Log_Len : Natural := 0;
         Cursor : Positive := 3;
         Globe : Megacorp.World.Atlas;
         Snap : Megacorp.Save.Snapshot;
         Book : Megacorp.Save.Log.Journal;
         Start : Natural := 0;
      begin
         Seed := Megacorp.RNG.Word'Value
           (Ada.Command_Line.Argument (2));
         while Cursor <= Ada.Command_Line.Argument_Count loop
            declare
               Arg : constant String :=
                 Ada.Command_Line.Argument (Cursor);
            begin
               if Arg = "--compact" then
                  Do_Compact := True;
                  Cursor := Cursor + 1;
               elsif Cursor = Ada.Command_Line.Argument_Count then
                  raise Constraint_Error;
               elsif Arg = "--days" then
                  Days := Natural'Value
                    (Ada.Command_Line.Argument (Cursor + 1));
                  Have_Days := True;
                  Cursor := Cursor + 2;
               elsif Arg = "--save" then
                  Keep
                    (Ada.Command_Line.Argument (Cursor + 1),
                     Save_Path, Save_Len);
                  Cursor := Cursor + 2;
               elsif Arg = "--load" then
                  Keep
                    (Ada.Command_Line.Argument (Cursor + 1),
                     Load_Path, Load_Len);
                  Cursor := Cursor + 2;
               elsif Arg = "--log" then
                  Keep
                    (Ada.Command_Line.Argument (Cursor + 1),
                     Log_Path, Log_Len);
                  Cursor := Cursor + 2;
               else
                  raise Constraint_Error;
               end if;
            end;
         end loop;
         if not Have_Days
           or else (Do_Compact and then Log_Len = 0)
           or else (Log_Len > 0
                    and then Save_Len = 0
                    and then Load_Len = 0)
           or else (Log_Len > 0 and then Save_Len > 0
                    and then Parent (Save_Path (1 .. Save_Len))
                      /= Parent (Log_Path (1 .. Log_Len)))
           or else (Log_Len > 0 and then Load_Len > 0
                    and then Parent (Load_Path (1 .. Load_Len))
                      /= Parent (Log_Path (1 .. Log_Len)))
         then
            raise Constraint_Error;
         end if;
         Globe := Megacorp.World.Gen.Generate (Seed, P);
         if Log_Len = 0 then
            if Load_Len > 0 then
               declare
                  Root : constant
                    Megacorp.Data.Virtual_FS.Native.Disk :=
                    Megacorp.Data.Virtual_FS.Native.Open
                      (Parent (Load_Path (1 .. Load_Len)));
               begin
                  Snap := Megacorp.Save.Load
                    (Root, Base (Load_Path (1 .. Load_Len)));
               end;
               if Snap.Seed /= Seed then
                  raise Megacorp.Save.Save_Error with "seed mismatch";
               end if;
               Globe := Megacorp.Save.Rebuild (Snap, P);
               Start := Snap.Day;
            else
               Snap := Megacorp.Save.Capture
                 (Globe, 0, Megacorp.Parameters.Auto_Play);
            end if;
            Megacorp.World.Campaign.Put_Day
              (Ada.Text_IO.Standard_Output, Globe, Start);
            for Day in 1 .. Days loop
               Megacorp.World.Campaign.Advance (Globe);
               Megacorp.World.Campaign.Put_Day
                 (Ada.Text_IO.Standard_Output, Globe, Start + Day);
            end loop;
            if Save_Len > 0 then
               Megacorp.Save.Take (Snap, Globe, Start + Days);
               declare
                  Root : Megacorp.Data.Virtual_FS.Native.Disk :=
                    Megacorp.Data.Virtual_FS.Native.Open
                      (Parent (Save_Path (1 .. Save_Len)));
               begin
                  Megacorp.Save.Store
                    (Root, Base (Save_Path (1 .. Save_Len)), Snap);
               end;
            end if;
         else
            declare
               package Native renames
                 Megacorp.Data.Virtual_FS.Native;
               package Journal renames Megacorp.Save.Log;
               Root : Native.Disk :=
                 Native.Open (Parent (Log_Path (1 .. Log_Len)));
               procedure Adopt (Path : String);
               procedure Fold;
               procedure Adopt (Path : String) is
                  Held : constant Native.Disk :=
                    Native.Open (Parent (Path));
               begin
                  Snap := Megacorp.Save.Load (Held, Base (Path));
                  if Snap.Seed /= Seed then
                     raise Megacorp.Save.Save_Error
                       with "seed mismatch";
                  end if;
                  Globe := Megacorp.Save.Rebuild (Snap, P);
               end Adopt;
               procedure Fold is
               begin
                  if Save_Len > 0 then
                     Journal.Compact
                       (Root,
                        Base (Save_Path (1 .. Save_Len)),
                        Base (Log_Path (1 .. Log_Len)),
                        Snap, Book);
                  end if;
                  if Load_Len > 0
                    and then (Save_Len = 0
                      or else Load_Path (1 .. Load_Len)
                        /= Save_Path (1 .. Save_Len))
                  then
                     if Save_Len > 0 then
                        Megacorp.Save.Store
                          (Root,
                           Base (Load_Path (1 .. Load_Len)),
                           Snap);
                     else
                        Journal.Compact
                          (Root,
                           Base (Load_Path (1 .. Load_Len)),
                           Base (Log_Path (1 .. Log_Len)),
                           Snap, Book);
                     end if;
                  end if;
               end Fold;
            begin
               if Load_Len > 0 then
                  Adopt (Load_Path (1 .. Load_Len));
               elsif Native.Exists
                 (Root, Base (Save_Path (1 .. Save_Len)))
               then
                  Adopt (Save_Path (1 .. Save_Len));
               else
                  Snap := Megacorp.Save.Capture
                    (Globe, 0, Megacorp.Parameters.Auto_Play);
                  Megacorp.Save.Store
                    (Root, Base (Save_Path (1 .. Save_Len)), Snap);
               end if;
               if Native.Exists
                 (Root, Base (Log_Path (1 .. Log_Len)))
               then
                  Book := Journal.Load
                    (Root, Base (Log_Path (1 .. Log_Len)));
                  if Journal.Notice (Book)
                    = "torn delta record dropped"
                  then
                     Journal.Rewrite
                       (Root,
                        Base (Log_Path (1 .. Log_Len)),
                        Snap, Book);
                  end if;
                  Journal.Replay (Snap, Globe, Book);
               else
                  Book := Journal.Start
                    (Root,
                     Base (Log_Path (1 .. Log_Len)),
                     Snap);
               end if;
               Start := Snap.Day;
               Megacorp.World.Campaign.Put_Day
                 (Ada.Text_IO.Standard_Output, Globe, Start);
               for Day in 1 .. Days loop
                  Journal.Commit
                    (Root,
                     Base (Log_Path (1 .. Log_Len)),
                     Snap, Globe, Book,
                     Journal.Day_None);
                  if Journal.Due (Book) then
                     Fold;
                  end if;
                  Megacorp.World.Campaign.Put_Day
                    (Ada.Text_IO.Standard_Output, Globe, Snap.Day);
               end loop;
               if Do_Compact then
                  Fold;
               end if;
            end;
         end if;
      exception
         when Constraint_Error =>
            Ada.Text_IO.Put_Line
              (Ada.Text_IO.Current_Error,
               "usage: megacorp [--export DIR]"
               & " [--world [SEED]]"
               & " [--campaign SEED --days N]"
               & " [--save FILE] [--load FILE]"
               & " [--log FILE] [--compact]"
               & " [--mission SEED [--ticks N]]");
            Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
         when Error : Megacorp.Save.Save_Error =>
            Ada.Text_IO.Put_Line
              (Ada.Text_IO.Current_Error,
               Ada.Exceptions.Exception_Message (Error));
            Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
      end;
   elsif Ada.Command_Line.Argument_Count in 1 .. 2
     and then Ada.Command_Line.Argument (1) = "--world"
   then
      declare
         Seed : Megacorp.RNG.Word := 42;
         Globe : Megacorp.World.Atlas;
      begin
         if Ada.Command_Line.Argument_Count = 2 then
            Seed := Megacorp.RNG.Word'Value
              (Ada.Command_Line.Argument (2));
         end if;
         Globe := Megacorp.World.Gen.Generate (Seed, P);
         Megacorp.World.Gen.Put
           (Ada.Text_IO.Standard_Output, Globe);
      exception
         when Constraint_Error =>
            Ada.Text_IO.Put_Line
              (Ada.Text_IO.Current_Error,
               "usage: megacorp [--export DIR]"
               & " [--world [SEED]]"
               & " [--campaign SEED --days N]"
               & " [--save FILE] [--load FILE]"
               & " [--log FILE] [--compact]"
               & " [--mission SEED [--ticks N]]");
            Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
      end;
   elsif Ada.Command_Line.Argument_Count in 2 .. 4
     and then Ada.Command_Line.Argument (1) = "--mission"
   then
      declare
         Seed : Megacorp.RNG.Word;
         Ticks : Natural := 200;
         City : Megacorp.Map.City :=
           Megacorp.Map.Gen.Generate (1, P);
         Run : Megacorp.Mission.Trace;
      begin
         Seed := Megacorp.RNG.Word'Value
           (Ada.Command_Line.Argument (2));
         if Ada.Command_Line.Argument_Count = 4
           and then Ada.Command_Line.Argument (3) = "--ticks"
         then
            Ticks := Natural'Value (Ada.Command_Line.Argument (4));
         elsif Ada.Command_Line.Argument_Count /= 2 then
            Ada.Text_IO.Put_Line
              (Ada.Text_IO.Current_Error,
               "usage: megacorp [--export DIR]"
               & " [--world [SEED]]"
               & " [--campaign SEED --days N]"
               & " [--save FILE] [--load FILE]"
               & " [--log FILE] [--compact]"
               & " [--mission SEED [--ticks N]]");
            Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
            return;
         end if;
         if Ticks < 1 then
            Ticks := 1;
         end if;
         City := Megacorp.Map.Gen.Generate (Seed, P);
         Run := Megacorp.Mission.Gen.Play (City, Seed, Ticks);
         Megacorp.Mission.Put
           (Ada.Text_IO.Standard_Output, Seed, Run.Outcome);
      exception
         when Constraint_Error =>
            Ada.Text_IO.Put_Line
              (Ada.Text_IO.Current_Error,
               "usage: megacorp [--export DIR]"
               & " [--world [SEED]]"
               & " [--campaign SEED --days N]"
               & " [--save FILE] [--load FILE]"
               & " [--log FILE] [--compact]"
               & " [--mission SEED [--ticks N]]");
            Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
      end;
   elsif Ada.Command_Line.Argument_Count = 0 then
      Ada.Text_IO.Put_Line ("sample map seed 42 (generated city)");
      Ada.Text_IO.Put_Line
        ("legend: . open  + road  = pavement  B building  ~ water");
      Megacorp.Map.Put_Sample (Megacorp.Map.Gen.Generate (42, P));
   else
      Ada.Text_IO.Put_Line
        (Ada.Text_IO.Current_Error,
         "usage: megacorp [--export DIR]"
         & " [--world [SEED]]"
         & " [--campaign SEED --days N]"
         & " [--save FILE] [--load FILE]"
         & " [--log FILE] [--compact]"
         & " [--mission SEED [--ticks N]]");
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end Megacorp_Main;
