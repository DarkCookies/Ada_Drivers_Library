package USB.Device.Classes is
   
   -- Device Class Interface --
   type USB_Device_Class is interface;
   type Any_USB_Device_Class is access all USB_Device_Class'Class;

   function Configure (This  : in out USB_Device_Class;
                       UDC   : in out USB_Device_Controller'Class;
                       Index : UInt16)
                       return Setup_Request_Answer
   is abstract;

   function Setup_Request (This  : in out USB_Device_Class;
                           Req   : HAL.USB.Setup_Data;
                           Buf   : out System.Address;
                           Len   : out Buffer_Len)
                           return Setup_Request_Answer
   is abstract;

   function Setup_Write_Request (This  : in out USB_Device_Class;
                                 Req   : HAL.USB.Setup_Data;
                                 Data  : UInt8_Array)
                                 return Setup_Request_Answer
   is abstract;

   procedure Transfer_Complete (This : in out USB_Device_Class;
                                UDC  : in out USB_Device_Controller'Class;
                                EP   : HAL.USB.EP_Addr)
   is abstract;

   procedure Data_Ready (This : in out USB_Device_Class;
                         UDC  : in out USB_Device_Controller'Class;
                         EP   : HAL.USB.EP_Id;
                         BCNT : UInt32)
   is abstract;

end USB.Device.Classes;
