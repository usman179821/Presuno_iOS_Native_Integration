//
//  shadowview.swift
//  RideShare
//
//  Created by Muhammad Usman on 02/06/1441 AH.
//  Copyright © 1441 Macbook. All rights reserved.
//

import Foundation
import UIKit


extension UIView {
    
    func shake(){
       let animation = CABasicAnimation(keyPath: "position")
       animation.duration = 0.07
       animation.repeatCount = 3
       animation.autoreverses = true
       animation.fromValue = NSValue(cgPoint: CGPoint(x: self.center.x - 10, y: self.center.y))
       animation.toValue = NSValue(cgPoint: CGPoint(x: self.center.x + 10, y: self.center.y))
       self.layer.add(animation, forKey: "position")
     }
}
extension UIButton {
    func adjustButtonSize() {
        titleLabel?.adjustsFontSizeToFitWidth = true
        titleLabel?.minimumScaleFactor = 0.5
    }
    func ButtonShadow() {
        self.layer.shadowOpacity = 1
         self.layer.shadowRadius = 1
         self.layer.cornerRadius = 6
         layer.shadowOffset = CGSize(width: 0.1, height: 0.3)
         self.layer.borderColor = #colorLiteral(red: 0.2549019754, green: 0.2745098174, blue: 0.3019607961, alpha: 1)
           //self.layer.borderWidth = 0
       }
    func pulsate() {
    let pulse = CASpringAnimation(keyPath: "transform.scale")
    pulse.duration = 0.4
    pulse.fromValue = 0.98
    pulse.toValue = 1.0
    pulse.autoreverses = true
    pulse.repeatCount = .infinity
    pulse.initialVelocity = 0.5
    pulse.damping = 1.0
    layer.add(pulse, forKey: nil)
        layer.backgroundColor = #colorLiteral(red: 0.501960814, green: 0.501960814, blue: 0.501960814, alpha: 1)
    }
    func flash() {
    let flash = CABasicAnimation(keyPath: "opacity")
    flash.duration = 0.5
    flash.fromValue = 1
    flash.toValue = 0.1
    flash.timingFunction = CAMediaTimingFunction(name: CAMediaTimingFunctionName.easeInEaseOut)
    flash.autoreverses = true
    flash.repeatCount = 2
    layer.add(flash, forKey: nil)
        layer.backgroundColor = #colorLiteral(red: 0, green: 0, blue: 0, alpha: 0.7866463566)
    }
}


