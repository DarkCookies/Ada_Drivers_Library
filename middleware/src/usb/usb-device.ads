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
with HAL;
with USB.Classes;
with HAL.USB.Device; use HAL.USB.Device;

private with System;
with HAL.USB; use HAL.USB;
with USB; use USB;

package USB.Device is
   type Device_Descriptor is record
      bLength            : UInt8;
      bDescriptorType    : UInt8;
      bcdUSB             : UInt16;
      bDeviceClass       : UInt8;
      bDeviceSubClass    : UInt8;
      bDeviceProtocol    : UInt8;
      bMaxPacketSize0    : UInt8;
      idVendor           : UInt16;
      idProduct          : UInt16;
      bcdDevice          : UInt16;
      iManufacturer      : UInt8;
      iProduct           : UInt8;
      iSerialNumber      : UInt8;
      bNumConfigurations : UInt8;
   end record with Pack;

   type Device_State is (Idle, Addressed, Configured, Suspended);

   type Control_State is (Idle, Stalled,

                          --  In means Device to Host
                          Data_In,
                          Last_Data_In,
                          Status_In,

                          --  Out means Host to Device
                          Data_Out,
                          Last_Data_Out,
                          Status_Out);

   type USB_Device is tagged limited record

      --  For better performances this buffer has to be word aligned. So we put
      --  it as the first field of this record.
      RX_Ctrl_Buf : UInt8_Array (1 .. 256);

      UDC     : HAL.USB.Device.Any_USB_Device_Controller := null;
      Class   : USB.Classes.Any_USB_Device_Class := null;
      Desc    : access constant Device_Descriptor := null;
      Config  : access constant UInt8_Array := null;
      Strings : access constant String_Array := null;

      Dev_Addr  : UInt7 := 0;
      Dev_State : Device_State := Idle;

      Ctrl_Req : Setup_Data;
      Ctrl_Buf : System.Address;
      Ctrl_Len : Buffer_Len := 0;
      Ctrl_State : Control_State := Idle;
      Ctrl_Need_ZLP : Boolean := False;
   end record;

   function Initialized (This : USB_Device) return Boolean;


   procedure Initalize (This       : in out USB_Device;
                        Controller : not null HAL.USB.Device.Any_USB_Device_Controller;
                        Class      : not null USB.Classes.Any_USB_Device_Class;
                        Dec        : not null access constant Device_Descriptor;
                        Config     : not null access constant UInt8_Array;
                        Strings    : not null access constant String_Array)
     with Post => This.Initialized;


   procedure Start (This : in out USB_Device)
     with Pre => This.Initialized;

   procedure Reset (This : in out USB_Device)
     with Pre => This.Initialized;

   procedure Poll (This : in out USB_Device)
     with Pre => This.Initialized;

   function Controller (This : USB_Device) return
     not null HAL.USB.Device.Any_USB_Device_Controller
     with Pre => This.Initialized;

   procedure Control_Setup_Read (This : in out USB_Device;
                                 Req  : Setup_Data);
   --  Handle setup read request

   procedure Control_Setup_Write (This : in out USB_Device;
                                  Req  : Setup_Data);
   --  Handle setup read request

   procedure Control_Setup (This : in out USB_Device;
                            EP   : EP_Id;
                            Req  : Setup_Data);
   --  Handle setup request

   function Control_Dispatch_Request (This : in out USB_Device;
                                      Req  : Setup_Data)
                                      return Setup_Request_Answer;
   --  Handle setup read request

   function Control_Dispatch_Write_Request (This : in out USB_Device)
                                            return Setup_Request_Answer;


   function Control_Device_Request  (This : in out USB_Device;
                                      Req  : Setup_Data)
                                      return Setup_Request_Answer;
   function Get_String (This  : in out USB_Device;
                        Index : UInt8)
                        return Setup_Request_Answer;
   function Get_Descriptor (This : in out USB_Device;
                            Req  : Setup_Data)
                            return Setup_Request_Answer;

   function Set_Address (This : in out USB_Device;
                            Req  : Setup_Data)
                            return Setup_Request_Answer;
   function Set_Configuration (This : in out USB_Device;
                               Req  : Setup_Data)
                               return Setup_Request_Answer;

   procedure Control_Send_Chunk (This : in out USB_Device);
   procedure Control_Receive_Chunk (This : in out USB_Device);

   procedure Control_In (This : in out USB_Device);
   procedure Control_Out (This : in out USB_Device;
                          BCNT : UInt11);

end USB.Device;
