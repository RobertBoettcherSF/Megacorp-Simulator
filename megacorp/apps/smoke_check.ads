--  SPDX-License-Identifier: MIT
--  Copyright (c) 2026 Robert Boettcher

--  Tiny helper for the smoke test. Not part of the core.
package Smoke_Check is
   procedure Expect (Condition : Boolean; Name : String)
     with Pre => Name'Length > 0;

   procedure Discard (Value : Integer);

   function Failure_Count return Natural;
end Smoke_Check;
