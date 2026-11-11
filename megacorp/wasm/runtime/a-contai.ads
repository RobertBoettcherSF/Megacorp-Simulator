--  SPDX-License-Identifier: MIT
--  Copyright (c) 2026 Robert Boettcher

--  The wasm runtime has no containers. The virtual file system
--  only needs an empty vector type.
package Ada.Containers is
   pragma Pure;
   type Count_Type is range 0 .. Natural'Last;
end Ada.Containers;
