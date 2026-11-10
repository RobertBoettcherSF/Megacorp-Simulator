--  SPDX-License-Identifier: MIT
--  Copyright (c) 2026 Robert Boettcher

--  Item 8. Placeholder weapons. The numbers are ours.
package Megacorp.Weapons is
   type Kind is (Pistol, SMG, Rifle);

   type Stats is record
      Reach     : Positive;
      Damage    : Positive;
      Rate      : Positive;
      Magazine  : Positive;
   end record;

   function Profile (Gun : Kind) return Stats;

   function Token (Gun : Kind) return String;
end Megacorp.Weapons;
