--  SPDX-License-Identifier: MIT
--  Copyright (c) 2026 Robert Boettcher

--  Item 21. A user file is stored only after this check.
--  A tileset is JSON that names tile_width and tiles.
--  A sprite is a PNG, recognised by its first eight bytes.
package Megacorp.Assets.Import is
   function Accepts (Name : String; Data : String) return Boolean;
end Megacorp.Assets.Import;
