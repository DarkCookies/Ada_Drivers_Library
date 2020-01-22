package STM32.USB is

   procedure Core_Init;
   procedure Core_Reset;
   procedure Flush_RX_FIFO;
   procedure Flush_TX_FIFO;
   procedure Disable_All_Interrupts;
   procedure Clear_All_Interrupts;
   procedure Set_Global_Interrupt (Enable : Boolean := True);
   procedure Set_Mode (Is_Device : Boolean);
   procedure Set_RX_Fifo (Size : UInt16);
   procedure Set_TX_Fifo (This : in out OTG_USB_Device;
                          Ep   : EP_Id;
                          Size : UInt16);
   procedure USB_Connect (Connect : Boolean := True);
   function Valid (EP : EP_Id) return Boolean;

end STM32.USB;
