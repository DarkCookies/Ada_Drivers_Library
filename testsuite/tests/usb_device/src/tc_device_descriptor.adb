with USB_Testing;               use USB_Testing;
with USB_Testing.UDC_Stub;
with USB_Testing.UDC_Scenarios;

with HAL; use HAL;

with USB;
with USB.Device;

procedure TC_Device_Descriptor is

   Scenario : aliased constant UDC_Stub.Stub_Scenario :=
     UDC_Scenarios.Enumeration (Verbose => True);

   RX_Data : aliased constant UInt8_Array := (0 .. 1 => 0);

begin

   USB_Testing.UDC_Scenarios.Basic_UDC_Test (Scenario, RX_Data);

end TC_Device_Descriptor;
