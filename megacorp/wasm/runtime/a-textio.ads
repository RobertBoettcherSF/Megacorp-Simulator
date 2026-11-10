--  SPDX-License-Identifier: MIT
--  Copyright (c) 2026 Robert Boettcher

--  Stub. The live wasm entry never calls these. The generator
--  still mentions them, so the unit has to exist to compile.
package Ada.Text_IO is
   type File_Type is limited private;
   type File_Mode is (In_File, Out_File, Append_File);

   procedure Create
     (File : in out File_Type;
      Mode : File_Mode;
      Name : String);

   procedure Close (File : in out File_Type);
   procedure Put (File : File_Type; Item : String);
   procedure Put_Line (File : File_Type; Item : String);
   procedure Put_Line (Item : String);
   procedure New_Line (File : File_Type);
   function Is_Open (File : File_Type) return Boolean;

private
   type File_Type is record
      Open : Boolean := False;
   end record;
end Ada.Text_IO;
