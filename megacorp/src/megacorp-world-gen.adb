--  SPDX-License-Identifier: MIT
--  Copyright (c) 2026 Robert Boettcher

with Ada.Characters.Handling;

package body Megacorp.World.Gen is
   type Ink is record
      Red   : Natural;
      Green : Natural;
      Blue  : Natural;
   end record;

   Palette : constant array (1 .. 8) of Ink :=
     ((220, 64, 48),
      (48, 120, 210),
      (230, 170, 40),
      (60, 170, 90),
      (160, 80, 200),
      (40, 180, 180),
      (230, 110, 40),
      (90, 90, 150));

   function Columns (Count : Positive) return Positive;
   function Syllable (Index : Positive) return String;
   function Other (Index : Positive) return Positive;
   function Capital (Word : String) return String;
   function Fit (Text : String) return Name;
   function Region_Name (G : in out RNG.Generator) return Name;
   function Corp_Name (G : in out RNG.Generator) return Name;
   procedure Join
     (Item : in out Atlas; Left, Right : Positive);
   function Linked (Item : Atlas; Left, Right : Positive) return Boolean;
   function Trim_Image (Value : Positive) return String;
   function Trim_Word (Value : RNG.Word) return String;
   function Hex (Value : Natural) return String;

   function Columns (Count : Positive) return Positive is
      Span : Positive := 1;
   begin
      while Span * Span < Count loop
         Span := Span + 1;
      end loop;
      return Span;
   end Columns;

   function Syllable (Index : Positive) return String is
   begin
      case Index is
         when 1 =>
            return "za";
         when 2 =>
            return "kor";
         when 3 =>
            return "vex";
         when 4 =>
            return "il";
         when 5 =>
            return "tha";
         when 6 =>
            return "quo";
         when 7 =>
            return "mer";
         when 8 =>
            return "dun";
         when 9 =>
            return "pax";
         when 10 =>
            return "lor";
         when 11 =>
            return "yve";
         when 12 =>
            return "ska";
         when 13 =>
            return "brin";
         when 14 =>
            return "tol";
         when 15 =>
            return "qen";
         when 16 =>
            return "aru";
         when 17 =>
            return "fex";
         when 18 =>
            return "osi";
         when 19 =>
            return "hul";
         when 20 =>
            return "nex";
         when 21 =>
            return "dra";
         when 22 =>
            return "vim";
         when 23 =>
            return "sol";
         when others =>
            return "kae";
      end case;
   end Syllable;

   function Capital (Word : String) return String is
      Result : String := Word;
   begin
      if Result'Length > 0
        and then Result (Result'First) in 'a' .. 'z'
      then
         Result (Result'First) :=
           Ada.Characters.Handling.To_Upper (Result (Result'First));
      end if;
      return Result;
   end Capital;

   function Fit (Text : String) return Name is
      Result : Name;
      Last : Natural;
   begin
      if Text'Length > Max_Name then
         Last := Max_Name;
      else
         Last := Text'Length;
      end if;
      Result.Length := Last;
      Result.Text (1 .. Last) := Text (Text'First .. Text'First + Last - 1);
      return Result;
   end Fit;

   function Other (Index : Positive) return Positive is
   begin
      if Index = 24 then
         return 1;
      end if;
      return Index + 1;
   end Other;

   function Region_Name (G : in out RNG.Generator) return Name is
      First : constant Positive := RNG.Pick (G, 1, 24);
      Second : Positive := RNG.Pick (G, 1, 24);
      Third : Positive;
   begin
      if Second = First then
         Second := Other (Second);
      end if;
      if RNG.Chance (G, 1, 3) then
         Third := RNG.Pick (G, 1, 24);
         if Third = Second then
            Third := Other (Third);
         end if;
         return Fit
           (Capital (Syllable (First)) & Syllable (Second) & " "
            & Capital (Syllable (Third)));
      end if;
      return Fit (Capital (Syllable (First)) & Syllable (Second));
   end Region_Name;

   function Corp_Name (G : in out RNG.Generator) return Name is
      First : constant Positive := RNG.Pick (G, 1, 24);
      Second : Positive := RNG.Pick (G, 1, 24);
      Tail : constant String :=
        (case RNG.Pick (G, 0, 5) is
            when 0 => "Combine",
            when 1 => "Works",
            when 2 => "Holdings",
            when 3 => "Foundry",
            when 4 => "Compact",
            when others => "Cartel");
   begin
      if Second = First then
         Second := Other (Second);
      end if;
      return Fit
        (Capital (Syllable (First)) & Syllable (Second) & " " & Tail);
   end Corp_Name;

   function Linked (Item : Atlas; Left, Right : Positive) return Boolean is
   begin
      for I in 1 .. Item.Links loop
         if (Item.Road (I).Left = Left and then Item.Road (I).Right = Right)
           or else (Item.Road (I).Left = Right
                    and then Item.Road (I).Right = Left)
         then
            return True;
         end if;
      end loop;
      return False;
   end Linked;

   procedure Join
     (Item : in out Atlas; Left, Right : Positive)
   is
   begin
      if Left = Right or else Left > Item.Regions
        or else Right > Item.Regions
        or else Linked (Item, Left, Right)
      then
         return;
      end if;
      pragma Assert (Item.Links < Max_Links);
      Item.Links := Item.Links + 1;
      Item.Road (Item.Links) := (Left => Left, Right => Right);
   end Join;

   function Connected (Item : Atlas) return Boolean is
      type Seen_List is array (1 .. Parameters.Max_Regions) of Boolean;
      Seen : Seen_List := (others => False);
      Queue : array (1 .. Parameters.Max_Regions) of Positive;
      Head : Natural := 1;
      Tail : Natural := 1;
      Reach : Natural := 1;
   begin
      Seen (1) := True;
      Queue (1) := 1;
      while Head <= Tail loop
         declare
            Here : constant Positive := Queue (Head);
         begin
            Head := Head + 1;
            for I in 1 .. Item.Links loop
               declare
                  Next : Natural := 0;
               begin
                  if Item.Road (I).Left = Here then
                     Next := Item.Road (I).Right;
                  elsif Item.Road (I).Right = Here then
                     Next := Item.Road (I).Left;
                  end if;
                  if Next in 1 .. Item.Regions and then not Seen (Next) then
                     Seen (Next) := True;
                     Tail := Tail + 1;
                     Queue (Tail) := Next;
                     Reach := Reach + 1;
                  end if;
               end;
            end loop;
         end;
      end loop;
      return Reach = Item.Regions;
   end Connected;

   function Distinct_Homes (Item : Atlas) return Boolean is
   begin
      for I in 1 .. Item.Corps loop
         for J in I + 1 .. Item.Corps loop
            if Item.Company (I).Home = Item.Company (J).Home then
               return False;
            end if;
         end loop;
         if Item.Company (I).Home > Item.Regions then
            return False;
         end if;
      end loop;
      return True;
   end Distinct_Homes;

   function Generate
     (Seed : RNG.Word;
      Size : Parameters.Generator_Parameters) return Atlas
   is
      Result : Atlas;
      World_G : RNG.Generator :=
        RNG.Child (RNG.Make (Seed), RNG.World, 1);
      Span : Positive;
      Col : Natural;
      Row : Natural;
      There : Positive;
      Pool : array (1 .. Parameters.Max_Regions) of Positive;
      Ink_Order : array (1 .. 8) of Positive;
      Swap : Positive;
      Pick : Integer;
      Best : Positive;
      Best_D : Natural;
      Dist : Natural;
      Trait_Order : array (1 .. 4) of Trait :=
        (Aggressive, Mercantile, Scientific, Secretive);
   begin
      Result.Seed := Seed;
      Result.Regions := Parameters.Region_Count (Size);
      Result.Corps := Parameters.Corporation_Count (Size);
      Result.Links := 0;
      Span := Columns (Result.Regions);
      for I in 1 .. Result.Regions loop
         declare
            Region_G : RNG.Generator :=
              RNG.Child
                (RNG.Make (Seed), RNG.Region, RNG.Stream_Index (I));
         begin
            Col := (I - 1) mod Span;
            Row := (I - 1) / Span;
            Result.Area (I).Title := Region_Name (Region_G);
            Result.Area (I).Population :=
              80 + RNG.Pick (Region_G, 0, 820);
            Result.Area (I).Tech := 15 + RNG.Pick (Region_G, 0, 70);
            Result.Area (I).Tax := 5 + RNG.Pick (Region_G, 0, 30);
            Result.Area (I).Unrest := RNG.Pick (Region_G, 0, 55);
            Result.Area (I).City := RNG.Derive
              (Seed,
               RNG.Domain_Key
                 (RNG.Region, RNG.Stream_Index (I)));
            Result.Area (I).X :=
              Col * 100 + RNG.Pick (Region_G, 0, 18);
            Result.Area (I).Y :=
              Row * 100 + RNG.Pick (Region_G, 0, 18);
            Result.Area (I).Owner := 1;
         end;
      end loop;
      for I in 1 .. Result.Regions loop
         Col := (I - 1) mod Span;
         Row := (I - 1) / Span;
         if Col + 1 < Span then
            There := Row * Span + Col + 2;
            Join (Result, I, There);
         end if;
         There := (Row + 1) * Span + Col + 1;
         Join (Result, I, There);
      end loop;
      for I in 1 .. Result.Regions loop
         Col := (I - 1) mod Span;
         Row := (I - 1) / Span;
         if Col + 1 < Span
           and then RNG.Chance (World_G, 1, 4)
         then
            There := (Row + 1) * Span + Col + 2;
            Join (Result, I, There);
         end if;
      end loop;
      for I in 1 .. Result.Regions loop
         Pool (I) := I;
      end loop;
      for I in 1 .. Result.Corps loop
         Pick := RNG.Pick (World_G, I, Result.Regions);
         Swap := Pool (I);
         Pool (I) := Pool (Pick);
         Pool (Pick) := Swap;
      end loop;
      for I in 1 .. 8 loop
         Ink_Order (I) := I;
      end loop;
      for I in 1 .. Result.Corps loop
         Pick := RNG.Pick (World_G, I, 8);
         Swap := Ink_Order (I);
         Ink_Order (I) := Ink_Order (Pick);
         Ink_Order (Pick) := Swap;
      end loop;
      for I in 1 .. 4 loop
         Pick := RNG.Pick (World_G, I, 4);
         declare
            Held : constant Trait := Trait_Order (I);
         begin
            Trait_Order (I) := Trait_Order (Pick);
            Trait_Order (Pick) := Held;
         end;
      end loop;
      for I in 1 .. Result.Corps loop
         Result.Company (I).Title := Corp_Name (World_G);
         Result.Company (I).Red := Palette (Ink_Order (I)).Red;
         Result.Company (I).Green := Palette (Ink_Order (I)).Green;
         Result.Company (I).Blue := Palette (Ink_Order (I)).Blue;
         Result.Company (I).Home := Pool (I);
         if I = 1 then
            Result.Company (I).Cash := 4000 + RNG.Pick (World_G, 0, 3000);
         else
            Result.Company (I).Cash := 6000 + RNG.Pick (World_G, 0, 8000);
         end if;
         Result.Company (I).Kind := Trait_Order ((I - 1) mod 4 + 1);
         Result.Area (Pool (I)).Owner := I;
         Result.Area (Pool (I)).Unrest :=
           Result.Area (Pool (I)).Unrest / 2;
      end loop;
      for I in 1 .. Result.Regions loop
         if I /= Result.Company (1).Home then
            Best := Result.Company (1).Home;
            Best_D := Natural'Last;
            for C in 1 .. Result.Corps loop
               if C /= 1 then
                  Dist :=
                    (Result.Area (I).X
                     - Result.Area (Result.Company (C).Home).X) ** 2
                    + (Result.Area (I).Y
                       - Result.Area (Result.Company (C).Home).Y) ** 2;
                  if Dist < Best_D then
                     Best_D := Dist;
                     Best := C;
                  end if;
               end if;
            end loop;
            if Result.Corps = 1 then
               Result.Area (I).Owner := 1;
            elsif I /= Result.Company (Best).Home then
               Result.Area (I).Owner := Best;
            end if;
         end if;
      end loop;
      return Result;
   end Generate;

   function Same (Left, Right : Atlas) return Boolean is
   begin
      if Left.Seed /= Right.Seed
        or else Left.Regions /= Right.Regions
        or else Left.Corps /= Right.Corps
        or else Left.Links /= Right.Links
      then
         return False;
      end if;
      for I in 1 .. Left.Corps loop
         if Image (Left.Company (I).Title)
             /= Image (Right.Company (I).Title)
           or else Left.Company (I).Home /= Right.Company (I).Home
           or else Left.Company (I).Cash /= Right.Company (I).Cash
           or else Left.Company (I).Kind /= Right.Company (I).Kind
           or else Left.Company (I).Red /= Right.Company (I).Red
         then
            return False;
         end if;
      end loop;
      for I in 1 .. Left.Regions loop
         if Image (Left.Area (I).Title) /= Image (Right.Area (I).Title)
           or else Left.Area (I).Owner /= Right.Area (I).Owner
           or else Left.Area (I).City /= Right.Area (I).City
           or else Left.Area (I).Population /= Right.Area (I).Population
           or else Left.Area (I).Tech /= Right.Area (I).Tech
           or else Left.Area (I).Tax /= Right.Area (I).Tax
           or else Left.Area (I).Unrest /= Right.Area (I).Unrest
         then
            return False;
         end if;
      end loop;
      for I in 1 .. Left.Links loop
         if Left.Road (I).Left /= Right.Road (I).Left
           or else Left.Road (I).Right /= Right.Road (I).Right
         then
            return False;
         end if;
      end loop;
      return True;
   end Same;

   function Hex (Value : Natural) return String is
      Glyphs : constant String := "0123456789abcdef";
   begin
      return Glyphs (Value / 16 + 1) & Glyphs (Value mod 16 + 1);
   end Hex;

   procedure Put (File : Ada.Text_IO.File_Type; Item : Atlas) is
   begin
      Ada.Text_IO.Put_Line
        (File,
         "world" & RNG.Word'Image (Item.Seed)
         & " regions" & Integer'Image (Item.Regions)
         & " corporations" & Integer'Image (Item.Corps)
         & " links" & Integer'Image (Item.Links));
      for I in 1 .. Item.Corps loop
         Ada.Text_IO.Put_Line
           (File,
            "corp" & Integer'Image (I) & " " & Image (Item.Company (I).Title)
            & " home" & Integer'Image (Item.Company (I).Home)
            & " cash" & Integer'Image (Item.Company (I).Cash)
            & " " & Item.Company (I).Kind'Image);
      end loop;
      for I in 1 .. Item.Regions loop
         Ada.Text_IO.Put_Line
           (File,
            "region" & Integer'Image (I) & " "
            & Image (Item.Area (I).Title)
            & " owner" & Integer'Image (Item.Area (I).Owner)
            & " pop" & Integer'Image (Item.Area (I).Population)
            & " tech" & Integer'Image (Item.Area (I).Tech)
            & " tax" & Integer'Image (Item.Area (I).Tax)
            & " unrest" & Integer'Image (Item.Area (I).Unrest));
      end loop;
   end Put;

   procedure Write
     (Path : String; Item : Atlas; Version : String)
   is
      File : Ada.Text_IO.File_Type;
   begin
      Ada.Text_IO.Create (File, Ada.Text_IO.Out_File, Path);
      Ada.Text_IO.Put_Line (File, "{");
      Ada.Text_IO.Put_Line
        (File, "  ""version"": """ & Version & """,");
      Ada.Text_IO.Put_Line
        (File,
         "  ""seed"": " & RNG.Word'Image (Item.Seed) & ",");
      Ada.Text_IO.Put_Line (File, "  ""corporations"": [");
      for I in 1 .. Item.Corps loop
         Ada.Text_IO.Put
           (File,
            "    {""id"": " & Integer'Image (I)
            & ", ""name"": """ & Image (Item.Company (I).Title)
            & """, ""colour"": ""#"
            & Hex (Item.Company (I).Red)
            & Hex (Item.Company (I).Green)
            & Hex (Item.Company (I).Blue)
            & """, ""home"": " & Integer'Image (Item.Company (I).Home)
            & ", ""cash"": " & Integer'Image (Item.Company (I).Cash)
            & ", ""trait"": """
            & Item.Company (I).Kind'Image & """}");
         if I = Item.Corps then
            Ada.Text_IO.New_Line (File);
         else
            Ada.Text_IO.Put_Line (File, ",");
         end if;
      end loop;
      Ada.Text_IO.Put_Line (File, "  ],");
      Ada.Text_IO.Put_Line (File, "  ""regions"": [");
      for I in 1 .. Item.Regions loop
         Ada.Text_IO.Put
           (File,
            "    {""id"": " & Integer'Image (I)
            & ", ""name"": """ & Image (Item.Area (I).Title)
            & """, ""x"": " & Integer'Image (Item.Area (I).X)
            & ", ""y"": " & Integer'Image (Item.Area (I).Y)
            & ", ""population"": "
            & Integer'Image (Item.Area (I).Population)
            & ", ""tech"": " & Integer'Image (Item.Area (I).Tech)
            & ", ""tax"": " & Integer'Image (Item.Area (I).Tax)
            & ", ""unrest"": " & Integer'Image (Item.Area (I).Unrest)
            & ", ""owner"": " & Integer'Image (Item.Area (I).Owner)
            & ", ""city_seed"": """
            & Trim_Word (Item.Area (I).City) & """"
            & ", ""city"": ""region-" & Trim_Image (I) & ".json""}");
         if I = Item.Regions then
            Ada.Text_IO.New_Line (File);
         else
            Ada.Text_IO.Put_Line (File, ",");
         end if;
      end loop;
      Ada.Text_IO.Put_Line (File, "  ],");
      Ada.Text_IO.Put_Line (File, "  ""links"": [");
      for I in 1 .. Item.Links loop
         Ada.Text_IO.Put
           (File,
            "    {""a"": " & Integer'Image (Item.Road (I).Left)
            & ", ""b"": " & Integer'Image (Item.Road (I).Right) & "}");
         if I = Item.Links then
            Ada.Text_IO.New_Line (File);
         else
            Ada.Text_IO.Put_Line (File, ",");
         end if;
      end loop;
      Ada.Text_IO.Put_Line (File, "  ]");
      Ada.Text_IO.Put_Line (File, "}");
      Ada.Text_IO.Close (File);
   exception
      when others =>
         if Ada.Text_IO.Is_Open (File) then
            Ada.Text_IO.Close (File);
         end if;
         raise;
   end Write;

   function Trim_Image (Value : Positive) return String is
      Image : constant String := Integer'Image (Value);
   begin
      return Image (Image'First + 1 .. Image'Last);
   end Trim_Image;

   function Trim_Word (Value : RNG.Word) return String is
      Image : constant String := RNG.Word'Image (Value);
   begin
      return Image (Image'First + 1 .. Image'Last);
   end Trim_Word;

end Megacorp.World.Gen;
