//
//  ControllerView.swift
//  ds4macos
//

import Foundation
import SwiftUI

@available(OSX 11.0, *)
struct ControllerBox: View {
    var dsuController: DSUController
    @State private var isCalibratingUI: Bool = false

    var body: some View {
        GroupBox {
            HStack {
                Text("🎮").font(.largeTitle)
                VStack(alignment: .leading) {
                    Text(dsuController.gameController!.vendorName ?? "?").font(.headline)
                    Text(dsuController.gameController!.productCategory).font(.subheadline)
                }
                Spacer()
                
                Button(action: {
                    self.isCalibratingUI = true
                    dsuController.startCalibration()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.1) {
                        self.isCalibratingUI = false
                    }
                }) {
                    Text(isCalibratingUI ? "Calibrating..." : "Calibrate Gyro")
                }
                .disabled(isCalibratingUI)
                .padding(.trailing, 10)
                
                Text("Slot")
                Image(systemName: "\(dsuController.slot).square.fill").font(.title)
            }.padding(10)
        }
    }
    
}
