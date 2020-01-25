with Ada.Real_Time; use Ada.Real_Time;

package body STM32.USB is

   procedure Core_Init is
   begin
      Set_Global_Interrupt (False);

      --  Using embedded PHY
      OTG_HS_GLOBAL_Periph.OTG_HS_GUSBCFG.PHYSEL := True;

      --  Do core soft reset
      Core_Reset;

      --  Enable VBUS sensing in device mode and power up the PHY
      OTG_HS_GLOBAL_Periph.OTG_HS_GCCFG := (PWRDWN => True,
                              others => <>);
      --  End of core init
   end Core_Init;

   procedure Core_Reset is
   begin
      --  Wait for AHB idle
      while not OTG_HS_GLOBAL_Periph.OTG_HS_GRSTCTL.AHBIDL loop
         null;
      end loop;

      OTG_HS_GLOBAL_Periph.OTG_HS_GRSTCTL.CSRST := True;

      while OTG_HS_GLOBAL_Periph.OTG_HS_GRSTCTL.CSRST loop
         null;
      end loop;
   end Core_Reset;

   ----------------------------
   -- Disable_All_Interrupts --
   ----------------------------

   procedure Disable_All_Interrupts is
   begin
      OTG_HS_GLOBAL_Periph.OTG_HS_GINTMSK := (MMISM           => False,
                                              --  OTG interrupt mask
                                              OTGINT          => False,
                                              --  Start of frame mask
                                              SOFM            => False,
                                              --  Receive FIFO nonempty mask
                                              RXFLVLM         => False,
                                              --  Nonperiodic TxFIFO empty mask
                                              NPTXFEM         => False,
                                              --  Global nonperiodic IN NAK effective mask
                                              GINAKEFFM       => False,
                                              --  Global OUT NAK effective mask
                                              GONAKEFFM       => False,
                                              --  Early suspend mask
                                              ESUSPM          => False,
                                              --  USB suspend mask
                                              USBSUSPM        => False,
                                              --  USB reset mask
                                              USBRST          => False,
                                              --  Enumeration done mask
                                              ENUMDNEM        => False,
                                              --  Isochronous OUT packet dropped interrupt mask
                                              ISOODRPM        => False,
                                              --  End of periodic frame interrupt mask
                                              EOPFM           => False,
                                              --  Endpoint mismatch interrupt mask
                                              EPMISM          => False,
                                              --  IN endpoints interrupt mask
                                              IEPINT          => False,
                                              --  OUT endpoints interrupt mask
                                              OEPINT          => False,
                                              --  Incomplete isochronous IN transfer mask
                                              IISOIXFRM       => False,
                                              --  Incomplete periodic transfer mask
                                              PXFRM_IISOOXFRM => False,
                                              --  Data fetch suspended mask
                                              FSUSPM          => False,
                                              --  Read-only. Host port interrupt mask
                                              PRTIM           => False,
                                              --  Host channels interrupt mask
                                              HCIM            => False,
                                              --  Periodic TxFIFO empty mask
                                              PTXFEM          => False,
                                              --  Connector ID status change mask
                                              CIDSCHGM        => False,
                                              --  Disconnect detected interrupt mask
                                              DISCINT         => False,
                                              --  Session request/new session detected interrupt mask
                                              SRQIM           => False,
                                              --  Resume/remote wakeup detected interrupt mask
                                              WUIM            => False,
                                              Reserved_8_9    => 0,
                                              others          => 0);
   end Disable_All_Interrupts;

   --------------------------
   -- Clear_All_Interrupts --
   --------------------------

   procedure Clear_All_Interrupts is
   begin
      OTG_HS_GLOBAL_Periph.OTG_HS_GINTSTS := (CMOD              => False,
                                              --  Mode mismatch interrupt
                                              MMIS              => False,
                                              --  Read-only. OTG interrupt
                                              OTGINT            => False,
                                              --  Start of frame
                                              SOF               => False,
                                              --  Read-only. RxFIFO nonempty
                                              RXFLVL            => False,
                                              --  Read-only. Nonperiodic TxFIFO empty
                                              NPTXFE            => True,
                                              --  Read-only. Global IN nonperiodic NAK effective
                                              GINAKEFF          => False,
                                              --  Read-only. Global OUT NAK effective
                                              BOUTNAKEFF        => False,
                                              --  unspecified
                                              Reserved_8_9      => 16#0#,
                                              --  Early suspend
                                              ESUSP             => False,
                                              --  USB suspend
                                              USBSUSP           => False,
                                              --  USB reset
                                              USBRST            => False,
                                              --  Enumeration done
                                              ENUMDNE           => False,
                                              --  Isochronous OUT packet dropped interrupt
                                              ISOODRP           => False,
                                              --  End of periodic frame interrupt
                                              EOPF              => False,
                                              --  unspecified
                                              Reserved_16_17    => 16#0#,
                                              --  Read-only. IN endpoint interrupt
                                              IEPINT            => False,
                                              --  Read-only. OUT endpoint interrupt
                                              OEPINT            => False,
                                              --  Incomplete isochronous IN transfer
                                              IISOIXFR          => False,
                                              --  Incomplete periodic transfer
                                              PXFR_INCOMPISOOUT => False,
                                              --  Data fetch suspended
                                              DATAFSUSP         => False,
                                              --  Read-only. Host port interrupt
                                              HPRTINT           => False,
                                              --  Read-only. Host channels interrupt
                                              HCINT             => False,
                                              --  Read-only. Periodic TxFIFO empty
                                              PTXFE             => True,
                                              --  Connector ID status change
                                              CIDSCHG           => False,
                                              --  Disconnect detected interrupt
                                              DISCINT           => False,
                                              --  Session request/new session detected interrupt
                                              SRQINT            => False,
                                              --  Resume/remote wakeup detected interrupt
                                              WKUINT            => False,
                                              others            => 0);
   end Clear_All_Interrupts;

   -----------------
   -- Set_RX_Fifo --
   -----------------

   procedure Set_RX_Fifo (Size : UInt16) is
   begin
      OTG_HS_GLOBAL_Periph.OTG_HS_GRXFSIZ.RXFD := Size;
   end Set_RX_Fifo;


   procedure Flush_RX_FIFO is
   begin
      OTG_HS_GLOBAL_Periph.OTG_HS_GRSTCTL.RXFFLSH := True;
      OTG_HS_GLOBAL_Periph.OTG_HS_GRSTCTL.RXFFLSH := True;

      while OTG_HS_GLOBAL_Periph.OTG_HS_GRSTCTL.RXFFLSH loop
         null;
      end loop;
   end Flush_RX_FIFO;

   -------------------
   -- Flush_TX_FIFO --
   -------------------

   procedure Flush_TX_FIFO is
   begin

      --  Flush all FIFO
      OTG_HS_GLOBAL_Periph.OTG_HS_GRSTCTL.TXFNUM := 2#10000#;

      OTG_HS_GLOBAL_Periph.OTG_HS_GRSTCTL.TXFFLSH := True;

      while OTG_HS_GLOBAL_Periph.OTG_HS_GRSTCTL.TXFFLSH loop
         null;
      end loop;
   end Flush_TX_FIFO;

   --------------------------
   -- Set_Global_Interrupt --
   --------------------------

   procedure Set_Global_Interrupt (Enable : Boolean := True) is
   begin
      OTG_HS_GLOBAL_Periph.OTG_HS_GAHBCFG.GINT := Enable;
   end Set_Global_Interrupt;


   --------------
   -- Set_Mode --
   --------------

   procedure Set_Mode (Is_Device : Boolean) is
   begin
      --  Clear mode
      OTG_HS_GLOBAL_Periph.OTG_HS_GUSBCFG.FHMOD := False;
      OTG_HS_GLOBAL_Periph.OTG_HS_GUSBCFG.FDMOD := False;

      --  Set device mode
      if Is_Device then
         OTG_HS_GLOBAL_Periph.OTG_HS_GUSBCFG.FDMOD := True;
      else
         OTG_HS_GLOBAL_Periph.OTG_HS_GUSBCFG.FHMOD := True;
      end if;

      delay until Clock + Milliseconds (50);
   end Set_Mode;

   -----------------
   -- USB_Connect --
   -----------------

   procedure USB_Connect (Connect : Boolean := True) is
   begin
      OTG_HS_DEVICE_Periph.OTG_HS_DCTL.SDIS := Connect;
   end USB_Connect;


   -----------
   -- Valid --
   -----------

   function Valid (EP : EP_Id) return Boolean
   is (EP <= EP_Id (All_EP_Index'Last));

end STM32.USB;
