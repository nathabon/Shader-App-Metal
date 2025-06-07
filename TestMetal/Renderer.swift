//
//  Renderer.swift
//  TestMetal
//
//  Created by Nathanaël BONTOUX on 03/06/2025.
//

import SwiftUI
import MetalKit
import AppKit
import Foundation
import simd
import Metal

// MARK: - Extensions utilitaires

extension SIMD3 where Scalar == Float {
	static let black = SIMD3(0, 0, 0)
	static let white = SIMD3(1, 1, 1)
	static let red = SIMD3(1, 0, 0)
	static let green = SIMD3(0, 1, 0)
	static let blue = SIMD3(0, 0, 1)
	static let gray = SIMD3(0.5, 0.5, 0.5)
}

// MARK: - Structures de données
struct Camera3D {
	var position: SIMD3<Float>
	var fovy: Float
}

struct Material {
	var color: SIMD3<Float>
	var emitingColor: SIMD3<Float>
	var emitingStrength: Float
	var smoothness: Float
	
	static let light = Material(color: .black, emitingColor: .white, emitingStrength: 3.0, smoothness: 0)
	static let white = Material(color: .white, emitingColor: .black, emitingStrength: 0.0, smoothness: 0)
	static let green = Material(color: .green, emitingColor: .black, emitingStrength: 0.0, smoothness: 0)
	static let red = Material(color: .red, emitingColor: .black, emitingStrength: 0.0, smoothness: 0)
	static let gray = Material(color: .gray, emitingColor: .black, emitingStrength: 0.0, smoothness: 0)
	
	static let mirror = Material(color: .white, emitingColor: .black, emitingStrength: 0, smoothness: 1)
	
	static func whiteReflective(smooth: Float) -> Material {
		return Material(color: .white, emitingColor: .black, emitingStrength: 0, smoothness: smooth)
	}
	
	static func coloredMirror(color: SIMD3<Float>) -> Material {
		return Material(color: color, emitingColor: .black, emitingStrength: 0, smoothness: 1)
	}
}

struct Triangle {
	var A: SIMD3<Float>
	var B: SIMD3<Float>
	var C: SIMD3<Float>
	var n: SIMD3<Float>
	var material: Material
}

struct Sphere {
	var center: SIMD3<Float>
	var radius: Float
	var material: Material
}

// MARK: - Scène
var triangles: [Triangle] = [
	// MUR DROIT (ROUGE)
	Triangle(A: SIMD3<Float>(5,0,-5), B: SIMD3<Float>(5,10,-5), C: SIMD3<Float>(5,10,5), n: SIMD3<Float>(-1,0,0), material: .coloredMirror(color: .red)),
	Triangle(A: SIMD3<Float>(5,10,5), B: SIMD3<Float>(5,0,-5), C: SIMD3<Float>(5,0,5), n: SIMD3<Float>(-1,0,0), material: .coloredMirror(color: .red)),
	// MUR GAUCHE (VERT)
	Triangle(A: SIMD3<Float>(-5,0,-5), B: SIMD3<Float>(-5,10,-5), C: SIMD3<Float>(-5,10,5), n: SIMD3<Float>(1,0,0), material: .coloredMirror(color: .green)),
	Triangle(A: SIMD3<Float>(-5,10,5), B: SIMD3<Float>(-5,0,-5), C: SIMD3<Float>(-5,0,5), n: SIMD3<Float>(1,0,0), material: .coloredMirror(color: .green)),
	// MUR DU FONC (BLANC)
	Triangle(A: SIMD3<Float>(-5,0,-5), B: SIMD3<Float>(-5,10,-5), C: SIMD3<Float>(5,0,-5), n: SIMD3<Float>(0,0,1), material: .mirror),
	Triangle(A: SIMD3<Float>(5,10,-5), B: SIMD3<Float>(-5,10,-5), C: SIMD3<Float>(5,0,-5), n: SIMD3<Float>(0,0,1), material: .mirror),
	// MUR DE DEVANT (BLANC)
	Triangle(A: SIMD3<Float>(-5,0,5), B: SIMD3<Float>(-5,10,5), C: SIMD3<Float>(5,0,5), n: SIMD3<Float>(0,0,-1), material: .mirror),
	Triangle(A: SIMD3<Float>(5,10,5), B: SIMD3<Float>(-5,10,5), C: SIMD3<Float>(5,0,5), n: SIMD3<Float>(0,0,-1), material: .mirror),
	// SOL (GRIS)
	Triangle(A: SIMD3<Float>(-5,0,-5), B: SIMD3<Float>(5,0,-5), C: SIMD3<Float>(5,0,5), n: SIMD3<Float>(0,1,0), material: .gray),
	Triangle(A: SIMD3<Float>(-5,0,-5), B: SIMD3<Float>(-5,0,5), C: SIMD3<Float>(5,0,5), n: SIMD3<Float>(0,1,0), material: .gray),
	// PLAFOND (GRIS)
	Triangle(A: SIMD3<Float>(-5,10,-5), B: SIMD3<Float>(5,10,-5), C: SIMD3<Float>(5,10,5), n: SIMD3<Float>(0,-1,0), material: .gray),
	Triangle(A: SIMD3<Float>(-5,10,-5), B: SIMD3<Float>(-5,10,5), C: SIMD3<Float>(5,10,5), n: SIMD3<Float>(0,-1,0), material: .gray),
	// LUMIÈRE
	Triangle(A: SIMD3<Float>(-3,9.9,-3), B: SIMD3<Float>(3,9.9,-3), C: SIMD3<Float>(3,9.9,3), n: SIMD3<Float>(0,-1,0), material: .light),
	Triangle(A: SIMD3<Float>(-3,9.9,-3), B: SIMD3<Float>(-3,9.9,3), C: SIMD3<Float>(3,9.9,3), n: SIMD3<Float>(0,-1,0), material: .light),
]


let spheres: [Sphere] = [
	Sphere(center: [0, 5, -3], radius: 1.0, material: .mirror),
	Sphere(center: [2, 6, -4], radius: 0.8, material: .green),
	Sphere(center: [-2, 6, -4], radius: 1.0, material: .red)
]


// MARK: Renderer Metal

class Renderer: NSObject, MTKViewDelegate, ObservableObject {
	private var view: MTKView!
	
	let device: MTLDevice
	let commandQueue: MTLCommandQueue
	let pipelineState: MTLRenderPipelineState
	private let spheresBuffer: MTLBuffer
	private let trianglesBuffer: MTLBuffer
	private var accumulationTexture: MTLTexture!
	private var frameCount: UInt32 = 0
	
	
	var keyZ = false // DEVANT
	var keyS = false // DERRIERE
	var keyQ = false // GAUCHE
	var keyD = false // DROITE
	var keyA = false // ACCUMULATION TOOGLE
	var keyC = false // SCREENSHOT
	var keyL = false // ROTATE LEFT
	var keyR = false // ROTATE RIGHT
	
	private var isAccumulating: Bool = false
	
	// Caméra and viewport
	let cameraSpeed: Float = 0.05
	var forward: SIMD3<Float> = SIMD3<Float>(0, 0, -1)
	var right: SIMD3<Float> = SIMD3<Float>(1, 0, 0)
	
	private var topLeft = SIMD3<Float>(0, 0, 0)
	private var vx = SIMD3<Float>(0, 0, 0)
	private var vy = SIMD3<Float>(0, 0, 0)
	private var yaw: Float = 0.0
	private var camera = Camera3D(position: SIMD3<Float>(0, 5, 5), fovy: 60)
	var cameraPosition: SIMD3<Float> {
		get { camera.position }
		set { camera.position = newValue }
	}
	
	// MARK: init
	init(metalView: MTKView) {
		self.device = metalView.device!
		self.commandQueue = device.makeCommandQueue()!
		self.view = metalView
		
		let library = device.makeDefaultLibrary()!
		let vertexFunction = library.makeFunction(name: "vertex_main")!
		let fragmentFunction = library.makeFunction(name: "fragment_main")!
		
		let pipelineDescriptor = MTLRenderPipelineDescriptor()
		pipelineDescriptor.vertexFunction = vertexFunction
		pipelineDescriptor.fragmentFunction = fragmentFunction
		pipelineDescriptor.colorAttachments[0].pixelFormat = metalView.colorPixelFormat
		
		spheresBuffer = device.makeBuffer(bytes: spheres, length: MemoryLayout<Sphere>.stride * spheres.count, options: [.storageModeShared])!
		
		trianglesBuffer = device.makeBuffer(
			bytes: triangles,
			length: MemoryLayout<Triangle>.stride * triangles.count,
			options: [.storageModeShared]
		)!
		
		self.pipelineState = try! device.makeRenderPipelineState(descriptor: pipelineDescriptor)
		
		super.init()
	}
	
	// MARK: initViewport
	func initViewport(camera: Camera3D, resolution: SIMD2<Float>, yaw: Float, topLeft: inout SIMD3<Float>, vx: inout SIMD3<Float>, vy: inout SIMD3<Float>) {
		
		let fov = camera.fovy * Float.pi / 180.0
		let aspect = resolution.x / resolution.y
		let viewportWidth = tan(fov / 2.0) * 2.0
		let viewportHeight = viewportWidth / aspect
		
		// Direction de la caméra
		forward = SIMD3<Float>(
			sin(yaw),
			0,
			-cos(yaw)
		)
		
		right = SIMD3<Float>(
			-sin(yaw - Float.pi / 2.0),
			 0,
			 cos(yaw - Float.pi / 2.0)
		)
		
		let up = SIMD3<Float>(0, 1, 0)
		
		let center = camera.position + forward
		let horizontal = right * viewportWidth
		let vertical = up * viewportHeight
		
		topLeft = center - 0.5 * horizontal + 0.5 * -vertical
		vx = horizontal / resolution.x
		vy = vertical / resolution.y
	}
	
	// MARK: Accumulation
	private func createAccumulationTexture(size: CGSize) {
		let width = Int(size.width)
		let height = Int(size.height)
		
		// Protection contre les tailles invalides
		guard width > 0 && height > 0 else { return }
		
		let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba32Float, width: width, height: height, mipmapped: false)
		descriptor.usage = [.shaderRead, .shaderWrite]
		accumulationTexture = device.makeTexture(descriptor: descriptor)
	}
	
	private func clearAccumulationTexture() {
		guard let texture = accumulationTexture else { return }
		
		let width = texture.width
		let height = texture.height
		
		let zeroColor = SIMD4<Float>(0, 0, 0, 0)
		let region = MTLRegionMake2D(0, 0, width, height)
		
		var zeros = [SIMD4<Float>](repeating: zeroColor, count: width * height)
		
		texture.replace(region: region, mipmapLevel: 0, withBytes: &zeros, bytesPerRow: MemoryLayout<SIMD4<Float>>.stride * width)
	}
	
	// MARK: Camera
	func updateCamera() {
		if keyZ { cameraPosition += forward * cameraSpeed }
		if keyS { cameraPosition -= forward * cameraSpeed }
		if keyQ { cameraPosition -= right * cameraSpeed }
		if keyD { cameraPosition += right * cameraSpeed }
		if keyL { yaw -= cameraSpeed * 0.5 }
		if keyR { yaw += cameraSpeed * 0.5 }
	}
	
	func toggleAccumulation() {
		isAccumulating = !isAccumulating
		
		if isAccumulating {
			clearAccumulationTexture()
			frameCount = 0
		}
	}
	
	// MARK: takeScreenshot
	func takeScreenshot(view: MTKView) {
		guard let drawable = view.currentDrawable else { return }
		
		let texture = drawable.texture
		let width = texture.width
		let height = texture.height
		let bytesPerPixel = 4
		let bytesPerRow = bytesPerPixel * width
		let length = height * bytesPerRow
		
		guard let bytes = malloc(length) else { return }
		defer { free(bytes) }
		
		let region = MTLRegionMake2D(0, 0, width, height)
		texture.getBytes(bytes, bytesPerRow: bytesPerRow, from: region, mipmapLevel: 0)
		
		let colorSpace = CGColorSpaceCreateDeviceRGB()
		let bitmapInfo = CGBitmapInfo.byteOrder32Little.union(
			CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue)
		)
		
		
		guard let context = CGContext(data: bytes, width: width, height: height, bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: bitmapInfo.rawValue),
			  let cgImage = context.makeImage() else {
			return
		}
		
		let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: width, height: height))
		
		guard let tiffData = nsImage.tiffRepresentation,
			  let bitmapRep = NSBitmapImageRep(data: tiffData),
			  let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
			return
		}
		
		DispatchQueue.main.async {
			let panel = NSSavePanel()
			panel.title = "Save Screenshot"
			panel.allowedFileTypes = ["png"]
			panel.nameFieldStringValue = "screenshot.png"
			
			panel.begin { response in
				if response == .OK, let url = panel.url {
					do {
						try pngData.write(to: url)
						print("Screenshot saved at \(url.path)")
					} catch {
						print("Error saving screenshot: \(error)")
					}
				}
			}
		}
	}
	
	// MARK: Draw
	func draw(in view: MTKView) {
		if (accumulationTexture == nil || Int(view.drawableSize.width) != accumulationTexture.width || Int(view.drawableSize.height) != accumulationTexture.height) {
			createAccumulationTexture(size: view.drawableSize)
			frameCount = 0
		}
		
		
		updateCamera()
		var resolution = SIMD2<Float>(Float(view.drawableSize.width), Float(view.drawableSize.height))
		initViewport(camera: camera, resolution: resolution, yaw: yaw, topLeft: &topLeft, vx: &vx, vy: &vy)
		
		
		
		guard let drawable = view.currentDrawable,
			  let descriptor = view.currentRenderPassDescriptor else { return }
		
		let commandBuffer = commandQueue.makeCommandBuffer()!
		let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor)!
		encoder.setRenderPipelineState(pipelineState)
		
		//var resolution = SIMD2<Float>(Float(view.drawableSize.width), Float(view.drawableSize.height))
		encoder.setFragmentBytes(&resolution, length: MemoryLayout<SIMD2<Float>>.stride, index: 0)
		encoder.setFragmentBytes(&cameraPosition, length: MemoryLayout<SIMD3<Float>>.stride, index: 1)
		encoder.setFragmentBuffer(spheresBuffer, offset: 0, index: 2)
		var nbSpheresVar = spheres.count
		encoder.setFragmentBytes(&nbSpheresVar, length: MemoryLayout<Int>.stride, index: 3)
		encoder.setFragmentBuffer(trianglesBuffer, offset: 0, index: 4)
		var nbTrianglesVar = triangles.count
		encoder.setFragmentBytes(&nbTrianglesVar, length: MemoryLayout<Int>.stride, index: 5)
		encoder.setFragmentBytes(&frameCount, length: MemoryLayout<UInt32>.stride, index: 6)
		encoder.setFragmentBytes(&isAccumulating, length: MemoryLayout<Bool>.stride, index: 7)
		encoder.setFragmentBytes(&topLeft, length: MemoryLayout<SIMD3<Float>>.stride, index: 8)
		encoder.setFragmentBytes(&vx, length: MemoryLayout<SIMD3<Float>>.stride, index: 9)
		encoder.setFragmentBytes(&vy, length: MemoryLayout<SIMD3<Float>>.stride, index: 10)
		
		encoder.setFragmentTexture(accumulationTexture, index: 0)
		
		
		encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
		encoder.endEncoding()
		commandBuffer.present(drawable)
		commandBuffer.commit()
		
		if keyA {
			toggleAccumulation()
			keyA = false
		}
		
		if keyC {
			takeScreenshot(view: view)
			keyC = false
		}
		
		if isAccumulating {
			frameCount += 1
		}
	}
	
	func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
		createAccumulationTexture(size: size)
		frameCount = 0
	}
}
