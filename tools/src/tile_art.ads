--  SPDX-License-Identifier: MIT
--  Copyright (c) 2026 Robert Boettcher

--  Draw the placeholder isometric tileset and write it to disk.
package Tile_Art is
   procedure Write (Directory : String)
     with Pre => Directory'Length > 0;
end Tile_Art;
