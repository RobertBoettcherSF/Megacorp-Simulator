--  SPDX-License-Identifier: MIT
--  Copyright (c) 2026 Robert Boettcher

package body System.Exception_Table is
   procedure Register_Exception
     (X : System.Standard_Library.Exception_Data_Ptr)
   is
      pragma Unreferenced (X);
   begin
      null;
   end Register_Exception;
end System.Exception_Table;
