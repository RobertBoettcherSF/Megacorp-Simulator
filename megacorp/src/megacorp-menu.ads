--  SPDX-License-Identifier: MIT
--  Copyright (c) 2026 Robert Boettcher

--  Item 26. Which screen is showing. The page only draws it.
--  A scenario is a fixed seed. Free play keeps a typed seed.
package Megacorp.Menu is
   type Screen is
     (Title, New_Game, Settings, Credits,
      Atlas, Briefing, Field, Debrief, Paused);

   type Action is
     (Up, Down, Activate, Back,
      New_Scenario, New_Free, Continue_Game,
      Open_Brief, Start_Field, Cancel_Brief, Ack_Debrief,
      Pause_Now, Resume_Now, Save_Now, Quit_Title,
      Set_Speed, Set_Volume, Roll_Seed, Type_Digit, Clear_Seed,
      Reroll_Region, Open_New, Open_Settings, Open_Credits,
      Set_Effects, Set_Music);

   type Effect is
     (Stay, Make_Scenario, Make_Free, Load_Continue,
      Launch, Write_Disk, Leave_Game, Reroll);

   type Card is record
      Where    : Screen := Title;
      Under    : Screen := Atlas;
      Cursor   : Natural := 0;
      Saved    : Boolean := False;
      Speed    : Natural := 1;
      Volume   : Natural := 70;
      Effects  : Natural := 80;
      Music    : Natural := 40;
      Region   : Natural := 0;
      Scenario : Natural := 1;
      Typed    : Natural := 42;
      Outcome  : Natural := 0;
      Dead     : Natural := 0;
      Loot     : Integer := 0;
      Before   : Integer := 0;
      After    : Integer := 0;
   end record;

   Scenario_Count : constant := 3;

   function Scenario_Seed (Index : Positive) return Positive
     with Pre => Index <= Scenario_Count;

   function Scenario_Name (Index : Positive) return String
     with Pre => Index <= Scenario_Count;

   function Free_Seed (Item : Card) return Positive;

   function Choice_Count (Item : Card) return Natural;

   function Handle
     (Item : in out Card;
      Act : Action;
      Arg : Integer) return Effect;

   procedure Arrive (Item : in out Card; Next : Screen);

   procedure Note_Result
     (Item : in out Card;
      Ending : Natural;
      Dead : Natural;
      Funds_Before : Integer;
      Funds_After : Integer)
     with Post => Item.Where = Debrief;
end Megacorp.Menu;
