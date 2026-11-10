--  SPDX-License-Identifier: MIT
--  Copyright (c) 2026 Robert Boettcher

package body Megacorp.Weapons is
   --  Reach is Chebyshev tiles. Rate is ticks from one shot to the
   --  next. Magazine is a full load.
   Table : constant array (Kind) of Stats :=
     (Pistol => (Reach => 8, Damage => 25, Rate => 4, Magazine => 12),
      SMG    => (Reach => 6, Damage => 10, Rate => 2, Magazine => 30),
      Rifle  => (Reach => 14, Damage => 40, Rate => 6, Magazine => 8));

   function Profile (Gun : Kind) return Stats is
   begin
      return Table (Gun);
   end Profile;

   function Token (Gun : Kind) return String is
   begin
      case Gun is
         when Pistol =>
            return "pistol";
         when SMG =>
            return "smg";
         when Rifle =>
            return "rifle";
      end case;
   end Token;
end Megacorp.Weapons;
