--  SPDX-License-Identifier: MIT
--  Copyright (c) 2026 Robert Boettcher

--  Item 27. Placeholder voices. The numbers are generated here.
--  The page plays them. It does not choose when they happen.
package Megacorp.Sound is
   type Kind is
     (Silent, Click, Gun, Hit, Death, Foot, Win, Loss, Alarm, Blip);

   type Wave is (Sine, Square, Saw, Noise);

   type Voice is record
      Shape  : Wave := Sine;
      Freq   : Natural := 440;
      Ms     : Natural := 80;
      Attack : Natural := 5;
      Gain   : Natural := 40;
   end record;

   function Tone (Which : Kind) return Voice
     with Pre => Which /= Silent;

   type Pitch is record
      Freq : Natural := 220;
      Ms   : Natural := 240;
   end record;

   type Bar is array (1 .. 8) of Pitch;

   type Scene is (Title, Map, City);

   function Loop_Of (Which : Scene) return Bar;

   Max_Events : constant := 16;

   type Event is record
      Which : Kind := Silent;
   end record;

   type Event_List is array (1 .. Max_Events) of Event;

   type Stream is record
      Count : Natural := 0;
      Item  : Event_List := (others => (Which => Silent));
   end record;

   procedure Clear (Log : in out Stream)
     with Post => Log.Count = 0;

   procedure Push (Log : in out Stream; Which : Kind)
     with Post =>
       Log.Count <= Max_Events
       and then Log.Count >= Log'Old.Count
       and then (if Log'Old.Count < Max_Events
                 and then Which /= Silent
                 then Log.Count = Log'Old.Count + 1);

   Tape_Max : constant := 256;

   type Code_List is array (1 .. Tape_Max) of Kind;

   type Tape is record
      Count : Natural := 0;
      Code  : Code_List := (others => Silent);
   end record;

   procedure Add (Item : in out Tape; Which : Kind)
     with Post =>
       Item.Count <= Tape_Max
       and then Item.Count >= Item'Old.Count;

   function Seal (Item : Tape) return String;
end Megacorp.Sound;
