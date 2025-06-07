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

// On garde toutes tes structures existantes ici sans modification (Camera3D, Material, Triangle, Sphere...)


class Renderer: NSObject, MTKViewDelegate, ObservableObject {
	
	// MARK: - Metal Core
	private var view: MTKView!
	let device: MTLDevice
	let commandQueue: MTLCommandQueue
	let computePipelineState: MTLComputePipelineState
	let displayPipelineState: MTLRenderPipelineState
	
	// MARK: - Scene buffers
	private let spheresBuffer: MTLBuffer
	private let trianglesBuffer: MTLBuffer
	
	private var accumulationTexture: MTLTexture!
	private var frameCount: UInt32 = 0
	private let renderingQueue = DispatchQueue(label: "RayTracingQueue")
	private var renderingInProgress = false
	
	// MARK: - Camera
	let cameraSpeed: Float = 0.1
	var forward = SIMD3<Float>(0, 0, -1)
	var right = SIMD3<Float>(1, 0, 0)
	var yaw: Float = 0.0
	var camera = Camera3D(position: SIMD3<Float>(0, 5, 5), fovy: 60)
	private var resolution = SIMD2<Float>(0, 0)
	
	private var topLeft = SIMD3<Float>(0,0,0)
	private var vx = SIMD3<Float>(0,0,0)
	private var vy = SIMD3<Float>(0,0,0)
	
	// MARK: - Controls
	var keyZ = false
	var keyS = false
	var keyQ = false
	var keyD = false
	var keyL = false
	var keyR = false
	var keyA = false
	var keyC = false
	private var isAccumulating = true
	
	// MARK: - Init
	init(metalView: MTKView) {
		self.device = metalView.device!
		self.commandQueue = device.makeCommandQueue()!
		self.view = metalView
		
		let library = device.makeDefaultLibrary()!
		let computeFunction = library.makeFunction(name: "raytraceKernel")!
		self.computePipelineState = try! device.makeComputePipelineState(function: computeFunction)
		
		let vertexFunction = library.makeFunction(name: "vertex_main")!
		let fragmentFunction = library.makeFunction(name: "fragment_main")!
		
		let pipelineDescriptor = MTLRenderPipelineDescriptor()
		pipelineDescriptor.vertexFunction = vertexFunction
		pipelineDescriptor.fragmentFunction = fragmentFunction
		pipelineDescriptor.colorAttachments[0].pixelFormat = metalView.colorPixelFormat
		self.displayPipelineState = try! device.makeRenderPipelineState(descriptor: pipelineDescriptor)
		
		self.spheresBuffer = device.makeBuffer(bytes: spheres, length: MemoryLayout<Sphere>.stride * spheres.count, options: [])!
		self.trianglesBuffer = device.makeBuffer(bytes: triangles, length: MemoryLayout<Triangle>.stride * triangles.count, options: [])!
		
		super.init()
	}
	
	private func createAccumulationTexture(size: CGSize) {
		let width = Int(size.width)
		let height = Int(size.height)
		resolution = SIMD2<Float>(Float(width), Float(height))
		let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba32Float, width: width, height: height, mipmapped: false)
		desc.usage = [.shaderRead, .shaderWrite]
		accumulationTexture = device.makeTexture(descriptor: desc)
		updateViewport()
	}
	
	func startRendering() {
		if renderingInProgress { return }
		renderingInProgress = true
		frameCount = 0
		renderingQueue.async { [weak self] in
			self?.renderLoop()
		}
	}
	
	private func renderLoop() {
		while renderingInProgress {
			autoreleasepool {
				self.updateCamera()
				self.renderOnePass()
				usleep(5000)
			}
		}
	}
	
	private func renderOnePass() {
		let commandBuffer = commandQueue.makeCommandBuffer()!
		let encoder = commandBuffer.makeComputeCommandEncoder()!
		encoder.setComputePipelineState(computePipelineState)
		encoder.setTexture(accumulationTexture, index: 0)
		
		encoder.setBytes(&resolution, length: MemoryLayout<SIMD2<Float>>.stride, index: 0)
		encoder.setBytes(&camera.position, length: MemoryLayout<SIMD3<Float>>.stride, index: 1)
		encoder.setBuffer(spheresBuffer, offset: 0, index: 2)
		var nbSpheresVar = spheresBuffer.length / MemoryLayout<Sphere>.stride
		encoder.setBytes(&nbSpheresVar, length: MemoryLayout<Int>.stride, index: 3)
		encoder.setBuffer(trianglesBuffer, offset: 0, index: 4)
		var nbTrianglesVar = trianglesBuffer.length / MemoryLayout<Triangle>.stride
		encoder.setBytes(&nbTrianglesVar, length: MemoryLayout<Int>.stride, index: 5)
		encoder.setBytes(&frameCount, length: MemoryLayout<UInt32>.stride, index: 6)
		encoder.setBytes(&isAccumulating, length: MemoryLayout<Bool>.stride, index: 7)
		encoder.setBytes(&topLeft, length: MemoryLayout<SIMD3<Float>>.stride, index: 8)
		encoder.setBytes(&vx, length: MemoryLayout<SIMD3<Float>>.stride, index: 9)
		encoder.setBytes(&vy, length: MemoryLayout<SIMD3<Float>>.stride, index: 10)
		
		let threadsPerGroup = MTLSize(width: 8, height: 8, depth: 1)
		let groups = MTLSize(width: (Int(resolution.x)+7)/8, height: (Int(resolution.y)+7)/8, depth: 1)
		encoder.dispatchThreadgroups(groups, threadsPerThreadgroup: threadsPerGroup)
		encoder.endEncoding()
		commandBuffer.commit()
		commandBuffer.waitUntilCompleted()
		
		frameCount += 1
		
		DispatchQueue.main.async {
			self.view.setNeedsDisplay(self.view.bounds)
		}
	}
	
	private func updateViewport() {
		let fov = camera.fovy * Float.pi / 180.0
		let aspect = resolution.x / resolution.y
		let viewportWidth = tan(fov / 2.0) * 2.0
		let viewportHeight = viewportWidth / aspect
		
		forward = SIMD3<Float>(sin(yaw), 0, -cos(yaw))
		right = SIMD3<Float>(-sin(yaw - Float.pi/2), 0, cos(yaw - Float.pi/2))
		let up = SIMD3<Float>(0, 1, 0)
		let center = camera.position + forward
		let horizontal = right * viewportWidth
		let vertical = up * viewportHeight
		topLeft = center - 0.5 * horizontal + 0.5 * -vertical
		vx = horizontal / resolution.x
		vy = vertical / resolution.y
	}
	
	private func updateCamera() {
		var moved = false
		if keyZ { camera.position += forward * cameraSpeed; moved = true }
		if keyS { camera.position -= forward * cameraSpeed; moved = true }
		if keyQ { camera.position -= right * cameraSpeed; moved = true }
		if keyD { camera.position += right * cameraSpeed; moved = true }
		if keyL { yaw -= cameraSpeed * 0.5; moved = true }
		if keyR { yaw += cameraSpeed * 0.5; moved = true }
		
		if moved {
			updateViewport()
			frameCount = 0
		}
		
		if keyA {
			isAccumulating.toggle()
			frameCount = 0
			keyA = false
		}
		
		if keyC {
			takeScreenshot(view: view)
			keyC = false
		}
	}
	
	func draw(in view: MTKView) {
		guard let drawable = view.currentDrawable,
			  let descriptor = view.currentRenderPassDescriptor else { return }
		let commandBuffer = commandQueue.makeCommandBuffer()!
		let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor)!
		encoder.setRenderPipelineState(displayPipelineState)
		encoder.setFragmentTexture(accumulationTexture, index: 0)
		encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
		encoder.endEncoding()
		commandBuffer.present(drawable)
		commandBuffer.commit()
	}
	
	func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
		createAccumulationTexture(size: size)
		frameCount = 0
	}
	
	private func takeScreenshot(view: MTKView) {
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
		let bitmapInfo = CGBitmapInfo.byteOrder32Little.union(CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue))
		guard let context = CGContext(data: bytes, width: width, height: height, bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: bitmapInfo.rawValue),
			  let cgImage = context.makeImage() else { return }
		
		let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: width, height: height))
		guard let tiffData = nsImage.tiffRepresentation,
			  let bitmapRep = NSBitmapImageRep(data: tiffData),
			  let pngData = bitmapRep.representation(using: .png, properties: [:]) else { return }
		
		DispatchQueue.main.async {
			let panel = NSSavePanel()
			panel.title = "Save Screenshot"
			panel.allowedFileTypes = ["png"]
			panel.nameFieldStringValue = "screenshot.png"
			panel.begin { response in
				if response == .OK, let url = panel.url {
					try? pngData.write(to: url)
				}
			}
		}
	}
}
