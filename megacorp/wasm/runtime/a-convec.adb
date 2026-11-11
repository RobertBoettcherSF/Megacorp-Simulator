--  SPDX-License-Identifier: MIT
--  Copyright (c) 2026 Robert Boettcher

with Ada.Unchecked_Deallocation;

package body Ada.Containers.Vectors is
   procedure Free is new Ada.Unchecked_Deallocation
     (Element_Array, Element_Access);

   function Slot (Index : Index_Type) return Positive;
   procedure Grow (Object : in out Vector);

   function Slot (Index : Index_Type) return Positive is
   begin
      return Positive
        (Index_Type'Pos (Index)
         - Index_Type'Pos (Index_Type'First) + 1);
   end Slot;

   function Element
     (Container : Vector;
      Index : Index_Type) return Element_Type
   is
   begin
      return Container.Data (Slot (Index));
   end Element;

   function Length (Container : Vector) return Count_Type is
   begin
      return Count_Type (Container.Used);
   end Length;

   function Is_Empty (Container : Vector) return Boolean is
   begin
      return Container.Used = 0;
   end Is_Empty;

   function First_Index (Container : Vector) return Index_Type is
      pragma Unreferenced (Container);
   begin
      return Index_Type'First;
   end First_Index;

   function Last_Index (Container : Vector) return Index_Type'Base is
   begin
      if Container.Used = 0 then
         return Index_Type'Pos (Index_Type'First) - 1;
      end if;
      return Index_Type'Val
        (Index_Type'Pos (Index_Type'First) + Container.Used - 1);
   end Last_Index;

   procedure Grow (Object : in out Vector) is
      Next_Len : Positive;
      Next : Element_Access;
   begin
      if Object.Data = null then
         Next_Len := 8;
      else
         Next_Len := Object.Data'Length * 2;
      end if;
      Next := new Element_Array (1 .. Next_Len);
      if Object.Data /= null then
         Next (1 .. Object.Used) := Object.Data (1 .. Object.Used);
         Free (Object.Data);
      end if;
      Object.Data := Next;
   end Grow;

   procedure Append
     (Container : in out Vector;
      Item : Element_Type)
   is
   begin
      if Container.Data = null
        or else Container.Used = Container.Data'Length
      then
         Grow (Container);
      end if;
      Container.Used := Container.Used + 1;
      Container.Data (Container.Used) := Item;
   end Append;

   procedure Clear (Container : in out Vector) is
   begin
      Container.Used := 0;
   end Clear;

   procedure Reverse_Elements (Container : in out Vector) is
      Tmp : Element_Type;
   begin
      for I in 1 .. Container.Used / 2 loop
         Tmp := Container.Data (I);
         Container.Data (I) :=
           Container.Data (Container.Used - I + 1);
         Container.Data (Container.Used - I + 1) := Tmp;
      end loop;
   end Reverse_Elements;

   procedure Adjust (Object : in out Vector) is
      Old : constant Element_Access := Object.Data;
      Copy : Element_Access;
   begin
      if Old = null or else Object.Used = 0 then
         Object.Data := null;
         return;
      end if;
      Copy := new Element_Array (1 .. Old'Length);
      Copy (1 .. Object.Used) := Old (1 .. Object.Used);
      Object.Data := Copy;
   end Adjust;

   procedure Finalize (Object : in out Vector) is
   begin
      if Object.Data /= null then
         Free (Object.Data);
      end if;
   end Finalize;
end Ada.Containers.Vectors;
