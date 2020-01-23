------------------------------------------------------------------------------
--                                                                          --
--                        Copyright (C) 2018, AdaCore                       --
--                                                                          --
--  Redistribution and use in source and binary forms, with or without      --
--  modification, are permitted provided that the following conditions are  --
--  met:                                                                    --
--     1. Redistributions of source code must retain the above copyright    --
--        notice, this list of conditions and the following disclaimer.     --
--     2. Redistributions in binary form must reproduce the above copyright --
--        notice, this list of conditions and the following disclaimer in   --
--        the documentation and/or other materials provided with the        --
--        distribution.                                                     --
--     3. Neither the name of the copyright holder nor the names of its     --
--        contributors may be used to endorse or promote products derived   --
--        from this software without specific prior written permission.     --
--                                                                          --
--   THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS    --
--   "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT      --
--   LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR  --
--   A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT   --
--   HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, --
--   SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT       --
--   LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,  --
--   DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY  --
--   THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT    --
--   (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE  --
--   OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.   --
--                                                                          --
------------------------------------------------------------------------------

with HAL;            use HAL;
with System.Storage_Elements;

private with System;

package USB is

   type String_Descriptor_Zero is record
      bLength            : UInt8;
      bDescriptorType    : UInt8 := 3;
      Str                : String (1 .. 2);
   end record;

   type USB_String is array (UInt8 range <>) of Character;

   type String_Descriptor (bLength : UInt8) is record
      bDescriptorType    : UInt8 := 3;
      Str                : USB_String (3 .. bLength);
   end record with Pack;

   type String_Rec is record
      Index  : UInt8;
      Str    : not null access constant String_Descriptor;
   end record;

   type String_Array is array (Natural range <>) of String_Rec;

   type Setup_Request_Answer is (Handled, Not_Supported, Next_Callback);

   subtype Buffer_Len is System.Storage_Elements.Storage_Offset;

   function Need_ZLP (Len     : Buffer_Len;
                      wLength : UInt16;
                      EP_Size : UInt8)
                      return Boolean;
end USB;
