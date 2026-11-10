--  SPDX-License-Identifier: MIT
--  Copyright (c) 2026 Robert Boettcher

with Ada.Directories;
with Ada.Text_IO;
with Megacorp.Actions;
with Megacorp.Shots;
with Megacorp.Weapons;
with Megacorp.Assets.Placeholder;
with Megacorp.Data.Virtual_FS.Native;
with Megacorp.Path;
with Megacorp.Peds;

package body Megacorp.Map is
   package Act renames Megacorp.Actions;
   package Placeholder renames Megacorp.Assets.Placeholder;
   package Disk renames Megacorp.Data.Virtual_FS.Native;
   use type Path.Status;

   --  Below this edge the test layout is open ground only.
   Min_Pattern : constant := 8;

   type Delta_XY is record
      DX : Integer;
      DY : Integer;
   end record;

   Four_Step : constant array (Four_Way) of Delta_XY :=
     (North => (DX => 0, DY => -1),
      East  => (DX => 1, DY => 0),
      South => (DX => 0, DY => 1),
      West  => (DX => -1, DY => 0));

   Eight_Step : constant array (Eight_Way) of Delta_XY :=
     (North => (DX => 0, DY => -1),
      East => (DX => 1, DY => 0),
      South => (DX => 0, DY => 1),
      West => (DX => -1, DY => 0),
      North_East => (DX => 1, DY => -1),
      South_East => (DX => 1, DY => 1),
      South_West => (DX => -1, DY => 1),
      North_West => (DX => -1, DY => -1));

   function Step_Of (Dir : Four_Way) return Delta_XY;
   function Step_Of (Dir : Eight_Way) return Delta_XY;
   function Trim (Image : String) return String;
   function Hex_Digit (Level : Height_Level) return Character;
   function Flag_Code (Cell : Tile) return Character;
   procedure Set_Cell
     (M : in out City;
      X, Y : Positive;
      Kind : Terrain;
      Level : Height_Level);
   procedure Fill_Open (M : in out City);
   function Clamp (Value, Low, High : Integer) return Integer;
   function Touches_Road
     (M : City; X, Y : Positive) return Boolean;
   procedure Lay_River
     (M : in out City; G : in out RNG.Generator);
   procedure Lay_Roads
     (M : in out City; G : in out RNG.Generator);
   procedure Lay_Pavement (M : in out City);
   procedure Lay_Buildings
     (M : in out City; G : in out RNG.Generator);
   function Hex_Pair (Value : Natural) return String;
   function Row_Image
     (M : City;
      Y : Positive;
      Tiles : Placeholder.Tileset) return String;
   function Parent_Directory (Path : String) return String;
   function Locate
     (M : City; Kind : Terrain; From_End : Boolean) return Point;
   function Mode_Token (How : Path.Mode) return String;
   function Status_Token (Kind : Path.Status) return String;
   procedure Put_Route
     (File : Ada.Text_IO.File_Type;
      M : City;
      Label : String;
      How : Path.Mode;
      Start, Goal : Point;
      Last_Item : Boolean);
   type Mission_Points is record
      Leader_At   : Point;
      Leader_Goal : Point;
      Follower_At : Point;
      Waypoint    : Point;
      Item_At     : Point;
   end record;
   function Route_Length
     (M : City; From, To : Point) return Natural;
   function Seek
     (M : City; Origin : Point; Low, High : Positive) return Point;
   function Side_Tile
     (M : City; Origin, Avoid : Point) return Point;
   function Mission_Of (M : City) return Mission_Points;
   function Script (M : City) return Act.Shot_Lists.Vector;
   procedure Write_Action_Frame
     (File : Ada.Text_IO.File_Type;
      Shot : Act.Snapshot;
      Last_Item : Boolean);
   procedure Write_Script_Ped
     (File : Ada.Text_IO.File_Type;
      Trace : Act.Shot_Lists.Vector;
      Who : Peds.Ped_Id;
      Last_Item : Boolean);
   procedure Write_Script (File : Ada.Text_IO.File_Type; M : City);
   procedure Write_Paths
     (File : Ada.Text_IO.File_Type; M : City);
   procedure Write_Map_File
     (Path : String;
      Version : String;
      M : City;
      Tiles : Placeholder.Tileset);
   procedure Write_Index
     (Path : String; Version : String);
   function Facing_Token (Dir : Eight_Way) return String;
   function State_Token (Kind : Peds.State_Kind) return String;
   procedure Write_Frame
     (File : Ada.Text_IO.File_Type;
      Item : Peds.Frame;
      Last_Item : Boolean);
   procedure Write_Ped_Trace
     (File : Ada.Text_IO.File_Type;
      Trace : Peds.Frame_Lists.Vector;
      Who : Peds.Ped_Id;
      Last_Item : Boolean);
   procedure Write_Motion
     (File : Ada.Text_IO.File_Type; M : City);
   procedure Write_Encounter
     (Target : String;
      Version : String;
      Tiles : Placeholder.Tileset);
   function Bare_Directory (Directory : String) return String;

   function Layout_Seed (M : City) return RNG.Word is
   begin
      return M.From_Seed;
   end Layout_Seed;

   function In_Bounds (M : City; X, Y : Integer) return Boolean is
   begin
      return X >= 1 and then X <= M.Width
        and then Y >= 1 and then Y <= M.Height;
   end In_Bounds;

   function Tile_At (M : City; X, Y : Integer) return Tile is
   begin
      return M.Cell (X, Y);
   end Tile_At;

   function Step_Of (Dir : Four_Way) return Delta_XY is
   begin
      return Four_Step (Dir);
   end Step_Of;

   function Step_Of (Dir : Eight_Way) return Delta_XY is
   begin
      return Eight_Step (Dir);
   end Step_Of;

   function Has_Neighbour_4
     (M : City; X, Y : Integer; Dir : Four_Way) return Boolean
   is
      Step : constant Delta_XY := Step_Of (Dir);
   begin
      return In_Bounds (M, X + Step.DX, Y + Step.DY);
   end Has_Neighbour_4;

   function Neighbour_4
     (M : City; X, Y : Integer; Dir : Four_Way) return Point
   is
      Step : constant Delta_XY := Step_Of (Dir);
   begin
      return (X => X + Step.DX, Y => Y + Step.DY);
   end Neighbour_4;

   function Has_Neighbour_8
     (M : City; X, Y : Integer; Dir : Eight_Way) return Boolean
   is
      Step : constant Delta_XY := Step_Of (Dir);
   begin
      return In_Bounds (M, X + Step.DX, Y + Step.DY);
   end Has_Neighbour_8;

   function Neighbour_8
     (M : City; X, Y : Integer; Dir : Eight_Way) return Point
   is
      Step : constant Delta_XY := Step_Of (Dir);
   begin
      return (X => X + Step.DX, Y => Y + Step.DY);
   end Neighbour_8;

   function Terrain_Code (Kind : Terrain) return Character is
   begin
      case Kind is
         when Open_Ground =>
            return '.';
         when Road =>
            return '+';
         when Pavement =>
            return '=';
         when Building =>
            return 'B';
         when Water =>
            return '~';
      end case;
   end Terrain_Code;

   function Hex_Digit (Level : Height_Level) return Character is
      Hex : constant String := "0123456789ABCDEF";
   begin
      return Hex (Hex'First + Level);
   end Hex_Digit;

   function Flag_Code (Cell : Tile) return Character is
      Bits : Natural := 0;
   begin
      if Cell.Walkable then
         Bits := Bits + 1;
      end if;
      if Cell.Drivable then
         Bits := Bits + 2;
      end if;
      return Character'Val (Character'Pos ('0') + Bits);
   end Flag_Code;

   function Trim (Image : String) return String is
   begin
      if Image'Length > 0 and then Image (Image'First) = ' ' then
         return Image (Image'First + 1 .. Image'Last);
      end if;
      return Image;
   end Trim;

   procedure Set_Cell
     (M : in out City;
      X, Y : Positive;
      Kind : Terrain;
      Level : Height_Level)
   is
      Cell : Tile;
   begin
      Cell.Kind := Kind;
      Cell.Level := Level;
      Cell.Walkable := Kind in Open_Ground | Road | Pavement;
      Cell.Drivable := Kind = Road;
      M.Cell (X, Y) := Cell;
   end Set_Cell;

   procedure Fill_Open (M : in out City) is
   begin
      for Y in 1 .. M.Height loop
         for X in 1 .. M.Width loop
            Set_Cell (M, X, Y, Open_Ground, 1);
         end loop;
      end loop;
   end Fill_Open;

   function Clamp (Value, Low, High : Integer) return Integer is
   begin
      if Value < Low then
         return Low;
      elsif Value > High then
         return High;
      else
         return Value;
      end if;
   end Clamp;

   function Touches_Road
     (M : City; X, Y : Positive) return Boolean
   is
   begin
      for Dir in Four_Way loop
         if Has_Neighbour_4 (M, X, Y, Dir) then
            declare
               At_Dir : constant Point := Neighbour_4 (M, X, Y, Dir);
            begin
               if Tile_At (M, At_Dir.X, At_Dir.Y).Kind = Road then
                  return True;
               end if;
            end;
         end if;
      end loop;
      return False;
   end Touches_Road;

   procedure Lay_River
     (M : in out City; G : in out RNG.Generator)
   is
      Base   : Integer;
      Thick  : Integer;
      Center : Integer;
      Shift  : Integer;
      Top    : Integer;
      Bottom : Integer;
   begin
      Base := RNG.Pick (G, M.Height / 3, (2 * M.Height) / 3);
      Thick := RNG.Pick (G, 2, 3);
      Center := Base;
      for X in 1 .. M.Width loop
         Shift := RNG.Pick (G, -1, 1);
         Center := Clamp
           (Center + Shift, Thick, M.Height - Thick);
         Top := Center - (Thick / 2);
         Bottom := Top + Thick - 1;
         for Y in Top .. Bottom loop
            Set_Cell (M, X, Y, Water, 0);
         end loop;
      end loop;
   end Lay_River;

   procedure Lay_Roads
     (M : in out City; G : in out RNG.Generator)
   is
      Spacing : constant Integer := RNG.Pick (G, 8, 12);
      X       : Integer := 1;
      Y       : Integer := 1;
   begin
      pragma Assert (Spacing > 0);
      while X <= M.Width loop
         for Row in 1 .. M.Height loop
            Set_Cell (M, X, Row, Road, 1);
         end loop;
         X := X + Spacing;
      end loop;
      while Y <= M.Height loop
         for Column in 1 .. M.Width loop
            Set_Cell (M, Column, Y, Road, 1);
         end loop;
         Y := Y + Spacing;
      end loop;
   end Lay_Roads;

   procedure Lay_Pavement (M : in out City) is
   begin
      for Y in 1 .. M.Height loop
         for X in 1 .. M.Width loop
            if M.Cell (X, Y).Kind = Open_Ground
              and then Touches_Road (M, X, Y)
            then
               Set_Cell (M, X, Y, Pavement, 1);
            end if;
         end loop;
      end loop;
   end Lay_Pavement;

   procedure Lay_Buildings
     (M : in out City; G : in out RNG.Generator)
   is
      Storey : Integer;
   begin
      for Y in 1 .. M.Height loop
         for X in 1 .. M.Width loop
            if M.Cell (X, Y).Kind = Open_Ground then
               Storey := RNG.Pick (G, 2, 5);
               Set_Cell (M, X, Y, Building, Storey);
            end if;
         end loop;
      end loop;
   end Lay_Buildings;

   function Blank (Width, Height : Positive) return City is
      Result : City (Width, Height);
   begin
      Result.From_Seed := 0;
      return Result;
   end Blank;

   procedure Set_Tile
     (M : in out City; X, Y : Integer; Cell : Tile)
   is
   begin
      M.Cell (X, Y) := Cell;
   end Set_Tile;

   function Test_Layout
     (From : RNG.Word; Width, Height : Positive) return City
   is
      Result : City (Width, Height);
      World  : constant RNG.Generator := RNG.Make (From);
      Stream : RNG.Generator :=
        RNG.Child (World, RNG.City, 1);
   begin
      Result.From_Seed := From;
      Fill_Open (Result);
      if Width >= Min_Pattern and then Height >= Min_Pattern then
         Lay_River (Result, Stream);
         Lay_Roads (Result, Stream);
         Lay_Pavement (Result);
         Lay_Buildings (Result, Stream);
      end if;
      return Result;
   end Test_Layout;

   function Test_Layout
     (From : RNG.Word;
      Size : Parameters.Generator_Parameters) return City
   is
   begin
      return Test_Layout
        (From,
         Parameters.City_Map_Width (Size),
         Parameters.City_Map_Height (Size));
   end Test_Layout;

   procedure Put_Window
     (M : City;
      First_X, First_Y : Positive;
      Columns, Rows : Natural)
   is
      Last_X : constant Integer :=
        Integer'Min (M.Width, First_X + Columns - 1);
      Last_Y : constant Integer :=
        Integer'Min (M.Height, First_Y + Rows - 1);
   begin
      for Y in First_Y .. Last_Y loop
         for X in First_X .. Last_X loop
            Ada.Text_IO.Put
              (Terrain_Code (Tile_At (M, X, Y).Kind));
         end loop;
         Ada.Text_IO.New_Line;
      end loop;
   end Put_Window;

   procedure Put_Sample (M : City) is
      Found   : Boolean := False;
      At_X    : Positive := 1;
      At_Y    : Positive := 1;
      First_X : Positive;
      First_Y : Positive;
   begin
      Ada.Text_IO.Put_Line ("northwest:");
      Put_Window (M, 1, 1, 36, 10);
      for Y in 1 .. M.Height loop
         for X in 1 .. M.Width loop
            if M.Cell (X, Y).Kind = Water and then not Found then
               Found := True;
               At_X := X;
               At_Y := Y;
            end if;
         end loop;
      end loop;
      if Found then
         Ada.Text_IO.Put_Line
           ("river near" & Integer'Image (At_X)
            & Integer'Image (At_Y) & ":");
         First_X := Positive (Integer'Max (1, At_X - 17));
         First_Y := Positive (Integer'Max (1, At_Y - 3));
         Put_Window (M, First_X, First_Y, 36, 8);
      end if;
   end Put_Sample;

   function Hex_Pair (Value : Natural) return String is
      Hex : constant String := "0123456789ABCDEF";
   begin
      return Hex (Hex'First + Value / 16)
        & Hex (Hex'First + Value mod 16);
   end Hex_Pair;

   function Row_Image
     (M : City;
      Y : Positive;
      Tiles : Placeholder.Tileset) return String
   is
      Image : String (1 .. M.Width * 5);
      Place : Positive := 1;
      Cell  : Tile;
      Id    : Natural;
   begin
      for X in 1 .. M.Width loop
         Cell := M.Cell (X, Y);
         Id := Placeholder.Tile_Id (Tiles, Cell.Kind, Cell.Level);
         Image (Place) := Terrain_Code (Cell.Kind);
         Image (Place + 1) := Hex_Digit (Cell.Level);
         Image (Place + 2) := Flag_Code (Cell);
         Image (Place + 3) := Hex_Pair (Id) (1);
         Image (Place + 4) := Hex_Pair (Id) (2);
         Place := Place + 5;
      end loop;
      return Image;
   end Row_Image;

   procedure Write_Map_File
     (Path : String;
      Version : String;
      M : City;
      Tiles : Placeholder.Tileset)
   is
      File : Ada.Text_IO.File_Type;
   begin
      Ada.Text_IO.Create (File, Ada.Text_IO.Out_File, Path);
      Ada.Text_IO.Put_Line (File, "{");
      Ada.Text_IO.Put_Line
        (File, "  ""version"": """ & Version & """,");
      Ada.Text_IO.Put_Line
        (File,
         "  ""seed"": " & Trim (RNG.Word'Image (Layout_Seed (M)))
         & ",");
      Ada.Text_IO.Put_Line
        (File, "  ""width"": " & Trim (Integer'Image (M.Width)) & ",");
      Ada.Text_IO.Put_Line
        (File,
         "  ""height"": " & Trim (Integer'Image (M.Height)) & ",");
      Ada.Text_IO.Put_Line (File, "  ""legend"": {");
      Ada.Text_IO.Put_Line (File, "    ""."": ""open"",");
      Ada.Text_IO.Put_Line (File, "    ""+"": ""road"",");
      Ada.Text_IO.Put_Line (File, "    ""="": ""pavement"",");
      Ada.Text_IO.Put_Line (File, "    ""B"": ""building"",");
      Ada.Text_IO.Put_Line (File, "    ""~"": ""water""");
      Ada.Text_IO.Put_Line (File, "  },");
      Ada.Text_IO.Put_Line (File, "  ""rows"": [");
      for Y in 1 .. M.Height loop
         Ada.Text_IO.Put
           (File, "    """ & Row_Image (M, Y, Tiles) & """");
         if Y < M.Height then
            Ada.Text_IO.Put_Line (File, ",");
         else
            Ada.Text_IO.New_Line (File);
         end if;
      end loop;
      Ada.Text_IO.Put_Line (File, "  ],");
      Write_Paths (File, M);
      Ada.Text_IO.Put_Line (File, ",");
      Write_Motion (File, M);
      Ada.Text_IO.Put_Line (File, "}");
      Ada.Text_IO.Close (File);
   exception
      when others =>
         if Ada.Text_IO.Is_Open (File) then
            Ada.Text_IO.Close (File);
         end if;
         raise;
   end Write_Map_File;

   procedure Write_Index (Path : String; Version : String) is
      File : Ada.Text_IO.File_Type;
      Seed : RNG.Word;
   begin
      Ada.Text_IO.Create (File, Ada.Text_IO.Out_File, Path);
      Ada.Text_IO.Put_Line (File, "{");
      Ada.Text_IO.Put_Line
        (File, "  ""version"": """ & Version & """,");
      Ada.Text_IO.Put_Line (File, "  ""maps"": [");
      for Index in Export_Seeds'Range loop
         Seed := Export_Seeds (Index);
         Ada.Text_IO.Put
           (File,
            "    {""seed"": " & Trim (RNG.Word'Image (Seed))
            & ", ""file"": ""seed-" & Trim (RNG.Word'Image (Seed))
            & ".json""}");
         Ada.Text_IO.Put_Line (File, ",");
      end loop;
      Ada.Text_IO.Put_Line
        (File,
         "    {""seed"": 0, ""file"": ""encounter.json"",");
      Ada.Text_IO.Put_Line
        (File, "     ""label"": ""Two peds""}");
      Ada.Text_IO.Put_Line (File, "  ]");
      Ada.Text_IO.Put_Line (File, "}");
      Ada.Text_IO.Close (File);
   exception
      when others =>
         if Ada.Text_IO.Is_Open (File) then
            Ada.Text_IO.Close (File);
         end if;
         raise;
   end Write_Index;

   function Bare_Directory (Directory : String) return String is
   begin
      if Directory'Length > 1
        and then Directory (Directory'Last) = '/'
      then
         return Directory (Directory'First .. Directory'Last - 1);
      end if;
      return Directory;
   end Bare_Directory;

   function Locate
     (M : City; Kind : Terrain; From_End : Boolean) return Point
   is
      Found : Point := (X => 1, Y => 1);
      Seen  : Boolean := False;
   begin
      for Y in 1 .. M.Height loop
         for X in 1 .. M.Width loop
            if M.Cell (X, Y).Kind = Kind then
               Found := (X => X, Y => Y);
               Seen := True;
               if not From_End then
                  return Found;
               end if;
            end if;
         end loop;
      end loop;
      pragma Assert (Seen);
      return Found;
   end Locate;

   function Mode_Token (How : Path.Mode) return String is
   begin
      case How is
         when Path.Walk =>
            return "walk";
         when Path.Drive =>
            return "drive";
      end case;
   end Mode_Token;

   function Status_Token (Kind : Path.Status) return String is
   begin
      case Kind is
         when Path.Found =>
            return "found";
         when Path.No_Path =>
            return "no_path";
         when Path.Budget_Exceeded =>
            return "budget_exceeded";
      end case;
   end Status_Token;

   procedure Put_Route
     (File : Ada.Text_IO.File_Type;
      M : City;
      Label : String;
      How : Path.Mode;
      Start, Goal : Point;
      Last_Item : Boolean)
   is
      Route : constant Path.Result := Path.Find (M, Start, Goal, How);
   begin
      Ada.Text_IO.Put_Line (File, "    {");
      Ada.Text_IO.Put_Line
        (File, "      ""label"": """ & Label & """,");
      Ada.Text_IO.Put_Line
        (File, "      ""mode"": """ & Mode_Token (How) & """,");
      Ada.Text_IO.Put_Line
        (File,
         "      ""status"": """ & Status_Token (Path.Kind (Route))
         & """,");
      Ada.Text_IO.Put_Line
        (File,
         "      ""start"": {""x"":" & Trim (Integer'Image (Start.X))
         & ", ""y"":" & Trim (Integer'Image (Start.Y)) & "},");
      Ada.Text_IO.Put_Line
        (File,
         "      ""goal"": {""x"":" & Trim (Integer'Image (Goal.X))
         & ", ""y"":" & Trim (Integer'Image (Goal.Y)) & "},");
      Ada.Text_IO.Put (File, "      ""tiles"": [");
      if Path.Kind (Route) = Path.Found then
         Ada.Text_IO.New_Line (File);
         for I in 1 .. Path.Length (Route) loop
            Ada.Text_IO.Put
              (File,
               "        {""x"":"
               & Trim (Integer'Image (Path.Step (Route, I).X))
               & ", ""y"":"
               & Trim (Integer'Image (Path.Step (Route, I).Y))
               & "}");
            if I < Path.Length (Route) then
               Ada.Text_IO.Put_Line (File, ",");
            else
               Ada.Text_IO.New_Line (File);
            end if;
         end loop;
         Ada.Text_IO.Put (File, "      ]");
      else
         Ada.Text_IO.Put (File, "]");
      end if;
      Ada.Text_IO.New_Line (File);
      if Last_Item then
         Ada.Text_IO.Put_Line (File, "    }");
      else
         Ada.Text_IO.Put_Line (File, "    },");
      end if;
   end Put_Route;

   function Route_Length
     (M : City; From, To : Point) return Natural
   is
      Route : constant Path.Result :=
        Path.Find (M, From, To, Path.Walk);
   begin
      if Path.Kind (Route) /= Path.Found then
         return 0;
      end if;
      return Path.Length (Route);
   end Route_Length;

   function Seek
     (M : City; Origin : Point; Low, High : Positive) return Point
   is
      X : Integer;
      Y : Integer;
      Steps : Natural;
   begin
      for DY in -20 .. 20 loop
         for DX in -20 .. 20 loop
            X := Origin.X + DX;
            Y := Origin.Y + DY;
            if In_Bounds (M, X, Y)
              and then (X /= Origin.X or else Y /= Origin.Y)
              and then M.Cell (X, Y).Walkable
            then
               Steps := Route_Length
                 (M, Origin, (X => X, Y => Y));
               if Steps >= Low and then Steps <= High then
                  return (X => X, Y => Y);
               end if;
            end if;
         end loop;
      end loop;
      pragma Assert (False);
      return Origin;
   end Seek;

   function Side_Tile
     (M : City; Origin, Avoid : Point) return Point
   is
      Next : Point;
   begin
      for Dir in Four_Way loop
         if Has_Neighbour_4 (M, Origin.X, Origin.Y, Dir) then
            Next := Neighbour_4 (M, Origin.X, Origin.Y, Dir);
            if Next /= Avoid
              and then M.Cell (Next.X, Next.Y).Walkable
            then
               return Next;
            end if;
         end if;
      end loop;
      return Seek (M, Origin, 2, 4);
   end Side_Tile;

   function Mission_Of (M : City) return Mission_Points is
      Start  : constant Point := Locate (M, Pavement, False);
      Goal   : constant Point := Seek (M, Start, 4, 7);
      Route  : constant Path.Result :=
        Path.Find (M, Start, Goal, Path.Walk);
      Second : Point;
   begin
      pragma Assert (Path.Kind (Route) = Path.Found);
      pragma Assert (Path.Length (Route) > 1);
      Second := Path.Step (Route, 2);
      return
        (Leader_At => Start,
         Leader_Goal => Goal,
         Follower_At => Side_Tile (M, Start, Second),
         Waypoint => Seek (M, Side_Tile (M, Start, Second), 2, 4),
         Item_At => Seek (M, Goal, 2, 5));
   end Mission_Of;

   function Script (M : City) return Act.Shot_Lists.Vector is
      Plan  : constant Mission_Points := Mission_Of (M);
      Group : Act.Cast (1 .. 2);
      Items : Act.Bag (1 .. 1);
   begin
      Group (1) := Act.Recruit (1, Plan.Leader_At, M);
      Group (2) := Act.Recruit (2, Plan.Follower_At, M);
      Items (1) :=
        (Ident => 1,
         X => Plan.Item_At.X,
         Y => Plan.Item_At.Y,
         Here => True);
      Act.Order
        (Group, 1,
         (1 => Act.Make_Walk (Plan.Leader_Goal)),
         Act.Replace);
      Act.Order
        (Group, 2,
         (1 => Act.Make_Walk (Plan.Waypoint),
          2 => Act.Make_Wait (2),
          3 => Act.Make_Turn (East),
          4 => Act.Make_Follow (1),
          5 => Act.Make_Walk (Plan.Item_At),
          6 => Act.Make_Pick (1)),
         Act.Replace);
      return Act.Run (M, Group, Items, 800);
   end Script;

   procedure Write_Action_Frame
     (File : Ada.Text_IO.File_Type;
      Shot : Act.Snapshot;
      Last_Item : Boolean)
   is
   begin
      Ada.Text_IO.Put (File, "          {""t"":");
      Ada.Text_IO.Put (File, Trim (Integer'Image (Shot.Tick)));
      Ada.Text_IO.Put (File, ",""x"":");
      Ada.Text_IO.Put (File, Trim (Integer'Image (Shot.X)));
      Ada.Text_IO.Put (File, ",""y"":");
      Ada.Text_IO.Put (File, Trim (Integer'Image (Shot.Y)));
      Ada.Text_IO.Put (File, ",""along"":");
      Ada.Text_IO.Put (File, Trim (Integer'Image (Shot.Along)));
      Ada.Text_IO.Put (File, ",""facing"":""");
      Ada.Text_IO.Put (File, Facing_Token (Shot.Facing));
      Ada.Text_IO.Put (File, """,""state"":""");
      Ada.Text_IO.Put (File, State_Token (Shot.State));
      Ada.Text_IO.Put (File, """,""action"":""");
      if Shot.Has_Action then
         Ada.Text_IO.Put
           (File, Act.Token_Strings.To_String (Shot.Action));
      end if;
      Ada.Text_IO.Put (File, """,""queue"":[");
      for I in 1 .. Shot.Rest_Count loop
         if I > 1 then
            Ada.Text_IO.Put (File, ",");
         end if;
         Ada.Text_IO.Put (File, """");
         Ada.Text_IO.Put
           (File, Act.Token_Strings.To_String (Shot.Rest (I)));
         Ada.Text_IO.Put (File, """");
      end loop;
      Ada.Text_IO.Put (File, "],""item_present"":");
      if Shot.Item_Here then
         Ada.Text_IO.Put (File, "true");
      else
         Ada.Text_IO.Put (File, "false");
      end if;
      Ada.Text_IO.Put (File, ",""health"":");
      Ada.Text_IO.Put (File, Trim (Integer'Image (Shot.Health)));
      Ada.Text_IO.Put (File, ",""ammo"":");
      Ada.Text_IO.Put (File, Trim (Integer'Image (Shot.Ammo)));
      Ada.Text_IO.Put (File, ",""alive"":");
      if Shot.Alive then
         Ada.Text_IO.Put (File, "true");
      else
         Ada.Text_IO.Put (File, "false");
      end if;
      if Shot.Fired then
         Ada.Text_IO.Put (File, ",""shot"":{""hit"":");
         if Shot.Landed then
            Ada.Text_IO.Put (File, "true");
         else
            Ada.Text_IO.Put (File, "false");
         end if;
         Ada.Text_IO.Put (File, ",""x"":");
         Ada.Text_IO.Put (File, Trim (Integer'Image (Shot.At_X)));
         Ada.Text_IO.Put (File, ",""y"":");
         Ada.Text_IO.Put (File, Trim (Integer'Image (Shot.At_Y)));
         Ada.Text_IO.Put (File, "}}");
      else
         Ada.Text_IO.Put (File, ",""shot"":null}");
      end if;
      if Last_Item then
         Ada.Text_IO.New_Line (File);
      else
         Ada.Text_IO.Put_Line (File, ",");
      end if;
   end Write_Action_Frame;

   procedure Write_Script_Ped
     (File : Ada.Text_IO.File_Type;
      Trace : Act.Shot_Lists.Vector;
      Who : Peds.Ped_Id;
      Last_Item : Boolean)
   is
      Count : Natural := 0;
      Seen  : Natural := 0;
   begin
      for I in Trace.First_Index .. Trace.Last_Index loop
         if Trace (I).Ident = Who then
            Count := Count + 1;
         end if;
      end loop;
      Ada.Text_IO.Put_Line (File, "      {");
      Ada.Text_IO.Put (File, "        ""id"": ");
      Ada.Text_IO.Put (File, Trim (Integer'Image (Integer (Who))));
      Ada.Text_IO.Put_Line (File, ",");
      Ada.Text_IO.Put_Line (File, "        ""frames"": [");
      for I in Trace.First_Index .. Trace.Last_Index loop
         if Trace (I).Ident = Who then
            Seen := Seen + 1;
            Write_Action_Frame (File, Trace (I), Seen = Count);
         end if;
      end loop;
      Ada.Text_IO.Put_Line (File, "        ]");
      if Last_Item then
         Ada.Text_IO.Put_Line (File, "      }");
      else
         Ada.Text_IO.Put_Line (File, "      },");
      end if;
   end Write_Script_Ped;

   procedure Write_Script (File : Ada.Text_IO.File_Type; M : City) is
      Plan  : constant Mission_Points := Mission_Of (M);
      Trace : constant Act.Shot_Lists.Vector := Script (M);
   begin
      pragma Assert (not Trace.Is_Empty);
      pragma Assert (not Trace (Trace.Last_Index).Item_Here);
      Ada.Text_IO.Put_Line (File, "    {");
      Ada.Text_IO.Put_Line
        (File, "      ""label"": ""Scripted mission"",");
      Ada.Text_IO.Put (File, "      ""steps_per_tile"": ");
      Ada.Text_IO.Put
        (File, Trim (Integer'Image (Peds.Steps_Per_Tile)));
      Ada.Text_IO.Put_Line (File, ",");
      Ada.Text_IO.Put (File, "      ""item"": {""id"": 1, ""name"": ");
      Ada.Text_IO.Put (File, """case"", ""x"":");
      Ada.Text_IO.Put (File, Trim (Integer'Image (Plan.Item_At.X)));
      Ada.Text_IO.Put (File, ", ""y"":");
      Ada.Text_IO.Put (File, Trim (Integer'Image (Plan.Item_At.Y)));
      Ada.Text_IO.Put_Line (File, "},");
      Ada.Text_IO.Put_Line (File, "      ""peds"": [");
      Write_Script_Ped (File, Trace, 1, False);
      Write_Script_Ped (File, Trace, 2, True);
      Ada.Text_IO.Put_Line (File, "      ]");
      Ada.Text_IO.Put_Line (File, "    },");
   end Write_Script;

   type Duel_Points is record
      Shooter : Point;
      Target  : Point;
   end record;

   function Fight_Of (M : City) return Duel_Points;
   function Firefight (M : City) return Act.Shot_Lists.Vector;
   procedure Write_Fight (File : Ada.Text_IO.File_Type; M : City);

   function Fight_Of (M : City) return Duel_Points is
      Start : constant Point := Locate (M, Pavement, False);
      X     : Integer;
      Y     : Integer;
      There : Point;
      Dist  : Natural;
   begin
      for DY in -16 .. 16 loop
         for DX in -16 .. 16 loop
            X := Start.X + DX;
            Y := Start.Y + DY;
            if In_Bounds (M, X, Y)
              and then M.Cell (X, Y).Walkable
            then
               There := (X => X, Y => Y);
               Dist := Natural'Max
                 (abs (There.X - Start.X), abs (There.Y - Start.Y));
               if Dist >= 5 and then Dist <= 7
                 and then not Shots.Blocked (M, Start, There)
               then
                  return (Shooter => Start, Target => There);
               end if;
            end if;
         end loop;
      end loop;
      pragma Assert (False);
      return (Shooter => Start, Target => Start);
   end Fight_Of;

   function Firefight (M : City) return Act.Shot_Lists.Vector is
      Duel  : constant Duel_Points := Fight_Of (M);
      Group : Act.Cast (1 .. 2);
      Items : Act.Bag (1 .. 1);
      Gun   : constant Weapons.Kind := Weapons.Pistol;
   begin
      Group (1) :=
        Act.Recruit (1, Duel.Shooter, M, Layout_Seed (M));
      Group (2) :=
        Act.Recruit (2, Duel.Target, M, Layout_Seed (M));
      Act.Arm
        (Group, 1, Gun, Weapons.Profile (Gun).Magazine);
      Act.Order
        (Group, 1,
         (1 => Act.Make_Shoot (2, Gun)),
         Act.Replace);
      Act.Order
        (Group, 2, (1 => Act.Make_Wait (80)), Act.Replace);
      Items (1) := (Ident => 1, X => 1, Y => 1, Here => False);
      return Act.Run (M, Group, Items, 200);
   end Firefight;

   procedure Write_Fight (File : Ada.Text_IO.File_Type; M : City) is
      Trace : constant Act.Shot_Lists.Vector := Firefight (M);
   begin
      pragma Assert (not Trace.Is_Empty);
      Ada.Text_IO.Put_Line (File, "    {");
      Ada.Text_IO.Put_Line
        (File, "      ""label"": ""Firefight"",");
      Ada.Text_IO.Put (File, "      ""steps_per_tile"": ");
      Ada.Text_IO.Put
        (File, Trim (Integer'Image (Peds.Steps_Per_Tile)));
      Ada.Text_IO.Put_Line (File, ",");
      Ada.Text_IO.Put_Line (File, "      ""peds"": [");
      Write_Script_Ped (File, Trace, 1, False);
      Write_Script_Ped (File, Trace, 2, True);
      Ada.Text_IO.Put_Line (File, "      ]");
      Ada.Text_IO.Put_Line (File, "    }");
   end Write_Fight;

   procedure Write_Paths
     (File : Ada.Text_IO.File_Type; M : City)
   is
      Walk_A : constant Point := Locate (M, Pavement, False);
      Walk_B : constant Point := Locate (M, Pavement, True);
      Road_A : constant Point := Locate (M, Road, False);
      Road_B : constant Point := Locate (M, Road, True);
      River  : constant Point := Locate (M, Water, False);
      Plan   : constant Mission_Points := Mission_Of (M);
   begin
      Ada.Text_IO.Put_Line (File, "  ""paths"": [");
      Put_Route
        (File, M, "Walk across the blocks", Path.Walk,
         Walk_A, Walk_B, False);
      Put_Route
        (File, M, "Drive along the roads", Path.Drive,
         Road_A, Road_B, False);
      Put_Route
        (File, M, "Walk into the river", Path.Walk,
         Walk_A, River, False);
      Put_Route
        (File, M, "Scripted mission", Path.Walk,
         Plan.Follower_At, Plan.Item_At, False);
      Put_Route
        (File, M, "Firefight", Path.Walk,
         Fight_Of (M).Shooter, Fight_Of (M).Target, True);
      Ada.Text_IO.Put_Line (File, "  ]");
   end Write_Paths;

   function Facing_Token (Dir : Eight_Way) return String is
   begin
      case Dir is
         when North =>
            return "north";
         when East =>
            return "east";
         when South =>
            return "south";
         when West =>
            return "west";
         when North_East =>
            return "north_east";
         when South_East =>
            return "south_east";
         when South_West =>
            return "south_west";
         when North_West =>
            return "north_west";
      end case;
   end Facing_Token;

   function State_Token (Kind : Peds.State_Kind) return String is
   begin
      case Kind is
         when Peds.Standing =>
            return "standing";
         when Peds.Walking =>
            return "walking";
         when Peds.Arrived =>
            return "arrived";
      end case;
   end State_Token;

   procedure Write_Frame
     (File : Ada.Text_IO.File_Type;
      Item : Peds.Frame;
      Last_Item : Boolean)
   is
   begin
      Ada.Text_IO.Put (File, "          {""t"":");
      Ada.Text_IO.Put (File, Trim (Integer'Image (Item.Tick)));
      Ada.Text_IO.Put (File, ",""x"":");
      Ada.Text_IO.Put (File, Trim (Integer'Image (Item.X)));
      Ada.Text_IO.Put (File, ",""y"":");
      Ada.Text_IO.Put (File, Trim (Integer'Image (Item.Y)));
      Ada.Text_IO.Put (File, ",""along"":");
      Ada.Text_IO.Put (File, Trim (Integer'Image (Item.Along)));
      Ada.Text_IO.Put (File, ",""facing"":""");
      Ada.Text_IO.Put (File, Facing_Token (Item.Facing));
      Ada.Text_IO.Put (File, """,""state"":""");
      Ada.Text_IO.Put (File, State_Token (Item.State));
      Ada.Text_IO.Put (File, """}");
      if Last_Item then
         Ada.Text_IO.New_Line (File);
      else
         Ada.Text_IO.Put_Line (File, ",");
      end if;
   end Write_Frame;

   procedure Write_Ped_Trace
     (File : Ada.Text_IO.File_Type;
      Trace : Peds.Frame_Lists.Vector;
      Who : Peds.Ped_Id;
      Last_Item : Boolean)
   is
      Count : Natural := 0;
      Seen  : Natural := 0;
   begin
      for I in Trace.First_Index .. Trace.Last_Index loop
         if Trace (I).Ident = Who then
            Count := Count + 1;
         end if;
      end loop;
      Ada.Text_IO.Put_Line (File, "      {");
      Ada.Text_IO.Put (File, "        ""id"": ");
      Ada.Text_IO.Put (File, Trim (Integer'Image (Integer (Who))));
      Ada.Text_IO.Put_Line (File, ",");
      Ada.Text_IO.Put_Line (File, "        ""frames"": [");
      for I in Trace.First_Index .. Trace.Last_Index loop
         if Trace (I).Ident = Who then
            Seen := Seen + 1;
            Write_Frame (File, Trace (I), Seen = Count);
         end if;
      end loop;
      Ada.Text_IO.Put_Line (File, "        ]");
      if Last_Item then
         Ada.Text_IO.Put_Line (File, "      }");
      else
         Ada.Text_IO.Put_Line (File, "      },");
      end if;
   end Write_Ped_Trace;

   procedure Write_Motion
     (File : Ada.Text_IO.File_Type; M : City)
   is
      Walk_A : constant Point := Locate (M, Pavement, False);
      Walk_B : constant Point := Locate (M, Pavement, True);
      Walker : constant Peds.Ped := Peds.Spawn (1, Walk_A, Walk_B, M);
      Route  : constant Path.Result :=
        Path.Find (M, Walk_A, Walk_B, Path.Walk);
      Span   : constant Natural :=
        Peds.Ticks_To_Cross (Peds.Default_Speed);
   begin
      pragma Assert (Path.Kind (Route) = Path.Found);
      pragma Assert (Path.Length (Route) > 1);
      declare
         Cap   : constant Natural :=
           (Path.Length (Route) - 1) * Span;
         Trace : constant Peds.Frame_Lists.Vector :=
           Peds.Run (M, (1 => Walker), Cap);
      begin
         Ada.Text_IO.Put_Line (File, "  ""motion"": [");
         Ada.Text_IO.Put_Line (File, "    {");
         Ada.Text_IO.Put_Line
           (File, "      ""label"": ""Walk across the blocks"",");
         Ada.Text_IO.Put (File, "      ""steps_per_tile"": ");
         Ada.Text_IO.Put
           (File, Trim (Integer'Image (Peds.Steps_Per_Tile)));
         Ada.Text_IO.Put_Line (File, ",");
         Ada.Text_IO.Put_Line (File, "      ""peds"": [");
         Write_Ped_Trace (File, Trace, 1, True);
         Ada.Text_IO.Put_Line (File, "      ]");
         Ada.Text_IO.Put_Line (File, "    },");
         Write_Script (File, M);
         Write_Fight (File, M);
         Ada.Text_IO.Put_Line (File, "  ]");
      end;
   end Write_Motion;

   procedure Write_Encounter
     (Target : String;
      Version : String;
      Tiles : Placeholder.Tileset)
   is
      Hall  : constant City := Blank (5, 3);
      East  : constant Peds.Ped :=
        Peds.Spawn (1, (X => 1, Y => 2), (X => 5, Y => 2), Hall);
      West  : constant Peds.Ped :=
        Peds.Spawn (2, (X => 5, Y => 2), (X => 1, Y => 2), Hall);
      Trace : constant Peds.Frame_Lists.Vector :=
        Peds.Run (Hall, (1 => East, 2 => West), 400);
      File  : Ada.Text_IO.File_Type;
   begin
      Ada.Text_IO.Create (File, Ada.Text_IO.Out_File, Target);
      Ada.Text_IO.Put_Line (File, "{");
      Ada.Text_IO.Put_Line
        (File, "  ""version"": """ & Version & """,");
      Ada.Text_IO.Put_Line (File, "  ""seed"": 0,");
      Ada.Text_IO.Put_Line (File, "  ""label"": ""Two peds"",");
      Ada.Text_IO.Put_Line (File, "  ""width"": 5,");
      Ada.Text_IO.Put_Line (File, "  ""height"": 3,");
      Ada.Text_IO.Put_Line (File, "  ""legend"": {");
      Ada.Text_IO.Put_Line (File, "    ""."": ""open"",");
      Ada.Text_IO.Put_Line (File, "    ""+"": ""road"",");
      Ada.Text_IO.Put_Line (File, "    ""="": ""pavement"",");
      Ada.Text_IO.Put_Line (File, "    ""B"": ""building"",");
      Ada.Text_IO.Put_Line (File, "    ""~"": ""water""");
      Ada.Text_IO.Put_Line (File, "  },");
      Ada.Text_IO.Put_Line (File, "  ""rows"": [");
      for Y in 1 .. Hall.Height loop
         Ada.Text_IO.Put
           (File, "    """ & Row_Image (Hall, Y, Tiles) & """");
         if Y < Hall.Height then
            Ada.Text_IO.Put_Line (File, ",");
         else
            Ada.Text_IO.New_Line (File);
         end if;
      end loop;
      Ada.Text_IO.Put_Line (File, "  ],");
      Ada.Text_IO.Put_Line (File, "  ""paths"": [");
      Put_Route
        (File, Hall, "Two peds meet", Path.Walk,
         (X => 1, Y => 2), (X => 5, Y => 2), True);
      Ada.Text_IO.Put_Line (File, "  ],");
      Ada.Text_IO.Put_Line (File, "  ""motion"": [");
      Ada.Text_IO.Put_Line (File, "    {");
      Ada.Text_IO.Put_Line
        (File, "      ""label"": ""Two peds meet"",");
      Ada.Text_IO.Put (File, "      ""steps_per_tile"": ");
      Ada.Text_IO.Put
        (File, Trim (Integer'Image (Peds.Steps_Per_Tile)));
      Ada.Text_IO.Put_Line (File, ",");
      Ada.Text_IO.Put_Line (File, "      ""peds"": [");
      Write_Ped_Trace (File, Trace, 1, False);
      Write_Ped_Trace (File, Trace, 2, True);
      Ada.Text_IO.Put_Line (File, "      ]");
      Ada.Text_IO.Put_Line (File, "    }");
      Ada.Text_IO.Put_Line (File, "  ]");
      Ada.Text_IO.Put_Line (File, "}");
      Ada.Text_IO.Close (File);
   exception
      when others =>
         if Ada.Text_IO.Is_Open (File) then
            Ada.Text_IO.Close (File);
         end if;
         raise;
   end Write_Encounter;

   function Parent_Directory (Path : String) return String is
      Bare : constant String := Bare_Directory (Path);
      Last : Natural := Bare'Last;
   begin
      while Last >= Bare'First and then Bare (Last) /= '/' loop
         Last := Last - 1;
      end loop;
      if Last > Bare'First then
         return Bare (Bare'First .. Last - 1);
      end if;
      return ".";
   end Parent_Directory;

   procedure Export_Maps (Directory : String; Version : String) is
      Folder : constant String := Bare_Directory (Directory);
      Store  : constant Disk.Disk :=
        Disk.Open (Parent_Directory (Folder));
      Tiles  : constant Placeholder.Tileset :=
        Placeholder.Load (Store);
   begin
      Ada.Directories.Create_Path (Folder);
      for Index in Export_Seeds'Range loop
         declare
            M : constant City :=
              Test_Layout (Export_Seeds (Index), Parameters.Defaults);
         begin
            Write_Map_File
              (Folder & "/seed-"
               & Trim (RNG.Word'Image (Export_Seeds (Index)))
               & ".json",
               Version,
               M,
               Tiles);
         end;
      end loop;
      Write_Encounter
        (Folder & "/encounter.json", Version, Tiles);
      Write_Index (Folder & "/index.json", Version);
   end Export_Maps;

end Megacorp.Map;
