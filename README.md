# Project Name: Environmental Monitor
Developed an environmental monitor that reads a dht11 sensor and displays the data on an lcd screen. Based on sensor's readings the system choses to activate the fans and decides whether to activate dehumidification, and enter either cooling mode, or stationary mode. I am currently developing the modular technology to deploy the device for different applications.

## 🛠️ System Specifications

### Hardware
* **Main Controller:** STM32F401RE
* **Sensors:** dht11, ky-040
* **Power:** 3S LiPo Battery with 5V Buck Regulator
* **Fan:** 30 mm Fan 3.3V DC 

### Software & Dependencies
* **OS:** Ubuntu 22.04 LTS
* **Framework:** ROS2 Humble Hawksbill
* **Libraries:** OpenCV 4.5, NumPy

---

## 🔌 Wiring & Architecture

### Wiring Diagram
<img width="810" height="567" alt="image" src="https://github.com/user-attachments/assets/a3857110-5ad5-4db3-ae70-6a9776e8fc15" />

### Pin Mapping Table

| Peripheral Device | Device Pin | Host Board | Host Pin |
| :--- | :--- | :--- | :--- |
| Left Motor Encoder | OUT A | ESP32 | GPIO 34 |
| MPU6050 IMU | SDA | ESP32 | GPIO 21 |



