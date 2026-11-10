--  SPDX-License-Identifier: MIT
--  Copyright (c) 2026 Robert Boettcher

with Ada.Containers.Vectors;

package body Megacorp.Map.Gen is
   type Side is (North, East, South, West);

   type Frame is record
      Core_X : Positive := 1;
      Core_Y : Positive := 1;
      Half_X : Natural := 1;
      Half_Y : Natural := 1;
      Ind    : Side := North;
      Slum   : Side := South;
      Ind_N  : Natural := 1;
      Slum_N : Natural := 1;
   end record;

   Max_Lines : constant := 64;

   type Line_List is array (1 .. Max_Lines) of Positive;

   procedure Read_Frame
     (G : in out RNG.Generator;
      Width, Height : Positive;
      Plan : out Frame);
   function Classify
     (Plan : Frame; Width, Height, X, Y : Positive) return District;
   function Opposite (Which : Side) return Side;
   function On_Strip
     (Which : Side;
      X, Y, Width, Height, Thick : Natural) return Boolean;
   procedure Paint
     (M : in out City; X, Y : Positive; Kind : Terrain; Level : Height_Level);
   procedure Lay_River (M : in out City; G : in out RNG.Generator);
   procedure Lay_Lake (M : in out City; G : in out RNG.Generator);
   procedure Collect
     (G : in out RNG.Generator;
      Limit : Positive;
      Lines : out Line_List;
      Count : out Natural);
   procedure Lay_Roads
     (M : in out City;
      Xs : Line_List;
      Xn : Natural;
      Ys : Line_List;
      Yn : Natural);
   function Beside_Road (M : City; X, Y : Positive) return Boolean;
   procedure Lay_Pavement (M : in out City);
   procedure Fill_Blocks
     (M : in out City;
      G : in out RNG.Generator;
      From : RNG.Word;
      Xs : Line_List;
      Xn : Natural;
      Ys : Line_List;
      Yn : Natural);
   function Linked
     (M : City; Drivable_Only : Boolean) return Boolean;

   function Min_Storey (Which : District) return Height_Level is
   begin
      case Which is
         when Corporate =>
            return 9;
         when Residential =>
            return 3;
         when Industrial =>
            return 2;
         when Slums =>
            return 1;
      end case;
   end Min_Storey;

   function Max_Storey (Which : District) return Height_Level is
   begin
      case Which is
         when Corporate =>
            return 14;
         when Residential =>
            return 6;
         when Industrial =>
            return 4;
         when Slums =>
            return 3;
      end case;
   end Max_Storey;

   function Opposite (Which : Side) return Side is
   begin
      case Which is
         when North =>
            return South;
         when East =>
            return West;
         when South =>
            return North;
         when West =>
            return East;
      end case;
   end Opposite;

   function On_Strip
     (Which : Side;
      X, Y, Width, Height, Thick : Natural) return Boolean
   is
   begin
      case Which is
         when North =>
            return Y <= Thick;
         when South =>
            return Y > Height - Thick;
         when West =>
            return X <= Thick;
         when East =>
            return X > Width - Thick;
      end case;
   end On_Strip;

   procedure Read_Frame
     (G : in out RNG.Generator;
      Width, Height : Positive;
      Plan : out Frame)
   is
      Low_X : constant Integer := Integer'Max (1, Width / 3);
      High_X : constant Integer := Integer'Max (Low_X, (2 * Width) / 3);
      Low_Y : constant Integer := Integer'Max (1, Height / 3);
      High_Y : constant Integer := Integer'Max (Low_Y, (2 * Height) / 3);
      Side_N : Integer;
   begin
      Plan.Core_X := RNG.Pick (G, Low_X, High_X);
      Plan.Core_Y := RNG.Pick (G, Low_Y, High_Y);
      Plan.Half_X := Natural'Max (1, Width / 6);
      Plan.Half_Y := Natural'Max (1, Height / 6);
      Side_N := RNG.Pick (G, 0, 3);
      Plan.Ind := Side'Val (Side_N);
      Plan.Slum := Opposite (Plan.Ind);
      if Plan.Ind in North | South then
         Plan.Ind_N := Natural'Max (2, Height / 5);
      else
         Plan.Ind_N := Natural'Max (2, Width / 5);
      end if;
      if Plan.Slum in North | South then
         Plan.Slum_N := Natural'Max (2, Height / 6);
      else
         Plan.Slum_N := Natural'Max (2, Width / 6);
      end if;
   end Read_Frame;

   function Classify
     (Plan : Frame; Width, Height, X, Y : Positive) return District
   is
   begin
      if abs (X - Plan.Core_X) <= Plan.Half_X
        and then abs (Y - Plan.Core_Y) <= Plan.Half_Y
      then
         return Corporate;
      elsif On_Strip
        (Plan.Ind, X, Y, Width, Height, Plan.Ind_N)
      then
         return Industrial;
      elsif On_Strip
        (Plan.Slum, X, Y, Width, Height, Plan.Slum_N)
      then
         return Slums;
      else
         return Residential;
      end if;
   end Classify;

   function District_At
     (From : RNG.Word;
      Width, Height : Positive;
      X, Y : Positive) return District
   is
      Stream : RNG.Generator :=
        RNG.Child (RNG.Make (From), RNG.City, 1);
      Plan : Frame;
   begin
      Read_Frame (Stream, Width, Height, Plan);
      return Classify (Plan, Width, Height, X, Y);
   end District_At;

   procedure Paint
     (M : in out City; X, Y : Positive; Kind : Terrain; Level : Height_Level)
   is
      Cell : Tile;
   begin
      Cell.Kind := Kind;
      Cell.Level := Level;
      Cell.Walkable := Kind in Open_Ground | Road | Pavement;
      Cell.Drivable := Kind = Road;
      Set_Tile (M, X, Y, Cell);
   end Paint;

   procedure Lay_River (M : in out City; G : in out RNG.Generator) is
      Base : Integer;
      Thick : Integer;
      Center : Integer;
      Shift : Integer;
      Top : Integer;
      Bottom : Integer;
   begin
      if M.Height < 8 then
         return;
      end if;
      Base := RNG.Pick (G, M.Height / 3, (2 * M.Height) / 3);
      Thick := RNG.Pick (G, 2, 3);
      Center := Base;
      for X in 1 .. M.Width loop
         Shift := RNG.Pick (G, -1, 1);
         if Center + Shift < Thick then
            Center := Thick;
         elsif Center + Shift > M.Height - Thick then
            Center := M.Height - Thick;
         else
            Center := Center + Shift;
         end if;
         Top := Center - (Thick / 2);
         Bottom := Top + Thick - 1;
         for Y in Top .. Bottom loop
            if Y in 1 .. M.Height then
               Paint (M, X, Y, Water, 0);
            end if;
         end loop;
      end loop;
   end Lay_River;

   procedure Lay_Lake (M : in out City; G : in out RNG.Generator) is
      Cx : Integer;
      Cy : Integer;
      Radius : Integer;
   begin
      if M.Width < 16 or else M.Height < 16 then
         return;
      end if;
      Cx := RNG.Pick (G, M.Width / 4, (3 * M.Width) / 4);
      Cy := RNG.Pick (G, M.Height / 4, (3 * M.Height) / 4);
      Radius := RNG.Pick (G, 3, 5);
      for Y in Cy - Radius .. Cy + Radius loop
         for X in Cx - Radius .. Cx + Radius loop
            if X in 1 .. M.Width
              and then Y in 1 .. M.Height
              and then abs (X - Cx) + abs (Y - Cy) <= Radius
              and then Tile_At (M, X, Y).Kind /= Road
            then
               Paint (M, X, Y, Water, 0);
            end if;
         end loop;
      end loop;
   end Lay_Lake;

   procedure Collect
     (G : in out RNG.Generator;
      Limit : Positive;
      Lines : out Line_List;
      Count : out Natural)
   is
      Cursor : Integer := 1;
      Gap : Integer;
      Next : Integer;
   begin
      Lines := (others => 1);
      Count := 1;
      Lines (1) := 1;
      if Limit < 16 then
         if Limit /= 1 then
            Count := 2;
            Lines (2) := Limit;
         end if;
         return;
      end if;
      while Cursor + 7 < Limit and then Count < Max_Lines - 1 loop
         Gap := RNG.Pick (G, 7, 13);
         Next := Cursor + Gap;
         exit when Next >= Limit;
         Count := Count + 1;
         Lines (Count) := Next;
         Cursor := Next;
      end loop;
      if Lines (Count) /= Limit then
         Count := Count + 1;
         Lines (Count) := Limit;
      end if;
   end Collect;

   procedure Lay_Roads
     (M : in out City;
      Xs : Line_List;
      Xn : Natural;
      Ys : Line_List;
      Yn : Natural)
   is
   begin
      for I in 1 .. Xn loop
         for Y in 1 .. M.Height loop
            Paint (M, Xs (I), Y, Road, 1);
         end loop;
      end loop;
      for I in 1 .. Yn loop
         for X in 1 .. M.Width loop
            Paint (M, X, Ys (I), Road, 1);
         end loop;
      end loop;
   end Lay_Roads;

   function Beside_Road (M : City; X, Y : Positive) return Boolean is
   begin
      for Dir in Four_Way loop
         if Has_Neighbour_4 (M, X, Y, Dir) then
            declare
               Next : constant Point := Neighbour_4 (M, X, Y, Dir);
            begin
               if Tile_At (M, Next.X, Next.Y).Kind = Road then
                  return True;
               end if;
            end;
         end if;
      end loop;
      return False;
   end Beside_Road;

   procedure Lay_Pavement (M : in out City) is
   begin
      for Y in 1 .. M.Height loop
         for X in 1 .. M.Width loop
            if Tile_At (M, X, Y).Kind = Open_Ground
              and then Beside_Road (M, X, Y)
            then
               Paint (M, X, Y, Pavement, 1);
            end if;
         end loop;
      end loop;
   end Lay_Pavement;

   procedure Fill_Blocks
     (M : in out City;
      G : in out RNG.Generator;
      From : RNG.Word;
      Xs : Line_List;
      Xn : Natural;
      Ys : Line_List;
      Yn : Natural)
   is
      Zone : District;
      Park : Boolean;
      Storey : Height_Level;
      Door_X : Positive;
      Door_Y : Positive;
   begin
      for Iy in 1 .. Yn - 1 loop
         for Ix in 1 .. Xn - 1 loop
            declare
               Left : constant Integer := Xs (Ix);
               Right : constant Integer := Xs (Ix + 1);
               Top : constant Integer := Ys (Iy);
               Bottom : constant Integer := Ys (Iy + 1);
            begin
               if Right > Left + 2 and then Bottom > Top + 2 then
                  Zone := District_At
                    (From, M.Width, M.Height,
                     (Left + Right) / 2, (Top + Bottom) / 2);
                  if Zone = Residential then
                     Park := RNG.Chance (G, 1, 4);
                  else
                     Park := RNG.Chance (G, 1, 10);
                  end if;
                  if not Park then
                     for Y in Top + 1 .. Bottom - 1 loop
                        for X in Left + 1 .. Right - 1 loop
                           if Tile_At (M, X, Y).Kind = Open_Ground then
                              Zone := District_At
                                (From, M.Width, M.Height, X, Y);
                              Storey := Height_Level
                                (RNG.Pick
                                   (G,
                                    Integer (Min_Storey (Zone)),
                                    Integer (Max_Storey (Zone))));
                              Paint (M, X, Y, Building, Storey);
                           end if;
                        end loop;
                     end loop;
                     Door_X := (Left + Right) / 2;
                     Door_Y := Bottom - 2;
                     if Door_Y > Top
                       and then Door_Y < M.Height
                       and then Door_X > Left
                       and then Door_X < Right
                       and then Tile_At (M, Door_X, Door_Y).Kind
                         = Building
                       and then Tile_At (M, Door_X, Door_Y + 1).Walkable
                     then
                        Paint (M, Door_X, Door_Y, Pavement, 1);
                     end if;
                  end if;
               end if;
            end;
         end loop;
      end loop;
   end Fill_Blocks;

   function Linked
     (M : City; Drivable_Only : Boolean) return Boolean
   is
      type Mark is array (Positive range <>, Positive range <>) of Boolean;
      Seen : Mark (1 .. M.Width, 1 .. M.Height) :=
        (others => (others => False));
      package Queues is new Ada.Containers.Vectors
        (Index_Type => Positive, Element_Type => Point);
      Queue : Queues.Vector;
      Total : Natural := 0;
      Reach : Natural := 0;
      Start : Point := (X => 1, Y => 1);
      Found : Boolean := False;
      Head : Natural := 1;

      function Pass (X, Y : Positive) return Boolean;
      function Pass (X, Y : Positive) return Boolean is
         Cell : constant Tile := Tile_At (M, X, Y);
      begin
         if Drivable_Only then
            return Cell.Drivable;
         end if;
         return Cell.Walkable;
      end Pass;
   begin
      for Y in 1 .. M.Height loop
         for X in 1 .. M.Width loop
            if Pass (X, Y) then
               Total := Total + 1;
               if not Found then
                  Start := (X => X, Y => Y);
                  Found := True;
               end if;
            end if;
         end loop;
      end loop;
      if Total = 0 then
         return True;
      end if;
      Queue.Append (Start);
      Seen (Start.X, Start.Y) := True;
      Reach := 1;
      while Head <= Reach loop
         declare
            Here : constant Point := Queue (Head);
            Next : Point;
         begin
            Head := Head + 1;
            for Dir in Four_Way loop
               if Has_Neighbour_4 (M, Here.X, Here.Y, Dir) then
                  Next := Neighbour_4 (M, Here.X, Here.Y, Dir);
                  if Pass (Next.X, Next.Y)
                    and then not Seen (Next.X, Next.Y)
                  then
                     Seen (Next.X, Next.Y) := True;
                     Queue.Append (Next);
                     Reach := Reach + 1;
                  end if;
               end if;
            end loop;
         end;
      end loop;
      return Reach = Total;
   end Linked;

   function Roads_Connected (M : City) return Boolean is
   begin
      return Linked (M, True);
   end Roads_Connected;

   function Foot_Connected (M : City) return Boolean is
   begin
      return Linked (M, False);
   end Foot_Connected;

   function Generate
     (From : RNG.Word; Width, Height : Positive) return City
   is
      Result : City (Width, Height);
      Stream : RNG.Generator :=
        RNG.Child (RNG.Make (From), RNG.City, 1);
      Plan : Frame;
      Xs : Line_List;
      Ys : Line_List;
      Xn : Natural;
      Yn : Natural;
   begin
      Result.From_Seed := From;
      for Y in 1 .. Height loop
         for X in 1 .. Width loop
            Paint (Result, X, Y, Open_Ground, 1);
         end loop;
      end loop;
      if Width >= 8 and then Height >= 8 then
         Read_Frame (Stream, Width, Height, Plan);
         Lay_River (Result, Stream);
         Lay_Lake (Result, Stream);
         Collect (Stream, Width, Xs, Xn);
         Collect (Stream, Height, Ys, Yn);
         Lay_Roads (Result, Xs, Xn, Ys, Yn);
         Lay_Pavement (Result);
         Fill_Blocks (Result, Stream, From, Xs, Xn, Ys, Yn);
      end if;
      return Result;
   end Generate;

   function Generate
     (From : RNG.Word;
      Size : Parameters.Generator_Parameters) return City
   is
   begin
      return Generate
        (From,
         Parameters.City_Map_Width (Size),
         Parameters.City_Map_Height (Size));
   end Generate;

end Megacorp.Map.Gen;
