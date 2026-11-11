--  SPDX-License-Identifier: MIT
--  Copyright (c) 2026 Robert Boettcher

package body Megacorp.Menu is
   function Title_Count (Item : Card) return Natural;
   procedure Move (Item : in out Card; By : Integer);
   procedure Activate (Item : in out Card; Result : out Effect);
   function Speed_Of (Index : Natural) return Natural;

   function Scenario_Seed (Index : Positive) return Positive is
   begin
      case Index is
         when 1 =>
            return 42;
         when 2 =>
            return 7;
         when 3 =>
            return 100;
         when others =>
            return 42;
      end case;
   end Scenario_Seed;

   function Scenario_Name (Index : Positive) return String is
   begin
      case Index is
         when 1 =>
            return "Harbour";
         when 2 =>
            return "Foundry";
         when 3 =>
            return "Marches";
         when others =>
            return "Harbour";
      end case;
   end Scenario_Name;

   function Free_Seed (Item : Card) return Positive is
   begin
      if Item.Typed = 0 then
         return 1;
      end if;
      return Item.Typed;
   end Free_Seed;

   function Title_Count (Item : Card) return Natural is
   begin
      if Item.Saved then
         return 4;
      end if;
      return 3;
   end Title_Count;

   function Choice_Count (Item : Card) return Natural is
   begin
      case Item.Where is
         when Title =>
            return Title_Count (Item);
         when New_Game =>
            return 6;
         when Settings =>
            return 5;
         when Credits =>
            return 1;
         when Briefing =>
            return 2;
         when Debrief =>
            return 1;
         when Paused =>
            return 3;
         when Atlas | Field =>
            return 0;
      end case;
   end Choice_Count;

   function Speed_Of (Index : Natural) return Natural is
   begin
      case Index is
         when 0 =>
            return 0;
         when 2 =>
            return 2;
         when 3 =>
            return 4;
         when others =>
            return 1;
      end case;
   end Speed_Of;

   procedure Move (Item : in out Card; By : Integer) is
      Count : constant Natural := Choice_Count (Item);
   begin
      if Count = 0 then
         return;
      end if;
      if By < 0 then
         if Item.Cursor = 0 then
            Item.Cursor := Count - 1;
         else
            Item.Cursor := Item.Cursor - 1;
         end if;
      else
         Item.Cursor := (Item.Cursor + 1) mod Count;
      end if;
   end Move;

   procedure Activate (Item : in out Card; Result : out Effect) is
      Pick : Natural;
   begin
      Result := Stay;
      case Item.Where is
         when Title =>
            Pick := Item.Cursor;
            if not Item.Saved and then Pick > 0 then
               Pick := Pick + 1;
            end if;
            if Pick = 0 then
               Item.Where := New_Game;
               Item.Cursor := 0;
            elsif Pick = 1 and then Item.Saved then
               Result := Load_Continue;
            elsif Pick = 2 then
               Item.Where := Settings;
               Item.Cursor := 0;
            elsif Pick = 3 then
               Item.Where := Credits;
               Item.Cursor := 0;
            end if;
         when New_Game =>
            if Item.Cursor <= 2 then
               Item.Scenario := Item.Cursor + 1;
               Result := Make_Scenario;
            elsif Item.Cursor = 3 then
               Item.Typed := (Item.Typed * 17 + 3) mod 100_000;
               if Item.Typed = 0 then
                  Item.Typed := 1;
               end if;
            elsif Item.Cursor = 4 then
               Result := Make_Free;
            else
               Item.Where := Title;
               Item.Cursor := 0;
            end if;
         when Settings =>
            if Item.Cursor <= 3 then
               Item.Speed := Speed_Of (Item.Cursor);
            else
               Item.Where := Title;
               Item.Cursor := 0;
            end if;
         when Credits =>
            Item.Where := Title;
            Item.Cursor := 0;
         when Briefing =>
            if Item.Cursor = 0 then
               Result := Launch;
            else
               Item.Where := Atlas;
               Item.Cursor := 0;
            end if;
         when Debrief =>
            Item.Where := Atlas;
            Item.Cursor := 0;
         when Paused =>
            if Item.Cursor = 0 then
               Item.Where := Item.Under;
            elsif Item.Cursor = 1 then
               Result := Write_Disk;
            else
               Result := Leave_Game;
            end if;
         when Atlas | Field =>
            null;
      end case;
   end Activate;

   function Handle
     (Item : in out Card;
      Act : Action;
      Arg : Integer) return Effect
   is
      Result : Effect := Stay;
   begin
      case Act is
         when Up =>
            Move (Item, -1);
         when Down =>
            Move (Item, 1);
         when Activate =>
            Activate (Item, Result);
         when Back =>
            case Item.Where is
               when New_Game | Settings | Credits =>
                  Item.Where := Title;
                  Item.Cursor := 0;
               when Briefing =>
                  Item.Where := Atlas;
                  Item.Cursor := 0;
               when Debrief =>
                  Item.Where := Atlas;
                  Item.Cursor := 0;
               when Paused =>
                  Item.Where := Item.Under;
               when others =>
                  null;
            end case;
         when New_Scenario =>
            if Item.Where = New_Game
              and then Arg >= 1
              and then Arg <= Scenario_Count
            then
               Item.Scenario := Arg;
               Result := Make_Scenario;
            end if;
         when New_Free =>
            if Item.Where = New_Game then
               if Arg > 0 and then Arg <= 999_999 then
                  Item.Typed := Arg;
               end if;
               Result := Make_Free;
            end if;
         when Continue_Game =>
            if Item.Where = Title and then Item.Saved then
               Result := Load_Continue;
            end if;
         when Open_Brief =>
            if Item.Where = Atlas and then Arg >= 1 then
               Item.Region := Arg;
               Item.Where := Briefing;
               Item.Cursor := 0;
            end if;
         when Start_Field =>
            if Item.Where = Briefing and then Item.Region >= 1 then
               Result := Launch;
            end if;
         when Cancel_Brief =>
            if Item.Where = Briefing then
               Item.Where := Atlas;
               Item.Cursor := 0;
            end if;
         when Ack_Debrief =>
            if Item.Where = Debrief then
               Item.Where := Atlas;
               Item.Cursor := 0;
            end if;
         when Pause_Now =>
            if Item.Where = Atlas or else Item.Where = Field then
               Item.Under := Item.Where;
               Item.Where := Paused;
               Item.Cursor := 0;
            end if;
         when Resume_Now =>
            if Item.Where = Paused then
               Item.Where := Item.Under;
            end if;
         when Save_Now =>
            if Item.Where = Paused then
               Result := Write_Disk;
            end if;
         when Quit_Title =>
            if Item.Where = Paused then
               Result := Leave_Game;
            end if;
         when Set_Speed =>
            if Arg = 0 or else Arg = 1 or else Arg = 2 or else Arg = 4
            then
               Item.Speed := Arg;
            end if;
         when Set_Volume =>
            if Arg >= 0 and then Arg <= 100 then
               Item.Volume := Arg;
            end if;
         when Set_Effects =>
            if Arg >= 0 and then Arg <= 100 then
               Item.Effects := Arg;
            end if;
         when Set_Music =>
            if Arg >= 0 and then Arg <= 100 then
               Item.Music := Arg;
            end if;
         when Roll_Seed =>
            if Item.Where = New_Game then
               Item.Typed := (Item.Typed * 17 + 3) mod 100_000;
               if Item.Typed = 0 then
                  Item.Typed := 1;
               end if;
            end if;
         when Type_Digit =>
            if Item.Where = New_Game
              and then Arg >= 0
              and then Arg <= 9
              and then Item.Typed <= 99_999
            then
               Item.Typed := Item.Typed * 10 + Arg;
            end if;
         when Clear_Seed =>
            if Item.Where = New_Game then
               Item.Typed := Item.Typed / 10;
            end if;
         when Reroll_Region =>
            if Item.Where = Atlas and then Arg >= 1 then
               Item.Region := Arg;
               Result := Reroll;
            end if;
         when Open_New =>
            if Item.Where = Title or else Item.Where = Atlas then
               Item.Where := New_Game;
               Item.Cursor := 0;
            end if;
         when Open_Settings =>
            if Item.Where = Title then
               Item.Where := Settings;
               Item.Cursor := 0;
            end if;
         when Open_Credits =>
            if Item.Where = Title then
               Item.Where := Credits;
               Item.Cursor := 0;
            end if;
      end case;
      return Result;
   end Handle;

   procedure Arrive (Item : in out Card; Next : Screen) is
   begin
      Item.Where := Next;
      Item.Cursor := 0;
      if Next = Atlas or else Next = Field then
         Item.Under := Next;
      end if;
   end Arrive;

   procedure Note_Result
     (Item : in out Card;
      Ending : Natural;
      Dead : Natural;
      Funds_Before : Integer;
      Funds_After : Integer)
   is
   begin
      Item.Outcome := Ending;
      Item.Dead := Dead;
      Item.Before := Funds_Before;
      Item.After := Funds_After;
      Item.Loot := Funds_After - Funds_Before;
      Item.Where := Debrief;
      Item.Cursor := 0;
   end Note_Result;
end Megacorp.Menu;
