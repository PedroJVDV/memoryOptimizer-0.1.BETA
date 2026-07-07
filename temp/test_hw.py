import HardwareMonitor as HM

def print_hardware():
    hardware_list = HM.get_hardware()
    for hw in hardware_list:
        print(f"[{hw.HardwareType}] {hw.Name}")
        for sensor in hw.Sensors:
            print(f"  - {sensor.SensorType} ({sensor.Name}): {sensor.Value}")

print_hardware()
