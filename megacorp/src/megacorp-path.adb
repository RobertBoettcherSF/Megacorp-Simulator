--  SPDX-License-Identifier: MIT
--  Copyright (c) 2026 Robert Boettcher

with Ada.Unchecked_Deallocation;

package body Megacorp.Path is

   type Node_Info is record
      G       : Natural := Natural'Last;
      Parent  : Natural := 0;
      Closed  : Boolean := False;
      Heap_At : Natural := 0;
   end record;

   type Node_Array is array (Positive range <>) of Node_Info;
   type Heap_Array is array (Positive range <>) of Positive;
   type Node_Array_Access is access Node_Array;
   type Heap_Array_Access is access Heap_Array;

   procedure Free_Nodes is new Ada.Unchecked_Deallocation
     (Node_Array, Node_Array_Access);
   procedure Free_Heap is new Ada.Unchecked_Deallocation
     (Heap_Array, Heap_Array_Access);

   function Node_Id
     (Width, X, Y : Positive) return Positive;
   function Node_X (Width, Id : Positive) return Positive;
   function Node_Y (Width, Id : Positive) return Positive;
   function Octile (X1, Y1, X2, Y2 : Integer) return Natural;
   function Step_Cost (Dir : Map.Eight_Way) return Positive;
   function Is_Diagonal (Dir : Map.Eight_Way) return Boolean;
   function Passable
     (M : Map.City; X, Y : Integer; How : Mode) return Boolean;
   function Is_Blocked
     (Blocked : Block_Lists.Vector;
      From : Map.Point;
      X, Y : Integer) return Boolean;
   function Sides_Open
     (M : Map.City;
      X, Y : Positive;
      Dir : Map.Eight_Way;
      How : Mode;
      From : Map.Point;
      Blocked : Block_Lists.Vector) return Boolean;
   function Better
     (Nodes : Node_Array;
      Width, Goal_X, Goal_Y : Positive;
      Left, Right : Positive) return Boolean;
   procedure Swap_Heap
     (Heap : in out Heap_Array;
      Nodes : in out Node_Array;
      I, J : Positive);
   procedure Sift_Up
     (Heap : in out Heap_Array;
      Nodes : in out Node_Array;
      Width, Goal_X, Goal_Y : Positive;
      At_Index : Positive);
   procedure Sift_Down
     (Heap : in out Heap_Array;
      Nodes : in out Node_Array;
      Count : Natural;
      Width, Goal_X, Goal_Y : Positive;
      At_Index : Positive);
   procedure Push
     (Heap : in out Heap_Array;
      Nodes : in out Node_Array;
      Count : in out Natural;
      Width, Goal_X, Goal_Y : Positive;
      Node : Positive);
   procedure Pop_Min
     (Heap : in out Heap_Array;
      Nodes : in out Node_Array;
      Count : in out Natural;
      Width, Goal_X, Goal_Y : Positive;
      Node : out Positive);

   function Node_Id (Width, X, Y : Positive) return Positive is
   begin
      return (Y - 1) * Width + X;
   end Node_Id;

   function Node_X (Width, Id : Positive) return Positive is
   begin
      return ((Id - 1) mod Width) + 1;
   end Node_X;

   function Node_Y (Width, Id : Positive) return Positive is
   begin
      return ((Id - 1) / Width) + 1;
   end Node_Y;

   function Octile (X1, Y1, X2, Y2 : Integer) return Natural is
      DX     : constant Natural := abs (X1 - X2);
      DY     : constant Natural := abs (Y1 - Y2);
      Longer : constant Natural := Natural'Max (DX, DY);
      Short  : constant Natural := Natural'Min (DX, DY);
   begin
      return 10 * Longer + 4 * Short;
   end Octile;

   function Step_Cost (Dir : Map.Eight_Way) return Positive is
   begin
      if Is_Diagonal (Dir) then
         return 14;
      end if;
      return 10;
   end Step_Cost;

   function Is_Diagonal (Dir : Map.Eight_Way) return Boolean is
   begin
      return Dir in Map.North_East | Map.South_East
        | Map.South_West | Map.North_West;
   end Is_Diagonal;

   function Passable
     (M : Map.City; X, Y : Integer; How : Mode) return Boolean
   is
      Cell : Map.Tile;
   begin
      if not Map.In_Bounds (M, X, Y) then
         return False;
      end if;
      Cell := Map.Tile_At (M, X, Y);
      case How is
         when Walk =>
            return Cell.Walkable;
         when Drive =>
            return Cell.Drivable;
      end case;
   end Passable;

   function Is_Blocked
     (Blocked : Block_Lists.Vector;
      From : Map.Point;
      X, Y : Integer) return Boolean
   is
   begin
      if Blocked.Is_Empty then
         return False;
      end if;
      if X = From.X and then Y = From.Y then
         return False;
      end if;
      for I in Blocked.First_Index .. Blocked.Last_Index loop
         if Blocked (I).X = X and then Blocked (I).Y = Y then
            return True;
         end if;
      end loop;
      return False;
   end Is_Blocked;

   function Sides_Open
     (M : Map.City;
      X, Y : Positive;
      Dir : Map.Eight_Way;
      How : Mode;
      From : Map.Point;
      Blocked : Block_Lists.Vector) return Boolean
   is
   begin
      case Dir is
         when Map.North | Map.East | Map.South | Map.West =>
            return True;
         when Map.North_East =>
            return Passable (M, X, Y - 1, How)
              and then not Is_Blocked (Blocked, From, X, Y - 1)
              and then Passable (M, X + 1, Y, How)
              and then not Is_Blocked (Blocked, From, X + 1, Y);
         when Map.South_East =>
            return Passable (M, X, Y + 1, How)
              and then not Is_Blocked (Blocked, From, X, Y + 1)
              and then Passable (M, X + 1, Y, How)
              and then not Is_Blocked (Blocked, From, X + 1, Y);
         when Map.South_West =>
            return Passable (M, X, Y + 1, How)
              and then not Is_Blocked (Blocked, From, X, Y + 1)
              and then Passable (M, X - 1, Y, How)
              and then not Is_Blocked (Blocked, From, X - 1, Y);
         when Map.North_West =>
            return Passable (M, X, Y - 1, How)
              and then not Is_Blocked (Blocked, From, X, Y - 1)
              and then Passable (M, X - 1, Y, How)
              and then not Is_Blocked (Blocked, From, X - 1, Y);
      end case;
   end Sides_Open;

   function Better
     (Nodes : Node_Array;
      Width, Goal_X, Goal_Y : Positive;
      Left, Right : Positive) return Boolean
   is
      LX : constant Positive := Node_X (Width, Left);
      LY : constant Positive := Node_Y (Width, Left);
      RX : constant Positive := Node_X (Width, Right);
      RY : constant Positive := Node_Y (Width, Right);
      LH : constant Natural := Octile (LX, LY, Goal_X, Goal_Y);
      RH : constant Natural := Octile (RX, RY, Goal_X, Goal_Y);
      LF : constant Natural := Nodes (Left).G + LH;
      RF : constant Natural := Nodes (Right).G + RH;
   begin
      if LF /= RF then
         return LF < RF;
      elsif LH /= RH then
         return LH < RH;
      elsif LY /= RY then
         return LY < RY;
      else
         return LX < RX;
      end if;
   end Better;

   procedure Swap_Heap
     (Heap : in out Heap_Array;
      Nodes : in out Node_Array;
      I, J : Positive)
   is
      Tmp : constant Positive := Heap (I);
   begin
      Heap (I) := Heap (J);
      Heap (J) := Tmp;
      Nodes (Heap (I)).Heap_At := I;
      Nodes (Heap (J)).Heap_At := J;
   end Swap_Heap;

   procedure Sift_Up
     (Heap : in out Heap_Array;
      Nodes : in out Node_Array;
      Width, Goal_X, Goal_Y : Positive;
      At_Index : Positive)
   is
      Index  : Positive := At_Index;
      Parent : Positive;
   begin
      while Index > 1 loop
         Parent := Index / 2;
         exit when not Better
           (Nodes, Width, Goal_X, Goal_Y, Heap (Index), Heap (Parent));
         Swap_Heap (Heap, Nodes, Index, Parent);
         Index := Parent;
      end loop;
   end Sift_Up;

   procedure Sift_Down
     (Heap : in out Heap_Array;
      Nodes : in out Node_Array;
      Count : Natural;
      Width, Goal_X, Goal_Y : Positive;
      At_Index : Positive)
   is
      Index : Positive := At_Index;
      Left  : Positive;
      Right : Positive;
      Best  : Positive;
   begin
      loop
         Left := Index * 2;
         Right := Left + 1;
         Best := Index;
         if Left <= Count
           and then Better
             (Nodes, Width, Goal_X, Goal_Y, Heap (Left), Heap (Best))
         then
            Best := Left;
         end if;
         if Right <= Count
           and then Better
             (Nodes, Width, Goal_X, Goal_Y, Heap (Right), Heap (Best))
         then
            Best := Right;
         end if;
         exit when Best = Index;
         Swap_Heap (Heap, Nodes, Index, Best);
         Index := Best;
      end loop;
   end Sift_Down;

   procedure Push
     (Heap : in out Heap_Array;
      Nodes : in out Node_Array;
      Count : in out Natural;
      Width, Goal_X, Goal_Y : Positive;
      Node : Positive)
   is
   begin
      Count := Count + 1;
      Heap (Count) := Node;
      Nodes (Node).Heap_At := Count;
      Sift_Up (Heap, Nodes, Width, Goal_X, Goal_Y, Count);
   end Push;

   procedure Pop_Min
     (Heap : in out Heap_Array;
      Nodes : in out Node_Array;
      Count : in out Natural;
      Width, Goal_X, Goal_Y : Positive;
      Node : out Positive)
   is
   begin
      Node := Heap (1);
      Nodes (Node).Heap_At := 0;
      Nodes (Node).Closed := True;
      Heap (1) := Heap (Count);
      Count := Count - 1;
      if Count > 0 then
         Nodes (Heap (1)).Heap_At := 1;
         Sift_Down
           (Heap, Nodes, Count, Width, Goal_X, Goal_Y, 1);
      end if;
   end Pop_Min;

   function Kind (Route : Result) return Status is
   begin
      return Route.Kind;
   end Kind;

   function Length (Route : Result) return Natural is
   begin
      return Natural (Route.Steps.Length);
   end Length;

   function Step
     (Route : Result; Index : Positive) return Map.Point
   is
   begin
      return Route.Steps (Index);
   end Step;

   function Steps_Fit
     (M : Map.City;
      From, To : Map.Point;
      Route : Result) return Boolean
   is
      DX : Natural;
      DY : Natural;
      Here : Map.Point;
      Prev : Map.Point;
   begin
      if Route.Kind /= Found then
         return True;
      end if;
      if Route.Steps (1) /= From
        or else Route.Steps (Route.Steps.Last_Index) /= To
      then
         return False;
      end if;
      for I in Route.Steps.First_Index .. Route.Steps.Last_Index loop
         Here := Route.Steps (I);
         if not Map.In_Bounds (M, Here.X, Here.Y) then
            return False;
         end if;
         if I > Route.Steps.First_Index then
            Prev := Route.Steps (I - 1);
            DX := abs (Here.X - Prev.X);
            DY := abs (Here.Y - Prev.Y);
            if DX > 1 or else DY > 1 or else (DX = 0 and then DY = 0)
            then
               return False;
            end if;
         end if;
      end loop;
      return True;
   end Steps_Fit;

   function Find
     (M : Map.City;
      From, To : Map.Point;
      How : Mode;
      Budget : Positive;
      Blocked : Block_Lists.Vector) return Result
   is
      Width  : constant Positive := M.Width;
      Height : constant Positive := M.Height;
      Total  : constant Positive := Width * Height;
      Nodes  : Node_Array_Access := new Node_Array (1 .. Total);
      Heap   : Heap_Array_Access := new Heap_Array (1 .. Total);
      Count  : Natural := 0;
      Start  : constant Positive := Node_Id (Width, From.X, From.Y);
      Goal   : constant Positive := Node_Id (Width, To.X, To.Y);
      Expanded : Natural := 0;
      Answer   : Result;
   begin
      if From = To then
         Answer.Kind := Found;
         Answer.Steps.Append (From);
         Free_Nodes (Nodes);
         Free_Heap (Heap);
         return Answer;
      end if;
      if not Passable (M, From.X, From.Y, How)
        or else not Passable (M, To.X, To.Y, How)
        or else Is_Blocked (Blocked, From, To.X, To.Y)
      then
         Free_Nodes (Nodes);
         Free_Heap (Heap);
         return Answer;
      end if;
      Nodes (Start).G := 0;
      Push (Heap.all, Nodes.all, Count, Width, To.X, To.Y, Start);
      while Count > 0 and then Answer.Kind = No_Path loop
         declare
            Current : Positive;
            CX      : Positive;
            CY      : Positive;
         begin
            Pop_Min
              (Heap.all, Nodes.all, Count, Width, To.X, To.Y, Current);
            CX := Node_X (Width, Current);
            CY := Node_Y (Width, Current);
            Expanded := Expanded + 1;
            if Expanded > Budget then
               Answer.Kind := Budget_Exceeded;
            elsif Current = Goal then
               declare
                  Cursor : Natural := Current;
               begin
                  while Cursor /= 0 loop
                     Answer.Steps.Append
                       ((X => Node_X (Width, Positive (Cursor)),
                         Y => Node_Y (Width, Positive (Cursor))));
                     if Nodes (Positive (Cursor)).Parent = 0 then
                        Cursor := 0;
                     else
                        Cursor := Nodes (Positive (Cursor)).Parent;
                     end if;
                  end loop;
                  Answer.Steps.Reverse_Elements;
                  Answer.Kind := Found;
               end;
            else
               for Dir in Map.Eight_Way loop
                  if Map.Has_Neighbour_8 (M, CX, CY, Dir) then
                     declare
                        Next : constant Map.Point :=
                          Map.Neighbour_8 (M, CX, CY, Dir);
                        Nid  : constant Positive :=
                          Node_Id (Width, Next.X, Next.Y);
                        Tentative : Natural;
                     begin
                        if not Nodes (Nid).Closed
                          and then Passable (M, Next.X, Next.Y, How)
                          and then not Is_Blocked
                            (Blocked, From, Next.X, Next.Y)
                          and then Sides_Open
                            (M, CX, CY, Dir, How, From, Blocked)
                        then
                           Tentative :=
                             Nodes (Current).G + Step_Cost (Dir);
                           if Tentative < Nodes (Nid).G then
                              Nodes (Nid).G := Tentative;
                              Nodes (Nid).Parent := Current;
                              if Nodes (Nid).Heap_At = 0 then
                                 Push
                                   (Heap.all, Nodes.all, Count,
                                    Width, To.X, To.Y, Nid);
                              else
                                 Sift_Up
                                   (Heap.all, Nodes.all, Width,
                                    To.X, To.Y, Nodes (Nid).Heap_At);
                              end if;
                           end if;
                        end if;
                     end;
                  end if;
               end loop;
            end if;
         end;
      end loop;
      Free_Nodes (Nodes);
      Free_Heap (Heap);
      return Answer;
   exception
      when others =>
         Free_Nodes (Nodes);
         Free_Heap (Heap);
         raise;
   end Find;

end Megacorp.Path;
