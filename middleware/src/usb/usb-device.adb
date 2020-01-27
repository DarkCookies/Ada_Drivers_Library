with Ada.Text_IO;

with System.Storage_Elements; use System.Storage_Elements;

package body USB.Device is
   Verbose : constant Boolean := False;
   procedure Put_Line (Str : String);
   procedure Put_Line (Str : String) is
   begin
      if Verbose then
         Ada.Text_IO.Put_Line (Str);
      end if;
   end Put_Line;

   ----------------
   -- Get_String --
   ----------------

   function Get_String (This  : in out USB.Device.USB_Device;
                        Index : UInt8)
                        return Setup_Request_Answer
   is
   begin
      for Str of This.Strings.all loop
         if Str.Index = Index then

            This.Ctrl_Buf := Str.Str.all'Address;
            This.Ctrl_Len := Str.Str.all'Size / 8;
            return Handled;
         end if;
      end loop;

      return Not_Supported;
   end Get_String;

   --------------------
   -- Get_Descriptor --
   --------------------

   function Get_Descriptor (This : in out USB_Device;
                            Req  : Setup_Data)
                            return Setup_Request_Answer
   is
      Index     : constant UInt8 := UInt8 (Req.Value and 16#FF#);
      Desc_Type : constant UInt8 := UInt8 (Shift_Right (Req.Value, 8) and 16#FF#);
   begin

      case Desc_Type is
         when 1 => -- DT_DEVICE
            Put_Line ("DT_DEVICE");
            This.Ctrl_Buf := This.Desc.all'Address;
            This.Ctrl_Len := This.Desc.all'Size / 8;
            return Handled;
         when 2 => -- DT_CONFIGURATION
            Put_Line ("DT_CONFIGURATION");
            This.Ctrl_Buf := This.Config.all'Address;
            This.Ctrl_Len := This.Config.all'Size / 8;
            return Handled;
         when 3 => -- DT_STRING
            Put_Line ("DT_STRING");
            return Get_String (This, Index);
         when 6 => -- DT_QUALIFIER

            Put_Line ("DT_QUALIFIER");

            --  Qualifier descriptor is only available on HS device. This is not
            --  supported yet.
            return Not_Supported;

         when others =>
            raise Program_Error with "Descriptor not implemented";
            return Not_Supported;
      end case;
   end Get_Descriptor;

   -----------------
   -- Set_Address --
   -----------------

   function Set_Address (This : in out USB_Device;
                         Req  : Setup_Data)
                         return Setup_Request_Answer
   is
   begin
      This.Dev_Addr := UInt7 (Req.Value and 16#7F#);

      if Verbose then
         Put_Line ("Set Address: " & This.Dev_Addr'Img);
      end if;

      if This.UDC.Early_Address then
         --  The DWC OTG USB requires the address to be set at this point...
         This.UDC.Set_Address (This.Dev_Addr);
      end if;

      --  Reply with Zero-Length-Packet
      This.Ctrl_Buf := System.Null_Address;
      This.Ctrl_Len := 0;
      return Handled;
   end Set_Address;

   -----------------------
   -- Set_Configuration --
   -----------------------

   function Set_Configuration (This : in out USB_Device;
                               Req  : Setup_Data)
                               return Setup_Request_Answer
   is
   begin
      return This.Class.Configure (This.UDC.all, Req.Value);
   end Set_Configuration;

   ----------------------------
   -- Control_Device_Request --
   ----------------------------

   function Control_Device_Request  (This : in out USB_Device;
                                     Req  : Setup_Data)
                                     return Setup_Request_Answer
   is
   begin
      Put_Line ("Control Dev Req");
      case Req.Request is
         when 0 => -- GET_STATUS
            raise Program_Error with "GET_STATUS not implemented";
         when 1 => -- CLEAR_FEATURE
            raise Program_Error with "CLEAR_FEATURE not implemented";
         when 3 => -- SET_FEATURE
            raise Program_Error with "SET_FEATURE not implemented";
         when 5 => -- SET_ADDRESS
            return Set_Address (This, Req);
         when 6 => -- GET_DESCRIPTOR
            return Get_Descriptor (This, Req);
         when 7 => -- SET_DESCRIPTOR
            raise Program_Error with "SET_DESCRIPTOR not implemented";
         when 8 => -- GET_CONFIGURATION
            raise Program_Error with "GET_CONFIGURATION not implemented";
         when 9 => -- SET_CONFIGURATION
            return Set_Configuration (This, Req);
         when others =>
            raise Program_Error with "Request not implemented";
      end case;
   end Control_Device_Request;

   ------------------------------
   -- Control_Dispatch_Request --
   ------------------------------

   function Control_Dispatch_Request (This : in out USB_Device;
                                      Req  : Setup_Data)
                                      return Setup_Request_Answer
   is
   begin
      Put_Line ("Control_Dispatch_Request");

      --  TODO: User callbacks...

      --  Standard handling

      if Req.RType.Typ in Class | Vendor then
         return This.Class.Setup_Request (Req, This.Ctrl_Buf, This.Ctrl_Len);
      end if;

      if Req.RType.Typ /= Stand then
         raise Program_Error with "Request type not supported";
      end if;

      case Req.RType.Recipient is
         when Dev =>
            return Control_Device_Request (This, Req);
         when Iface =>
            Put_Line ("Control Iface Req not impl");

            --  Send interface request to the class
            return This.Class.Setup_Request (Req, This.Ctrl_Buf, This.Ctrl_Len);
         when Endpoint =>
            Put_Line ("Control Endpoint Req not impl");
            return Not_Supported;
         when Other =>
            Put_Line ("Control Other Req not impl");
            return Not_Supported;
      end case;
   end Control_Dispatch_Request;

   ------------------------------------
   -- Control_Dispatch_Write_Request --
   ------------------------------------

   function Control_Dispatch_Write_Request (This : in out USB_Device)
                                            return Setup_Request_Answer
   is
   begin

      --  If we don't know how to handle this request, fallback to the class
      return This.Class.Setup_Write_Request (This.Ctrl_Req,
                                             This.RX_Ctrl_Buf (1 .. Natural (This.Ctrl_Len)));
   end Control_Dispatch_Write_Request;

   ------------------------
   -- Control_Send_Chunk --
   ------------------------

   procedure Control_Send_Chunk (This : in out USB_Device) is
   begin
      if Buffer_Len (This.Desc.bMaxPacketSize0) < This.Ctrl_Len then

         This.UDC.EP_Write_Packet (0,
                                   This.Ctrl_Buf,
                                   UInt32 (This.Desc.bMaxPacketSize0));

         This.Ctrl_Buf := This.Ctrl_Buf + Buffer_Len (This.Desc.bMaxPacketSize0);
         This.Ctrl_Len := This.Ctrl_Len - Buffer_Len (This.Desc.bMaxPacketSize0);
         This.Ctrl_State := Data_In;

      else
         This.UDC.EP_Write_Packet (0, This.Ctrl_Buf, UInt32 (This.Ctrl_Len));

         if This.Ctrl_Need_ZLP then
            This.Ctrl_State := Data_In;
         else
            This.Ctrl_State := Last_Data_In;
         end if;

         This.Ctrl_Buf := System.Null_Address;
         This.Ctrl_Len := 0;
         This.Ctrl_Need_ZLP := False;
      end if;
   end Control_Send_Chunk;

   ---------------------------
   -- Control_Receive_Chunk --
   ---------------------------

   procedure Control_Receive_Chunk (This : in out USB_Device) is
      Read_Size : constant Buffer_Len :=
        Buffer_Len'Min (Buffer_Len (This.Desc.bMaxPacketSize0),
                        Buffer_Len (This.Ctrl_Req.Length) - This.Ctrl_Len);
   begin

      This.UDC.EP_Read_Packet (Ep   => 0,
                               Addr => This.Ctrl_Buf,
                               Len  => UInt32 (Read_Size));

      This.Ctrl_Len := This.Ctrl_Len + Read_Size;
      This.Ctrl_Buf := This.Ctrl_Buf + Read_Size;
   end Control_Receive_Chunk;

   ------------------------
   -- Control_Setup_Read --
   ------------------------

   procedure Control_Setup_Read (This : in out USB_Device;
                                 Req  : Setup_Data)
   is
   begin
      Put_Line ("Control_Setup_Read");
      if Control_Dispatch_Request (This, Req) /= Not_Supported then

         if Req.Length > 0 then

            This.Ctrl_Len :=
              Buffer_Len'Min (This.Ctrl_Len, Buffer_Len (Req.Length));

            This.Ctrl_Need_ZLP := Need_ZLP (This.Ctrl_Len,
                                            Req.Length,
                                            This.Desc.bMaxPacketSize0);

            Control_Send_Chunk (This);
         else
            --  zero-length-packet to ack the setup req
            This.UDC.EP_Write_Packet (0, System.Null_Address, 0);
            This.Ctrl_State := Status_In;
         end if;
      else
         --  Stall transaction to indicate an error
         This.UDC.EP_Set_Stall ((0, EP_In));
         This.UDC.EP_Set_Stall ((0, EP_Out));
         This.Ctrl_State := Idle;
      end if;
   end Control_Setup_Read;

   -------------------------
   -- Control_Setup_Write --
   -------------------------

   procedure Control_Setup_Write (This : in out USB_Device;
                                  Req  : Setup_Data)
   is
   begin
      Put_Line ("Control_Setup_Write");

      if Req.Length > This.RX_Ctrl_Buf'Length then
         --  Error, cannot receive data
         --  FIXME: Stall transaction
         return;
      end if;

      --  Get ready to recieve the data

      This.Ctrl_Len := 0;
      This.Ctrl_Buf := This.RX_Ctrl_Buf'Address;

      if Req.Length > UInt16 (This.Desc.bMaxPacketSize0) then
         This.Ctrl_State := Data_Out;
      else
         This.Ctrl_State := Last_Data_Out;
      end if;

      This.UDC.EP_Set_NAK ((0, EP_Out), False);

   end Control_Setup_Write;

   -------------------
   -- Control_Setup --
   -------------------

   procedure Control_Setup (This : in out USB_Device;
                            EP   : EP_Id;
                            Req  : Setup_Data)
   is
   begin

      This.UDC.EP_Set_NAK ((EP, EP_Out), True);

      if Verbose then
         Put_Line ("Req: " & Img (Req));
      end if;

      if Req.RType.Dir = Device_To_Host or else Req.Length = 0 then
         Control_Setup_Read (This, Req);
      else
         Control_Setup_Write (This, Req);
      end if;
   end Control_Setup;

   -----------------
   -- Initialized --
   -----------------

   function Initialized (This : USB_Device) return Boolean
   is (This.UDC /= null);

   ---------------
   -- Initalize --
   ---------------

   procedure Initalize (This       : in out USB_Device;
                        Controller : not null HAL.USB.Device.Any_USB_Device_Controller;
                        Class      : not null USB.Classes.Any_USB_Device_Class;
                        Dec        : not null access constant Device_Descriptor;
                        Config     : not null access constant UInt8_Array;
                        Strings    : not null access constant String_Array)
   is
   begin
      This.UDC := Controller;
      This.Class := Class;
      This.Desc := Dec;
      This.Config := Config;
      This.Strings := Strings;
   end Initalize;

   -----------
   -- Start --
   -----------

   procedure Start (This : in out USB_Device) is
   begin

      --  TODO: Clear previous Class

      --  TODO: Set descriptor

      --  TODO: This.State := Default
      --  TODO: This.Id := Id;

      This.UDC.Initialize; --  This should actually init

      This.UDC.Start;

      --  TODO: Register class
   end Start;

   -----------
   -- Reset --
   -----------

   procedure Reset (This : in out USB_Device) is
   begin
      This.UDC.EP_Setup ((0, EP_In), Control, UInt16 (This.Desc.bMaxPacketSize0), null);

      This.UDC.EP_Setup ((0, EP_Out), Control, UInt16 (This.Desc.bMaxPacketSize0), null);

      This.UDC.Set_Address (0);

      --  TODO: reset callback
   end Reset;

   ----------------
   -- Control_In --
   ----------------

   procedure Control_In (This : in out USB_Device) is
   begin
      case This.Ctrl_State is
         when Data_In =>
            Control_Send_Chunk (This);
         when Last_Data_In =>
            This.Ctrl_State := Status_Out;
            This.UDC.EP_Set_NAK ((0, EP_Out), False);
         when Status_In =>
            --  FIXME: Status_In Complete callback?

            Put_Line ("Status_In");
            --  Handle set address request
            if This.Ctrl_Req.RType = (Dev, 0, Stand, Host_To_Device)
              and then
                This.Ctrl_Req.Request = 5 -- SET_ADDRESS

            then
               This.UDC.Set_Address (UInt7 (This.Ctrl_Req.Value and 16#7F#));
               This.Dev_State := Addressed;
            end if;

            This.Ctrl_State := Idle;

         when others =>
            --  FIXME: Stall transaction
            raise Program_Error with "should stall";
      end case;
   end Control_In;

   -----------------
   -- Control_Out --
   -----------------

   procedure Control_Out (This : in out USB_Device;
                          BCNT : UInt11)
   is
   begin
      case This.Ctrl_State is
         when Status_Out =>

            if BCNT /= 0 then
               raise Program_Error with "ZLP expected for Status_Out";
            end if;

            --  "Read" Zero_Length-Packet
            This.UDC.EP_Read_Packet (0, System.Null_Address, 0);

            This.Ctrl_State := Idle;

            --  FIXME: Callback?

         when Data_Out =>

            --  Receive a chunk
            Control_Receive_Chunk (This);

            --  Check if the next chunk is going to be the last
            if (Buffer_Len (This.Ctrl_Req.Length) - This.Ctrl_Len) <= Buffer_Len (This.Desc.bMaxPacketSize0)
            then
               This.Ctrl_State := Last_Data_Out;
            end if;

         when Last_Data_Out =>

            --  Receive the last chunk
            Control_Receive_Chunk (This);

            if Control_Dispatch_Write_Request (This) = Handled then
               --  zero-length-packet to ack the setup req
               This.UDC.EP_Write_Packet (0, System.Null_Address, 0);
               This.Ctrl_State := Status_In;
            else
               This.UDC.EP_Set_Stall (EP => EP_Addr'(0, EP_Out));
            end if;

         when others =>
            This.UDC.EP_Set_Stall (EP => EP_Addr'(0, EP_Out));
      end case;
   end Control_Out;

   ----------
   -- Poll --
   ----------

   procedure Poll (This : in out USB_Device) is
   begin

      loop
         declare
            Evt : constant UDC_Event := This.UDC.Poll;
         begin
            case Evt.Kind is
            when Reset =>
               Put_Line ("Poll: Reset");
               Reset (This);
            when Setup_Request =>
               Put_Line ("Poll: Setup_Request");
               This.Ctrl_Req := Evt.Req;
               Control_Setup (This, Evt.Req_EP, Evt.Req);
               null;
            when Data_Ready =>
               Put_Line ("Poll: Data_Ready");
               if Evt.RX_EP = 0 then
                  Control_Out (This, Evt.RX_BCNT);
               else
                  This.Class.Data_Ready (This.UDC.all,
                                         Evt.RX_EP,
                                         UInt32 (Evt.RX_BCNT));
               end if;
            when Transfer_Complete =>
               Put_Line ("Poll: Transfer_Complete");
               if Evt.T_EP = (0, EP_In) then
                  Control_In (This);
               else
                  This.Class.Transfer_Complete (This.UDC.all, Evt.T_EP);
               end if;
            when None =>
               Put_Line ("Poll: None");
               return;
            end case;
         end;
      end loop;
   end Poll;

   ----------------
   -- Controller --
   ----------------

   function Controller (This : USB_Device) return not null Any_USB_Device_Controller
   is (This.UDC);

end USB.Device;