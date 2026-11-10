--  SPDX-License-Identifier: MIT
--  Copyright (c) 2026 Robert Boettcher

with Ada.Real_Time;
with Ada.Text_IO;

package body Megacorp.Host is
   Epoch : constant Ada.Real_Time.Time := Ada.Real_Time.Clock;

   procedure Log (Level : Log_Level; Message : String) is
   begin
      Ada.Text_IO.Put_Line
        (Ada.Text_IO.Current_Error,
         "megacorp: " & Level'Image & ": " & Message);
   end Log;

   function Monotonic_Milliseconds return Milliseconds is
      use type Ada.Real_Time.Time;

      Elapsed : constant Duration :=
        Ada.Real_Time.To_Duration (Ada.Real_Time.Clock - Epoch);
      Scaled  : constant Duration := Elapsed * 1_000;
   begin
      if Scaled <= 0.0 then
         return 0;
      end if;
      return Milliseconds (Scaled);
   end Monotonic_Milliseconds;

end Megacorp.Host;
