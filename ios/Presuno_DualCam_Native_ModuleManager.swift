//  Created by react-native-create-bridge
import UIKit
import Foundation
import React


@objc(Presuno_DualCam_Native_Module)
class Presuno_DualCam_Native_ModuleManager : RCTViewManager {
  // Export constants to use in your native module
  func constantsToExport() -> [String : Any]! {
    return ["EXAMPLE_CONSTANT": "example"]
  }

  // Return the native view that represents your React component
  override func view() -> UIView! {
    return UIView()
  }
}
