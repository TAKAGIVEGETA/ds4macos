Based on the original ds4macos project, the following macOS-specific enhancements have been added:

### New Features:

- **陀螺仪软件校准 / Software Gyro Calibration**
  - **中文**: 彻底解决了 macOS 平台手柄（Pro Controller, DS4, DualSense）在模拟器中的体感漂移问题。新增 3 秒静止采样校准功能。
  - **English**: Completely resolved gyroscope drift issues for controllers (Pro Controller, DS4, DualSense) on macOS emulators. Added a 3-second static sampling calibration feature.

- **DSU 服务器稳定性优化 / DSU Server Stability Optimization**
  - **中文**: 修复了 DSU 协议在处理高频数据时的计算溢出 Bug，提升了体感数据回传的响应速度与稳定性。
  - **English**: Fixed calculation overflow bugs in the DSU protocol during high-frequency data processing, enhancing the responsiveness and stability of motion data.
  
<img width="1800" height="900" alt="image" src="https://github.com/user-attachments/assets/f6febc8b-6197-4ebc-888c-02aa683ee0aa" />
