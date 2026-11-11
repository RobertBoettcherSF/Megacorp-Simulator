--  SPDX-License-Identifier: MIT
--  Copyright (c) 2026 Robert Boettcher

package body Ada.Directories is
   function Exists (Name : String) return Boolean is
      pragma Unreferenced (Name);
   begin
      return False;
   end Exists;
end Ada.Directories;
