--  SPDX-License-Identifier: MIT
--  Copyright (c) 2026 Robert Boettcher

with Ada.Unchecked_Deallocation;
with Megacorp.Map.Gen;
with Megacorp.Parameters;
with Megacorp.Path;
with Megacorp.Peds;
with Megacorp.Vehicles;

package body Megacorp.Play is
   use type Interfaces.Unsigned_32;
   use type Interfaces.Unsigned_64;
   use type Map.Point;

   Edge   : constant := Parameters.Default_City_Map_Width;
   Squad  : constant := 6;
   Fleet_N : constant := 2;
   Order_Max : constant := 8;
   Zoom_Min : constant := 2;
   Zoom_Max : constant := 16;

   Buf_Head : constant := 16;
   Buf_Map  : constant := Edge * Edge;
   Buf_Unit : constant := 8;
   Buf_Limit : constant :=
     Buf_Head + Buf_Map + (Squad + Fleet_N) * Buf_Unit;

   type Octet is new Interfaces.Unsigned_8;
   type Store is array (0 .. Buf_Limit - 1) of Octet;
   type City_Ref is access Map.City;

   type Order is record
      Who : Positive := 1;
      X   : Positive := 1;
      Y   : Positive := 1;
   end record;

   type Row is record
      X  : Positive := 1;
      Y  : Positive := 1;
      GX : Positive := 1;
      GY : Positive := 1;
      On : Boolean := False;
   end record;

   procedure Free is new Ada.Unchecked_Deallocation
     (Map.City, City_Ref);

   Ground : City_Ref;
   People : Peds.Crowd (1 .. Squad);
   Cars   : Vehicles.Fleet (1 .. Fleet_N);
   Chosen : array (1 .. Squad) of Boolean := (others => False);
   Move_X : array (1 .. Squad) of Positive := (others => 1);
   Move_Y : array (1 .. Squad) of Positive := (others => 1);
   Car_X  : array (1 .. Fleet_N) of Positive := (others => 1);
   Car_Y  : array (1 .. Fleet_N) of Positive := (others => 1);
   Road_A : Map.Point := (X => 1, Y => 1);
   Road_B : Map.Point := (X => 1, Y => 1);
   Orders : array (1 .. Order_Max) of Order;
   Order_N : Natural := 0;
   Ticks  : Natural := 0;
   Cam_X  : Integer := 1;
   Cam_Y  : Integer := 1;
   Zoom_N : Positive := 8;
   Buf    : Store := (others => 0);
   Used   : Natural := 0;

   function Trim_Int (Value : Integer) return String;
   function Mix (Hash : RNG.Word; Value : Natural) return RNG.Word;
   function Is_Standing (P : Peds.Ped) return Boolean;
   function Is_Driving (V : Vehicles.Vehicle) return Boolean;
   procedure Put_U8 (Value : Natural);
   procedure Put_U16 (Value : Natural);
   procedure Put_U32 (Value : Interfaces.Unsigned_32);
   procedure Publish;
   procedure Clamp_Cam;
   function Ped_At (TX, TY : Positive) return Natural;
   procedure Pixel_Tile
     (PX, PY : Integer;
      Tile : out Map.Point;
      Inside : out Boolean);
   procedure Queue_Move (Index : Positive; Tile : Map.Point);
   procedure Foot_Blocks (Into : in out Path.Block_Lists.Vector);
   procedure Apply_Orders;
   procedure Drive_Cars;
   procedure Wander;
   procedure Step_Once;
   function Field (Line : String; Index : Positive) return String;
   function Line_At (Text : String; Number : Positive) return String;
   function Image return String;

   function Trim_Int (Value : Integer) return String is
      Text : constant String := Integer'Image (Value);
   begin
      if Text (Text'First) = ' ' then
         return Text (Text'First + 1 .. Text'Last);
      end if;
      return Text;
   end Trim_Int;

   function Mix (Hash : RNG.Word; Value : Natural) return RNG.Word is
      Prime : constant RNG.Word := 16#0000_0100_0000_01B3#;
   begin
      return (Hash xor RNG.Word (Value mod 256)) * Prime;
   end Mix;

   function Is_Standing (P : Peds.Ped) return Boolean is
      use all type Peds.State_Kind;
   begin
      return Peds.State_Of (P) = Standing
        or else Peds.State_Of (P) = Arrived;
   end Is_Standing;

   function Is_Driving (V : Vehicles.Vehicle) return Boolean is
      use all type Vehicles.State_Kind;
   begin
      return Vehicles.State_Of (V) = Driving;
   end Is_Driving;

   function Ready return Boolean is
   begin
      return Ground /= null;
   end Ready;

   procedure Put_U8 (Value : Natural) is
   begin
      Buf (Used) := Octet (Value mod 256);
      Used := Used + 1;
   end Put_U8;

   procedure Put_U16 (Value : Natural) is
   begin
      Put_U8 (Value);
      Put_U8 (Value / 256);
   end Put_U16;

   procedure Put_U32 (Value : Interfaces.Unsigned_32) is
      Rest : Interfaces.Unsigned_32 := Value;
   begin
      for Drop in 1 .. 4 loop
         Put_U8 (Natural (Rest mod 256));
         Rest := Rest / 256;
      end loop;
   end Put_U32;

   procedure Publish is
      Cell : Map.Tile;
   begin
      if Ground = null then
         return;
      end if;
      Used := 0;
      Put_U16 (Ground.Width);
      Put_U16 (Ground.Height);
      Put_U16 (Natural (Cam_X));
      Put_U16 (Natural (Cam_Y));
      Put_U8 (Zoom_N);
      Put_U8 (Squad);
      Put_U8 (Fleet_N);
      Put_U8 (0);
      Put_U32 (Interfaces.Unsigned_32 (Ticks));
      for Y in 1 .. Ground.Height loop
         for X in 1 .. Ground.Width loop
            Cell := Map.Tile_At (Ground.all, X, Y);
            Put_U8 (Map.Terrain'Pos (Cell.Kind));
         end loop;
      end loop;
      for I in People'Range loop
         Put_U8 (Peds.Ident (People (I)));
         Put_U8 (Peds.Tile_X (People (I)));
         Put_U8 (Peds.Tile_Y (People (I)));
         Put_U8 (Peds.Along (People (I)));
         Put_U8 (Map.Eight_Way'Pos (Peds.Facing (People (I))));
         Put_U8 (Peds.State_Kind'Pos (Peds.State_Of (People (I))));
         if Chosen (I) then
            Put_U8 (1);
         else
            Put_U8 (0);
         end if;
         Put_U8 (0);
      end loop;
      for I in Cars'Range loop
         Put_U8 (Vehicles.Ident (Cars (I)));
         Put_U8 (Vehicles.Tile_X (Cars (I)));
         Put_U8 (Vehicles.Tile_Y (Cars (I)));
         Put_U8 (Vehicles.Along (Cars (I)));
         Put_U8 (Map.Eight_Way'Pos (Vehicles.Facing (Cars (I))));
         Put_U8
           (Vehicles.State_Kind'Pos (Vehicles.State_Of (Cars (I))));
         Put_U8 (Vehicles.Kind'Pos (Vehicles.Sort_Of (Cars (I))));
         Put_U8 (0);
      end loop;
   end Publish;

   procedure Clamp_Cam is
      Wide  : constant Integer := View_W / Zoom_N;
      High  : constant Integer := View_H / Zoom_N;
      Limit : Integer;
   begin
      if Ground = null then
         return;
      end if;
      if Cam_X < 1 then
         Cam_X := 1;
      end if;
      Limit := Ground.Width - Wide + 1;
      if Limit < 1 then
         Limit := 1;
      end if;
      if Cam_X > Limit then
         Cam_X := Limit;
      end if;
      if Cam_Y < 1 then
         Cam_Y := 1;
      end if;
      Limit := Ground.Height - High + 1;
      if Limit < 1 then
         Limit := 1;
      end if;
      if Cam_Y > Limit then
         Cam_Y := Limit;
      end if;
   end Clamp_Cam;

   function Ped_At (TX, TY : Positive) return Natural is
   begin
      for I in People'Range loop
         if Peds.Tile_X (People (I)) = TX
           and then Peds.Tile_Y (People (I)) = TY
         then
            return I;
         end if;
      end loop;
      return 0;
   end Ped_At;

   procedure Pixel_Tile
     (PX, PY : Integer;
      Tile : out Map.Point;
      Inside : out Boolean)
   is
      X : constant Integer := Cam_X + PX / Zoom_N;
      Y : constant Integer := Cam_Y + PY / Zoom_N;
   begin
      Tile := (X => 1, Y => 1);
      Inside := Ground /= null
        and then Map.In_Bounds (Ground.all, X, Y);
      if Inside then
         Tile := (X => Positive (X), Y => Positive (Y));
      end if;
   end Pixel_Tile;

   procedure Queue_Move (Index : Positive; Tile : Map.Point) is
   begin
      if Order_N >= Order_Max then
         return;
      end if;
      if not Map.Tile_At (Ground.all, Tile.X, Tile.Y).Walkable then
         return;
      end if;
      Order_N := Order_N + 1;
      Orders (Order_N) := (Who => Index, X => Tile.X, Y => Tile.Y);
      Move_X (Index) := Tile.X;
      Move_Y (Index) := Tile.Y;
   end Queue_Move;

   procedure Foot_Blocks (Into : in out Path.Block_Lists.Vector) is
   begin
      Into.Clear;
      for I in People'Range loop
         Into.Append
           ((X => Peds.Tile_X (People (I)),
             Y => Peds.Tile_Y (People (I))));
      end loop;
   end Foot_Blocks;

   procedure Apply_Orders is
      Goal : Map.Point;
      Accepted : Boolean;
   begin
      for I in 1 .. Order_N loop
         Goal := (X => Orders (I).X, Y => Orders (I).Y);
         Peds.Command_Walk
           (People, Orders (I).Who, Goal, Ground.all,
            Accepted => Accepted);
      end loop;
      Order_N := 0;
   end Apply_Orders;

   procedure Drive_Cars is
      Foot : Path.Block_Lists.Vector;
      Accepted : Boolean;
      Goal : Map.Point;
   begin
      Foot_Blocks (Foot);
      for I in Cars'Range loop
         if not Is_Driving (Cars (I)) then
            if I = 1 then
               Goal := Road_B;
            else
               Goal := Road_A;
            end if;
            if Goal.X /= Vehicles.Tile_X (Cars (I))
              or else Goal.Y /= Vehicles.Tile_Y (Cars (I))
            then
               Vehicles.Command_Drive
                 (Cars, I, Goal, Ground.all, Foot, Accepted);
               if Accepted then
                  Car_X (I) := Goal.X;
                  Car_Y (I) := Goal.Y;
               end if;
            end if;
         end if;
         Vehicles.Advance (Cars, I, Ground.all, Foot);
      end loop;
   end Drive_Cars;

   procedure Wander is
      Goal : Map.Point;
      Accepted : Boolean;
   begin
      if Ticks = 0 or else Ticks mod 16 /= 0 then
         return;
      end if;
      for I in 5 .. Squad loop
         if not Chosen (I) and then Is_Standing (People (I)) then
            Goal := Goal_Near (I);
            if Goal /= (X => Peds.Tile_X (People (I)),
                        Y => Peds.Tile_Y (People (I)))
            then
               Peds.Command_Walk
                 (People, I, Goal, Ground.all, Accepted => Accepted);
               if Accepted then
                  Move_X (I) := Goal.X;
                  Move_Y (I) := Goal.Y;
               end if;
            end if;
         end if;
      end loop;
   end Wander;

   procedure Step_Once is
      Blocks : Path.Block_Lists.Vector;
   begin
      Apply_Orders;
      Wander;
      Vehicles.Add_Blocks (Cars, 0, True, Blocks);
      Peds.Tick (People, Ground.all, Blocks);
      Drive_Cars;
      Ticks := Ticks + 1;
   end Step_Once;

   procedure Open (City_Seed : RNG.Word) is
      type Point_List is array (1 .. Squad) of Map.Point;
      Feet  : Point_List := (others => (X => 1, Y => 1));
      Roads : array (1 .. Fleet_N) of Map.Point :=
        (others => (X => 1, Y => 1));
      Foot_N : Natural := 0;
      Road_N : Natural := 0;
      Cell : Map.Tile;
      Far : Boolean;

      procedure Take_Foot (X, Y : Positive);
      procedure Take_Road (X, Y : Positive);
      procedure Scan (Roads_Only : Boolean);

      procedure Take_Foot (X, Y : Positive) is
      begin
         if Foot_N >= Squad then
            return;
         end if;
         Foot_N := Foot_N + 1;
         Feet (Foot_N) := (X => X, Y => Y);
      end Take_Foot;

      procedure Take_Road (X, Y : Positive) is
         Here : constant Map.Point := (X => X, Y => Y);
      begin
         if Road_N >= Fleet_N then
            return;
         end if;
         Far := True;
         for I in 1 .. Road_N loop
            if abs (X - Roads (I).X) + abs (Y - Roads (I).Y) < 12 then
               Far := False;
            end if;
         end loop;
         if Far or else Road_N = 0 then
            Road_N := Road_N + 1;
            Roads (Road_N) := Here;
         end if;
      end Take_Road;

      procedure Scan (Roads_Only : Boolean) is
      begin
         for Y in 1 .. Ground.Height loop
            for X in 1 .. Ground.Width loop
               Cell := Map.Tile_At (Ground.all, X, Y);
               if not Roads_Only
                 and then Cell.Walkable
                 and then not Cell.Drivable
                 and then Foot_N < Squad
               then
                  Take_Foot (X, Y);
               elsif Cell.Drivable and then Road_N < Fleet_N then
                  Take_Road (X, Y);
               end if;
            end loop;
         end loop;
      end Scan;
   begin
      if Ground /= null then
         Free (Ground);
      end if;
      Ground := new Map.City'
        (Map.Gen.Generate (City_Seed, Edge, Edge));
      Scan (False);
      if Foot_N < Squad or else Road_N < Fleet_N then
         Scan (True);
      end if;
      while Foot_N < Squad loop
         Foot_N := Foot_N + 1;
         Feet (Foot_N) := Feet (1);
      end loop;
      if Road_N < 1 then
         Roads (1) := Feet (1);
         Road_N := 1;
      end if;
      if Road_N < 2 then
         Roads (2) := Roads (1);
      end if;
      Road_A := Roads (1);
      Road_B := Roads (2);
      for I in People'Range loop
         People (I) := Peds.Place (I, Feet (I), Ground.all);
         Chosen (I) := False;
         Move_X (I) := Feet (I).X;
         Move_Y (I) := Feet (I).Y;
      end loop;
      for I in Cars'Range loop
         Cars (I) := Vehicles.Park
           (I, Vehicles.Kind'First, Roads (I), Ground.all);
         Car_X (I) := Roads (I).X;
         Car_Y (I) := Roads (I).Y;
      end loop;
      Order_N := 0;
      Ticks := 0;
      Zoom_N := 8;
      Cam_X := Integer (Peds.Tile_X (People (1)))
        - (View_W / Zoom_N) / 2;
      Cam_Y := Integer (Peds.Tile_Y (People (1)))
        - (View_H / Zoom_N) / 2;
      Clamp_Cam;
      Publish;
   end Open;

   procedure Handle (Code, A, B, C, D, E : Integer) is
      pragma Unreferenced (E);
      Tile : Map.Point;
      Other : Map.Point;
      Inside : Boolean;
      Hit : Natural;
      Left : Positive;
      Top : Positive;
      Right : Positive;
      Bottom : Positive;
   begin
      if Ground = null then
         return;
      end if;
      case Code is
         when 1 =>
            Pixel_Tile (A, B, Tile, Inside);
            if not Inside then
               Publish;
               return;
            end if;
            Hit := Ped_At (Tile.X, Tile.Y);
            if Hit > 0 then
               Chosen := (others => False);
               Chosen (Hit) := True;
            else
               for I in People'Range loop
                  if Chosen (I) then
                     Queue_Move (I, Tile);
                  end if;
               end loop;
            end if;
         when 2 =>
            Pixel_Tile (A, B, Tile, Inside);
            Pixel_Tile (C, D, Other, Inside);
            if Map.In_Bounds (Ground.all, Tile.X, Tile.Y)
              and then Map.In_Bounds (Ground.all, Other.X, Other.Y)
            then
               Left := Tile.X;
               Right := Other.X;
               if Right < Left then
                  Left := Other.X;
                  Right := Tile.X;
               end if;
               Top := Tile.Y;
               Bottom := Other.Y;
               if Bottom < Top then
                  Top := Other.Y;
                  Bottom := Tile.Y;
               end if;
               Chosen := (others => False);
               for I in People'Range loop
                  if Peds.Tile_X (People (I)) >= Left
                    and then Peds.Tile_X (People (I)) <= Right
                    and then Peds.Tile_Y (People (I)) >= Top
                    and then Peds.Tile_Y (People (I)) <= Bottom
                  then
                     Chosen (I) := True;
                  end if;
               end loop;
            end if;
         when 3 =>
            case A is
               when 1 =>
                  Cam_X := Cam_X - 2;
               when 2 =>
                  Cam_X := Cam_X + 2;
               when 3 =>
                  Cam_Y := Cam_Y - 2;
               when 4 =>
                  Cam_Y := Cam_Y + 2;
               when 5 =>
                  if Zoom_N > Zoom_Min then
                     Zoom_N := Zoom_N - 1;
                  end if;
               when 6 =>
                  if Zoom_N < Zoom_Max then
                     Zoom_N := Zoom_N + 1;
                  end if;
               when others =>
                  null;
            end case;
            Clamp_Cam;
         when 4 =>
            Cam_X := Cam_X - A / Zoom_N;
            Cam_Y := Cam_Y - B / Zoom_N;
            if C < 0 and then Zoom_N > Zoom_Min then
               Zoom_N := Zoom_N - 1;
            elsif C > 0 and then Zoom_N < Zoom_Max then
               Zoom_N := Zoom_N + 1;
            end if;
            Clamp_Cam;
         when 5 =>
            Cam_X := Cam_X - A / Zoom_N;
            Cam_Y := Cam_Y - B / Zoom_N;
            Clamp_Cam;
         when others =>
            null;
      end case;
      Publish;
   end Handle;

   procedure Run (Count : Positive) is
   begin
      if Ground = null then
         return;
      end if;
      for Drop in 1 .. Count loop
         Step_Once;
      end loop;
      Publish;
   end Run;

   function Clock return Natural is
   begin
      return Ticks;
   end Clock;

   function Actor_X (Index : Positive) return Positive is
   begin
      return Peds.Tile_X (People (Index));
   end Actor_X;

   function Actor_Y (Index : Positive) return Positive is
   begin
      return Peds.Tile_Y (People (Index));
   end Actor_Y;

   function Pixel_X (Tile : Positive) return Integer is
   begin
      return (Integer (Tile) - Cam_X) * Zoom_N + Zoom_N / 2;
   end Pixel_X;

   function Pixel_Y (Tile : Positive) return Integer is
   begin
      return (Integer (Tile) - Cam_Y) * Zoom_N + Zoom_N / 2;
   end Pixel_Y;

   function Goal_Near (Index : Positive) return Map.Point is
      Origin_X : constant Positive := Peds.Tile_X (People (Index));
      Origin_Y : constant Positive := Peds.Tile_Y (People (Index));
      X : Integer;
      Y : Integer;
   begin
      for Radius in 3 .. 10 loop
         for DY in -Radius .. Radius loop
            for DX in -Radius .. Radius loop
               if abs DX = Radius or else abs DY = Radius then
                  X := Integer (Origin_X) + DX;
                  Y := Integer (Origin_Y) + DY;
                  if Map.In_Bounds (Ground.all, X, Y)
                    and then Map.Tile_At (Ground.all, X, Y).Walkable
                    and then Ped_At (Positive (X), Positive (Y)) = 0
                  then
                     return (X => Positive (X), Y => Positive (Y));
                  end if;
               end if;
            end loop;
         end loop;
      end loop;
      return (X => Origin_X, Y => Origin_Y);
   end Goal_Near;

   function Digest return RNG.Word is
      Basis : constant RNG.Word := 16#CBF2_9CE4_8422_2325#;
      Hash : RNG.Word := Basis;
   begin
      if Ground = null then
         return 0;
      end if;
      Hash := Mix (Hash, Ticks);
      Hash := Mix (Hash, Natural (Cam_X));
      Hash := Mix (Hash, Natural (Cam_Y));
      Hash := Mix (Hash, Zoom_N);
      for I in People'Range loop
         Hash := Mix (Hash, Peds.Tile_X (People (I)));
         Hash := Mix (Hash, Peds.Tile_Y (People (I)));
         Hash := Mix (Hash, Peds.Along (People (I)));
         Hash := Mix
           (Hash, Map.Eight_Way'Pos (Peds.Facing (People (I))));
         Hash := Mix
           (Hash, Peds.State_Kind'Pos (Peds.State_Of (People (I))));
         if Chosen (I) then
            Hash := Mix (Hash, 1);
         else
            Hash := Mix (Hash, 0);
         end if;
      end loop;
      for I in Cars'Range loop
         Hash := Mix (Hash, Vehicles.Tile_X (Cars (I)));
         Hash := Mix (Hash, Vehicles.Tile_Y (Cars (I)));
         Hash := Mix (Hash, Vehicles.Along (Cars (I)));
         Hash := Mix
           (Hash,
            Vehicles.State_Kind'Pos (Vehicles.State_Of (Cars (I))));
      end loop;
      return Hash;
   end Digest;

   function Field (Line : String; Index : Positive) return String is
      Seen : Natural := 0;
      Start : Natural := Line'First;
   begin
      for I in Line'Range loop
         if Line (I) = ' ' then
            Seen := Seen + 1;
            if Seen = Index then
               return Line (Start .. I - 1);
            end if;
            Start := I + 1;
         end if;
      end loop;
      Seen := Seen + 1;
      if Seen = Index and then Start <= Line'Last then
         return Line (Start .. Line'Last);
      end if;
      return "";
   end Field;

   function Line_At (Text : String; Number : Positive) return String is
      Seen : Natural := 0;
      Start : Positive := Text'First;
   begin
      for I in Text'Range loop
         if Text (I) = ASCII.LF then
            Seen := Seen + 1;
            if Seen = Number then
               if I = Start then
                  return "";
               end if;
               return Text (Start .. I - 1);
            end if;
            Start := I + 1;
         end if;
      end loop;
      return "";
   end Line_At;

   function Image return String is
      Text : String (1 .. 800) := (others => ' ');
      Last : Natural := 0;

      procedure Add (Item : String);
      procedure Add (Item : String) is
      begin
         Text (Last + 1 .. Last + Item'Length) := Item;
         Last := Last + Item'Length;
         Last := Last + 1;
         Text (Last) := ASCII.LF;
      end Add;
   begin
      Add ("CITY 1");
      Add ("tick " & Trim_Int (Ticks));
      Add ("cam " & Trim_Int (Cam_X)
        & " " & Trim_Int (Cam_Y)
        & " " & Trim_Int (Zoom_N));
      for I in People'Range loop
         Add ("ped " & Trim_Int (Peds.Ident (People (I)))
           & " " & Trim_Int (Peds.Tile_X (People (I)))
           & " " & Trim_Int (Peds.Tile_Y (People (I)))
           & " " & Trim_Int (Move_X (I))
           & " " & Trim_Int (Move_Y (I))
           & " " & Trim_Int (Boolean'Pos (Chosen (I))));
      end loop;
      for I in Cars'Range loop
         Add ("car " & Trim_Int (Vehicles.Ident (Cars (I)))
           & " " & Trim_Int (Vehicles.Tile_X (Cars (I)))
           & " " & Trim_Int (Vehicles.Tile_Y (Cars (I)))
           & " " & Trim_Int (Car_X (I))
           & " " & Trim_Int (Car_Y (I)));
      end loop;
      return Text (1 .. Last);
   end Image;

   procedure Write
     (Disk : in out Data.Virtual_FS.Backend'Class;
      Path : String)
   is
   begin
      Data.Virtual_FS.Write (Disk, Path, Image);
   end Write;

   function Read
     (Disk : Data.Virtual_FS.Backend'Class;
      Path : String) return Boolean
   is
      Text : constant String := Data.Virtual_FS.Read (Disk, Path);
      Peds_Ok : Natural := 0;
      Cars_Ok : Natural := 0;
      Mark : Row;
      Saved_Peds : array (1 .. Squad) of Row;
      Saved_Cars : array (1 .. Fleet_N) of Row;
      Line : String (1 .. 80);
      Last : Natural;
      Goal : Map.Point;
      Spot : Map.Point;
      Accepted : Boolean;

      procedure Keep (Kind : String);
      procedure Keep (Kind : String) is
         Got : constant String :=
           Line (Line'First .. Line'First + Last - 1);
      begin
         if Field (Got, 1) /= Kind then
            return;
         end if;
         Mark.X := Positive'Value (Field (Got, 3));
         Mark.Y := Positive'Value (Field (Got, 4));
         Mark.GX := Positive'Value (Field (Got, 5));
         Mark.GY := Positive'Value (Field (Got, 6));
         if Kind = "ped" then
            Mark.On := Field (Got, 7) = "1";
            Peds_Ok := Peds_Ok + 1;
            if Peds_Ok <= Squad then
               Saved_Peds (Peds_Ok) := Mark;
            end if;
         else
            Cars_Ok := Cars_Ok + 1;
            if Cars_Ok <= Fleet_N then
               Saved_Cars (Cars_Ok) := Mark;
            end if;
         end if;
      end Keep;
   begin
      if Line_At (Text, 1) /= "CITY 1" then
         return False;
      end if;
      for Number in 4 .. 11 loop
         declare
            Item : constant String := Line_At (Text, Number);
         begin
            if Item'Length = 0 or else Item'Length > Line'Length then
               return False;
            end if;
            Last := Item'Length;
            Line (1 .. Last) := Item;
            if Number <= 9 then
               Keep ("ped");
            else
               Keep ("car");
            end if;
         end;
      end loop;
      if Peds_Ok /= Squad or else Cars_Ok /= Fleet_N then
         return False;
      end if;
      Ticks := Natural'Value (Field (Line_At (Text, 2), 2));
      Cam_X := Integer'Value (Field (Line_At (Text, 3), 2));
      Cam_Y := Integer'Value (Field (Line_At (Text, 3), 3));
      Zoom_N := Positive'Value (Field (Line_At (Text, 3), 4));
      for I in People'Range loop
         Spot := (X => Saved_Peds (I).X, Y => Saved_Peds (I).Y);
         if Map.Tile_At (Ground.all, Spot.X, Spot.Y).Walkable then
            People (I) := Peds.Place (I, Spot, Ground.all);
         end if;
         Chosen (I) := Saved_Peds (I).On;
         Move_X (I) := Saved_Peds (I).GX;
         Move_Y (I) := Saved_Peds (I).GY;
         Goal := (X => Move_X (I), Y => Move_Y (I));
         if Goal /= Spot
           and then Map.Tile_At (Ground.all, Goal.X, Goal.Y).Walkable
         then
            Peds.Command_Walk
              (People, I, Goal, Ground.all, Accepted => Accepted);
         end if;
      end loop;
      for I in Cars'Range loop
         Spot := (X => Saved_Cars (I).X, Y => Saved_Cars (I).Y);
         if Map.Tile_At (Ground.all, Spot.X, Spot.Y).Drivable then
            Cars (I) := Vehicles.Park
              (I, Vehicles.Kind'First, Spot, Ground.all);
         end if;
         Car_X (I) := Saved_Cars (I).GX;
         Car_Y (I) := Saved_Cars (I).GY;
      end loop;
      Clamp_Cam;
      Publish;
      return True;
   end Read;

   function City_State return System.Address is
   begin
      return Buf'Address;
   end City_State;

   function City_State_Size return Interfaces.Unsigned_32 is
   begin
      return Interfaces.Unsigned_32 (Buf_Limit);
   end City_State_Size;
end Megacorp.Play;
