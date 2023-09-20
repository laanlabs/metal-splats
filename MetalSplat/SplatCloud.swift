//
//  SplatCloud.swift
//  MetalSplat
//
//  Created by CC Laan on 9/14/23.
//

import Foundation
import Metal
import MetalKit
import Satin
import SatinCore




protocol RenderDestinationProvider {
    var currentRenderPassDescriptor: MTLRenderPassDescriptor? { get }
    var currentDrawable: CAMetalDrawable? { get }
    var colorPixelFormat: MTLPixelFormat { get set }
    var depthStencilPixelFormat: MTLPixelFormat { get set }
    var sampleCount: Int { get set }
}

extension MTKView: RenderDestinationProvider {
    
}


enum SplatError: Error {
    case deviceCreationFailed
    case plyParsingFailed
    case plyNonFloatPropertyFound
}



class SplatCloud : Object, Renderable {
    
    
    var splats : MetalBuffer<Splat>
    var temp_splats : MetalBuffer<Splat>
    var splat_indices : MetalBuffer<Int64>
    
    var numPoints : Int {
        return splats.count
    }
    
    private let device : MTLDevice
    private let library: MTLLibrary
    
    private let quadBuffer : MetalBuffer<packed_float2>
    
    
    private var pipelineState: MTLRenderPipelineState!
    private var depthState: MTLDepthStencilState!
    
    private var uniforms : Uniforms = Uniforms()
    
    //  Compute Pipeline  //
    private var commandQueue: MTLCommandQueue!
    private var computePipelineState: MTLComputePipelineState!
    private var isSorting = false
    
    private var frame_index : Int = 0
    
    
    // MARK: PLY Init
    
    //init(plyFile : URL,
    init(model : SplatModelInfo,
         renderDestination : RenderDestinationProvider) throws {
                
        guard let device = MTLCreateSystemDefaultDevice(),
              let library = device.makeDefaultLibrary() else {
            throw SplatError.deviceCreationFailed
        }
        
        self.device = device
        self.library = library
                        
        assert(FileManager.default.fileExists(atPath: model.plyUrl.path ))
        
        // Read header
        
        func readData(from stream: InputStream, maxLength: Int) -> Data {
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: maxLength)
            defer {
                buffer.deallocate()
            }

            let bytesRead = stream.read(buffer, maxLength: maxLength)
            return Data(bytes: buffer, count: bytesRead)
        }
        
        struct VertexData {
            
            var x: Float
            var y: Float
            var z: Float
            
            
            var opacity: Float
            var scale_0: Float
            
            var scale_1: Float
            var scale_2: Float
            
            var rot_0: Float
            var rot_1: Float
            var rot_2: Float
            var rot_3: Float
            
            // SH0
            var f_dc_0: Float
            var f_dc_1: Float
            var f_dc_2: Float
            
            // SH1
            var f_rest_0 : Float
            var f_rest_1 : Float
            var f_rest_2 : Float
            var f_rest_3 : Float
            var f_rest_4 : Float
            var f_rest_5 : Float
            var f_rest_6 : Float
            var f_rest_7 : Float
            var f_rest_8 : Float
            
        }

        
        
        // Read PLY
        
        var inputStream = InputStream(url: model.plyUrl)!
        
        inputStream.open()
        
        // Read and check the header
        let headerData = readData(from: inputStream, maxLength: 10000 )
        guard let header = String(data: headerData, encoding: .ascii),
                  header.contains("ply"),
                  let endOfHeaderRange = header.range(of: "end_header") else {
            throw SplatError.plyParsingFailed
        }
        
        var properties: [String] = []
        let lines = header.split(separator: "\n")
        
        var numPoints : Int = -1
        
        for line in lines {
            
            if line.contains("property ") {
                
                if !line.contains("float") {
                    throw SplatError.plyNonFloatPropertyFound // only grabbing floats
                }
                let property = line.split(separator: " ").last!
                properties.append(String(property))
                
            } else if line.contains("element vertex ") {
                
                numPoints = Int( line.split(separator: " ").last! )!
                print("Got numpoints: " , numPoints )
                
            }
        }
        
        
        
        
        let binaryStartPosition = header.distance(from: header.startIndex, to: endOfHeaderRange.upperBound)
        
        // Reset stream
        inputStream.close()
        inputStream = InputStream(url: model.plyUrl)!
        inputStream.open()
        
        let _ = readData(from: inputStream, maxLength: binaryStartPosition + 1)
        
        
        let strideLength = properties.count * MemoryLayout<Float>.size
        var offsetDict: [String: Int] = [:]
        
        // Build offset dictionary
        for (index, prop) in properties.enumerated() {
            offsetDict[prop] = index * MemoryLayout<Float>.size
        }
        
        func extractValue(from buffer: Data, property: String) -> Float {
            guard let offset = offsetDict[property] else { return 0.0 }
            let value = buffer.dropFirst(offset).prefix(4).withUnsafeBytes { $0.load(as: Float.self) }
            return value
        }
        
        
        // Load points...
        
        var points : [VertexData] = []
            
        for _ in 0..<numPoints {
            
            let buffer = readData(from: inputStream, maxLength: strideLength)
            
            if buffer.count != strideLength {
                throw SplatError.plyParsingFailed
            }
            
            var attrs = VertexData(
                
                x: extractValue(from: buffer, property: "x"),
                y: extractValue(from: buffer, property: "y"),
                z: extractValue(from: buffer, property: "z"),
                                
                opacity: extractValue(from: buffer, property: "opacity"),
                
                scale_0: extractValue(from: buffer, property: "scale_0"),
                scale_1: extractValue(from: buffer, property: "scale_1"),
                scale_2: extractValue(from: buffer, property: "scale_2"),
                
                rot_0: extractValue(from: buffer, property: "rot_0"),
                rot_1: extractValue(from: buffer, property: "rot_1"),
                rot_2: extractValue(from: buffer, property: "rot_2"),
                rot_3: extractValue(from: buffer, property: "rot_3"),
                
                f_dc_0: extractValue(from: buffer, property: "f_dc_0"),
                f_dc_1: extractValue(from: buffer, property: "f_dc_1"),
                f_dc_2: extractValue(from: buffer, property: "f_dc_2"),
                
                f_rest_0: extractValue(from: buffer, property: "f_rest_0" ),
                f_rest_1: extractValue(from: buffer, property: "f_rest_1" ),
                f_rest_2: extractValue(from: buffer, property: "f_rest_2" ),
                f_rest_3: extractValue(from: buffer, property: "f_rest_3" ),
                f_rest_4: extractValue(from: buffer, property: "f_rest_4" ),
                f_rest_5: extractValue(from: buffer, property: "f_rest_5" ),
                f_rest_6: extractValue(from: buffer, property: "f_rest_6" ),
                f_rest_7: extractValue(from: buffer, property: "f_rest_7" ),
                f_rest_8: extractValue(from: buffer, property: "f_rest_8" )
                
            )
            
            attrs.x -= model.centroid.x
            attrs.y -= model.centroid.y
            attrs.z -= model.centroid.z
            
            
            var center : simd_float3 = .one
            
            center.x = attrs.x
            center.y = attrs.y
            center.z = attrs.z
            
            
            let dist = simd_length( center )
            
            if model.clipOutsideRadius > 0.001 && dist > model.clipOutsideRadius {
                continue
            }
            
            // 0.1 = keep 10% of points
            if (model.randomDownsample > 0.0) && (Float.random(in: 0.0...1.0) > model.randomDownsample) {
                continue
            }
            
            points.append( attrs )
            
        }
        
        
        numPoints = points.count
        
        
        // Allocate buffers:
        
        var splats : MetalBuffer<Splat> = MetalBuffer(device: device,
                                                      count: numPoints,
                                                      index: UInt32(1),
                                                      label: "points",
                                                      options: MTLResourceOptions.storageModeShared )
        
        var temp_splats : MetalBuffer<Splat> = MetalBuffer(device: device,
                                       count: numPoints,
                                       index: UInt32(1),
                                       label: "points2",
                                       options: MTLResourceOptions.storageModeShared )
        
        for i in 0..<numPoints {
            
            let attrs = points[i]
            
            var center : simd_float4 = .one
            
            center.x = attrs.x
            center.y = attrs.y
            center.z = attrs.z
                        
            //====== Rotation =======//
            
            
            
            var quat : simd_float4 = .init(x: attrs.rot_0, y: attrs.rot_1, z: attrs.rot_2, w: attrs.rot_3)
            let qlen = simd_length(quat);
            
            // keep normalize ?
            quat.x = (quat.x / qlen);
            quat.y = (quat.y / qlen);
            quat.z = (quat.z / qlen);
            quat.w = (quat.w / qlen);
            
            var scales : simd_float4 = .one
            scales.x = exp(attrs.scale_0)
            scales.y = exp(attrs.scale_1)
            scales.z = exp(attrs.scale_2)
            
            
            var rgba : simd_float4 = .one
            
            let SH_C0 : Float = 0.28209479177387814;
            rgba[0] = (0.5 + SH_C0 * attrs.f_dc_0);
            rgba[1] = (0.5 + SH_C0 * attrs.f_dc_1);
            rgba[2] = (0.5 + SH_C0 * attrs.f_dc_2);
            
            rgba[3] = (1.0 / (1.0 + exp(-attrs.opacity)));
            //rgba[3] = attrs.opacity;
                        
            let splat : Splat = Splat(center: center,
                                      color: rgba,
                                      scale: scales,
                                      quat: quat
                                      //sh_0: .zero,
                                      //sh_1_x: .zero,
                                      //sh_1_y: .zero,
                                      //sh_1_z: .zero
            )
            
//            splat.sh_0 = [attrs.f_dc_0, attrs.f_dc_1, attrs.f_dc_2]
//            
//            splat.sh_1_x = [attrs.f_rest_0, attrs.f_rest_1, attrs.f_rest_2]
//            splat.sh_1_y = [attrs.f_rest_3, attrs.f_rest_4, attrs.f_rest_5]
//            splat.sh_1_z = [attrs.f_rest_6, attrs.f_rest_7, attrs.f_rest_8]
            
            
            splats[i] = splat
            temp_splats[i] = splat
            
        }
        
        self.temp_splats = temp_splats
        self.splats = splats
                                
        print("Loaded splats: ", splats.count, numPoints )
        
        assert(numPoints == splats.count )
        
        inputStream.close()
        
        
        // Index buffer
        self.splat_indices = .init(device: device,
                                   count: numPoints,
                                   index: 0,
                                   label: "indices",
                                   options: MTLResourceOptions.storageModeShared)
        
        
        
        // ========================= //
        // Make fixed quad vertices
                      
        let _quads : [packed_float2] = [  [1, -1], [1,1], [-1,-1], [-1,1] ]
        
        
        self.quadBuffer = .init(device: device,
                                array: _quads,
                                index: 0,
                                options: MTLResourceOptions.storageModePrivate )
        
        super.init()
        
        self.setupShaders(renderDestination)
        
        self.setupCompute(renderDestination)
        
                
    }
    
    required init(from decoder: Decoder) throws {
        fatalError("init(from:) has not been implemented")
    }
    
    // Uniforms
    func updateUniforms(uniforms : Uniforms) {
        self.uniforms = uniforms
    }
    
    
    func sortSplats() {
        
        if frame_index % 4 == 0 && !isSorting {
            
            isSorting = true
            
            //let d1 = Date()
            
            // ~2 ms
            self.setSplatDepthsComputeShader()
            
            //let durComputeMs = d1.timeIntervalSinceNow * -1000.0
            
            //DispatchQueue.global(qos: .userInteractive).async {
                
            
                //let d2 = Date()
                
                self._sortSplatsCpp()
                //let durCpuMs = d2.timeIntervalSinceNow * -1000
            
                //let durTotalMs = d1.timeIntervalSinceNow * -1000.0
            
                //NSLog("Sort took %6.1f ms - shader: %.1f ms ,  std::sort %.1f ms", durTotalMs, durComputeMs, durCpuMs )
                
                
                self.isSorting = false
            
            //}
            
        }
        
        
        
    }
    
    private func _sortSplatsCpp() {
        
        sort_splats(splats.buffer.contents(),
                    temp_splats.buffer.contents(),
                    splat_indices.buffer.contents(),
                    uniforms,
                    Int32(numPoints))
            
        
    }
    
    // MARK: - Render
    
    
    func render(renderEncoder: MTLRenderCommandEncoder) {
        
        self.sortSplats()
        
        
        //renderEncoder.setCullMode(.none)
        //renderEncoder.setFrontFacing(.counterClockwise)
        
        renderEncoder.setDepthStencilState(depthState)
        renderEncoder.setRenderPipelineState(pipelineState)
                
        renderEncoder.setVertexBuffer(self.quadBuffer.buffer, offset: 0, index: 0)
        renderEncoder.setVertexBuffer(self.splats.buffer, offset: 0, index: 1)
        
        
        
        
        var uni : Uniforms = self.uniforms
        renderEncoder.setVertexBytes(&uni, length: MemoryLayout<Uniforms>.stride, index: 2)
        renderEncoder.setFragmentBytes(&uni, length: MemoryLayout<Uniforms>.stride, index: 2)
                        
        
        renderEncoder.drawPrimitives(
                                    type: .triangleStrip,
                                    vertexStart: 0,
                                    vertexCount: self.quadBuffer.count,
                                    instanceCount: self.splats.count )

                
        frame_index += 1
        
        
    }
    
    // MARK: - Metal Setup
    
    private func setupShaders( _ renderDestination : RenderDestinationProvider ) {
        
        let depthStateDescriptor = MTLDepthStencilDescriptor()
        depthStateDescriptor.depthCompareFunction = .always
        depthStateDescriptor.isDepthWriteEnabled = false
                
        self.depthState = device.makeDepthStencilState(descriptor: depthStateDescriptor)!
        
        self.pipelineState = makePipelineState(renderDestination)!
        
    }
    
    private func makePipelineState(_ renderDestination : RenderDestinationProvider) -> MTLRenderPipelineState? {
        
        guard let vertexFunction = library.makeFunction(name: "splat_vertex"),
            let fragmentFunction = library.makeFunction(name: "splat_fragment") else {
                return nil
        }
        
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        
        descriptor.depthAttachmentPixelFormat = renderDestination.depthStencilPixelFormat
        descriptor.colorAttachments[0].pixelFormat = renderDestination.colorPixelFormat
        
        //descriptor.colorAttachments[0].pixelFormat = metalKitView.colorPixelFormat
        //descriptor.depthAttachmentPixelFormat = metalKitView.depthStencilPixelFormat
        //descriptor.stencilAttachmentPixelFormat = renderDestination.depthStencilPixelFormat
        
        
        descriptor.stencilAttachmentPixelFormat = .invalid
        
        descriptor.rasterSampleCount = renderDestination.sampleCount
        
        assert(renderDestination.sampleCount == 1)
        
        
        // =========== Blending ============= //
        descriptor.colorAttachments[0].isBlendingEnabled = true
        
        descriptor.colorAttachments[0].sourceRGBBlendFactor = .oneMinusDestinationAlpha
        descriptor.colorAttachments[0].destinationRGBBlendFactor = .one
        descriptor.colorAttachments[0].sourceAlphaBlendFactor = .oneMinusDestinationAlpha
        descriptor.colorAttachments[0].destinationAlphaBlendFactor = .one

        descriptor.colorAttachments[0].rgbBlendOperation = .add
        descriptor.colorAttachments[0].alphaBlendOperation = .add
        
        return try? device.makeRenderPipelineState(descriptor: descriptor)
        
    }
    
    
    // MARK: - Metal Compute
    
    private func setupCompute( _ renderDestination : RenderDestinationProvider ) {
                
        guard let commandQueue = device.makeCommandQueue() else {
            fatalError("Failed to create command queue.")
        }
        self.commandQueue = commandQueue
        
        let defaultLibrary = device.makeDefaultLibrary()
        
        let computeFunction = defaultLibrary?.makeFunction(name: "splat_set_depths")
        do {
            computePipelineState = try device.makeComputePipelineState(function: computeFunction!)
        } catch {
            fatalError("Failed to create compute pipeline state.")
        }
        
    }
    
    
    private func setSplatDepthsComputeShader() {
        
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let computeEncoder = commandBuffer.makeComputeCommandEncoder() else {
            return
        }
        
        computeEncoder.setComputePipelineState(computePipelineState)
        
        
        computeEncoder.setBuffer(self.splat_indices.buffer, offset: 0, index: 0)
        computeEncoder.setBuffer(self.splats.buffer, offset: 0, index: 1)
        
        var uni : Uniforms = self.uniforms
        computeEncoder.setBytes(&uni, length: MemoryLayout<Uniforms>.stride, index: 2)
                                        
        let threadPerGrid = MTLSize(width: numPoints, height: 1, depth: 1)
        let threadsPerThreadgroup = MTLSize(width: computePipelineState.threadExecutionWidth, height: 1, depth: 1)
        computeEncoder.dispatchThreads(threadPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
        
        computeEncoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        
    }
    
    // MARK: - Satin : Object + Renderable
        
    var renderOrder: Int {
        return 0
    }
    
    var receiveShadow: Bool {
        return false
    }
    
    var castShadow: Bool {
        return false
    }
    
    var drawable: Bool {
        return true
    }
    
    var cullMode: MTLCullMode {
        get {
            return .none
        }
        set(newValue) {
            
        }
    }
    
    var opaque: Bool {
        return true
    }
    
    //let _material = BasicColorMaterial(simd_make_float4(1.0, 1.0, 1.0, 1.0))
    
    var material: Satin.Material? {
        get {
            return nil
        }
        set(newValue) {
                
        }
    }
    
    var materials: [Satin.Material] {
        return []
    }
    
    private var dragAlpha : Float = 0.0 // tween this value
    private var _dragAlpha : Float = 0.0
    
    var isDragging : Bool = false {
        didSet {
            _dragAlpha = isDragging ? 1.0 : 0.0
        }
    }
    
    override func update(camera: Satin.Camera, viewport: simd_float4) {
        
        let modelMatrix = self.worldMatrix
        
        let modelViewMatrix = simd_mul(camera.viewMatrix, modelMatrix)
        
        let width = viewport.z
        let height = viewport.w

        // Extracting tangent of half-angles of the FoVs
        let tan_fovx = 1.0 / camera.projectionMatrix[0][0];
        let tan_fovy = 1.0 / camera.projectionMatrix[1][1];
            
        let focal_y = height / (2.0 * tan_fovy)
        let focal_x = width / (2.0 * tan_fovx)
        
        let time : Double = CACurrentMediaTime()
        
        let cameraPos = simd_float4(camera.worldPosition, 1.0)
        //let cameraPosOrig = simd_mul( cameraPos, simd_inverse(modelMatrix) );
        let cameraPosOrig = simd_mul( simd_inverse(modelMatrix) , cameraPos );
        
        let uni = Uniforms(projection_matrix: camera.projectionMatrix,
                           model_matrix: modelMatrix,
                           model_view_matrix: modelViewMatrix,
                           inv_model_view_matrix: simd_inverse(modelViewMatrix),
                           camera_pos: cameraPos,
                           camera_pos_orig: cameraPosOrig,
                           viewport_width: viewport.z,
                           viewport_height: viewport.w,
                           focal_x: focal_x,
                           focal_y: focal_y,
                           tan_fovx: tan_fovx,
                           tan_fovy: tan_fovy,
                           drag_alpha: dragAlpha,
                           time: Float(time) )
        
        self.updateUniforms(uniforms: uni)
                        
        dragAlpha = dragAlpha - (dragAlpha - _dragAlpha) * 0.1;
        
        
    }
    
    func draw(renderEncoder: MTLRenderCommandEncoder, shadow: Bool) {
        
        self.render(renderEncoder: renderEncoder)
        
    }
    
    
}


/*
extension SplatCloud : Renderable {
    
    var label: String {
        return "SplatCloud"
    }
    
    var renderOrder: Int {
        return 10
    }
    
    var receiveShadow: Bool {
        return false
    }
    
    var castShadow: Bool {
        return false
    }
    
    var drawable: Bool {
        return true
    }
    
    var cullMode: MTLCullMode {
        get {
            return .none
        }
        set(newValue) {
            
        }
    }
    
    var opaque: Bool {
        return true
    }
    
    var material: Satin.Material? {
        get {
            return nil
        }
        set(newValue) {
                
        }
    }
    
    var materials: [Satin.Material] {
        return []
    }
    
    func update(camera: Satin.Camera, viewport: simd_float4) {
        
        var uni : Uniforms = Uniforms(projectionMatrix: camera.projectionMatrix,
                                      modelViewMatrix: camera.viewMatrix,
                                      viewport_width: viewport.x, viewport_height: viewport.y)
        
        self.updateUniforms(uniforms: uni)
        
    }
    
    func draw(renderEncoder: MTLRenderCommandEncoder, shadow: Bool) {
        self.render(renderEncoder: renderEncoder)
        
    }
    
    
}
*/
