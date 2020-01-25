with HAL.USB; use HAL.USB;

with STM32_SVD.USB_OTG_HS; use STM32_SVD.USB_OTG_HS;

package STM32.USB is
   type All_EP_Index is range 0 .. 5;

   subtype EP_Index is All_EP_Index range 1 .. All_EP_Index'Last;

   subtype TX_Fifo_Index is EP_Index;

   type DIEPTXF_Register_Array is array (TX_Fifo_Index)
     of OTG_HS_DIEPTXF_Register;

   Global_DIEPTXF : DIEPTXF_Register_Array := (OTG_HS_GLOBAL_Periph.OTG_HS_DIEPTXF1,
                                               OTG_HS_GLOBAL_Periph.OTG_HS_DIEPTXF2,
                                               OTG_HS_GLOBAL_Periph.OTG_HS_DIEPTXF3,
                                               OTG_HS_GLOBAL_Periph.OTG_HS_DIEPTXF4,
                                               OTG_HS_GLOBAL_Periph.OTG_HS_DIEPTXF5);

   procedure Core_Init;
   procedure Core_Reset;
   procedure Flush_RX_FIFO;
   procedure Flush_TX_FIFO;
   procedure Disable_All_Interrupts;
   procedure Clear_All_Interrupts;
   procedure Set_Global_Interrupt (Enable : Boolean := True);
   procedure Set_Mode (Is_Device : Boolean);
   procedure Set_RX_Fifo (Size : UInt16);
   procedure USB_Connect (Connect : Boolean := True);
   function Valid (EP : EP_Id) return Boolean;

end STM32.USB;
