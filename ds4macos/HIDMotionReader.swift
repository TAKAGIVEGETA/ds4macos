//
//  HIDMotionReader.swift
//  ds4macos
//
//  Fallback IMU reader using IOKit HID for Bluetooth Pro Controllers
//  when GameController framework returns zero motion data.
//

import Foundation
import IOKit
import IOKit.hid

@available(OSX 11.0, *)
class HIDMotionReader {
    
    private var hidManager: IOHIDManager?
    private var hidDevice: IOHIDDevice?
    private var thread: Thread?
    private var runLoop: CFRunLoop?
    private var reportBuffer: UnsafeMutablePointer<UInt8>?
    
    // Parsed IMU data (protected by lock)
    private let lock = NSLock()
    var accelX: Double = 0.0
    var accelY: Double = 0.0
    var accelZ: Double = 0.0
    var gyroXRad: Double = 0.0  // radians/sec
    var gyroYRad: Double = 0.0
    var gyroZRad: Double = 0.0
    var hasData: Bool = false
    var reportCount: Int = 0
    
    // Pro Controller IMU conversion factors
    // Accel: ±8G range, 16-bit → 1G = 4096 LSB
    static let ACCEL_FACTOR: Double = 1.0 / 4096.0
    // Gyro: ±2000°/s → 1°/s ≈ 16.375 LSB → to rad/s
    static let GYRO_FACTOR_RAD: Double = (1.0 / 16.375) * (Double.pi / 180.0)
    
    deinit {
        stop()
    }
    
    func start(vendorID: Int = 0x057E, productID: Int = 0x2009) {
        print("🔌 HIDMotionReader: Starting HID reader thread...")
        thread = Thread {
            self.setupHID(vendorID: vendorID, productID: productID)
        }
        thread?.qualityOfService = .userInteractive
        thread?.name = "HIDMotionReader"
        thread?.start()
    }
    
    private func setupHID(vendorID: Int, productID: Int) {
        hidManager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        guard let manager = hidManager else {
            print("❌ HIDMotionReader: Failed to create IOHIDManager")
            return
        }
        
        let matchDict: [String: Any] = [
            kIOHIDVendorIDKey as String: vendorID,
            kIOHIDProductIDKey as String: productID
        ]
        
        IOHIDManagerSetDeviceMatching(manager, matchDict as CFDictionary)
        
        self.runLoop = CFRunLoopGetCurrent()
        IOHIDManagerScheduleWithRunLoop(manager, self.runLoop!, CFRunLoopMode.defaultMode.rawValue)
        
        let ret = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        guard ret == kIOReturnSuccess else {
            print("❌ HIDMotionReader: Failed to open HID manager: \(ret)")
            return
        }
        
        guard let deviceSet = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>,
              let device = deviceSet.first else {
            print("❌ HIDMotionReader: No Pro Controller found via IOKit HID")
            return
        }
        
        self.hidDevice = device
        
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 512)
        buffer.initialize(repeating: 0, count: 512)
        self.reportBuffer = buffer
        
        let context = Unmanaged.passUnretained(self).toOpaque()
        
        IOHIDDeviceRegisterInputReportCallback(
            device,
            buffer,
            512,
            hidReportCallback,
            context
        )
        
        print("✅ HIDMotionReader: Listening for raw HID reports")
        
        // Keep the run loop alive to receive callbacks
        CFRunLoopRun()
    }
    
    func stop() {
        if let rl = self.runLoop {
            CFRunLoopStop(rl)
        }
        if let manager = hidManager {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        reportBuffer?.deallocate()
        reportBuffer = nil
        hidManager = nil
        hidDevice = nil
    }
    
    func getIMUData() -> (ax: Double, ay: Double, az: Double, gx: Double, gy: Double, gz: Double)? {
        lock.lock()
        defer { lock.unlock() }
        guard hasData else { return nil }
        return (accelX, accelY, accelZ, gyroXRad, gyroYRad, gyroZRad)
    }
    
    // Called from the C callback
    fileprivate func handleReport(reportID: UInt32, report: UnsafeMutablePointer<UInt8>, length: Int) {
        
        guard reportID == 0x30, length >= 49 else { return }
        
        // Report buffer INCLUDES report ID at byte 0, so all offsets shift +1
        // Layout: [0]=ReportID [1]=Timer [2]=Battery [3-5]=Buttons
        //         [6-8]=LStick [9-11]=RStick [12]=Vibrator
        //         [13-24]=IMU Frame1 [25-36]=IMU Frame2 [37-48]=IMU Frame3
        let imuOffset = 13  // First IMU frame (after report ID byte)
        
        let rawAccX  = readInt16LE(report, offset: imuOffset + 0)
        let rawAccY  = readInt16LE(report, offset: imuOffset + 2)
        let rawAccZ  = readInt16LE(report, offset: imuOffset + 4)
        let rawGyroX = readInt16LE(report, offset: imuOffset + 6)
        let rawGyroY = readInt16LE(report, offset: imuOffset + 8)
        let rawGyroZ = readInt16LE(report, offset: imuOffset + 10)
        
        lock.lock()
        accelX  = Double(rawAccX)  * HIDMotionReader.ACCEL_FACTOR
        accelY  = Double(rawAccY)  * HIDMotionReader.ACCEL_FACTOR
        accelZ  = Double(rawAccZ)  * HIDMotionReader.ACCEL_FACTOR
        gyroXRad = Double(rawGyroX) * HIDMotionReader.GYRO_FACTOR_RAD
        gyroYRad = Double(rawGyroY) * HIDMotionReader.GYRO_FACTOR_RAD
        gyroZRad = Double(rawGyroZ) * HIDMotionReader.GYRO_FACTOR_RAD
        hasData = true
        reportCount += 1
        lock.unlock()
    }
    
    private func readInt16LE(_ ptr: UnsafeMutablePointer<UInt8>, offset: Int) -> Int16 {
        let lo = UInt16(ptr[offset])
        let hi = UInt16(ptr[offset + 1])
        return Int16(bitPattern: lo | (hi << 8))
    }
}

// C-compatible callback for IOKit HID
private func hidReportCallback(
    context: UnsafeMutableRawPointer?,
    result: IOReturn,
    sender: UnsafeMutableRawPointer?,
    type: IOHIDReportType,
    reportID: UInt32,
    report: UnsafeMutablePointer<UInt8>,
    reportLength: CFIndex
) {
    guard let ctx = context else { return }
    let reader = Unmanaged<HIDMotionReader>.fromOpaque(ctx).takeUnretainedValue()
    reader.handleReport(reportID: reportID, report: report, length: Int(reportLength))
}
