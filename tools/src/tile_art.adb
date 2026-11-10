--  SPDX-License-Identifier: MIT
--  Copyright (c) 2026 Robert Boettcher

with Ada.Directories;
with Ada.Streams.Stream_IO;
with Ada.Text_IO;
with Interfaces;
with Interfaces.C;
with System;

package body Tile_Art is
   use type Interfaces.C.int;
   use type Interfaces.Unsigned_32;
   type Byte is mod 256;
   type Byte_Array is array (Natural range <>) of Byte;
   type Byte_Ref is access Byte_Array;

   subtype U32 is Interfaces.Unsigned_32;

   Tile_Width     : constant := 32;
   Diamond_Height : constant := 16;
   Level_Px       : constant := 4;
   Max_Level      : constant := 15;
   Cell_Height    : constant := Diamond_Height + Max_Level * Level_Px;
   Columns        : constant := 16;
   Terrains       : constant := 5;

   type Terrain_Name is (Open, Road, Pavement, Building, Water);

   type Rgb is record
      R : Long_Float;
      G : Long_Float;
      B : Long_Float;
   end record;

   Base : constant array (Terrain_Name) of Rgb :=
     (Open => (98.0, 142.0, 90.0),
      Road => (68.0, 68.0, 74.0),
      Pavement => (176.0, 168.0, 152.0),
      Building => (156.0, 84.0, 60.0),
      Water => (46.0, 118.0, 168.0));

   type Vertex is record
      X : Long_Float;
      Y : Long_Float;
   end record;

   type Quad is array (1 .. 4) of Vertex;

   function Compress2
     (Dest : System.Address;
      Dest_Len : access Interfaces.C.unsigned_long;
      Source : System.Address;
      Source_Len : Interfaces.C.unsigned_long;
      Level : Interfaces.C.int) return Interfaces.C.int
     with Import, Convention => C, External_Name => "compress2";

   function Py_Round (Value : Long_Float) return Integer;
   function Channel (Value, Factor : Long_Float) return Byte;
   function Crc32 (Data : Byte_Array) return U32;
   procedure Put_U32 (Into : in out Byte_Array; Place : Natural; Value : U32);
   procedure Fill
     (Cell : in out Byte_Array;
      Points : Quad;
      Count : Positive;
      Red, Green, Blue, Alpha : Byte);
   function Diamond (Center_X, South_Y : Long_Float) return Quad;
   procedure Paint
     (Pixels : in out Byte_Array;
      Atlas_W : Natural;
      Column, Row : Natural;
      Which : Terrain_Name;
      Level : Natural);
   procedure Write_Png
     (Path : String; Width, Height : Natural; Pixels : Byte_Array);
   procedure Write_Index (Path : String);
   procedure Write_Licence (Path : String);
   function Name_Of (Which : Terrain_Name) return String;
   function Trim (Image : String) return String;

   function Py_Round (Value : Long_Float) return Integer is
      Negative : constant Boolean := Value < 0.0;
      Magnitude : constant Long_Float := abs Value;
      Base_Value : constant Long_Float := Long_Float'Floor (Magnitude);
      Fraction : constant Long_Float := Magnitude - Base_Value;
      Whole : Integer := Integer (Base_Value);
   begin
      if Fraction > 0.5
        or else (Fraction = 0.5 and then Whole mod 2 /= 0)
      then
         Whole := Whole + 1;
      end if;
      if Negative then
         return -Whole;
      end if;
      return Whole;
   end Py_Round;

   function Channel (Value, Factor : Long_Float) return Byte is
      Scaled : constant Long_Float := Value * Factor;
      Cut : Integer;
   begin
      if Scaled <= 0.0 then
         return 0;
      end if;
      Cut := Integer (Long_Float'Floor (Scaled));
      if Cut > 255 then
         return 255;
      end if;
      return Byte (Cut);
   end Channel;

   function Crc32 (Data : Byte_Array) return U32 is
      Crc : U32 := 16#FFFF_FFFF#;
      Bit : U32;
   begin
      for I in Data'Range loop
         Crc := Crc xor U32 (Data (I));
         for Unused in 1 .. 8 loop
            Bit := Crc and 1;
            Crc := Interfaces.Shift_Right (Crc, 1);
            if Bit = 1 then
               Crc := Crc xor 16#EDB8_8320#;
            end if;
         end loop;
      end loop;
      return Crc xor 16#FFFF_FFFF#;
   end Crc32;

   procedure Put_U32
     (Into : in out Byte_Array; Place : Natural; Value : U32)
   is
   begin
      Into (Place) := Byte (Interfaces.Shift_Right (Value, 24) and 16#FF#);
      Into (Place + 1) :=
        Byte (Interfaces.Shift_Right (Value, 16) and 16#FF#);
      Into (Place + 2) :=
        Byte (Interfaces.Shift_Right (Value, 8) and 16#FF#);
      Into (Place + 3) := Byte (Value and 16#FF#);
   end Put_U32;

   procedure Fill
     (Cell : in out Byte_Array;
      Points : Quad;
      Count : Positive;
      Red, Green, Blue, Alpha : Byte)
   is
      Width : constant Natural := Tile_Width;
      Height : constant Natural := Cell_Height;
      Low_Y : Long_Float := Points (1).Y;
      High_Y : Long_Float := Points (1).Y;
      Y0 : Integer;
      Y1 : Integer;
      Cross : array (1 .. 8) of Long_Float;
      Used : Natural;
      Left : Integer;
      Right : Integer;
      Tmp : Long_Float;
      X1 : Long_Float;
      Y_A : Long_Float;
      X2 : Long_Float;
      Y_B : Long_Float;
      Low : Long_Float;
      High : Long_Float;
      Scan : Long_Float;
      Place : Natural;
   begin
      for I in 1 .. Count loop
         if Points (I).Y < Low_Y then
            Low_Y := Points (I).Y;
         end if;
         if Points (I).Y > High_Y then
            High_Y := Points (I).Y;
         end if;
      end loop;
      Y0 := Integer (Long_Float'Floor (Low_Y));
      Y1 := Integer (Long_Float'Floor (High_Y));
      if Y0 < 0 then
         Y0 := 0;
      end if;
      if Y1 > Height - 1 then
         Y1 := Height - 1;
      end if;
      for Y in Y0 .. Y1 loop
         Used := 0;
         Scan := Long_Float (Y);
         for Index in 1 .. Count loop
            X1 := Points (Index).X;
            Y_A := Points (Index).Y;
            if Index = Count then
               X2 := Points (1).X;
               Y_B := Points (1).Y;
            else
               X2 := Points (Index + 1).X;
               Y_B := Points (Index + 1).Y;
            end if;
            if Y_A /= Y_B then
               if Y_A < Y_B then
                  Low := Y_A;
                  High := Y_B;
               else
                  Low := Y_B;
                  High := Y_A;
               end if;
               if Scan >= Low and then Scan < High then
                  Used := Used + 1;
                  Cross (Used) :=
                    X1 + (Scan - Y_A) * (X2 - X1) / (Y_B - Y_A);
               end if;
            end if;
         end loop;
         for I in 2 .. Used loop
            Tmp := Cross (I);
            declare
               J : Natural := I;
            begin
               while J > 1 and then Cross (J - 1) > Tmp loop
                  Cross (J) := Cross (J - 1);
                  J := J - 1;
               end loop;
               Cross (J) := Tmp;
            end;
         end loop;
         declare
            Pair : Natural := 1;
         begin
            while Pair + 1 <= Used loop
               Left := Py_Round (Cross (Pair));
               Right := Py_Round (Cross (Pair + 1));
               if Left > Right then
                  declare
                     Swap : constant Integer := Left;
                  begin
                     Left := Right;
                     Right := Swap;
                  end;
               end if;
               if Left < 0 then
                  Left := 0;
               end if;
               if Right >= Width then
                  Right := Width - 1;
               end if;
               for X in Left .. Right loop
                  Place := (Y * Width + X) * 4;
                  Cell (Place) := Red;
                  Cell (Place + 1) := Green;
                  Cell (Place + 2) := Blue;
                  Cell (Place + 3) := Alpha;
               end loop;
               Pair := Pair + 2;
            end loop;
         end;
      end loop;
   end Fill;

   function Diamond (Center_X, South_Y : Long_Float) return Quad is
      Half_W : constant Long_Float := Long_Float (Tile_Width / 2);
      Half_H : constant Long_Float := Long_Float (Diamond_Height / 2);
   begin
      return
        ((Center_X, South_Y),
         (Center_X + Half_W, South_Y - Half_H),
         (Center_X, South_Y - Long_Float (Diamond_Height)),
         (Center_X - Half_W, South_Y - Half_H));
   end Diamond;

   procedure Paint
     (Pixels : in out Byte_Array;
      Atlas_W : Natural;
      Column, Row : Natural;
      Which : Terrain_Name;
      Level : Natural)
   is
      Cell : Byte_Array (0 .. Tile_Width * Cell_Height * 4 - 1) :=
        (others => 0);
      Center : constant Long_Float := Long_Float (Tile_Width / 2);
      South : constant Long_Float :=
        Long_Float (Cell_Height - 1 - Level * Level_Px);
      Top : constant Quad := Diamond (Center, South);
      Color : constant Rgb := Base (Which);
      Lift : constant Long_Float := Long_Float (Level_Px);
      Wall : Quad;
   begin
      if Which = Building and then Level > 0 then
         Wall :=
           (Top (4), Top (1),
            (Top (1).X, Top (1).Y + Long_Float (Level) * Lift),
            (Top (4).X, Top (4).Y + Long_Float (Level) * Lift));
         Fill
           (Cell, Wall, 4,
            Channel (Color.R, 0.62), Channel (Color.G, 0.62),
            Channel (Color.B, 0.62), 255);
         Wall :=
           (Top (1), Top (2),
            (Top (2).X, Top (2).Y + Long_Float (Level) * Lift),
            (Top (1).X, Top (1).Y + Long_Float (Level) * Lift));
         Fill
           (Cell, Wall, 4,
            Channel (Color.R, 0.84), Channel (Color.G, 0.84),
            Channel (Color.B, 0.84), 255);
      elsif Which /= Water and then Which /= Building then
         Wall :=
           (Top (4), Top (1),
            (Top (1).X, Top (1).Y + Lift),
            (Top (4).X, Top (4).Y + Lift));
         Fill
           (Cell, Wall, 4,
            Channel (Color.R, 0.62), Channel (Color.G, 0.62),
            Channel (Color.B, 0.62), 255);
         Wall :=
           (Top (1), Top (2),
            (Top (2).X, Top (2).Y + Lift),
            (Top (1).X, Top (1).Y + Lift));
         Fill
           (Cell, Wall, 4,
            Channel (Color.R, 0.84), Channel (Color.G, 0.84),
            Channel (Color.B, 0.84), 255);
      end if;
      Fill
        (Cell, Top, 4,
         Channel (Color.R, 1.18), Channel (Color.G, 1.18),
         Channel (Color.B, 1.18), 255);
      for Y in 0 .. Cell_Height - 1 loop
         for X in 0 .. Tile_Width * 4 - 1 loop
            Pixels
              (((Row * Cell_Height + Y) * Atlas_W
                + Column * Tile_Width) * 4 + X) :=
              Cell (Y * Tile_Width * 4 + X);
         end loop;
      end loop;
   end Paint;

   procedure Write_Png
     (Path : String; Width, Height : Natural; Pixels : Byte_Array)
   is
      Stride : constant Natural := Width * 4;
      Raw_Len : constant Natural := Height * (1 + Stride);
      Raw : constant Byte_Ref := new Byte_Array (0 .. Raw_Len - 1);
      Bound : constant Natural := Raw_Len + Raw_Len / 10 + 64;
      Comp : constant Byte_Ref := new Byte_Array (0 .. Bound - 1);
      Dest_Len : aliased Interfaces.C.unsigned_long :=
        Interfaces.C.unsigned_long (Bound);
      Status : Interfaces.C.int;
      File : Ada.Streams.Stream_IO.File_Type;
      Signature : constant Byte_Array (0 .. 7) :=
        (137, 80, 78, 71, 13, 10, 26, 10);
   begin
      for Y in 0 .. Height - 1 loop
         Raw (Y * (1 + Stride)) := 0;
         for X in 0 .. Stride - 1 loop
            Raw (Y * (1 + Stride) + 1 + X) :=
              Pixels (Y * Stride + X);
         end loop;
      end loop;
      Status := Compress2
        (Comp (0)'Address, Dest_Len'Access, Raw (0)'Address,
         Interfaces.C.unsigned_long (Raw_Len), 9);
      pragma Assert (Status = 0);
      declare
         use Ada.Streams;
         Packed : constant Natural := Natural (Dest_Len);
         Ihdr : Byte_Array (0 .. 12);
         Chunk : Byte_Ref;
         procedure Emit (Tag : String; Data : Byte_Array);
         procedure Emit (Tag : String; Data : Byte_Array) is
            Head : Byte_Array (0 .. Data'Length + 3);
            Sum : U32;
            Len : Byte_Array (0 .. 3);
         begin
            Head (0) := Character'Pos (Tag (Tag'First));
            Head (1) := Character'Pos (Tag (Tag'First + 1));
            Head (2) := Character'Pos (Tag (Tag'First + 2));
            Head (3) := Character'Pos (Tag (Tag'First + 3));
            for I in Data'Range loop
               Head (4 + I - Data'First) := Data (I);
            end loop;
            Sum := Crc32 (Head);
            Put_U32 (Len, 0, U32 (Data'Length));
            declare
               Out_Buf : Stream_Element_Array (1 .. 4);
            begin
               for I in 0 .. 3 loop
                  Out_Buf (Stream_Element_Offset (I + 1)) :=
                    Stream_Element (Len (I));
               end loop;
               Ada.Streams.Stream_IO.Write (File, Out_Buf);
            end;
            declare
               Out_Buf : Stream_Element_Array (1 .. Head'Length);
            begin
               for I in Head'Range loop
                  Out_Buf
                    (Stream_Element_Offset (I - Head'First + 1)) :=
                    Stream_Element (Head (I));
               end loop;
               Ada.Streams.Stream_IO.Write (File, Out_Buf);
            end;
            declare
               Tail : Byte_Array (0 .. 3);
               Out_Buf : Stream_Element_Array (1 .. 4);
            begin
               Put_U32 (Tail, 0, Sum);
               for I in 0 .. 3 loop
                  Out_Buf (Stream_Element_Offset (I + 1)) :=
                    Stream_Element (Tail (I));
               end loop;
               Ada.Streams.Stream_IO.Write (File, Out_Buf);
            end;
         end Emit;
      begin
         Put_U32 (Ihdr, 0, U32 (Width));
         Put_U32 (Ihdr, 4, U32 (Height));
         Ihdr (8) := 8;
         Ihdr (9) := 6;
         Ihdr (10) := 0;
         Ihdr (11) := 0;
         Ihdr (12) := 0;
         Ada.Streams.Stream_IO.Create
           (File, Ada.Streams.Stream_IO.Out_File, Path);
         declare
            Out_Buf : Stream_Element_Array (1 .. 8);
         begin
            for I in 0 .. 7 loop
               Out_Buf (Stream_Element_Offset (I + 1)) :=
                 Stream_Element (Signature (I));
            end loop;
            Ada.Streams.Stream_IO.Write (File, Out_Buf);
         end;
         Emit ("IHDR", Ihdr);
         Chunk := new Byte_Array'(0 .. Packed - 1 => 0);
         Chunk (0 .. Packed - 1) := Comp (0 .. Packed - 1);
         Emit ("IDAT", Chunk.all);
         Emit ("IEND", (1 .. 0 => 0));
         Ada.Streams.Stream_IO.Close (File);
      end;
   end Write_Png;

   function Trim (Image : String) return String is
   begin
      if Image'Length > 0 and then Image (Image'First) = ' ' then
         return Image (Image'First + 1 .. Image'Last);
      end if;
      return Image;
   end Trim;

   function Name_Of (Which : Terrain_Name) return String is
   begin
      case Which is
         when Open =>
            return "open";
         when Road =>
            return "road";
         when Pavement =>
            return "pavement";
         when Building =>
            return "building";
         when Water =>
            return "water";
      end case;
   end Name_Of;

   procedure Write_Index (Path : String) is
      File : Ada.Text_IO.File_Type;
      Id : Natural;
      Which : Terrain_Name;
      Comma : Boolean;
   begin
      Ada.Text_IO.Create (File, Ada.Text_IO.Out_File, Path);
      Ada.Text_IO.Put_Line (File, "{");
      Ada.Text_IO.Put_Line (File, "  ""format"": 1,");
      Ada.Text_IO.Put_Line (File, "  ""tile_width"": 32,");
      Ada.Text_IO.Put_Line (File, "  ""diamond_height"": 16,");
      Ada.Text_IO.Put_Line (File, "  ""level_px"": 4,");
      Ada.Text_IO.Put_Line (File, "  ""cell_height"": 76,");
      Ada.Text_IO.Put_Line (File, "  ""columns"": 16,");
      Ada.Text_IO.Put_Line (File, "  ""atlas"": ""assets/atlas.png"",");
      Ada.Text_IO.Put_Line (File, "  ""tiles"": [");
      for Row in Terrain_Name loop
         for Level in 0 .. Max_Level loop
            Which := Row;
            Id := Terrain_Name'Pos (Which) * Columns + Level;
            Comma := not
              (Which = Water and then Level = Max_Level);
            Ada.Text_IO.Put (File, "    {""id"": ");
            Ada.Text_IO.Put (File, Trim (Natural'Image (Id)));
            Ada.Text_IO.Put (File, ", ""terrain"": """);
            Ada.Text_IO.Put (File, Name_Of (Which));
            Ada.Text_IO.Put (File, """, ""height"": ");
            Ada.Text_IO.Put (File, Trim (Natural'Image (Level)));
            Ada.Text_IO.Put (File, ", ""column"": ");
            Ada.Text_IO.Put (File, Trim (Natural'Image (Level)));
            Ada.Text_IO.Put (File, ", ""row"": ");
            Ada.Text_IO.Put
              (File, Trim (Natural'Image (Terrain_Name'Pos (Which))));
            if Comma then
               Ada.Text_IO.Put_Line (File, "},");
            else
               Ada.Text_IO.Put_Line (File, "}");
            end if;
         end loop;
      end loop;
      Ada.Text_IO.Put_Line (File, "  ]");
      Ada.Text_IO.Put_Line (File, "}");
      Ada.Text_IO.Close (File);
   end Write_Index;

   procedure Write_Licence (Path : String) is
      File : Ada.Text_IO.File_Type;
   begin
      Ada.Text_IO.Create (File, Ada.Text_IO.Out_File, Path);
      Ada.Text_IO.Put_Line (File, "Megacorp Simulator placeholder tileset");
      Ada.Text_IO.New_Line (File);
      Ada.Text_IO.Put_Line
        (File, "These pictures are original. They were drawn by");
      Ada.Text_IO.Put_Line
        (File, "tools/gen_tileset (Ada). They are not from any other game,");
      Ada.Text_IO.Put_Line
        (File, "and they contain no copied game art.");
      Ada.Text_IO.New_Line (File);
      Ada.Text_IO.Put_Line
        (File, "They are part of Megacorp Simulator and are covered by the");
      Ada.Text_IO.Put_Line
        (File, "MIT licence. Copyright (c) 2026 Robert Boettcher. See");
      Ada.Text_IO.Put_Line
        (File, "LICENSE at the repository root.");
      Ada.Text_IO.Close (File);
   end Write_Licence;

   procedure Write (Directory : String) is
      Atlas_W : constant Natural := Columns * Tile_Width;
      Atlas_H : constant Natural := Terrains * Cell_Height;
      Pixels : constant Byte_Ref :=
        new Byte_Array'(0 .. Atlas_W * Atlas_H * 4 - 1 => 0);
      Which : Terrain_Name;
   begin
      Ada.Directories.Create_Path (Directory);
      for Row in Terrain_Name loop
         Which := Row;
         for Level in 0 .. Max_Level loop
            Paint
              (Pixels.all, Atlas_W, Level, Terrain_Name'Pos (Which),
               Which, Level);
         end loop;
      end loop;
      Write_Png
        (Directory & "/atlas.png", Atlas_W, Atlas_H, Pixels.all);
      Write_Index (Directory & "/tiles.json");
      Write_Licence (Directory & "/LICENCE.txt");
   end Write;

end Tile_Art;
