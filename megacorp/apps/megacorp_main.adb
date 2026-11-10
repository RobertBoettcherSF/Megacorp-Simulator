--  SPDX-License-Identifier: MIT
--  Copyright (c) 2026 Robert Boettcher

with Ada.Command_Line;
with Ada.Text_IO;
with Megacorp.Host;
with Megacorp.Map;
with Megacorp.Parameters;

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
   elsif Ada.Command_Line.Argument_Count = 0 then
      Ada.Text_IO.Put_Line ("sample map seed 42 (test layout)");
      Ada.Text_IO.Put_Line
        ("legend: . open  + road  = pavement  B building  ~ water");
      Megacorp.Map.Put_Sample (Megacorp.Map.Test_Layout (42, P));
   else
      Ada.Text_IO.Put_Line
        (Ada.Text_IO.Current_Error,
         "usage: megacorp [--export DIR]");
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end Megacorp_Main;
