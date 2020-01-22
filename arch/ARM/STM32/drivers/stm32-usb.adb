with Ada.Real_Time; use Ada.Real_Time;

package body STM32.USB is

   procedure Core_Reset;
   
   procedure Core_Init is
   begin
      Set_Global_Interrupt(False);

      --  Using embedded PHY
      GLOBAL_Periph.GUSBCFG.PHYSEL := True;

      --  Do core soft reset
      Core_Reset;

      --  Enable VBUS sensing in device mode and power up the PHY
      GLOBAL_Periph.GCCFG := (PWRDWN => True,
                              others => <>);
      --  End of core init
   end Core_Init;
   
   procedure Core_Reset is
   begin
      --  Wait for AHB idle
      while not GLOBAL_Periph.GRSTCTL.AHBIDL loop
         null;
      end loop;
      
      GLOBAL_Periph.GRSTCTL.CSRST := True;
      
      while GLOBAL_Periph.GRSTCTL.CSRST loop
         null;
      end loop;
   end Core_Reset;
   
   -----------------
   -- Set_RX_Fifo --
   -----------------

   procedure Set_RX_Fifo (Size : UInt16) is
   begin
      GLOBAL_Periph.GRXFSIZ.RXFD := Size;
   end Set_RX_Fifo;

   -----------------
   -- Set_TX_Fifo --
   -----------------

   procedure Set_TX_Fifo (This : in out OTG_USB_Device;
                          Ep   : EP_Id;
                          Size : UInt16) is
      pragma Unreferenced (This);
      TX_Offset : UInt16 := GLOBAL_Periph.GRXFSIZ.RXFD;
   begin

      if not Valid (Ep) then
         raise Program_Error with "invalid EP in Set_TX_Fifo";
      end if;

      if Ep = 0 then
         GLOBAL_Periph.HPTXFSIZ.PTXFD := Size;
         GLOBAL_Periph.HPTXFSIZ.PTXSA := TX_Offset;
      else
         TX_Offset := TX_Offset + GLOBAL_Periph.HPTXFSIZ.PTXFD;

         for Index in TX_Fifo_Index loop
            if TX_Fifo_Index (All_EP_Index (Ep)) >= Index then
               TX_Offset := TX_Offset + GLOBAL_Periph.DIEPTXF (Index).INEPTXFD;
            else
               exit;
            end if;
         end loop;

         GLOBAL_Periph.DIEPTXF (TX_Fifo_Index (Ep)).INEPTXSA := TX_Offset;
         GLOBAL_Periph.DIEPTXF (TX_Fifo_Index (Ep)).INEPTXFD := Size;
      end if;
   end Set_TX_Fifo;
   
   -------------------
   -- Flush_RX_FIFO --
   -------------------

   procedure Flush_RX_FIFO is
   begin
      GLOBAL_Periph.GRSTCTL.RXFFLSH := True;
      GLOBAL_Periph.GRSTCTL.RXFFLSH := True;

      while GLOBAL_Periph.GRSTCTL.RXFFLSH loop
         null;
      end loop;
   end Flush_RX_FIFO;

   -------------------
   -- Flush_TX_FIFO --
   -------------------

   procedure Flush_TX_FIFO is
   begin

      --  Flush all FIFO
      GLOBAL_Periph.GRSTCTL.TXFNUM := 2#10000#;

      GLOBAL_Periph.GRSTCTL.TXFFLSH := True;

      while GLOBAL_Periph.GRSTCTL.TXFFLSH loop
         null;
      end loop;
   end Flush_TX_FIFO;
   
   --------------------------
   -- Set_Global_Interrupt --
   --------------------------

   procedure Set_Global_Interrupt (Enable : Boolean := True) is
   begin
      GLOBAL_Periph.GAHBCFG.GINT := Enable;
   end Set_Globbal_Interrupt
   

   --------------
   -- Set_Mode --
   --------------
   
   procedure Set_Mode (Is_Device : Boolean) is
   begin
      --  Clear mode
      GLOBAL_Periph.GUSBCFG.FHMOD := False;
      GLOBAL_Periph.GUSBCFG.FDMOD := False;

      --  Set device mode
      if Is_Device
      GLOBAL_Periph.GUSBCFG.FDMOD := True;

      delay until Clock + Milliseconds (50);
   
   -----------------
   -- USB_Connect --
   -----------------

   procedure USB_Connect (Connect : Boolean := True) is
   begin
      DEVICE_Periph.DCTL.SDIS := False;
   end USB_Connect;
   
   
   -----------
   -- Valid --
   -----------

   function Valid (EP : EP_Id) return Boolean
   is (EP <= EP_Id (All_EP_Index'Last));

end STM32.USB;
