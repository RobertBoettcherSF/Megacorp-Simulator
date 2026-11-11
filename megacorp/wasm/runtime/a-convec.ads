--  SPDX-License-Identifier: MIT
--  Copyright (c) 2026 Robert Boettcher

--  A small definite vector for the wasm runtime. The native
--  build keeps the GNAT containers. This one is only copied
--  into the wasm runtime overlay.
with Ada.Finalization;

generic
   type Index_Type is range <>;
   type Element_Type is private;
package Ada.Containers.Vectors is
   type Vector is new Ada.Finalization.Controlled with private
     with Constant_Indexing => Element;

   function Element
     (Container : Vector;
      Index : Index_Type) return Element_Type;

   function Length (Container : Vector) return Count_Type;

   function Is_Empty (Container : Vector) return Boolean;

   function First_Index (Container : Vector) return Index_Type;

   function Last_Index (Container : Vector) return Index_Type'Base;

   procedure Append
     (Container : in out Vector;
      Item : Element_Type);

   procedure Clear (Container : in out Vector);

   procedure Reverse_Elements (Container : in out Vector);

   Empty_Vector : constant Vector;

private
   type Element_Array is array (Positive range <>) of Element_Type;
   type Element_Access is access Element_Array;

   type Vector is new Ada.Finalization.Controlled with record
      Data : Element_Access := null;
      Used : Natural := 0;
   end record;

   overriding procedure Adjust (Object : in out Vector);
   overriding procedure Finalize (Object : in out Vector);

   Empty_Vector : constant Vector :=
     (Ada.Finalization.Controlled with Data => null, Used => 0);
end Ada.Containers.Vectors;
