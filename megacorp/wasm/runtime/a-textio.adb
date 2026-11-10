--  SPDX-License-Identifier: MIT
--  Copyright (c) 2026 Robert Boettcher

package body Ada.Text_IO is
   procedure Create
     (File : in out File_Type;
      Mode : File_Mode;
      Name : String)
   is
      pragma Unreferenced (Mode, Name);
   begin
      File.Open := True;
   end Create;

   procedure Close (File : in out File_Type) is
   begin
      File.Open := False;
   end Close;

   procedure Put (File : File_Type; Item : String) is
      pragma Unreferenced (File, Item);
   begin
      null;
   end Put;

   procedure Put_Line (File : File_Type; Item : String) is
      pragma Unreferenced (File, Item);
   begin
      null;
   end Put_Line;

   procedure Put_Line (Item : String) is
      pragma Unreferenced (Item);
   begin
      null;
   end Put_Line;

   procedure New_Line (File : File_Type) is
      pragma Unreferenced (File);
   begin
      null;
   end New_Line;

   function Is_Open (File : File_Type) return Boolean is
   begin
      return File.Open;
   end Is_Open;
end Ada.Text_IO;
