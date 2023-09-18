//
//  ARSplatView.swift
//  MetalSplat
//
//  Created by CC Laan on 9/16/23.
//

import Foundation
import SwiftUI

#if os(iOS)
import ARKit
import Metal
import MetalKit

import Forge
import Satin
import SatinCore



import Forge
import SwiftUI


struct ARSplatView: View {
    let model : SplatModelInfo
    var body: some View {
        ForgeView(renderer: ARSplatRenderer(model: model ))
            .ignoresSafeArea()
        
            .navigationBarBackButtonHidden(true)
            
        
    }
}



class BlendMaterial: SourceMaterial {
    
    public var backgroundTexture: MTLTexture?
    public var contentTexture: MTLTexture?

    override func bind(_ renderEncoder: MTLRenderCommandEncoder, shadow: Bool) {
        super.bind(renderEncoder, shadow: shadow)
        renderEncoder.setFragmentTexture(backgroundTexture, index: FragmentTextureIndex.Custom0.rawValue)
        renderEncoder.setFragmentTexture(contentTexture, index: FragmentTextureIndex.Custom1.rawValue)
    }
    
}


class ARSplatRenderer: Forge.Renderer, ARSessionDelegate, UIGestureRecognizerDelegate {

    
    var session = ARSession()
    
    var scene = Object("Scene")
    
    var splatCloud : SplatCloud?
    
    //lazy var context = Context(device, sampleCount, colorPixelFormat, .depth32Float_stencil8)
    lazy var context = Context(device, sampleCount, colorPixelFormat, .invalid)
    lazy var camera = ARPerspectiveCamera(session: session, mtkView: mtkView, near: 0.001, far: 100.0)
    lazy var renderer = Satin.Renderer(context: context)

    let drag = DragHelper()
    
    var backgroundRenderer: ARBackgroundRenderer!
    var backgroundTexture: MTLTexture?
    
    // Offscreen Texture to render the splat to
    var contentTexture: MTLTexture?
    let renderDownsample : Float // = 1.0 // How much to downsample splat offscreen target
    
    
    var assetsURL: URL { Bundle.main.resourceURL!.appendingPathComponent("Assets") }
    var rendererAssetsURL: URL { assetsURL.appendingPathComponent(String(describing: type(of: self))) }
    var pipelinesURL: URL { rendererAssetsURL.appendingPathComponent("Pipelines") }
    
    lazy var postMaterial: BlendMaterial = {
        let material = BlendMaterial(pipelinesURL: pipelinesURL)
        material.depthWriteEnabled = false
        material.blending = .alpha
        return material
    }()

    lazy var postProcessor = PostProcessor(context: Context(device, 1, colorPixelFormat), material: postMaterial)

    
    var _updateTextures = true
    
    let model : SplatModelInfo
    
    init(model : SplatModelInfo) {
        
        self.model = model
        self.renderDownsample = model.rendererDownsample
        
        super.init()
        
        session.delegate = self
        session.run(ARWorldTrackingConfiguration())
    }

    override func setup() {
        
        renderer.colorLoadAction = .clear
        
        let sampleCount : Int = 1
        
        backgroundRenderer = ARBackgroundRenderer(
            context: Context(device, sampleCount, colorPixelFormat),
            session: session
        )
        
        /*
        scene.add(self.grid)
        scene.add(self.axisMesh)
        */
        
        
        if let splatCloud = self.splatCloud {
            scene.add(splatCloud)
        }
        
    }
    
    
    override func setupMtkView(_ metalKitView: MTKView) {
        
        metalKitView.sampleCount = 1
        
        //metalKitView.depthStencilPixelFormat = .invalid
        //metalKitView.depthStencilPixelFormat = .depth32Float_stencil8
        metalKitView.depthStencilPixelFormat = context.depthPixelFormat
        metalKitView.backgroundColor = UIColor.black
        metalKitView.preferredFramesPerSecond = 30
        
        renderer.clearColor = MTLClearColorMake(0.0, 0.0, 0.0, 0.0)
        
        
        
        assert(FileManager.default.fileExists(atPath: model.plyUrl.path ))
        
        self.splatCloud = try! SplatCloud(model: model, renderDestination: metalKitView)
        
        
        splatCloud?.orientation = model.initialOrientation
        splatCloud?.scale = .init(repeating: model.initialScale)
        
        // offset a bit
        splatCloud!.worldPosition.z -= 0.7
                
        drag.setup(view: metalKitView, camera: camera, object: self.splatCloud! )
        
        
        // Tap for glow effect
        let tapRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleTapGesture))
        tapRecognizer.delegate = self
        metalKitView.addGestureRecognizer(tapRecognizer)
        
        
    }
    
    @objc private func handleTapGesture() {
        
        self.splatCloud?.isDragging = true
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            self.splatCloud?.isDragging = false
        }
        
    }
    
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool
    {
        return true
    }



    override func update() {
        if _updateTextures {
            backgroundTexture = createTexture("Background Texture", colorPixelFormat, 1)
            contentTexture = createTexture("Content Texture", colorPixelFormat, self.renderDownsample)
            _updateTextures = false
        }
    }
    
    override func draw(_ view: MTKView, _ commandBuffer: MTLCommandBuffer) {
                
        guard let renderPassDescriptor = view.currentRenderPassDescriptor,
              let contentTexture,
              let backgroundTexture else { return }
        
        // Draw camera BG into texture
        backgroundRenderer.draw(
            renderPassDescriptor: renderPassDescriptor,
            commandBuffer: commandBuffer,
            renderTarget: backgroundTexture
        )

        // Draw splats into render texture
        renderer.draw(
            renderPassDescriptor: renderPassDescriptor,
            commandBuffer: commandBuffer,
            scene: scene,
            camera: camera,
            renderTarget: contentTexture
        )
        
        
        postMaterial.backgroundTexture = backgroundTexture
        postMaterial.contentTexture = contentTexture
        
        //postMaterial.time = Float(getTime() - startTime)
        
        // Blend splats with camera view
        postProcessor.draw(
            renderPassDescriptor: renderPassDescriptor,
            commandBuffer: commandBuffer
        )


    }

    override func resize(_ size: (width: Float, height: Float)) {
        
        renderer.resize((width: size.width / Float(renderDownsample), height: size.height / Float(renderDownsample)))
        
        backgroundRenderer.resize(size)
        postProcessor.resize(size)
        _updateTextures = true
        
    }

    override func cleanup() {
        session.pause()
    }
    
    
    // MARK: - Util
    internal func createTexture(_ label: String, _ pixelFormat: MTLPixelFormat, _ textureScale: Float) -> MTLTexture? {
        
        if mtkView.drawableSize.width > 0, mtkView.drawableSize.height > 0 {
            
            let descriptor = MTLTextureDescriptor()
            descriptor.pixelFormat = pixelFormat
                        
            descriptor.width = Int(Float(mtkView.drawableSize.width) / textureScale)
            descriptor.height = Int(Float(mtkView.drawableSize.height) / textureScale)
            
            descriptor.sampleCount = 1
            descriptor.textureType = .type2D
            descriptor.usage = [.renderTarget, .shaderRead, .shaderWrite]
            descriptor.storageMode = .private
            descriptor.resourceOptions = .storageModePrivate
            guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
            texture.label = label
            return texture
        }
        return nil
    }
    
    // MARK: - Grid / axis
    var gridInterval: Float = 1.0

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
        let alpha : Float = 0.1
        let object = Object()
        let intervals = 5
        let intervalsf = Float(intervals)
        let size = (Float(0.005), intervalsf)
        object.add(Mesh(geometry: CapsuleGeometry(size: size, axis: .x), material: BasicColorMaterial(simd_make_float4(1.0, 0.0, 0.0, alpha))))
        object.add(Mesh(geometry: CapsuleGeometry(size: size, axis: .y), material: BasicColorMaterial(simd_make_float4(0.0, 1.0, 0.0, alpha))))
        object.add(Mesh(geometry: CapsuleGeometry(size: size, axis: .z), material: BasicColorMaterial(simd_make_float4(0.0, 0.0, 1.0, alpha))))
        return object
    }()
    
}

#endif
