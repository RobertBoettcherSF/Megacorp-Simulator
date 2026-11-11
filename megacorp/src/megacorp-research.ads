--  SPDX-License-Identifier: MIT
--  Copyright (c) 2026 Robert Boettcher

--  Item 25. A short tree paid for with the v2 research total.
--  Points are not spent. A node opens when the total is high
--  enough and its predecessor, if it has one, is already open.
package Megacorp.Research is
   type Branch is (SMG, Vest, Reflex, Rifle, Plate);

   type Known is array (Branch) of Boolean;

   function Cost (Item : Branch) return Positive;

   function Token (Item : Branch) return String;

   function Ready
     (Item : Branch;
      Points : Natural;
      Have : Known) return Boolean;

   procedure Mark (Points : Natural; Have : in out Known)
     with Post =>
       (for all Item in Branch =>
          (if Have'Old (Item) then Have (Item)));
end Megacorp.Research;
