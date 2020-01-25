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

with HAL;                  use HAL;
with System;
with HAL.USB;              use HAL.USB;
with HAL.USB.Device;       use HAL.USB.Device;
with STM32.USB;            use STM32.USB;
with STM32_SVD.USB_OTG_HS; use STM32_SVD.USB_OTG_HS;

generic
   Base_Address : HAL.UInt32;
package DWC_OTG_FS is

   type EP_Callback_Array is array (EP_Id, EP_Dir) of EP_Callback;
   type Setup_Callback_Array is array (EP_Id) of Setup_Callback;

   type Force_NAK_Array is array (EP_Id) of Boolean;

   type OTG_USB_Device is new USB_Device_Controller with private;

   RX_FIFO : aliased UInt32
     with Size => 32,
     Volatile_Full_Access,
     Address => System'To_Address (Base_Address + 16#1000#);

   type OEPCTL_Registers_Array is array (1 .. All_EP_Index'Last - 2) of OTG_HS_DOEPCTL_Register;
   type OEPSIZ_Registers_Array is array (1 .. All_EP_Index'Last - 1) of OTG_HS_DOEPTSIZ_Register;
   type OEPINT_Registers_Array is array (EP_Index) of OTG_HS_DOEPINT_Register;

   Device_OEPCTL : OEPCTL_Registers_Array := (OTG_HS_DEVICE_Periph.OTG_HS_DOEPCTL1,
                                              OTG_HS_DEVICE_Periph.OTG_HS_DOEPCTL2,
                                              OTG_HS_DEVICE_Periph.OTG_HS_DOEPCTL3);

   Device_OEPINT : OEPINT_Registers_Array := (OTG_HS_DEVICE_Periph.OTG_HS_DOEPINT1,
                                              OTG_HS_DEVICE_Periph.OTG_HS_DOEPINT2,
                                              OTG_HS_DEVICE_Periph.OTG_HS_DOEPINT3,
                                              OTG_HS_DEVICE_Periph.OTG_HS_DOEPINT4,
                                              OTG_HS_DEVICE_Periph.OTG_HS_DOEPINT5);

   Device_OEPSIZ : OEPSIZ_Registers_Array := (OTG_HS_DEVICE_Periph.OTG_HS_DOEPTSIZ1,
                                              OTG_HS_DEVICE_Periph.OTG_HS_DOEPTSIZ2,
                                              OTG_HS_DEVICE_Periph.OTG_HS_DOEPTSIZ3,
                                              OTG_HS_DEVICE_Periph.OTG_HS_DOEPTSIZ4);

   type IEPCTL_Registers_Array is array (EP_Index) of OTG_HS_DIEPCTL_Register;
   type IEPINT_Registers_Array is array (EP_Index) of OTG_HS_DIEPINT_Register;
   type IEPSIZ_Registers_Array is array (EP_Index) of OTG_HS_DIEPTSIZ_Register;

   Device_IEPCTL : IEPCTL_Registers_Array := (OTG_HS_DEVICE_Periph.OTG_HS_DIEPCTL1,
                                              OTG_HS_DEVICE_Periph.OTG_HS_DIEPCTL2,
                                              OTG_HS_DEVICE_Periph.OTG_HS_DIEPCTL3,
                                              OTG_HS_DEVICE_Periph.OTG_HS_DIEPCTL4,
                                              OTG_HS_DEVICE_Periph.OTG_HS_DIEPCTL5);

   Device_IEPINT : IEPINT_Registers_Array := (OTG_HS_DEVICE_Periph.OTG_HS_DIEPINT1,
                                              OTG_HS_DEVICE_Periph.OTG_HS_DIEPINT2,
                                              OTG_HS_DEVICE_Periph.OTG_HS_DIEPINT3,
                                              OTG_HS_DEVICE_Periph.OTG_HS_DIEPINT4,
                                              OTG_HS_DEVICE_Periph.OTG_HS_DIEPINT5);

   Device_IEPSIZ : IEPSIZ_Registers_Array := (OTG_HS_DEVICE_Periph.OTG_HS_DIEPTSIZ1,
                                              OTG_HS_DEVICE_Periph.OTG_HS_DIEPTSIZ2,
                                              OTG_HS_DEVICE_Periph.OTG_HS_DIEPTSIZ3,
                                              OTG_HS_DEVICE_Periph.OTG_HS_DIEPTSIZ4,
                                              OTG_HS_DEVICE_Periph.OTG_HS_DIEPTSIZ5);
   overriding
   procedure Set_EP_Callback (This     : in out OTG_USB_Device;
                              EP       : EP_Addr;
                              Callback : EP_Callback);

   overriding
   procedure Set_Setup_Callback (This     : in out OTG_USB_Device;
                                 EP       : EP_Id;
                                 Callback : Setup_Callback);

   overriding
   procedure Initialize (This : in out OTG_USB_Device);

   overriding
   procedure Start (This : in out OTG_USB_Device);

   overriding
   function Poll (This : in out OTG_USB_Device) return UDC_Event;

   overriding
   procedure EP_Setup (This     : in out OTG_USB_Device;
                       EP       : EP_Addr;
                       Typ      : EP_Type;
                       Max_Size : UInt16;
                       Callback : EP_Callback);
   overriding
   procedure EP_Set_NAK (This : in out OTG_USB_Device;
                         EP   : EP_Addr;
                         NAK  : Boolean);

   overriding
   procedure EP_Set_Stall (This : in out OTG_USB_Device;
                           EP   : EP_Addr);


   overriding
   procedure Set_Address (This : in out OTG_USB_Device;
                          Addr : UInt7);

   overriding
   function Early_Address (This : OTG_USB_Device) return Boolean
   is (True);

   overriding
   procedure EP_Read_Packet (This : in out OTG_USB_Device;
                             EP   : EP_Id;
                             Addr : System.Address;
                             Len  : UInt32);

   overriding
   procedure EP_Write_Packet (This : in out OTG_USB_Device;
                              Ep   : EP_Id;
                              Addr : System.Address;
                              Len  : UInt32);

private

   procedure EP_Config (Direction : EP_Dir);

   procedure Enable_Device_Interrupts;

   procedure Clear_Device_Interrupts;

   type FIFO_Address_Array is array (All_EP_Index) of System.Address;

   type OTG_USB_Device is new USB_Device_Controller with record
      RX_BCNT : UInt11;
      Setup_Req : Setup_Data;
      EP_Callbacks : EP_Callback_Array := (others => (others => null));
      Setup_Callbacks : Setup_Callback_Array := (others => null);

      Force_NAK : Force_NAK_Array := (others => False);
   end record;

end DWC_OTG_FS;
