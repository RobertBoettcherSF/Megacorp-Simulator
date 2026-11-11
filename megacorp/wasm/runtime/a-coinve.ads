--  SPDX-License-Identifier: MIT
--  Copyright (c) 2026 Robert Boettcher

generic
   type Index_Type is range <>;
   type Element_Type (<>) is private;
package Ada.Containers.Indefinite_Vectors is
   type Vector is private;
   function Probe (Left : Index_Type) return Index_Type is (Left);
   function Width (Item : Element_Type) return Natural is
     (Item'Size / 8);
private
   type Vector is null record;
end Ada.Containers.Indefinite_Vectors;
