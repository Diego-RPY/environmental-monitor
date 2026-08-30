# Project Name: Environmental Monitor
Developed an environmental monitor that reads a DHT11 sensor and displays the data on an lcd screen. Based on sensor's readings the system choses to activate the fans and decides whether to activate dehumidification, and enter either cooling mode, or stationary mode. I am currently developing the modular technology to deploy the device for different applications.

## Firmware Architecture
<img width="792" height="827" alt="image" src="https://github.com/user-attachments/assets/9f7aed65-95d0-4af9-9eff-564ad5cd0369" />

---

## Hardware Architecture
WARNING: Make sure all the components are tied to the STM32 ground.

<img width="810" height="567" alt="image" src="https://github.com/user-attachments/assets/a3857110-5ad5-4db3-ae70-6a9776e8fc15" />

---

## System Specifications

### Hardware
* **Main Controller:** STM32F401RE
* **Sensors:** DHT11, KY-040
* **Power:** 3.7V 3000mAh 103665 1S LiPo Battery, Micro JST 1.25mm 2-Pin, micro-USB to USB and plug into computer
* **Actuators & Fans:** 30 mm Fan 3.3V DC
* **Displays:** LCD 2004

### Software & Dependencies
* **Development Environment:** Arduino IDE (v2.3.10 recommended)
* **Board Manager:** STM 32 MCU based boards (v2.12.0) installed via the the Arduino Boards Manager

---

## Usage & Bringup

### Prerequisites
* Arduino IDE
* STM 32 Board Support Package (version 2.12.0) installed via the Arduino Boards Manager

### 1. Hardware Checklist
1. Connect the power source and ensure the LCD 2004 screen backlight turns on (blue screen light).
2. Manually connect the fan to the battery and check that the fan blades are spinning.
3. Connect the STM 32 board to the computer. Ensure the ARDUINO IDE recognizes the STM 32 board, and that the board's red LED turns on.

### 2. Execution
Note: This project leverages ARM Assembly (.S) for low-level performance.
1. Open your file manager and navigate to the /firmware/Final_Test_With_Treshold/ directory in this repository.
2. Double-click the main .ino file to launch it directly inside the Arduino IDE. (The IDE will automatically open the accompanying .S assembly tab next to it).
3. Navigate to the Tools > Board menu and select STM32F401RE
4. Select your exact board type and COM Port from the **Tools** menu.
5. Click the **Upload** arrow button in the top toolbar.



