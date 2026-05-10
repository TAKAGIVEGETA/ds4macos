//
//  Client.swift
//  ds4macos
//

import Foundation
import Network
import SwiftAsyncSocket

class Client {

    var slots: [Bool] = [false, false, false, false]

    var server: DSUServer
    var address: SwiftAsyncUDPSocketAddress
    var socket: SwiftAsyncUDPSocket
    var timeStampLastDataRequest: TimeInterval
    var port: UInt16
    
    let timeOut: TimeInterval = 10.0 // 10 seconds

    init(server: DSUServer, socket: SwiftAsyncUDPSocket, address: SwiftAsyncUDPSocketAddress, port: UInt16) {
        self.server = server
        self.socket = socket
        self.timeStampLastDataRequest = Date().timeIntervalSince1970
        self.address = address
        self.port = port
    }
    
    func setTimeStampOnDataRequest() {
        self.timeStampLastDataRequest = Date().timeIntervalSince1970
    }

    func setSlot(slot: Int) {
        if slot >= 0 && slot < self.slots.count {
            self.slots[slot] = true
        }
    }
    
    func unsetSlot(slot: Int) {
        if slot >= 0 && slot < self.slots.count {
            self.slots[slot] = false
        }
    }
    
    func send(dataMessage: Data) {
        if (Date().timeIntervalSince1970 - self.timeStampLastDataRequest) > self.timeOut {
            print("client timed out, removing from client list")
            self.close()
            return
        }
        do {
            try self.socket.send(data: dataMessage, address: self.address.address, tag: 10)
        } catch {
            self.close()
            print("could not send data to client")
        }
    }
    
    func close() {
        self.server.clients.removeValue(forKey: "\(self.address.host):\(self.address.port)")
        self.server.updateClientsViewModel()
    }
    
    func getViewValue() -> String {
        return "\(self.address.host):\(self.address.port)"
    }

}
