//
//  DSUController.swift
//  ds4macos
//

import Foundation
import GameController


@available(OSX 11.0, *)
class DSUController {
    
    let motionLock = NSLock()
    
    static let GRAVITY: Double = 1.0
    
    var slot: UInt8 = 0x00
    var model: UInt8 = 0x02 // (with gyro, according to specs)
    var connectionType: UInt8 = 0x02 // 0x01: USB, 0x02: Bluetooth
    var battery: UInt8 = 0x05
    var macAddress: [UInt8] = [0xFA, 0xCE, 0xB0, 0x0C, 0x00, 0x00]
    
    var buttons1: UInt8 = 0x00
    var buttons2: UInt8 = 0x00
    var psButton: UInt8 = 0x00
    var touchBtn: UInt8 = 0x00
    
    var leftStickXplusRightward: UInt8 = 0x00
    var leftStickYplusUpward: UInt8 = 0x00
    
    var rightStickXplusRightward: UInt8 = 0x00
    var rightStickYplusUpward: UInt8 = 0x00
    
    var dpadLeft: UInt8 = 0x00
    var dpadDown: UInt8 = 0x00
    var dpadRight: UInt8 = 0x00
    var dpadUp: UInt8 = 0x00
    
    var buttonSquare: UInt8 = 0x00
    var buttonCross: UInt8 = 0x00
    var buttonCircle: UInt8 = 0x00
    var buttonTriangle: UInt8 = 0x00
    
    var buttonR1: UInt8 = 0x00
    var buttonL1: UInt8 = 0x00
    var buttonR2: UInt8 = 0x00
    var buttonL2: UInt8 = 0x00
    
    var touchPad: [UInt8] = [
        0x00,   // trackpad 1 active
        0x00,   // trackpad 1 id
        0x00, 0x00, // x
        0x00, 0x00, // y
        0x00,   // trackpad 2 active
        0x00,   // trackpad 2 id
        0x00, 0x00, // x
        0x00, 0x00  // y
    ]
    var timeStamp: UInt64 = 0x0000000000000000
    
    let empty: [UInt8] = [0x00, 0x00, 0x00, 0x00]
    
    var accX: [UInt8] = [0x00, 0x00, 0x00, 0x00]
    var accY: [UInt8] = [0x00, 0x00, 0x00, 0x00]
    var accZ: [UInt8] = [0x00, 0x00, 0x00, 0x00]
    
    var gyroX: [UInt8] = [0x00, 0x00, 0x00, 0x00]
    var gyroY: [UInt8] = [0x00, 0x00, 0x00, 0x00]
    var gyroZ: [UInt8] = [0x00, 0x00, 0x00, 0x00]
    
    var prevMotion: GCMotion?
    var controllerService: ControllerService?
    var gameController: GCController?
    
    // Gyro calibration state
    var isCalibrating: Bool = false
    var calibrationSamples: [(x: Double, y: Double, z: Double)] = []
    let requiredSamples = 300
    var gyroDriftOffset: (x: Double, y: Double, z: Double) = (0, 0, 0)
    
    // Diagnostic counters
    var motionCallbackCount: Int = 0
    var lastDiagnosticTime: TimeInterval = 0
    
    // HID fallback for Bluetooth mode
    var hidMotionReader: HIDMotionReader?
    var useHIDMotion: Bool = false
    var hidDiagnosticPrinted: Bool = false
    
    func startCalibration() {
        print("Starting gyro calibration for slot \(slot)...")
        motionLock.lock()
        isCalibrating = true
        calibrationSamples.removeAll()
        gyroDriftOffset = (0, 0, 0)
        motionLock.unlock()
    }
    
    init(controllerService: ControllerService, gameController: GCController, slot: UInt8) {
        self.controllerService = controllerService
        self.gameController = gameController
        
        
        if (self.gameController!.extendedGamepad != nil) {
            self.gameController!.extendedGamepad!.valueChangedHandler = inputValueChange
        } else if (self.gameController!.microGamepad != nil) {
            self.gameController!.microGamepad!.valueChangedHandler = microInputValueChange
        }
        
        if (self.gameController!.motion != nil) {
            self.gameController!.motion!.sensorsActive = true
            self.gameController!.motion!.valueChangedHandler = motionValueChange
            
            // Check if GameController actually provides motion data (BT may return zeros)
            if !isAttached {
                // Start HID reader as fallback, will be activated after first motion check
                self.hidMotionReader = HIDMotionReader()
                self.hidMotionReader?.start()
                // We'll switch to HID after confirming GCMotion returns zeros (in motionValueChange)
            }
        } else {
            self.useHIDMotion = true
            self.hidMotionReader = HIDMotionReader()
            self.hidMotionReader?.start()
        }
        
        self.slot = slot
        self.macAddress[5] = self.slot
        self.lastDiagnosticTime = Date().timeIntervalSince1970
        
        if (self.gameController!.extendedGamepad != nil) {
            self.updateControllerVariables()
        } else if (self.gameController!.microGamepad != nil) {
            self.updateMicroControllerVariables()
        }
    }
    
    func inputValueChange(gamePad: GCExtendedGamepad, element: GCControllerElement) {
        self.updateControllerVariables()
    }
    
    func microInputValueChange(gamePad: GCMicroGamepad, element: GCControllerElement) {
        self.updateMicroControllerVariables()
    }
    
    func motionValueChange(motion: GCMotion) {
        self.motionCallbackCount += 1
        
        // Auto-detect: if BT mode and GCMotion returns zeros, switch to HID fallback
        if !self.useHIDMotion && self.hidMotionReader != nil && self.motionCallbackCount == 50 {
            if !motion.hasAttitudeAndRotationRate &&
               motion.rotationRate.x == 0 && motion.rotationRate.y == 0 && motion.rotationRate.z == 0 {
                self.useHIDMotion = true
            } else {
                // GCMotion works fine, stop the HID reader
                self.hidMotionReader?.stop()
                self.hidMotionReader = nil
            }
        }
        
        self.updateControllerVariables()
        self.prevMotion = motion
        
        // Reset counters every 5 seconds
        let now = Date().timeIntervalSince1970
        if now - self.lastDiagnosticTime > 5.0 {
            self.motionCallbackCount = 0
            self.lastDiagnosticTime = now
        }
    }
    
    func updateControllerVariables() {
        // BUTTONS
        let gamePad = self.gameController!.extendedGamepad!
        
        buttons1 = 0x00
        if gamePad.buttonOptions != nil {
            buttons1 |= gamePad.buttonOptions!.isPressed ?          0x01      : 0x00 // SHARE BUTTON
        }
        if gamePad.leftThumbstickButton != nil {
            buttons1 |= gamePad.leftThumbstickButton!.isPressed ?   0x01 << 1 : 0x00 // L3
        }
        if gamePad.rightThumbstickButton != nil {
            buttons1 |= gamePad.rightThumbstickButton!.isPressed ?  0x01 << 2 : 0x00 // R3
        }
        buttons1 |= gamePad.buttonMenu.isPressed ?                  0x01 << 3 : 0x00 // OPTIONS BUTTON
        buttons1 |= gamePad.dpad.up.isPressed ?                     0x01 << 4 : 0x00
        buttons1 |= gamePad.dpad.right.isPressed ?                  0x01 << 5 : 0x00
        buttons1 |= gamePad.dpad.down.isPressed ?                   0x01 << 6 : 0x00
        buttons1 |= gamePad.dpad.left.isPressed ?                   0x01 << 7 : 0x00
        
        buttons2 = 0x00
        buttons2 |= gamePad.leftTrigger.isPressed ?         0x01      : 0x00 // L2
        buttons2 |= gamePad.rightTrigger.isPressed ?        0x01 << 1 : 0x00 // R2
        buttons2 |= gamePad.leftShoulder.isPressed ?        0x01 << 2 : 0x00 // L1
        buttons2 |= gamePad.rightShoulder.isPressed ?       0x01 << 3 : 0x00 // R1
        buttons2 |= gamePad.buttonX.isPressed ?             0x01 << 4 : 0x00
        buttons2 |= gamePad.buttonA.isPressed ?             0x01 << 5 : 0x00
        buttons2 |= gamePad.buttonB.isPressed ?             0x01 << 6 : 0x00
        buttons2 |= gamePad.buttonY.isPressed ?             0x01 << 7 : 0x00
        
        if gamePad.buttonHome != nil {
            psButton = gamePad.buttonHome!.isPressed ?      0xFF      : 0x00 // PS
        }
        
        leftStickXplusRightward = getUInt8fromFloat(num: gamePad.leftThumbstick.xAxis.value)
        leftStickYplusUpward = getUInt8fromFloat(num: gamePad.leftThumbstick.yAxis.value)

        rightStickXplusRightward = getUInt8fromFloat(num: gamePad.rightThumbstick.xAxis.value)
        rightStickYplusUpward = getUInt8fromFloat(num: gamePad.rightThumbstick.yAxis.value)

        dpadLeft = UInt8(gamePad.dpad.left.value * 255)
        dpadDown = UInt8(gamePad.dpad.down.value * 255)
        dpadRight = UInt8(gamePad.dpad.right.value * 255)
        dpadUp = UInt8(gamePad.dpad.up.value * 255)

        buttonSquare = UInt8(gamePad.buttonX.value * 255)
        buttonCross = UInt8(gamePad.buttonA.value * 255)
        buttonCircle = UInt8(gamePad.buttonB.value * 255)
        buttonTriangle = UInt8(gamePad.buttonY.value * 255)
        
        buttonR1 = UInt8(gamePad.rightShoulder.value * 255)
        buttonL1 = UInt8(gamePad.leftShoulder.value * 255)
        
        buttonR2 = UInt8(gamePad.rightTrigger.value * 255)
        buttonL2 = UInt8(gamePad.leftTrigger.value * 255)
        
        // skipping touchpad for now
        
        // MOTION
        timeStamp = UInt64(Date.init().timeIntervalSince1970 * 1000000)
        
        self.motionLock.lock()
        
        if self.useHIDMotion, let hidData = self.hidMotionReader?.getIMUData() {
            // === HID Fallback Path (Bluetooth) ===
            // Nintendo Switch Pro Controller raw HID axis mapping -> DSU Server axis mapping
            accX = getUInt8arrayFromDouble(num: hidData.ay)
            accY = getUInt8arrayFromDouble(num: -hidData.az)
            accZ = getUInt8arrayFromDouble(num: hidData.ax)
            
            var rawX = hidData.gx
            var rawY = hidData.gy
            var rawZ = hidData.gz
            
            if self.isCalibrating {
                self.calibrationSamples.append((rawX, rawY, rawZ))
                if self.calibrationSamples.count >= self.requiredSamples {
                    let avgX = self.calibrationSamples.map { $0.x }.reduce(0, +) / Double(self.calibrationSamples.count)
                    let avgY = self.calibrationSamples.map { $0.y }.reduce(0, +) / Double(self.calibrationSamples.count)
                    let avgZ = self.calibrationSamples.map { $0.z }.reduce(0, +) / Double(self.calibrationSamples.count)
                    self.gyroDriftOffset = (avgX, avgY, avgZ)
                    self.isCalibrating = false
                    print("Calibration complete (HID) for slot \(self.slot). Offset: \(self.gyroDriftOffset)")
                }
            } else {
                rawX -= self.gyroDriftOffset.x
                rawY -= self.gyroDriftOffset.y
                rawZ -= self.gyroDriftOffset.z
            }
            
            gyroX = getUInt8arrayFromDouble(num: -self.radiansToDegree(num: rawY))
            gyroY = getUInt8arrayFromDouble(num: -self.radiansToDegree(num: rawZ))
            gyroZ = getUInt8arrayFromDouble(num: self.radiansToDegree(num: rawX))
            
        } else if self.gameController!.motion != nil, let motion = self.gameController?.motion! {
            // === Normal GameController Path (USB) ===
            accX = getUInt8arrayFromDouble(num: motion.acceleration.x)
            accY = getUInt8arrayFromDouble(num: motion.acceleration.z)
            accZ = getUInt8arrayFromDouble(num: -motion.acceleration.y)
            
            var rawX = motion.rotationRate.x
            var rawY = motion.rotationRate.y
            var rawZ = motion.rotationRate.z
            
            if self.isCalibrating {
                self.calibrationSamples.append((rawX, rawY, rawZ))
                if self.calibrationSamples.count >= self.requiredSamples {
                    let avgX = self.calibrationSamples.map { $0.x }.reduce(0, +) / Double(self.calibrationSamples.count)
                    let avgY = self.calibrationSamples.map { $0.y }.reduce(0, +) / Double(self.calibrationSamples.count)
                    let avgZ = self.calibrationSamples.map { $0.z }.reduce(0, +) / Double(self.calibrationSamples.count)
                    self.gyroDriftOffset = (avgX, avgY, avgZ)
                    self.isCalibrating = false
                    print("Calibration complete for slot \(self.slot). Offset: \(self.gyroDriftOffset)")
                }
            } else {
                rawX -= self.gyroDriftOffset.x
                rawY -= self.gyroDriftOffset.y
                rawZ -= self.gyroDriftOffset.z
            }
            
            gyroX = getUInt8arrayFromDouble(num: self.radiansToDegree(num: rawX))
            gyroY = getUInt8arrayFromDouble(num: -self.radiansToDegree(num: rawZ))
            gyroZ = getUInt8arrayFromDouble(num: self.radiansToDegree(num: rawY))
        }
        
        self.motionLock.unlock()
    }
    
    func updateMicroControllerVariables() {
        // BUTTONS
        let gamePad = self.gameController!.microGamepad!
        
        buttons1 = 0x00
        buttons1 |= gamePad.buttonMenu.isPressed ?              0x01 << 3 : 0x00 // OPTIONS BUTTON
        buttons1 |= gamePad.dpad.up.isPressed ?                 0x01 << 4 : 0x00
        buttons1 |= gamePad.dpad.right.isPressed ?              0x01 << 5 : 0x00
        buttons1 |= gamePad.dpad.down.isPressed ?               0x01 << 6 : 0x00
        buttons1 |= gamePad.dpad.left.isPressed ?               0x01 << 7 : 0x00
        
        buttons2 = 0x00
        buttons2 |= gamePad.buttonX.isPressed ?         0x01 << 4 : 0x00
        buttons2 |= gamePad.buttonA.isPressed ?         0x01 << 5 : 0x00
//        buttons2 |= gamePad.buttonB.isPressed ?         0x01 << 6 : 0x00
//        buttons2 |= gamePad.buttonY.isPressed ?         0x01 << 7 : 0x00

        dpadLeft = UInt8(gamePad.dpad.left.value * 255)
        dpadDown = UInt8(gamePad.dpad.down.value * 255)
        dpadRight = UInt8(gamePad.dpad.right.value * 255)
        dpadUp = UInt8(gamePad.dpad.up.value * 255)

        buttonSquare = UInt8(gamePad.buttonX.value * 255)
        buttonCross = UInt8(gamePad.buttonA.value * 255)
        
        // skipping touchpad for now
        
        // MOTION
        timeStamp = UInt64(Date.init().timeIntervalSince1970 * 1000000)
        
        if self.gameController!.motion != nil, let motion = self.gameController?.motion! {
            self.motionLock.lock()
            // acceleration
            accX = getUInt8arrayFromDouble(num: motion.acceleration.x)
            accY = getUInt8arrayFromDouble(num: -motion.acceleration.z)
            accZ = getUInt8arrayFromDouble(num: motion.acceleration.y)
            
            // gyroscope
            var rawX = motion.rotationRate.x
            var rawY = motion.rotationRate.y
            var rawZ = motion.rotationRate.z
            
            if self.isCalibrating {
                self.calibrationSamples.append((rawX, rawY, rawZ))
                if self.calibrationSamples.count >= self.requiredSamples {
                    let avgX = self.calibrationSamples.map { $0.x }.reduce(0, +) / Double(self.calibrationSamples.count)
                    let avgY = self.calibrationSamples.map { $0.y }.reduce(0, +) / Double(self.calibrationSamples.count)
                    let avgZ = self.calibrationSamples.map { $0.z }.reduce(0, +) / Double(self.calibrationSamples.count)
                    
                    self.gyroDriftOffset = (avgX, avgY, avgZ)
                    self.isCalibrating = false
                    print("Calibration complete for slot \(self.slot). Offset: \(self.gyroDriftOffset)")
                }
            } else {
                rawX -= self.gyroDriftOffset.x
                rawY -= self.gyroDriftOffset.y
                rawZ -= self.gyroDriftOffset.z
            }
            
            gyroX = getUInt8arrayFromDouble(num: self.radiansToDegree(num: rawX))
            gyroY = getUInt8arrayFromDouble(num: -self.radiansToDegree(num: rawZ))
            gyroZ = getUInt8arrayFromDouble(num: self.radiansToDegree(num: rawY))
            self.motionLock.unlock()
        }
    }
    
    private func getUInt8fromFloat(num: Float) -> UInt8 {
        if num < 0 {
            return UInt8(bitPattern: Int8((num + 1) * 127))
        } else {
            return UInt8(num * 127 + 128)
        }
    }
    
    private func radiansToDegree(num: Double) -> Double {
        return num * (180.0 / Double.pi)
    }
    
    private func getUInt8arrayFromDouble(num: Double) -> [UInt8] {
        return self.toByteArray(Float(num))
    }
    
    private func getTimestampUInt8array(timeStamp: UInt64) -> [UInt8] {
        return [
            UInt8(truncatingIfNeeded: timeStamp) & 0xFF,
            UInt8(truncatingIfNeeded: timeStamp >> 8) & 0xFF,
            UInt8(truncatingIfNeeded: timeStamp >> 16) & 0xFF,
            UInt8(truncatingIfNeeded: timeStamp >> 24) & 0xFF,
            UInt8(truncatingIfNeeded: timeStamp >> 32) & 0xFF,
            UInt8(truncatingIfNeeded: timeStamp >> 40) & 0xFF,
            UInt8(truncatingIfNeeded: timeStamp >> 48) & 0xFF,
            UInt8(truncatingIfNeeded: timeStamp >> 56) & 0xFF,
        ]
    }
    
    func getDataPacket(counter: UInt32) -> [UInt8] {
        var packet: [UInt8] = [
            slot,
            0x02,
            model,
            0x02,
            macAddress[0], macAddress[1], macAddress[2], // Mac part 1
            macAddress[3], macAddress[4], macAddress[5], // Mac part 2
            battery,
            0x01,   // Controller ACTIVE state
            UInt8(truncatingIfNeeded: counter) & 0xFF,
            UInt8(truncatingIfNeeded: counter >> 8) & 0xFF,
            UInt8(truncatingIfNeeded: counter >> 16) & 0xFF,
            UInt8(truncatingIfNeeded: counter >> 24) & 0xFF,
            
            buttons1,
            buttons2,
            
            psButton,
            touchBtn,
            
            leftStickXplusRightward,
            leftStickYplusUpward,
            rightStickXplusRightward,
            rightStickYplusUpward,
            
            dpadLeft,
            dpadDown,
            dpadRight,
            dpadUp,
            
            buttonSquare,
            buttonCross,
            buttonCircle,
            buttonTriangle,
            
            buttonR1,
            buttonL1,
            
            buttonR2,
            buttonL2,
        ]
        
        packet.append(contentsOf: touchPad)
        packet.append(contentsOf: getTimestampUInt8array(timeStamp: timeStamp))
        self.motionLock.lock()
        packet.append(contentsOf: accX)
        packet.append(contentsOf: accY)
        packet.append(contentsOf: accZ)
        packet.append(contentsOf: gyroX)
        packet.append(contentsOf: gyroY)
        packet.append(contentsOf: gyroZ)
        self.motionLock.unlock()
        
        return DSUMessage.make(type: DSUMessage.TYPE_DATA, data: packet)
    }
    
    func getInfoPacket() -> [UInt8] {
        let packet: [UInt8] = [
            slot,
            0x02,
            model,
            connectionType,
            macAddress[0], macAddress[1], macAddress[2], // Mac part 1
            macAddress[3], macAddress[4], macAddress[5], // Mac part 2
            battery,
            0x01,   // Controller ACTIVE state
        ]
        
        return packet
    }
    
    static func defaultInfoPacket(index: UInt8) -> [UInt8] {
        let packet: [UInt8] = [
            index, // pad id
            0x00, // state (disconnected)
            0x01, // model (generic)
            0x01, // Connection type USB
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // Mac
            0x00, // Battery
            0x00, // ? (Needs to be a zero byte according to specs)
        ]
        
        return packet
    }
    
    private func toByteArray<T>(_ value: T) -> [UInt8] {
        var value = value
        return withUnsafeBytes(of: &value) { Array($0) }
    }
    
}

extension GCMotion {
    
    func radiansToDegree(num: Double) -> Double {
        return num * (180.0 / Double.pi)
    }
    
    func eulerAngles() -> GCEulerAngles {
        let x = self.attitude.x
        let y = self.attitude.y
        let z = self.attitude.z
        let w = self.attitude.w
        let roll  = self.radiansToDegree(num: atan2(2 * y * w - 2 * x * z, 1 - 2 * y * y - 2 * z * z))
        let pitch = self.radiansToDegree(num: atan2(2 * x * w - 2 * y * z, 1 - 2 * x * x - 2 * z * z))
        let yaw   = self.radiansToDegree(num: asin(2 * x * y + 2 * z * w))
        return GCEulerAngles(pitch: pitch, yaw: yaw, roll: roll)
    }
    
}
