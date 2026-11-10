--  SPDX-License-Identifier: MIT
--  Copyright (c) 2026 Robert Boettcher

package body Megacorp.World is
   function Image (Item : Name) return String is
   begin
      return Item.Text (1 .. Item.Length);
   end Image;
end Megacorp.World;
