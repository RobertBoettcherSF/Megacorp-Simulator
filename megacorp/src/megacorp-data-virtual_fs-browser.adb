--  SPDX-License-Identifier: MIT
--  Copyright (c) 2026 Robert Boettcher

with System;

package body Megacorp.Data.Virtual_FS.Browser is
   function Host_Exists
     (Path : System.Address;
      Length : Integer) return Integer
     with Import, Convention => C, External_Name => "host_exists";

   function Host_Length
     (Path : System.Address;
      Length : Integer) return Integer
     with Import, Convention => C, External_Name => "host_length";

   procedure Host_Read
     (Path : System.Address;
      Path_Length : Integer;
      Dest : System.Address;
      Dest_Length : Integer)
     with Import, Convention => C, External_Name => "host_read";

   procedure Host_Write
     (Path : System.Address;
      Path_Length : Integer;
      Data : System.Address;
      Data_Length : Integer)
     with Import, Convention => C, External_Name => "host_write";

   procedure Host_Append
     (Path : System.Address;
      Path_Length : Integer;
      Data : System.Address;
      Data_Length : Integer)
     with Import, Convention => C, External_Name => "host_append";

   function Open return Disk is
      Result : Disk;
   begin
      return Result;
   end Open;

   overriding function Exists
     (Store : Disk; Path : String) return Boolean
   is
      pragma Unreferenced (Store);
   begin
      if not Is_Logical_Path (Path) or else Path'Length = 0 then
         return False;
      end if;
      return Host_Exists
        (Path (Path'First)'Address, Path'Length) /= 0;
   end Exists;

   overriding function Read
     (Store : Disk; Path : String) return String
   is
      pragma Unreferenced (Store);
      Length : constant Integer :=
        Host_Length (Path (Path'First)'Address, Path'Length);
   begin
      if Length <= 0 then
         return "";
      end if;
      declare
         Result : String (1 .. Length);
      begin
         Host_Read
           (Path (Path'First)'Address, Path'Length,
            Result (1)'Address, Length);
         return Result;
      end;
   end Read;

   overriding function List
     (Store : Disk; Path : String) return Name_Lists.Vector
   is
      pragma Unreferenced (Store, Path);
      Result : Name_Lists.Vector;
   begin
      return Result;
   end List;

   overriding procedure Write
     (Store : in out Disk;
      Path : String;
      Data : String)
   is
      pragma Unreferenced (Store);
      Data_Addr : System.Address := Path (Path'First)'Address;
   begin
      if Data'Length > 0 then
         Data_Addr := Data (Data'First)'Address;
      end if;
      Host_Write
        (Path (Path'First)'Address, Path'Length,
         Data_Addr, Data'Length);
   end Write;

   overriding procedure Append
     (Store : in out Disk;
      Path : String;
      Data : String)
   is
      pragma Unreferenced (Store);
   begin
      Host_Append
        (Path (Path'First)'Address, Path'Length,
         Data (Data'First)'Address, Data'Length);
   end Append;
end Megacorp.Data.Virtual_FS.Browser;
