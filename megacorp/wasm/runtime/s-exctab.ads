--  SPDX-License-Identifier: MIT
--  Copyright (c) 2026 Robert Boettcher

with System.Standard_Library;

--  The wasm runtime omits exception registration. A no-op lets
--  the save units declare Save_Error. Names are not looked up.
package System.Exception_Table is
   pragma Elaborate_Body;
   procedure Register_Exception
     (X : System.Standard_Library.Exception_Data_Ptr);
end System.Exception_Table;
