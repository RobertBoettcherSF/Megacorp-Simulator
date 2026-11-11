--  SPDX-License-Identifier: MIT
--  Copyright (c) 2026 Robert Boettcher

with Interfaces;
with System;
with Megacorp.Data.Virtual_FS;
with Megacorp.Map;
with Megacorp.RNG;

--  Item 22. One city, ticked by the page.
--  JavaScript sends compact commands. This package selects,
--  orders a walk, and pans or zooms the camera. A tick moves
--  the peds and the vehicles. The same commands, replayed,
--  produce the same Digest.
package Megacorp.Play is
   View_W : constant := 480;
   View_H : constant := 480;

   procedure Open (City_Seed : RNG.Word);

   function Ready return Boolean;

   --  Code 1 tap, 2 box drag, 3 key, 4 pinch, 5 touch pan.
   --  Coordinates are city-canvas pixels. Keys are 1..4
   --  for the arrows and 5..6 for zoom out and in.
   procedure Handle (Code, A, B, C, D, E : Integer);

   procedure Run (Count : Positive)
     with Pre => Count <= 32;

   function Digest return RNG.Word;

   function Clock return Natural;

   function Actor_X (Index : Positive) return Positive
     with Pre => Ready and then Index <= 6;

   function Actor_Y (Index : Positive) return Positive
     with Pre => Ready and then Index <= 6;

   function Pixel_X (Tile : Positive) return Integer
     with Pre => Ready;

   function Pixel_Y (Tile : Positive) return Integer
     with Pre => Ready;

   function Goal_Near (Index : Positive) return Map.Point
     with Pre => Ready and then Index <= 6;

   procedure Write
     (Disk : in out Data.Virtual_FS.Backend'Class;
      Path : String)
     with Pre =>
       Ready
       and then Data.Virtual_FS.Is_Logical_Path (Path)
       and then Path'Length > 0;

   function Read
     (Disk : Data.Virtual_FS.Backend'Class;
      Path : String) return Boolean
     with Pre =>
       Ready and then Data.Virtual_FS.Exists (Disk, Path);

   function City_State return System.Address;

   function City_State_Size return Interfaces.Unsigned_32;
end Megacorp.Play;
