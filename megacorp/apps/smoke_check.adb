--  SPDX-License-Identifier: MIT
--  Copyright (c) 2026 Robert Boettcher

with Ada.Text_IO;

package body Smoke_Check is
   Failures : Natural := 0;

   procedure Expect (Condition : Boolean; Name : String) is
   begin
      if Condition then
         Ada.Text_IO.Put_Line ("PASS " & Name);
      else
         Ada.Text_IO.Put_Line ("FAIL " & Name);
         Failures := Failures + 1;
      end if;
   end Expect;

   procedure Discard (Value : Integer) is
      pragma Unreferenced (Value);
   begin
      null;
   end Discard;

   function Failure_Count return Natural is
   begin
      return Failures;
   end Failure_Count;
end Smoke_Check;
