--  SPDX-License-Identifier: MIT
--  Copyright (c) 2026 Robert Boettcher

package body Megacorp.Research is
   function Cost (Item : Branch) return Positive is
   begin
      case Item is
         when SMG =>
            return 80;
         when Vest =>
            return 100;
         when Reflex =>
            return 120;
         when Rifle =>
            return 200;
         when Plate =>
            return 280;
      end case;
   end Cost;

   function Token (Item : Branch) return String is
   begin
      case Item is
         when SMG =>
            return "SMG";
         when Vest =>
            return "Vest";
         when Reflex =>
            return "Reflex";
         when Rifle =>
            return "Rifle";
         when Plate =>
            return "Plate";
      end case;
   end Token;

   function Ready
     (Item : Branch;
      Points : Natural;
      Have : Known) return Boolean
   is
   begin
      case Item is
         when SMG =>
            return Points >= Cost (SMG);
         when Vest =>
            return Points >= Cost (Vest);
         when Reflex =>
            return Points >= Cost (Reflex);
         when Rifle =>
            return Points >= Cost (Rifle) and then Have (SMG);
         when Plate =>
            return Points >= Cost (Plate) and then Have (Reflex);
      end case;
   end Ready;

   procedure Mark (Points : Natural; Have : in out Known) is
   begin
      for Item in Branch loop
         if Ready (Item, Points, Have) then
            Have (Item) := True;
         end if;
      end loop;
   end Mark;
end Megacorp.Research;
