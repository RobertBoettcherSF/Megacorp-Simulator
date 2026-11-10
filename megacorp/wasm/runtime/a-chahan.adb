--  SPDX-License-Identifier: MIT
--  Copyright (c) 2026 Robert Boettcher

package body Ada.Characters.Handling is
   function To_Upper (Item : Character) return Character is
   begin
      if Item in 'a' .. 'z' then
         return Character'Val
           (Character'Pos (Item)
            - Character'Pos ('a')
            + Character'Pos ('A'));
      end if;
      return Item;
   end To_Upper;
end Ada.Characters.Handling;
