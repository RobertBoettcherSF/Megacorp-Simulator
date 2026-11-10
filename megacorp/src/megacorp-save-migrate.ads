--  SPDX-License-Identifier: MIT
--  Copyright (c) 2026 Robert Boettcher

--  Item 19. One pure step per format version. A file older than
--  the current format walks the chain. A newer file is not
--  passed here: the loader refuses it first.
package Megacorp.Save.Migrate is
   function Listed_Version (Text : String) return Natural;

   function Sum_Ok (Text : String) return Boolean;

   function Note (From, To : Positive) return String
     with Pre => From < To,
          Post => Note'Result'Length > 0;

   function Step (Text : String) return String
     with Pre =>
       Listed_Version (Text) in 1 .. Format_Version - 1
       and then Sum_Ok (Text),
       Post =>
         Listed_Version (Step'Result)
           = Listed_Version (Text) + 1
         and then Sum_Ok (Step'Result);

   function To_Current (Text : String) return String
     with Pre =>
       Listed_Version (Text) in 1 .. Format_Version
       and then Sum_Ok (Text),
       Post =>
         Listed_Version (To_Current'Result) = Format_Version
         and then Sum_Ok (To_Current'Result);
end Megacorp.Save.Migrate;
