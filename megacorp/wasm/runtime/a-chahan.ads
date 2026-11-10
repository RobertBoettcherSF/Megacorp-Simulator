--  SPDX-License-Identifier: MIT
--  Copyright (c) 2026 Robert Boettcher

--  The wasm runtime we link does not ship Ada.Characters.Handling.
--  The world generator only needs To_Upper of one letter.
package Ada.Characters.Handling is
   pragma Pure;
   function To_Upper (Item : Character) return Character;
end Ada.Characters.Handling;
