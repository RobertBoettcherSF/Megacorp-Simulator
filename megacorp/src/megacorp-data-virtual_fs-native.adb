--  SPDX-License-Identifier: MIT
--  Copyright (c) 2026 Robert Boettcher

with Ada.Directories;
with Ada.Streams.Stream_IO;

package body Megacorp.Data.Virtual_FS.Native is
   use type Ada.Containers.Count_Type;
   use type Ada.Directories.File_Kind;
   use type Ada.Streams.Stream_IO.Count;

   function Full (Store : Disk; Path : String) return String;
   procedure Sort (Names : in out Name_Lists.Vector);

   function Open (Root : String) return Disk is
      Result : Disk (Root'Length);
   begin
      Result.Root := Root;
      return Result;
   end Open;

   function Full (Store : Disk; Path : String) return String is
   begin
      if Path'Length = 0 then
         return Store.Root;
      elsif Store.Root (Store.Root'Last) = '/' then
         return Store.Root & Path;
      else
         return Store.Root & "/" & Path;
      end if;
   end Full;

   overriding function Exists
     (Store : Disk; Path : String) return Boolean
   is
      Name : constant String := Full (Store, Path);
   begin
      if not Is_Logical_Path (Path) then
         return False;
      end if;
      return Ada.Directories.Exists (Name)
        and then Ada.Directories.Kind (Name)
          = Ada.Directories.Ordinary_File;
   end Exists;

   overriding function Read
     (Store : Disk; Path : String) return String
   is
      use Ada.Streams;
      Name : constant String := Full (Store, Path);
      File : Stream_IO.File_Type;
      Size : Stream_IO.Count;
   begin
      pragma Assert (Exists (Store, Path));
      Stream_IO.Open (File, Stream_IO.In_File, Name);
      Size := Stream_IO.Size (File);
      declare
         Data : Stream_Element_Array
           (1 .. Stream_Element_Offset (Size));
         Last : Stream_Element_Offset;
         Text : String (1 .. Natural (Size));
      begin
         if Size > 0 then
            Stream_IO.Read (File, Data, Last);
            for I in 1 .. Natural (Size) loop
               Text (I) := Character'Val
                 (Stream_Element'Pos
                    (Data (Stream_Element_Offset (I))));
            end loop;
         end if;
         Stream_IO.Close (File);
         return Text;
      end;
   exception
      when others =>
         if Stream_IO.Is_Open (File) then
            Stream_IO.Close (File);
         end if;
         raise;
   end Read;

   procedure Sort (Names : in out Name_Lists.Vector) is
      J : Natural;
   begin
      if Names.Length < 2 then
         return;
      end if;
      for I in 2 .. Positive (Names.Length) loop
         J := I;
         while J > 1
           and then Names.Element (J) < Names.Element (J - 1)
         loop
            Names.Swap (J, J - 1);
            J := J - 1;
         end loop;
      end loop;
   end Sort;

   overriding function List
     (Store : Disk; Path : String) return Name_Lists.Vector
   is
      Name   : constant String := Full (Store, Path);
      Search : Ada.Directories.Search_Type;
      Item   : Ada.Directories.Directory_Entry_Type;
      Names  : Name_Lists.Vector;
   begin
      if not Ada.Directories.Exists (Name)
        or else Ada.Directories.Kind (Name) /= Ada.Directories.Directory
      then
         return Names;
      end if;
      Ada.Directories.Start_Search
        (Search, Name, "*",
         (Ada.Directories.Ordinary_File => True, others => False));
      while Ada.Directories.More_Entries (Search) loop
         Ada.Directories.Get_Next_Entry (Search, Item);
         Names.Append (Ada.Directories.Simple_Name (Item));
      end loop;
      Ada.Directories.End_Search (Search);
      Sort (Names);
      return Names;
   exception
      when others =>
         Ada.Directories.End_Search (Search);
         raise;
   end List;

end Megacorp.Data.Virtual_FS.Native;
