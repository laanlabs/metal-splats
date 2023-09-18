//
//  SplatSimpleView.swift
//  MetalSplat
//
//  Created by CC Laan on 9/15/23.
//

import SwiftUI

import Metal
import MetalKit

import Forge
import Satin
import SatinCore


class CameraControllerRenderer: Forge.Renderer {
    
    let model : SplatModelInfo
    
    var splatCloud : SplatCloud?
    
    var gridInterval: Float = 1.0
    
    init(model: SplatModelInfo) {
        self.model = model
        super.init()
    }

    lazy var grid: Object = {
        let alpha : Float = 0.1
        let object = Object()
        let material = BasicColorMaterial(simd_make_float4(1.0, 1.0, 1.0, alpha))
        let intervals = 5
        let intervalsf = Float(intervals)
        let geometryX = CapsuleGeometry(size: (0.005, intervalsf), axis: .x)
        let geometryZ = CapsuleGeometry(size: (0.005, intervalsf), axis: .z)
        for i in 0 ... intervals {
            let fi = Float(i)
            let meshX = Mesh(geometry: geometryX, material: material)
            let offset = remap(fi, 0.0, Float(intervals), -intervalsf * 0.5, intervalsf * 0.5)
            meshX.position = [0.0, 0.0, offset]
            object.add(meshX)

            let meshZ = Mesh(geometry: geometryZ, material: material)
            meshZ.position = [offset, 0.0, 0.0]
            object.add(meshZ)
        }
        return object
    }()

    lazy var axisMesh: Object = {
        let alpha : Float = 0.5
        let object = Object()
        let intervals = 5
        let intervalsf = Float(intervals)
        let size = (Float(0.005), intervalsf)
        object.add(Mesh(geometry: CapsuleGeometry(size: size, axis: .x), material: BasicColorMaterial(simd_make_float4(1.0, 0.0, 0.0, alpha))))
        object.add(Mesh(geometry: CapsuleGeometry(size: size, axis: .y), material: BasicColorMaterial(simd_make_float4(0.0, 1.0, 0.0, alpha))))
        object.add(Mesh(geometry: CapsuleGeometry(size: size, axis: .z), material: BasicColorMaterial(simd_make_float4(0.0, 0.0, 1.0, alpha))))
        return object
    }()

    lazy var targetMesh = Mesh(geometry: BoxGeometry(size: 0.1), material: NormalColorMaterial())
    
    lazy var scene = Object("Scene", [grid, axisMesh])
    
    lazy var context: Context = .init(device, sampleCount, colorPixelFormat, depthPixelFormat, stencilPixelFormat)

    lazy var camera: PerspectiveCamera = {
        
        let pos = simd_make_float3(1.5, 1.5, 1.5)
        
        let camera = PerspectiveCamera(position: pos, near: 0.01, far: 100.0)

        camera.orientation = simd_quatf(from: [0, 0, 1], to: simd_normalize(pos))

        let forward = simd_normalize(camera.forwardDirection)
       
        let worldUp = Satin.worldUpDirection
        let right = -simd_normalize(simd_cross(forward, worldUp))
        let angle = acos(simd_dot(simd_normalize(camera.rightDirection), right))

        camera.orientation = simd_quatf(angle: angle, axis: forward) * camera.orientation

        return camera
    }()

    lazy var cameraController: PerspectiveCameraController = .init(camera: camera, view: mtkView)
    lazy var renderer: Satin.Renderer = .init(context: context)

    override func setupMtkView(_ metalKitView: MTKView) {
        
        metalKitView.depthStencilPixelFormat = .invalid
                
        metalKitView.backgroundColor = UIColor.black
        metalKitView.autoResizeDrawable = false
        metalKitView.clearColor = MTLClearColorMake(0, 0, 0, 0) // must be 0000 for the blend funcs
        metalKitView.preferredFramesPerSecond = 30
        
        metalKitView.drawableSize = mtkView.drawableSize.applying(
            CGAffineTransform(scaleX: 1.0 / CGFloat(model.rendererDownsample),
                                   y: 1.0 / CGFloat(model.rendererDownsample))
        )
        
        print("Drawble size; ", mtkView.drawableSize )
        
        renderer.clearColor = MTLClearColorMake(0.0, 0.0, 0.0, 0.0)
        
        
        //let plyUrl = Bundle.main.url(forResource: "plush_cloud.ply", withExtension: nil)!
        //assert(FileManager.default.fileExists(atPath: plyUrl.path ))
        //self.splatCloud = try! SplatCloud(plyFile: plyUrl, renderDestination: metalKitView)
        self.splatCloud = try! SplatCloud(model: model, renderDestination: metalKitView)
        
        splatCloud?.orientation = model.initialOrientation
        splatCloud?.scale = .init(repeating: model.initialScale)
        
        
    }

    override func setup() {
        
        scene.attach(cameraController.target)
                
        if let splatCloud = self.splatCloud {
            scene.add(splatCloud)
        }
        
        targetMesh.position = simd_float3(x: 1, y: 0, z: 1)
        scene.add(targetMesh)
        
    }

    deinit {
        cameraController.disable()
    }

    override func update() {
        cameraController.update()
        //targetMesh.orientation = cameraController.camera.worldOrientation.inverse
    }

    override func draw(_ view: MTKView, _ commandBuffer: MTLCommandBuffer) {
        
        guard let renderPassDescriptor = view.currentRenderPassDescriptor else { return }
        
        renderer.draw(
            renderPassDescriptor: renderPassDescriptor,
            commandBuffer: commandBuffer,
            scene: scene,
            camera: camera
        )
        
        
    }

    override func resize(_ size: (width: Float, height: Float)) {
        camera.aspect = size.width / size.height
        renderer.resize(size)
    }
}


struct SplatSimpleView: View {
    let model : SplatModelInfo
    var body: some View {
        ForgeView(renderer: CameraControllerRenderer(model: model))
            .ignoresSafeArea()
    }
}



#Preview {
    SplatSimpleView(model: Models.Plush )
}
