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

with Ada.Text_IO;
with System.Storage_Elements;  use System.Storage_Elements;
with Ada.Unchecked_Conversion;
with Hex_Dump;

package body DWC_OTG_FS is

   Rx_FIFO_Size : constant := 64;

   type U8_Index is mod 4;
   type U8_Array is array (U8_Index) of UInt8
     with Pack, Size => 4 * 8;
   --  4 x Byte array used for un-aligned read/write to the FIFOs

   function To_U8_Array is new Ada.Unchecked_Conversion (UInt32, U8_Array);
   function To_U32 is new Ada.Unchecked_Conversion (U8_Array, UInt32);

   Verbose : constant Boolean := False;
   procedure Put_Line (Str : String);
   procedure Put_Line (Str : String) is
   begin
      if Verbose then
         Ada.Text_IO.Put_Line (Str);
      end if;
   end Put_Line;

   procedure Device_Init (This : in out OTG_USB_Device);
   procedure EP0_Out_Start (This : in out OTG_USB_Device);
   procedure Set_TX_Fifo (This : in out OTG_USB_Device;
                          Ep   :        EP_Id;
                          Size :        UInt16);

   -----------------
   -- Device_Init --
   -----------------

   procedure Device_Init (This : in out OTG_USB_Device) is
   begin
      --  VBus sensing depends on the version of the OTG controller
      if OTG_HS_GLOBAL_Periph.OTG_HS_CID < 16#2000# then

         OTG_HS_GLOBAL_Periph.OTG_HS_GCCFG.VBUSBSEN := True;

         --  FIXME: User should be able to disable VBUS sensing (f40x era)
      else

         --  This version of the device has a different layout for the GCCFG
         --  register. It happens that NOVBUSSENS on the old device is the
         --  same as VBDEN on the newer device.

         --  FIXME: Have a correct layout for this version
         OTG_HS_GLOBAL_Periph.OTG_HS_GCCFG.NOVBUSSENS := True;

         --  FIXME: User should be able to disable VBUS sensing (f446 era)
      end if;

      --  Restart the Phy Clock
      OTG_HS_PWRCLK_Periph.OTG_HS_PCGCR := (STPPCLK  => False,
                                            GATEHCLK => False,
                                            PHYSUSP  => False,
                                            others   => <>);

      --  Device mode configuration
      OTG_HS_DEVICE_Periph.OTG_HS_DCFG.PFIVL := 0; -- 80% frame interval

      OTG_HS_DEVICE_Periph.OTG_HS_DCFG.DSPD := 3; -- Set full speed

      Flush_RX_FIFO;
      Flush_TX_FIFO;

      Clear_Device_Interrupts;

      --  FIXME? Should we clear FIFO underrun? But it doesn't exist in the SVD
      --  OTG_HS_DEVICE_Periph.OTG_HS_DIEPMSK.

      EP_Config (Direction => EP_In);
      EP_Config (Direction => EP_Out);

      --  Disable all interrupts
      OTG_HS_GLOBAL_Periph.OTG_HS_GINTMSK := (others => <>);
      --  Clear all interrupts
      OTG_HS_GLOBAL_Periph.OTG_HS_GINTSTS :=
        (
         CMOD              => True,
         MMIS              => True,
         OTGINT            => True,
         SOF               => True,
         RXFLVL            => True,
         NPTXFE            => True,
         GINAKEFF          => True,
         BOUTNAKEFF        => True,
         ESUSP             => True,
         USBSUSP           => True,
         USBRST            => True,
         ENUMDNE           => True,
         ISOODRP           => True,
         EOPF              => True,
         IEPINT            => True,
         OEPINT            => True,
         IISOIXFR          => True,
         PXFR_INCOMPISOOUT => True,
         HPRTINT           => True,
         HCINT             => True,
         PTXFE             => True,
         CIDSCHG           => True,
         DISCINT           => True,
         SRQINT            => True,
         WKUINT            => True,
         others => <>);

      --  if DMA disabled
      OTG_HS_GLOBAL_Periph.OTG_HS_GINTMSK.RXFLVLM := True;

      Enable_Device_Interrupts;

      --  VBUS sensing interrupt
      OTG_HS_GLOBAL_Periph.OTG_HS_GINTMSK.SRQIM := True;
      OTG_HS_GLOBAL_Periph.OTG_HS_GINTMSK.OTGINT := True;

      USB_Connect (Connect => False);

      Set_RX_Fifo (16#80#);
      Set_TX_Fifo (This, 0, 16#40#);
      Set_TX_Fifo (This, 1, 16#80#);

      Put_Line ("Init finished");
   end Device_Init;

   -------------------
   -- EP0_Out_Start --
   -------------------

   procedure EP0_Out_Start (This : in out OTG_USB_Device) is
   begin
      OTG_HS_DEVICE_Periph.OTG_HS_DOEPTSIZ0 := (STUPCNT => 3,
                                                PKTCNT  => True,
                                                XFRSIZ  => 3 * 8,
                                                others  => <>);
      if This.Force_NAK (0) then
         OTG_HS_DEVICE_Periph.OTG_HS_DOEPCTL0.SNAK := True;
      else
         OTG_HS_DEVICE_Periph.OTG_HS_DOEPCTL0.CNAK := True;
      end if;
      OTG_HS_DEVICE_Periph.OTG_HS_DOEPCTL0.EPENA := True;
   end EP0_Out_Start;


   -----------------
   -- Set_TX_Fifo --
   -----------------

   procedure Set_TX_Fifo (This : in out OTG_USB_Device;
                          Ep   : EP_Id;
                          Size : UInt16) is
      pragma Unreferenced (This);
      TX_Offset : UInt16 := OTG_HS_GLOBAL_Periph.OTG_HS_GRXFSIZ.RXFD;
   begin

      if not Valid (Ep) then
         raise Program_Error with "invalid EP in Set_TX_Fifo";
      end if;

      if Ep = 0 then
         OTG_HS_GLOBAL_Periph.OTG_HS_HPTXFSIZ.PTXFD := Size;
         OTG_HS_GLOBAL_Periph.OTG_HS_HPTXFSIZ.PTXSA := TX_Offset;
      else
         TX_Offset := TX_Offset + OTG_HS_GLOBAL_Periph.OTG_HS_HPTXFSIZ.PTXFD;

         for Index in TX_Fifo_Index loop
            if TX_Fifo_Index (All_EP_Index (Ep)) >= Index then
               TX_Offset := TX_Offset + Global_DIEPTXF (Index).INEPTXFD;
            else
               exit;
            end if;
         end loop;
         Global_DIEPTXF (TX_Fifo_Index (Ep)).INEPTXSA := TX_Offset;
         Global_DIEPTXF (TX_Fifo_Index (Ep)).INEPTXFD := Size;
      end if;
   end Set_TX_Fifo;

   -------------------
   -- Flush_RX_FIFO --
   -------------------

   -----------
   -- Start --
   -----------

   overriding
   procedure Start (This : in out OTG_USB_Device) is
      pragma Unreferenced (This);
   begin
      USB_Connect;
      Set_Global_Interrupt;
   end Start;

   ----------------
   -- Initialize --
   ----------------

   overriding
   procedure Initialize (This : in out OTG_USB_Device) is
   begin

      Core_Init;

      Set_Mode (Is_Device => True);

      --  USB_DevInit...
      Device_Init (This => This);
      --  Enable VBUS sensing
   end Initialize;

   ------------------------------
   -- Enable_Device_Interrupts --
   ------------------------------

   procedure Enable_Device_Interrupts is
   begin
      --  Common interrupt
      OTG_HS_GLOBAL_Periph.OTG_HS_GINTMSK.USBSUSPM := True;
      OTG_HS_GLOBAL_Periph.OTG_HS_GINTMSK.USBRST := True;
      OTG_HS_GLOBAL_Periph.OTG_HS_GINTMSK.ENUMDNEM := True;
      OTG_HS_GLOBAL_Periph.OTG_HS_GINTMSK.IEPINT := True;
      OTG_HS_GLOBAL_Periph.OTG_HS_GINTMSK.OEPINT := True;
      OTG_HS_GLOBAL_Periph.OTG_HS_GINTMSK.IISOIXFRM := True;
      OTG_HS_GLOBAL_Periph.OTG_HS_GINTMSK.PXFRM_IISOOXFRM := True;
      OTG_HS_GLOBAL_Periph.OTG_HS_GINTMSK.WUIM := True;
   end Enable_Device_Interrupts;

   ---------------------
   -- Set_EP_Callback --
   ---------------------

   overriding
   procedure Set_EP_Callback (This     : in out OTG_USB_Device;
                              EP       : EP_Addr;
                              Callback : EP_Callback)

   is
   begin
      This.EP_Callbacks (EP.Num, EP.Dir) := Callback;
   end Set_EP_Callback;

   ------------------------
   -- Set_Setup_Callback --
   ------------------------

   overriding
   procedure Set_Setup_Callback (This     : in out OTG_USB_Device;
                                 EP       : EP_Id;
                                 Callback : Setup_Callback)
   is
   begin
      This.Setup_Callbacks (EP) := Callback;
   end Set_Setup_Callback;

   -----------------------------
   -- Clear_Device_Interrupts --
   -----------------------------

   procedure Clear_Device_Interrupts is
   begin
      --  Clear all device interrupts
      OTG_HS_DEVICE_Periph.OTG_HS_DIEPMSK :=
        (XFRCM     => False,
         EPDM      => False,
         TOM       => False,
         ITTXFEMSK => False,
         INEPNMM   => False,
         INEPNEM   => False,
         others    => <>);
      OTG_HS_DEVICE_Periph.OTG_HS_DOEPMSK :=
        (XFRCM  => False,
         EPDM   => False,
         STUPM  => False,
         OTEPDM => False,
         others    => <>);
      OTG_HS_DEVICE_Periph.OTG_HS_DAINT := (16#FFFF#, 16#FFFF#);
      OTG_HS_DEVICE_Periph.OTG_HS_DAINTMSK := (0, 0);
   end Clear_Device_Interrupts;

   --------------
   -- EP_Setup --
   --------------

   overriding
   procedure EP_Setup (This     : in out OTG_USB_Device;
                       EP       : EP_Addr;
                       Typ      : EP_Type;
                       Max_Size : UInt16;
                       Callback : EP_Callback)
   is
      MPSIZ : UInt2;
   begin

      if EP.Num = 0 then
         --  Control endpoint

         --  Input
         if Max_Size >= 64 then
            MPSIZ := 0;
         elsif Max_Size >= 32 then
            MPSIZ := 1;
         elsif Max_Size >= 16 then
            MPSIZ := 2;
         else
            MPSIZ := 3;
         end if;

         OTG_HS_DEVICE_Periph.OTG_HS_DIEPTSIZ0.XFRSIZ :=
           OTG_HS_DIEPTSIZ0_XFRSIZ_Field (Max_Size);
         OTG_HS_DEVICE_Periph.OTG_HS_DIEPTSIZ0.PKTCNT := 0;
         OTG_HS_DEVICE_Periph.OTG_HS_DIEPCTL0 :=
           (
            MPSIZ          => UInt11 (MPSIZ),
            USBAEP         => True,
            NAKSTS         => False,
            EPTYP          => 0, -- hardcoded 0 for control
            Stall          => False,
            TXFNUM         => 0,
            CNAK           => False,
            SNAK           => True,
            EPDIS          => False,
            EPENA          => True,
            others => <>);
         OTG_HS_DEVICE_Periph.OTG_HS_DIEPINT0 :=
           (XFRC   => True,
            EPDISD => True,
            TOC    => True,
            ITTXFE => True,
            INEPNE => True,
            TXFE   => True,
            others => <>);

         --  Output
         OTG_HS_DEVICE_Periph.OTG_HS_DOEPTSIZ0 := (STUPCNT => 3,
                                                   PKTCNT  => True,
                                                   XFRSIZ  => 3 * 8,
                                                   others  => <>);
         OTG_HS_DEVICE_Periph.OTG_HS_DOEPCTL0 :=
           (
            MPSIZ          => MPSIZ,
            USBAEP         => True,
            NAKSTS         => False,
            EPTYP          => 0, -- hardcoded 0 for control
            SNPM           => False,
            Stall          => False,
            CNAK           => False,
            SNAK           => True,
            EPDIS          => False,
            EPENA          => True,
            others => <>);

         --  FIFO
         OTG_HS_GLOBAL_Periph.OTG_HS_GNPTXFSIZ_Host.NPTXFD := Max_Size / 4;
         OTG_HS_GLOBAL_Periph.OTG_HS_GNPTXFSIZ_Host.NPTXFSA := Rx_FIFO_Size;

         OTG_HS_DEVICE_Periph.OTG_HS_DOEPINT0 :=
           (XFRC    => True,
            EPDISD  => True,
            STUP    => True,
            OTEPDIS => True,
            B2BSTUP => True,
            others  => <>);

         OTG_HS_DEVICE_Periph.OTG_HS_DAINTMSK.IEPM := OTG_HS_DEVICE_Periph.OTG_HS_DAINTMSK.IEPM or 1;
         OTG_HS_DEVICE_Periph.OTG_HS_DAINTMSK.OEPM := OTG_HS_DEVICE_Periph.OTG_HS_DAINTMSK.OEPM or 1;

         return;
      end if;

      if EP.Num not in EP_Id (EP_Index'First) .. EP_Id (EP_Index'Last) then
         raise Program_Error with "invalid EP number";
      end if;

      case EP.Dir is
         when EP_In =>
            Set_TX_Fifo (This, EP.Num, Max_Size);

            Device_IEPSIZ (EP_Index (EP.Num)).XFRSIZ := UInt19 (Max_Size);
            Device_IEPCTL (EP_Index (EP.Num)) :=
              (
               MPSIZ          => UInt11 (Max_Size),
               USBAEP         => True,
               EONUM_DPID     => False,
               NAKSTS         => False,
               EPTYP          => EP_Type'Enum_Rep (Typ),
               Stall          => False,
               TXFNUM         => EP.Num,
               CNAK           => False,
               SNAK           => True,

               --  USB data packet have either a 0 or 1 id alternatively. This
               --  bit should not be set when restarting and EP, otherwise the
               --  controller will reject every other packet.
               --
               --  FIXME: How to set this bit only when configuring an EP and
               --  not when restarting it? Maybe with a dedicated sub-program
               --  to restart en EP.
               SD0PID_SEVNFRM => False,

               SODDFRM        => False,
               EPDIS          => False,
               EPENA          => True,
               others => <>
              );

            This.EP_Callbacks (EP.Num, EP_In) := Callback;
         when EP_Out =>
            This.EP_Callbacks (EP.Num, EP_Out) := Callback;

            Device_OEPSIZ (EP_Index (EP.Num)).XFRSIZ := UInt19 (Max_Size);
            Device_OEPSIZ (EP_Index (EP.Num)).PKTCNT := 1;
            Device_OEPCTL (EP_Index (EP.Num)) :=
              (
               MPSIZ          => UInt11 (Max_Size),
               USBAEP         => True,
               EONUM_DPID     => False,
               NAKSTS         => False,
               EPTYP          => EP_Type'Enum_Rep (Typ),
               Stall          => False,
               CNAK           => True,
               SNAK           => False,

               --  See above
               SD0PID_SEVNFRM => False,

               SODDFRM        => False,
               EPDIS          => False,
               EPENA          => True,
               others => <>
              );
      end case;
   end EP_Setup;

   ----------------
   -- EP_Set_NAK --
   ----------------

   overriding
   procedure EP_Set_NAK (This : in out OTG_USB_Device;
                         EP   : EP_Addr;
                         NAK  : Boolean)
   is
   begin
      if EP.Dir /= EP_Out then
         return;
      end if;

      This.Force_NAK (EP.Num) := NAK;

      if EP.Num > EP_Id (All_EP_Index'Last) then
         raise Program_Error with "invalid EP number in set NAK";
      end if;

      if NAK then
         case EP.Num is
            when 0 => OTG_HS_DEVICE_Periph.OTG_HS_DOEPCTL0.SNAK := True;
            when others =>
               Device_OEPCTL (EP_Index (EP.Num)).SNAK := True;
         end case;
      else
         case EP.Num is
            when 0 => OTG_HS_DEVICE_Periph.OTG_HS_DOEPCTL0.CNAK := True;
            when others =>
               Device_OEPCTL (EP_Index (EP.Num)).CNAK := True;
         end case;
      end if;

   end EP_Set_NAK;

   ------------------
   -- EP_Set_Stall --
   ------------------

   overriding
   procedure EP_Set_Stall (This : in out OTG_USB_Device;
                           EP   : EP_Addr)
   is
   begin

      if EP.Num > EP_Id (All_EP_Index'Last) then
         raise Program_Error with "invalid EP number in set stall";
      end if;

      case EP.Dir is
         when EP_In =>
            case EP.Num is
               when 0 => OTG_HS_DEVICE_Periph.OTG_HS_DIEPCTL0.Stall := True;
               when others =>
                  Device_IEPCTL (EP_Index (EP.Num)).Stall := True;
            end case;
         when EP_Out =>
            case EP.Num is
               when 0 =>
                  OTG_HS_DEVICE_Periph.OTG_HS_DOEPCTL0.Stall := True;
                  --  We still want to be able to receive setup packets
                  EP0_Out_Start (This);
               when others =>
                  Device_OEPCTL (EP_Index (EP.Num)).Stall := True;
            end case;
      end case;
   end EP_Set_Stall;

   -----------------
   -- Set_Address --
   -----------------

   overriding
   procedure Set_Address (This : in out OTG_USB_Device;
                          Addr : UInt7)
   is
      pragma Unreferenced (This);
   begin
      OTG_HS_DEVICE_Periph.OTG_HS_DCFG.DAD := 0;
      OTG_HS_DEVICE_Periph.OTG_HS_DCFG.DAD := Addr;
   end Set_Address;

   ---------------
   -- EP_Config --
   ---------------

   procedure EP_Config (Direction : EP_Dir) is
   begin
      if Direction = EP_In then
         if OTG_HS_DEVICE_Periph.OTG_HS_DIEPCTL0.EPENA then
            OTG_HS_DEVICE_Periph.OTG_HS_DIEPCTL0 := (EPDIS  => True,
                                                     SNAK   => True,
                                                     others => <>);
         else
            OTG_HS_DEVICE_Periph.OTG_HS_DIEPCTL0 := (others => <>);
         end if;
         OTG_HS_DEVICE_Periph.OTG_HS_DIEPTSIZ0 := (others => <>);
         OTG_HS_DEVICE_Periph.OTG_HS_DIEPINT0 :=
           (XFRC   => True,
            EPDISD => True,
            TOC    => True,
            ITTXFE => True,
            INEPNE => True,
            TXFE   => True,
            others => <>);

         -- In End Points --
         for Ep in EP_Index loop
            if Device_IEPCTL (Ep).EPENA then
               Device_IEPCTL (Ep) := (EPDIS  => True,
                                      SNAK   => True,
                                      others => <>);
            else
               Device_IEPCTL (Ep) := (others => <>);
            end if;
            Device_IEPSIZ (Ep) := (others => <>);
            Device_IEPINT (Ep) :=
              (XFRC   => True,
               EPDISD => True,
               TOC    => True,
               ITTXFE => True,
               INEPNE => True,
               TXFE   => True,
               others => <>);
         end loop;
      else
         if OTG_HS_DEVICE_Periph.OTG_HS_DOEPCTL0.EPENA then
            OTG_HS_DEVICE_Periph.OTG_HS_DOEPCTL0 := (EPDIS  => True,
                                                     SNAK   => True,
                                                     others => <>);
         else
            OTG_HS_DEVICE_Periph.OTG_HS_DOEPCTL0 := (others => <>);
         end if;

         OTG_HS_DEVICE_Periph.OTG_HS_DOEPTSIZ0 := (others => <>);
         OTG_HS_DEVICE_Periph.OTG_HS_DOEPINT0 :=
           (XFRC   => True,
            EPDISD => True,
            STUP    => True,
            OTEPDIS => True,
            B2BSTUP => True,
            others => <>);

         -- Out End Points --
         for Ep in Device_OEPCTL'Range loop

            if Device_OEPCTL (Ep).EPENA then
               Device_OEPCTL (Ep) := (EPDIS  => True,
                                      SNAK   => True,
                                      others => <>);
            else
               Device_OEPCTL (Ep) := (others => <>);
            end if;
            Device_OEPSIZ (Ep) := (others => <>);
            Device_OEPINT (Ep) :=
              (XFRC   => True,
               EPDISD => True,
               STUP    => True,
               OTEPDIS => True,
               B2BSTUP => True,
               others => <>);
         end loop;
      end if;
   end EP_Config;

   --------------------
   -- EP_Read_Packet --
   --------------------

   overriding
   procedure EP_Read_Packet (This : in out OTG_USB_Device;
                             EP   : EP_Id;
                             Addr : System.Address;
                             Len  : UInt32)
   is
      pragma Unreferenced (EP); -- Only on RX FIFO for all EPs

      Actual_Len : constant UInt32 := UInt32'Min (Len, UInt32 (This.RX_BCNT));

   begin

      if To_Integer (Addr) mod 4 /= 0 then

         --  The buffer is _not_ aligned

         declare
            Buf_8 : UInt8_Array (1 .. Integer (Actual_Len))
              with Address => Addr;
            Arr : U8_Array;
            Conv_Index : U8_Index := U8_Index'First;
         begin
            for Index in Buf_8'Range loop

               if Conv_Index = U8_Index'First then
                  Arr := To_U8_Array (RX_FIFO);
               end if;

               Buf_8 (Index) := Arr (Conv_Index);
               Conv_Index := Conv_Index + 1;
            end loop;
         end;
      else

         --  The buffer is aligned

         declare
            Cnt_32 : constant UInt32 := (Actual_Len + 3) / 4;
            Buf_32  : UInt32_Array (1 .. Integer (Cnt_32)) with Address => Addr;
         begin
            for Index in Buf_32'Range loop
               Buf_32 (Index) := RX_FIFO;
            end loop;
         end;
      end if;

      This.RX_BCNT := This.RX_BCNT - UInt11 (Actual_Len);
   end EP_Read_Packet;

   ---------------------
   -- EP_Write_Packet --
   ---------------------

   overriding
   procedure EP_Write_Packet (This : in out OTG_USB_Device;
                              Ep   : EP_Id;
                              Addr : System.Address;
                              Len  : UInt32)
   is
      pragma Unreferenced (This);
      Cnt_8  : constant UInt32 := Len;
      Buf_8  : UInt8_Array (1 .. Integer (Cnt_8)) with Address => Addr;
   begin

      if Len > UInt32 (UInt7'Last) then
         raise Program_Error with "invalid size";
      end if;

      if Ep = 0 then

         OTG_HS_DEVICE_Periph.OTG_HS_DIEPTSIZ0.XFRSIZ := UInt7 (Len);
         OTG_HS_DEVICE_Periph.OTG_HS_DIEPTSIZ0.PKTCNT := 1;
         OTG_HS_DEVICE_Periph.OTG_HS_DIEPCTL0.CNAK := True;
         OTG_HS_DEVICE_Periph.OTG_HS_DIEPCTL0.EPENA := True;

      elsif Valid (Ep) then

         Device_IEPSIZ (EP_Index (Ep)).XFRSIZ := UInt19 (Len);
         Device_IEPSIZ (EP_Index (Ep)).PKTCNT := 1;
         Device_IEPSIZ (EP_Index (Ep)).MCNT := 1; -- FIXME: Is that always a good value?

         Device_IEPCTL (EP_Index (Ep)).CNAK := True;
         Device_IEPCTL (EP_Index (Ep)).EPENA := True;

      else
         raise Program_Error with "Invalid EP in write packet";
      end if;

      Hex_Dump.Hex_Dump (Buf_8, Ada.Text_IO.Put_Line'Access);

      declare
         TX_FIFO : aliased UInt32
           with Size => 32,
           Volatile_Full_Access,
           Address =>
             System'To_Address (Base_Address + 16#1000# + 16#1000# * UInt32 (Ep));

      begin
         if To_Integer (Addr) mod 4 /= 0 then

            --  The buffer is _not_ aligned

            declare
               Arr        : U8_Array;
               Conv_Index : U8_Index := U8_Index'First;
            begin
               for Elt of Buf_8 loop
                  Arr (Conv_Index) := Elt;

                  if Conv_Index = U8_Index'Last then
                     TX_FIFO := To_U32 (Arr);
                  end if;

                  Conv_Index := Conv_Index + 1;
               end loop;

               if Conv_Index /= U8_Index'First then
                  TX_FIFO := To_U32 (Arr);
               end if;
            end;

         else
            --  The buffer is aligned
            declare
               Cnt_32 : constant Integer := Integer (Len + 3) / 4;
               Buf_32  : UInt32_Array (1 .. Cnt_32) with Address => Addr;
            begin
               for Elt of Buf_32 loop
                  TX_FIFO := Elt;
               end loop;
            end;
         end if;
      end;
   end EP_Write_Packet;

   ----------
   -- Poll --
   ----------

   overriding
   function Poll (This : in out OTG_USB_Device) return UDC_Event is
      GINTSTS : UInt32 with Volatile_Full_Access,
        Address => OTG_HS_GLOBAL_Periph.OTG_HS_GINTSTS'Address;
   begin

      --  It is important to check the interrupt flag in this order
      --  In particular, reset should be checked last to make sure the transfer
      --  completions are processed before doing a reset.

      Put_Line ("GINTSTS:" & GINTSTS'Img);

      if OTG_HS_GLOBAL_Periph.OTG_HS_GINTSTS.OEPINT then
         Put_Line ("GINTSTS.OEPINT");
         OTG_HS_GLOBAL_Periph.OTG_HS_GINTSTS.OEPINT := True;

         declare
            EP : EP_Id := 0;
            OEPINT : UInt16 :=  OTG_HS_DEVICE_Periph.OTG_HS_DAINT.OEPINT;

         begin

            while OEPINT /= 0 loop
               if (OEPINT and 1) /= 0 then

                  if EP = 0 then
                     if OTG_HS_DEVICE_Periph.OTG_HS_DOEPINT0.STUP then
                        OTG_HS_DEVICE_Periph.OTG_HS_DOEPINT0.STUP := True;
                        Put_Line ("DOEPINT0.STUP");

                        --  Prepare EP0 for the next setup
                        EP0_Out_Start (This);
                        return (Kind   => Setup_Request,
                                Req    => This.Setup_Req,
                                Req_EP => EP);
                     end if;
                     if OTG_HS_DEVICE_Periph.OTG_HS_DOEPINT0.XFRC then
                        OTG_HS_DEVICE_Periph.OTG_HS_DOEPINT0.XFRC := True;
                        Put_Line ("DOEPINT0.XFRC");
                     end if;
                     if OTG_HS_DEVICE_Periph.OTG_HS_DOEPINT0.EPDISD then
                        OTG_HS_DEVICE_Periph.OTG_HS_DOEPINT0.EPDISD := True;
                        Put_Line ("DOEPINT0.EPDISD");
                     end if;
                     if OTG_HS_DEVICE_Periph.OTG_HS_DOEPINT0.OTEPDIS then
                        OTG_HS_DEVICE_Periph.OTG_HS_DOEPINT0.OTEPDIS := True;
                        Put_Line ("DOEPINT0.OTEPDIS");
                     end if;
                     if OTG_HS_DEVICE_Periph.OTG_HS_DOEPINT0.B2BSTUP then
                        OTG_HS_DEVICE_Periph.OTG_HS_DOEPINT0.B2BSTUP := True;
                        Put_Line ("DOEPINT0.B2BSTUP");
                     end if;
                  else
                     if Device_OEPINT (EP_Index (EP)).XFRC then
                        Device_OEPINT (EP_Index (EP)).XFRC := True;
                        return (Kind  => Transfer_Complete,
                                T_EP => (EP, EP_Out));
                     end if;
                     if Device_OEPINT (EP_Index (EP)).NYET then
                        Device_OEPINT (EP_Index (EP)).NYET := True;
                        Put_Line ("DOEPINTX.NYET");
                     end if;
                     if Device_OEPINT (EP_Index (EP)).EPDISD then
                        Device_OEPINT (EP_Index (EP)).EPDISD := True;
                        Put_Line ("DOEPINTX.EPDISD");
                     end if;
                     if Device_OEPINT (EP_Index (EP)).OTEPDIS then
                        Device_OEPINT (EP_Index (EP)).OTEPDIS := True;
                        Put_Line ("DOEPINTX.OTEPDIS");
                     end if;
                  end if;
               end if;
               OEPINT := Shift_Right (OEPINT, 1);
               EP := EP + 1;
            end loop;
         end;
      end if;

      if OTG_HS_GLOBAL_Periph.OTG_HS_GINTSTS.IEPINT then

         Put_Line ("GINTSTS.IEPINT");
         OTG_HS_GLOBAL_Periph.OTG_HS_GINTSTS.IEPINT := True;
         declare
            EP : EP_Id := 0;
            IEPINT :  UInt16 :=  OTG_HS_DEVICE_Periph.OTG_HS_DAINT.IEPINT;

         begin

            while IEPINT /= 0 loop
               if (IEPINT and 1) /= 0 then

                  case EP is

                     when 0 =>
                        if OTG_HS_DEVICE_Periph.OTG_HS_DIEPINT0.XFRC then
                           OTG_HS_DEVICE_Periph.OTG_HS_DIEPINT0.XFRC := True;
                           Put_Line ("DIEPINT0");

                           return (Kind => Transfer_Complete, T_EP => (0, EP_In));
                        end if;
                     when EP_Id (EP_Index'First) .. EP_Id (EP_Index'Last) =>
                        if Device_IEPINT (EP_Index (EP)).XFRC then
                           Device_IEPINT (EP_Index (EP)).XFRC := True;

                           if Verbose then
                              Put_Line ("DIEPINT" & EP'Img);
                           end if;

                           return (Kind => Transfer_Complete, T_EP => (EP, EP_In));
                        end if;
                     when others =>
                        raise Program_Error with "IEP doesn't exists";
                  end case;
               end if;
               IEPINT := Shift_Right (IEPINT, 1);
               EP := EP + 1;
            end loop;
         end;
      end if;

      if OTG_HS_GLOBAL_Periph.OTG_HS_GINTSTS.USBSUSP then
         OTG_HS_GLOBAL_Periph.OTG_HS_GINTSTS.USBSUSP := True;
         Put_Line ("GINTSTS.USBSUSP");
      end if;
      if OTG_HS_GLOBAL_Periph.OTG_HS_GINTSTS.WKUINT then
         OTG_HS_GLOBAL_Periph.OTG_HS_GINTSTS.WKUINT := True;
         Put_Line ("GINTSTS.WLUPINT");
      end if;
      if OTG_HS_GLOBAL_Periph.OTG_HS_GINTSTS.SOF then
         OTG_HS_GLOBAL_Periph.OTG_HS_GINTSTS.SOF := True;
         Put_Line ("GINTSTS.SOF");
      end if;

      if OTG_HS_GLOBAL_Periph.OTG_HS_GINTSTS.RXFLVL then

         --  This interrupt is not cleared by setting the flag to 1???
         --  OTG_HS_GLOBAL_Periph.OTG_HS_GINTSTS.RXFLVL := True;

         Put_Line ("GINTSTS.RXFLVL");

         declare
            --  PKTSTS_GOUTNAK    : constant := 1;
            PKTSTS_OUT        : constant := 2;
            --  PKTSTS_OUT_COMP   : constant := 3;
            --  PKTSTS_SETUP_COMP : constant := 4;
            PKTSTS_SETUP      : constant := 6;

            RX_Status : constant OTG_HS_GRXSTSP_Peripheral_Register
              := OTG_HS_GLOBAL_Periph.OTG_HS_GRXSTSP_Peripheral;
            --  It is very important to use the pop version of this register,
            --  otherwise the control data stays in the FIFO and will be mixed
            --  with the real data.

         begin
--              Put_Line ("DIEPTSIZ0.PKTCNT:" &
--                          OTG_HS_DEVICE_Periph.OTG_HS_DIEPTSIZ0.PKTCNT'Img);

            if Verbose then
               Put_Line ("PKTSTS:" & RX_Status.PKTSTS'Img);
               Put_Line ("BCNT:" & RX_Status.BCNT'Img);
            end if;

            if RX_Status.PKTSTS = PKTSTS_OUT then

               Put_Line ("PKTSTS_OUT");
               This.RX_BCNT := RX_Status.BCNT;
               return (Kind    => Data_Ready,
                       RX_EP   => RX_Status.EPNUM,
                       RX_BCNT => RX_Status.BCNT);
            elsif RX_Status.PKTSTS = PKTSTS_SETUP then

               This.RX_BCNT := RX_Status.BCNT;

               --  Receive a setup packet
               This.EP_Read_Packet (RX_Status.EPNUM,
                                    This.Setup_Req'Address,
                                    8);
            end if;

         end;
      end if;

      if OTG_HS_GLOBAL_Periph.OTG_HS_GINTSTS.USBRST then
         OTG_HS_GLOBAL_Periph.OTG_HS_GINTSTS.USBRST := True;
         Put_Line ("GINTSTS.USBRST");

         OTG_HS_DEVICE_Periph.OTG_HS_DCTL.RWUSIG := False;

         Flush_TX_FIFO;

         --  FIXME: Not needed -> Flush_RX_FIFO;

         OTG_HS_DEVICE_Periph.OTG_HS_DIEPMSK.XFRCM := True;
         OTG_HS_DEVICE_Periph.OTG_HS_DIEPMSK.EPDM := True;
         OTG_HS_DEVICE_Periph.OTG_HS_DIEPMSK.TOM := True;

         OTG_HS_DEVICE_Periph.OTG_HS_DOEPMSK.XFRCM := True;
         OTG_HS_DEVICE_Periph.OTG_HS_DOEPMSK.EPDM := True;
         OTG_HS_DEVICE_Periph.OTG_HS_DOEPMSK.STUPM := True;
         OTG_HS_DEVICE_Periph.OTG_HS_DOEPMSK.OTEPDM := True; -- FIXME: Not needed?

         This.Set_Address (0);

         OTG_HS_DEVICE_Periph.OTG_HS_DOEPTSIZ0 :=
           (XFRSIZ  => 3 * 8,
            PKTCNT  => True,
            STUPCNT => 3,
            others => <>);

      end if;

      if OTG_HS_GLOBAL_Periph.OTG_HS_GINTSTS.ENUMDNE then

         OTG_HS_GLOBAL_Periph.OTG_HS_GINTSTS.ENUMDNE := True;
         --  TODO? fifo_mem_top
         Put_Line ("GINTSTS.ENUMDNE");

         return (Kind => Reset);
      end if;

      return No_Event;
   end Poll;

end DWC_OTG_FS;
