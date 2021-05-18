//
//  ImageTransform.swift
//  SwiftApp
//
//  Created by Denis Slobodskoy on 04.06.2020.
//  Copyright © 2020 Segey Ignatov. All rights reserved.
//

import Foundation

class ImageTransform {
    
    public var portraitVideo: Bool = false
    public var orientation: AVCaptureVideoOrientation = .landscapeLeft
    public var postion: AVCaptureDevice.Position = .back
    public var alignX: CGFloat = 0.5
    public var alignY: CGFloat = 0.5
    public var scalePip: CGFloat

    private let wCam: CGFloat
    private let hCam: CGFloat

    private var extent = CGRect()
    private var scaleF: CGFloat = 1.0
    
    private var normH: CGFloat {
        portraitVideo ? extent.width : extent.height
    }

    private var normW: CGFloat {
        portraitVideo ? extent.height : extent.width
    }

    
    init(size: CMVideoDimensions, scale: CGFloat = 1.0) {
        wCam = CGFloat(size.width)
        hCam = CGFloat(size.height)
        scalePip = scale
    }
    
    
    func getMatrix(extent: CGRect, flipped: Bool = false) -> CGAffineTransform {
        self.extent = extent
        var transformMatrix = CGAffineTransform(scaleX: 1.0, y: 1.0)
        var rotated = false
        switch (orientation) {
        case .landscapeRight:
            if (flipped) {
                transformMatrix = flip(transformMatrix)
            }
            rotated = portraitVideo
        case .landscapeLeft:
            if !flipped {
                transformMatrix = flip(transformMatrix)
            }
            rotated = portraitVideo

        case .portrait:
            transformMatrix = rotate(transformMatrix, clockwise: (postion == .front) != (flipped == true))
            rotated = !portraitVideo

        case .portraitUpsideDown:
            if !flipped {
                transformMatrix = flip(transformMatrix)
            }
            transformMatrix = rotate(transformMatrix, clockwise: (postion == .back) != (flipped == true))
            rotated = !portraitVideo
        @unknown default: break
        }

        let outWidth = rotated ? hCam : wCam
        let outHeight = rotated ? wCam : hCam
        let scaleX = wCam / outWidth * scalePip
        let scaleY = hCam / outHeight * scalePip
        scaleF = min(scaleX, scaleY)

        if scaleF < 0.999 || scaleF > 1.001 {
            transformMatrix = scale(transformMatrix)
            let offsetX = (wCam - outWidth * scaleF) * alignX
            let offsetY = (hCam - outHeight * scaleF) * alignY
            transformMatrix = transformMatrix.concatenating(CGAffineTransform(translationX: offsetX, y: offsetY))
        }
        return transformMatrix

    }
    
    func flip(_ matrix: CGAffineTransform) -> CGAffineTransform {
        return matrix.concatenating(CGAffineTransform(scaleX: -1, y: -1)).translatedBy(x: -normW, y: -normH)
    }

    func rotate(_ matrix: CGAffineTransform, clockwise: Bool) -> CGAffineTransform {
        let angle = CGFloat(Float.pi / 2.0)  * (clockwise ? 1.0: -1.0)
        var m1 =  matrix.concatenating(CGAffineTransform(translationX: -normW/2, y: -normH/2))
        m1 = m1.concatenating(CGAffineTransform(rotationAngle: angle))
        m1 = m1.concatenating(CGAffineTransform(translationX: normH/2, y: normW/2))
        return m1
    }
    
    func scale(_ matrix: CGAffineTransform) -> CGAffineTransform {
        return matrix.concatenating(CGAffineTransform(scaleX: scaleF, y: scaleF))
    }
    
}
