//
//  DragHelper.swift
//  MetalSplat
//
//  Created by CC Laan on 9/17/23.
//

import Foundation
import UIKit
import Satin

// TODO: fixme

class DragHelper {
    
    
    private var rollRotation: Float = 0.0
    
    private var rollGestureRecognizer: UIRotationGestureRecognizer!

    private var panCurrentPoint: simd_float2 = .zero
    private var panPreviousPoint: simd_float2 = .zero
    private var panGestureRecognizer: UIPanGestureRecognizer!

    private var rotateGestureRecognizer: UIPanGestureRecognizer!

    private var pinchScale: Float = 1.0
    private var pinchGestureRecognizer: UIPinchGestureRecognizer!

    private var tapGestureRecognizer: UITapGestureRecognizer!
    
    private func getTime() -> TimeInterval {
        return CFAbsoluteTimeGetCurrent()
    }

//    private func updateTime() {
//        let currentTime = getTime()
//        deltaTime = Float(currentTime - previousTime)
//        previousTime = currentTime
//    }
    
    weak var object : Object!
    weak var camera : Camera!
    weak var view : UIView!
    
    func setup( view : UIView, camera : Camera, object : Object ) {
        
        self.camera = camera
        self.view = view
        self.object = object
        
        view.isMultipleTouchEnabled = true

        let allowedTouchTypes = [UITouch.TouchType.direct.rawValue as NSNumber]
        
        rotateGestureRecognizer = UIPanGestureRecognizer(target: self, action: #selector(rotateGesture))
        rotateGestureRecognizer.allowedTouchTypes = allowedTouchTypes
        rotateGestureRecognizer.minimumNumberOfTouches = 1
        rotateGestureRecognizer.maximumNumberOfTouches = 1
        view.addGestureRecognizer(rotateGestureRecognizer)

        panGestureRecognizer = UIPanGestureRecognizer(target: self, action: #selector(panGesture))
        panGestureRecognizer.allowedTouchTypes = allowedTouchTypes
        panGestureRecognizer.minimumNumberOfTouches = 2
        panGestureRecognizer.maximumNumberOfTouches = 2
        view.addGestureRecognizer(panGestureRecognizer)

        pinchGestureRecognizer = UIPinchGestureRecognizer(target: self, action: #selector(pinchGesture))
        pinchGestureRecognizer.allowedTouchTypes = allowedTouchTypes
        view.addGestureRecognizer(pinchGestureRecognizer)
        
    }
    
    @objc private func rotateGesture(_ gestureRecognizer: UIPanGestureRecognizer) {
        guard let view = gestureRecognizer.view else { return }

        if gestureRecognizer.state == .changed {
            
            let t = Float(gestureRecognizer.translation(in: view).x)
            
            let rotate = simd_quatf(angle: t * 0.002, axis: .init(x: 0, y: 1, z: 0))
            
            //object.orientation = simd_mul(object.orientation, rotate)
            
            
            object.orientation = simd_mul(rotate, object.orientation)
            
            gestureRecognizer.setTranslation(.zero, in: view )
            
            
        }
        
    }

    @objc private func panGesture(_ gestureRecognizer: UIPanGestureRecognizer) {
        
        if gestureRecognizer.state == .changed {
            
            let t = gestureRecognizer.translation(in: view)
                        
            let scale : Float = 0.005
            
            object.position.x += Float(t.x) * scale
            object.position.z += Float(t.y) * scale
            
            
            gestureRecognizer.setTranslation(.zero, in: view )
            
            
        }
        
    }

    @objc private func pinchGesture(_ gestureRecognizer: UIPinchGestureRecognizer) {

        if gestureRecognizer.state == .changed {
            
            let s : Float = Float(gestureRecognizer.scale)
            
            let o = self.object.scale
            
            self.object.scale = .init(x: o.x * s, y: o.y * s, z: o.z * s)
            
            gestureRecognizer.scale = 1.0 // reset
            
        }
        
    }
    
    
}
