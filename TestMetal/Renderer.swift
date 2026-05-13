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
import UniformTypeIdentifiers
import time_h


struct StatsGPU {
	var onScreenTriangles: UInt32 = UInt32(0)
	var totalTriangles:    UInt32 = UInt32(0)
	var trianglesTest:     UInt32 = UInt32(0)
}

struct StatsNodes {
	var nbNodes: Int = 0
	var nbLeafs: Int = 0
	var maxDepth: Int = 0
	var maxTriangles: Int = 0
	var cost: Float = 0
}


func makeDefaultScene() -> SceneInfo {
//		var scene = loadMesh(named: "dragon_80k")
		var scene = loadSalleMirroirs()
//		var scene = loadMesh(named: "Salle2_2")
//		var scene = loadSalleBoules()
	
	var nodes: [Node] = []
	var bound = Bounds.empty
	for t in scene.triangles {
		bound.growToInclude(t.A)
		bound.growToInclude(t.B)
		bound.growToInclude(t.C)
	}
	
	nodes = []
	
	var stats = StatsNodes()
	let dtime = Date().timeIntervalSince1970
	
	for i in 0..<scene.meshes.count {
		var mesh = scene.meshes[i]
		scene.meshes[i].firstNodeIndex = Int32(nodes.count)
		var root = Node(
			childIndex: Int32(nodes.count),
			triangleIndex: mesh.firstTriangleIndex,
			nbTriangles: Int32(mesh.nbTriangles),
			depth: 0,
			bounds: Bounds(boundMin: mesh.boundMin, boundMax: mesh.boundMax)
		)
		nodes.append(root)
		
		split(
			parentIndex: nodes.count - 1,
			parent: &root,
			triangles: &scene.triangles,
			nodes: &nodes,
			depth: 0,
			maxDepth: 32,
			stats: &stats
		)
	}
	
	//	var root = Node(childIndex: 0, triangleIndex: 0, nbTriangles: Int32(scene.triangles.count), depth: 0, bounds: bound)
	//	nodes.append(root)
	//
	//	split(parentIndex: 0, parent: &root, triangles: &scene.triangles, nodes: &nodes, depth: 0, maxDepth: 32, stats: &stats)
	let ftime = Date().timeIntervalSince1970
	let time = ftime - dtime
	
	scene.nodes = nodes
	
	print("Stats nodes")
	print("Time (s) = \(time)")
	print("Cost: \(stats.cost)")
	print("Triangles : \(scene.triangles.count)")
	print("Node count : \(scene.nodes?.count ?? 0)")
	print("Leaf count : \(stats.nbLeafs)")
	print("Max leaf depth : \(stats.maxDepth)")
	print("Max triangles : \(stats.maxTriangles)")
	print("Mean triangles : \(Float(scene.triangles.count) / Float(stats.nbLeafs))")
	
	
	return scene
}

let scene = makeDefaultScene()
var materials = scene.materials
var spheres: [Sphere] = scene.spheres/* + [Sphere(center: SIMD3<Float>(10, 2, 0), radius: 2, material: .whiteGlass), Sphere(center: SIMD3<Float>(3, 4, 0), radius: 1, material: .light)]*/
var triangles: [Triangle] = scene.triangles
var meshes = scene.meshes
var nodes = scene.nodes!


// MARK: Renderer Metal

class Renderer: NSObject, MTKViewDelegate, ObservableObject {
	var view: MTKView!
	
	let device: MTLDevice
	let commandQueue: MTLCommandQueue
	let pipelineState: MTLRenderPipelineState
	private var pipelineStateDisplay: MTLRenderPipelineState!
	
	private var statsBuffer: MTLBuffer!
	private let materialsBuffer: MTLBuffer
	private let spheresBuffer: MTLBuffer?
	private let trianglesBuffer: MTLBuffer
	private let meshesBuffer: MTLBuffer
	private let nodesBuffer: MTLBuffer
	private var accumulationTexture: MTLTexture!
	private var lastTimestamp: CFTimeInterval = CACurrentMediaTime()
	private var frameCount: UInt32 = 0
	private var frameCounter: Int = 0
	@Published var fps: CGFloat = 60.0
	@Published var GPUTime: CGFloat = 1.0
	@Published var tileSize = 128
	private var tileX = 0
	private var tileY = 0
	private var renderingFinished = false
	private var isOfflineRender = false
	private var currentOfflinePass = 0
	@Published var maxOfflinePasses = 20
	private var needViewport = true
	
	var keyZ = false // DEVANT
	var keyS = false // DERRIERE
	var keyQ = false // GAUCHE
	var keyD = false // DROITE
	var keyA = false // ACCUMULATION TOOGLE
	var keyC = false // SCREENSHOT
	var keyL = false // ROTATE LEFT
	var keyR = false // ROTATE RIGHT
	var keyr = false
	var keyUp = false
	var keyDown = false
	
	@Published var isAccumulating: Bool = false {
		didSet {
			// Quand on désactive l'accumulation, on repasse en direct (frameCount à 0)
			if !isAccumulating {
				frameCount = 0
			}
		}
	}
	@Published var isRayTracing: Bool = false
	@Published var isBetterRayTracing: Bool = false
	
	@Published var maxBouncePreviews = 3
	@Published var maxBounce = 10
	@Published var raysPerPixel = 10
	
	@Published var makeStat: Bool = false
	
	
	// Caméra and viewport
	@Published var cameraSpeed: Float = 0.1
	var forward: SIMD3<Float> = SIMD3<Float>(0, 0, -1)
	var right: SIMD3<Float> = SIMD3<Float>(1, 0, 0)
	
	private var topLeft = SIMD3<Float>(0, 0, 0)
	private var vx = SIMD3<Float>(0, 0, 0)
	private var vy = SIMD3<Float>(0, 0, 0)
	private var yaw: Float = 0.0
	private var yaz: Float = 0.0
	@Published var cameraRotation: SIMD3<Float> = .zero {
		didSet {
			yaw = cameraRotation.y
			yaz = cameraRotation.x
			needViewport = true
		}
	}
	var camera = Camera3D(position: SIMD3<Float>(0, 4, 14), fovy: 80)
	@Published var cameraPosition: SIMD3<Float> {
		didSet {
			camera.position = cameraPosition
		}
	}
	var currentCameraRotation: Float = 0.0
	
	// get only of GPUTime
	var gpuTime: CGFloat {
		get { GPUTime }
	}
	
	@Published var gpuMsPerFrame: Double = 0
	
	private var lastGPUEndTime: CFTimeInterval? = nil
	private var emaFPS: Double = 0          // for smoothing
	private let alpha = 0.5                 // EMA factor
	
	// Removed cameraPositionProp setter to avoid modifying camera.position through it
	var cameraPositionProp: SIMD3<Float> {
		get { camera.position }
	}
	
	var stats: StatsGPU
	var recordStats: [(Float, CGFloat)?] = []
	
	@Published var benchmarking = false
	private var offscreenTexture: MTLTexture?
	@Published var framesPerTick: Int = 5
	
	// GROSSE MODIFICATION :
	// On met en cache tout ce qui ne change pas pour éviter des conversions/recalculs à chaque frame.
	private let nbMaterialsU32: UInt32
	private let nbSpheresU32: UInt32
	private let nbTrianglesU32: UInt32
	private let nbMeshesU32: UInt32
	private let nbNodesU32: UInt32
	private let sceneBarycentre: SIMD3<Float>
	
	// GROSSE MODIFICATION :
	// Buffer CPU réutilisé pour remettre la texture d'accumulation à zéro.
	// Cela évite de réallouer un gros tableau à chaque clear.
	private var accumulationZeroPixels: [SIMD4<Float>] = []
	private var accumulationZeroCapacity: Int = 0
	
	
	// MARK: init
	init(metalView: MTKView) {
		//		print(meshes)
		
		self.device = metalView.device!
		self.commandQueue = device.makeCommandQueue()!
		self.view = metalView
		
		let library = device.makeDefaultLibrary()!
		
		let vertexFunction = library.makeFunction(name: "vertex_main")!
		let fragmentDisplayFunction = library.makeFunction(name: "fragment_displayAccumulation")!
		
		let fragmentFunction = library.makeFunction(name: "fragment_main")!
		
		let displayDescriptor = MTLRenderPipelineDescriptor()
		displayDescriptor.vertexFunction = vertexFunction
		displayDescriptor.fragmentFunction = fragmentDisplayFunction
		displayDescriptor.colorAttachments[0].pixelFormat = metalView.colorPixelFormat // .bgra8Unorm
		
		pipelineStateDisplay = try! device.makeRenderPipelineState(descriptor: displayDescriptor)
		
		
		
		let pipelineDescriptor = MTLRenderPipelineDescriptor()
		pipelineDescriptor.vertexFunction = vertexFunction
		pipelineDescriptor.fragmentFunction = fragmentFunction
		pipelineDescriptor.colorAttachments[0].pixelFormat = metalView.colorPixelFormat
		
		materialsBuffer = device.makeBuffer(
			bytes: materials,
			length: MemoryLayout<Material>.stride * materials.count,
			options: [.storageModeShared]
		)!
		
		spheresBuffer = device.makeBuffer(
			bytes: spheres,
			length: MemoryLayout<Sphere>.stride * spheres.count,
			options: [.storageModeShared]
		)
		
		trianglesBuffer = device.makeBuffer(
			bytes: triangles,
			length: MemoryLayout<Triangle>.stride * triangles.count,
			options: [.storageModeShared]
		)!
		
		meshesBuffer = device.makeBuffer(
			bytes: meshes,
			length: MemoryLayout<MeshInfo>.stride * meshes.count,
			options: [.storageModeShared]
		)!
		
		nodesBuffer = device.makeBuffer(
			bytes: nodes,
			length: MemoryLayout<Node>.stride * nodes.count,
			options: [.storageModeShared]
		)!
		
		self.cameraPosition = camera.position
		self.cameraRotation = .zero // Initialize cameraRotation
		
		self.pipelineState = try! device.makeRenderPipelineState(descriptor: pipelineDescriptor)
		
		self.stats = StatsGPU()
		statsBuffer = device.makeBuffer(length: MemoryLayout<StatsGPU>.stride, options: .storageModeShared)
		
		self.nbMaterialsU32 = UInt32(materials.count)
		self.nbSpheresU32 = UInt32(spheres.count)
		self.nbTrianglesU32 = UInt32(triangles.count)
		self.nbMeshesU32 = UInt32(meshes.count)
		self.nbNodesU32 = UInt32(nodes.count)
		self.sceneBarycentre = getBarycentre(scene: scene, mesh: 0)
		
		super.init()
	}
	
	// MARK: initViewport
	func initViewport(camera: Camera3D, resolution: SIMD2<Float>, yaw: Float, topLeft: inout SIMD3<Float>, vx: inout SIMD3<Float>, vy: inout SIMD3<Float>) {
		
		let fov = camera.fovy * Float.pi / 180.0
		let aspect = resolution.x / resolution.y
		let viewportWidth = tan(fov / 2.0) * 2.0
		let viewportHeight = viewportWidth / aspect
		
		// Direction de la caméra
		let cy = cos(yaz)
		let sy = sin(yaz)
		let cx = cos(yaw)
		let sx = sin(yaw)
		
		forward = SIMD3<Float>(
			sx * cy,
			sy,
			-cx * cy
		)
		
		right = SIMD3<Float>(
			cx,
			0,
			sx
		)
		
		let up = cross(right, forward)
		
		
		let center = camera.position + forward
		let horizontal = right * viewportWidth
		let vertical = up * viewportHeight
		
		topLeft = center - 0.5 * horizontal + 0.5 * -vertical
		vx = horizontal / resolution.x
		vy = vertical / resolution.y
	}
	
	// MARK: Accumulation
	func createOffscreenTexture(size: CGSize) {
		let w = Int(size.width), h = Int(size.height)
		guard w > 0, h > 0 else { return }
		let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba32Float, width: w, height: h, mipmapped: false)
		desc.usage = [.shaderRead, .shaderWrite, .renderTarget]
		offscreenTexture = device.makeTexture(descriptor: desc)
	}
	
	
	
	private func createAccumulationTexture(size: CGSize) {
		let width = Int(size.width)
		let height = Int(size.height)
		
		// Protection contre les tailles invalides
		guard width > 0 && height > 0 else { return }
		
		let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba32Float, width: width, height: height, mipmapped: false)
		descriptor.usage = [.shaderRead, .shaderWrite]
		accumulationTexture = device.makeTexture(descriptor: descriptor)
		
		// GROSSE MODIFICATION :
		// On prépare un buffer réutilisable pour le clear CPU.
		let pixelCount = width * height
		if pixelCount > accumulationZeroCapacity {
			accumulationZeroPixels = [SIMD4<Float>](repeating: SIMD4<Float>(0, 0, 0, 0), count: pixelCount)
			accumulationZeroCapacity = pixelCount
		}
	}
	
	private func clearAccumulationTexture() {
		guard let texture = accumulationTexture else { return }
		
		let width = texture.width
		let height = texture.height
		
		let region = MTLRegionMake2D(0, 0, width, height)
		let pixelCount = width * height
		
		if pixelCount > accumulationZeroCapacity {
			accumulationZeroPixels = [SIMD4<Float>](repeating: SIMD4<Float>(0, 0, 0, 0), count: pixelCount)
			accumulationZeroCapacity = pixelCount
		}
		
		accumulationZeroPixels.withUnsafeMutableBytes { rawPtr in
			guard let base = rawPtr.baseAddress else { return }
			texture.replace(
				region: region,
				mipmapLevel: 0,
				withBytes: base,
				bytesPerRow: MemoryLayout<SIMD4<Float>>.stride * width
			)
		}
	}
	
	private func ensureAccumulationTexture(for size: CGSize) {
		let width = Int(size.width)
		let height = Int(size.height)
		guard width > 0, height > 0 else { return }
		
		if accumulationTexture == nil ||
			width != accumulationTexture.width ||
			height != accumulationTexture.height {
			createAccumulationTexture(size: size)
			frameCount = 0
			needViewport = true
		}
	}
	
	private func ensureOffscreenTexture(for size: CGSize) {
		let width = Int(size.width)
		let height = Int(size.height)
		guard width > 0, height > 0 else { return }
		
		if offscreenTexture == nil ||
			offscreenTexture!.width != width ||
			offscreenTexture!.height != height {
			createOffscreenTexture(size: size)
		}
	}
	
	func startOfflineRender() {
		renderingFinished = false
		tileX = 0
		tileY = 0
		currentOfflinePass = 0
		// clearAccumulationTexture() -- removed here per instruction
		frameCount = 0
		isOfflineRender = true
	}
	
	func toggleAccumulation() {
		isAccumulating = !isAccumulating
		if isAccumulating {
			clearAccumulationTexture() // Nettoie la texture au début de l'accumulation
			frameCount = 0
		}
	}
	
	// MARK: Camera
	func updateCamera() {
		var moved = false
		
		if keyZ { camera.position += forward * cameraSpeed ; moved = true }
		if keyS { camera.position -= forward * cameraSpeed ; moved = true }
		if keyQ { camera.position -= right * cameraSpeed ; moved = true }
		if keyD { camera.position += right * cameraSpeed ; moved = true }
		if keyL { yaw -= cameraSpeed * 0.5 ; moved = true }
		if keyR { yaw += cameraSpeed * 0.5 ; moved = true }
		if keyUp { yaz += cameraSpeed * 0.5 ; moved = true }
		if keyDown { yaz -= cameraSpeed * 0.5 ; moved = true }
		
		if moved {
			needViewport = true
		}
		
		// Keep cameraRotation in sync with yaw and yaz
		cameraRotation.x = yaz
		cameraRotation.y = yaw
		
		self.cameraPosition = camera.position
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
			panel.allowedContentTypes = [.png]
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
	
	func writeRecordStats() {
		let lines = recordStats.compactMap { entry -> String? in
			guard let (rotation, fps) = entry else { return nil }
			let rotStr = String(format: "%.4f", rotation * 180.0 / Float.pi)
			let gpuStr = String(format: "%.1f", fps)
			return "\(rotStr), \(gpuStr)"
		}
		let content = lines.joined(separator: "\n")
		
		DispatchQueue.main.async {
			let panel = NSSavePanel()
			panel.title = "Enregistrer les statistiques de rendu"
			panel.allowedContentTypes = [.plainText]
			panel.nameFieldStringValue = "stats.txt"
			panel.begin { response in
				if response == .OK, let url = panel.url {
					do {
						try content.write(to: url, atomically: true, encoding: .utf8)
						print("Stats saved at \(url.path)")
					} catch {
						print("Error writing stats: \(error)")
					}
				}
			}
		}
	}
	
	// GROSSE MODIFICATION :
	// On centralise la rotation auto/stat pour éviter le code dupliqué
	// entre benchmark et mode normal.
	private func updateAutomaticCameraRotation(step: Float) {
		camera.position = rotatePoint(
			camera.position,
			around: sceneBarycentre,
			byX: 0.0,
			byY: step,
			byZ: 0.0
		)
		
		let direction = simd_normalize(sceneBarycentre - camera.position)
		yaw = atan2(direction.x, -direction.z)
		yaz = asin(direction.y / simd_length(direction))
		cameraRotation = SIMD3<Float>(yaz, yaw, 0)
		
		currentCameraRotation += step
		if currentCameraRotation >= 6.28 {
			makeStat = false
			currentCameraRotation = 0.0
			writeRecordStats()
		}
		
		needViewport = true
	}
	
	// GROSSE MODIFICATION :
	// On centralise tous les bindings communs pour éviter les gros blocs répétitifs.
	private func setCommonFragmentState(
		encoder: MTLRenderCommandEncoder,
		resolution: inout SIMD2<Float>,
		cameraPosition: inout SIMD3<Float>,
		frameCount: inout UInt32,
		isAccumulating: inout Bool,
		isRayTracing: inout Bool,
		topLeft: inout SIMD3<Float>,
		vx: inout SIMD3<Float>,
		vy: inout SIMD3<Float>,
		tileOrigin: inout SIMD2<UInt32>,
		tileSizeVec: inout SIMD2<UInt32>,
		maxBounce: inout Int,
		maxBouncePreviews: inout Int,
		raysPerPixel: inout Int,
		isBetterRayTracing: inout Bool,
		accumulationTexture: MTLTexture?
	) {
		encoder.setFragmentBytes(&resolution, length: MemoryLayout<SIMD2<Float>>.stride, index: 0)
		encoder.setFragmentBytes(&cameraPosition, length: MemoryLayout<SIMD3<Float>>.stride, index: 1)
		encoder.setFragmentBuffer(materialsBuffer, offset: 0, index: 23)
		encoder.setFragmentBytes(UnsafeMutableRawPointer(mutating: [nbMaterialsU32]), length: MemoryLayout<UInt32>.stride, index: 24)
		encoder.setFragmentBuffer(spheresBuffer, offset: 0, index: 2)
		encoder.setFragmentBytes(UnsafeMutableRawPointer(mutating: [nbSpheresU32]), length: MemoryLayout<UInt32>.stride, index: 3)
		encoder.setFragmentBuffer(trianglesBuffer, offset: 0, index: 4)
		encoder.setFragmentBytes(UnsafeMutableRawPointer(mutating: [nbTrianglesU32]), length: MemoryLayout<UInt32>.stride, index: 5)
		encoder.setFragmentBuffer(meshesBuffer, offset: 0, index: 6)
		encoder.setFragmentBytes(UnsafeMutableRawPointer(mutating: [nbMeshesU32]), length: MemoryLayout<UInt32>.stride, index: 7)
		encoder.setFragmentBuffer(nodesBuffer, offset: 0, index: 8)
		encoder.setFragmentBytes(UnsafeMutableRawPointer(mutating: [nbNodesU32]), length: MemoryLayout<UInt32>.stride, index: 9)
		encoder.setFragmentBytes(&frameCount, length: MemoryLayout<UInt32>.stride, index: 10)
		encoder.setFragmentBytes(&isAccumulating, length: MemoryLayout<Bool>.stride, index: 11)
		encoder.setFragmentBytes(&isRayTracing, length: MemoryLayout<Bool>.stride, index: 12)
		encoder.setFragmentBytes(&topLeft, length: MemoryLayout<SIMD3<Float>>.stride, index: 13)
		encoder.setFragmentBytes(&vx, length: MemoryLayout<SIMD3<Float>>.stride, index: 14)
		encoder.setFragmentBytes(&vy, length: MemoryLayout<SIMD3<Float>>.stride, index: 15)
		encoder.setFragmentTexture(accumulationTexture, index: 0)
		encoder.setFragmentBytes(&tileOrigin, length: MemoryLayout<SIMD2<UInt32>>.stride, index: 16)
		encoder.setFragmentBytes(&tileSizeVec, length: MemoryLayout<SIMD2<UInt32>>.stride, index: 17)
		encoder.setFragmentBytes(&maxBounce, length: MemoryLayout<Int>.stride, index: 18)
		encoder.setFragmentBytes(&maxBouncePreviews, length: MemoryLayout<Int>.stride, index: 19)
		encoder.setFragmentBytes(&raysPerPixel, length: MemoryLayout<Int>.stride, index: 20)
		encoder.setFragmentBytes(&isBetterRayTracing, length: MemoryLayout<Bool>.stride, index: 21)
		encoder.setFragmentBuffer(statsBuffer, offset: 0, index: 22)
	}
	
	// Version plus sûre pour les valeurs constantes UInt32
	private func setUInt32(_ value: UInt32, encoder: MTLRenderCommandEncoder, index: Int) {
		var v = value
		encoder.setFragmentBytes(&v, length: MemoryLayout<UInt32>.stride, index: index)
	}
	
	private func setCommonFragmentStateSafe(
		encoder: MTLRenderCommandEncoder,
		resolution: inout SIMD2<Float>,
		cameraPosition: inout SIMD3<Float>,
		frameCount: inout UInt32,
		isAccumulating: inout Bool,
		isRayTracing: inout Bool,
		topLeft: inout SIMD3<Float>,
		vx: inout SIMD3<Float>,
		vy: inout SIMD3<Float>,
		tileOrigin: inout SIMD2<UInt32>,
		tileSizeVec: inout SIMD2<UInt32>,
		maxBounce: inout Int,
		maxBouncePreviews: inout Int,
		raysPerPixel: inout Int,
		isBetterRayTracing: inout Bool,
		accumulationTexture: MTLTexture?
	) {
		encoder.setFragmentBytes(&resolution, length: MemoryLayout<SIMD2<Float>>.stride, index: 0)
		encoder.setFragmentBytes(&cameraPosition, length: MemoryLayout<SIMD3<Float>>.stride, index: 1)
		encoder.setFragmentBuffer(materialsBuffer, offset: 0, index: 23)
		setUInt32(nbMaterialsU32, encoder: encoder, index: 24)
		encoder.setFragmentBuffer(spheresBuffer, offset: 0, index: 2)
		setUInt32(nbSpheresU32, encoder: encoder, index: 3)
		encoder.setFragmentBuffer(trianglesBuffer, offset: 0, index: 4)
		setUInt32(nbTrianglesU32, encoder: encoder, index: 5)
		encoder.setFragmentBuffer(meshesBuffer, offset: 0, index: 6)
		setUInt32(nbMeshesU32, encoder: encoder, index: 7)
		encoder.setFragmentBuffer(nodesBuffer, offset: 0, index: 8)
		setUInt32(nbNodesU32, encoder: encoder, index: 9)
		encoder.setFragmentBytes(&frameCount, length: MemoryLayout<UInt32>.stride, index: 10)
		encoder.setFragmentBytes(&isAccumulating, length: MemoryLayout<Bool>.stride, index: 11)
		encoder.setFragmentBytes(&isRayTracing, length: MemoryLayout<Bool>.stride, index: 12)
		encoder.setFragmentBytes(&topLeft, length: MemoryLayout<SIMD3<Float>>.stride, index: 13)
		encoder.setFragmentBytes(&vx, length: MemoryLayout<SIMD3<Float>>.stride, index: 14)
		encoder.setFragmentBytes(&vy, length: MemoryLayout<SIMD3<Float>>.stride, index: 15)
		encoder.setFragmentTexture(accumulationTexture, index: 0)
		encoder.setFragmentBytes(&tileOrigin, length: MemoryLayout<SIMD2<UInt32>>.stride, index: 16)
		encoder.setFragmentBytes(&tileSizeVec, length: MemoryLayout<SIMD2<UInt32>>.stride, index: 17)
		encoder.setFragmentBytes(&maxBounce, length: MemoryLayout<Int>.stride, index: 18)
		encoder.setFragmentBytes(&maxBouncePreviews, length: MemoryLayout<Int>.stride, index: 19)
		encoder.setFragmentBytes(&raysPerPixel, length: MemoryLayout<Int>.stride, index: 20)
		encoder.setFragmentBytes(&isBetterRayTracing, length: MemoryLayout<Bool>.stride, index: 21)
		encoder.setFragmentBuffer(statsBuffer, offset: 0, index: 22)
	}
	
	// GROSSE MODIFICATION :
	// Gestion unifiée du timing GPU et de l'enregistrement des stats.
	private func handleCompletedCommandBuffer(_ cmd: MTLCommandBuffer, appendStats: Bool) {
		let start = cmd.gpuStartTime
		let end = cmd.gpuEndTime
		guard start > 0, end > 0 else { return }
		
		let workMs = (end - start) * 1000.0
		var cadenceMs = workMs
		if let prevEnd = self.lastGPUEndTime {
			cadenceMs = (end - prevEnd) * 1000.0
		}
		self.lastGPUEndTime = end
		
		let instFPS = 1000.0 / max(cadenceMs, 0.001)
		self.emaFPS = self.emaFPS == 0 ? instFPS : (self.alpha * instFPS + (1 - self.alpha) * self.emaFPS)
		
		if appendStats && self.makeStat {
			let angle = self.currentCameraRotation
			let sample: (Float, CGFloat) = (angle, CGFloat(self.emaFPS))
			DispatchQueue.main.async {
				self.recordStats.append(sample)
			}
		}
		
		DispatchQueue.main.async {
			self.gpuMsPerFrame = cadenceMs
			self.GPUTime = workMs
			self.fps = self.emaFPS
		}
	}
	
	private func updateViewportIfNeeded(resolution: SIMD2<Float>) {
		if needViewport {
			initViewport(camera: camera, resolution: resolution, yaw: yaw, topLeft: &topLeft, vx: &vx, vy: &vy)
			needViewport = false
		}
	}
	
	private func handleInputToggles(view: MTKView) {
		if keyA { toggleAccumulation(); keyA = false }
		if keyC { takeScreenshot(view: view); keyC = false }
		if keyr { startOfflineRender(); keyr = false }
		if isAccumulating { frameCount += 1 }
	}
	
	// MARK: Draw
	@MainActor
	func draw(in view: MTKView) {
		// ─────────────────────────────────────────────────────────────
		// MODE BENCHMARK : multi-command buffers offscreen par tick UI
		// ─────────────────────────────────────────────────────────────
		if benchmarking {
			// 1) textures / stats
			ensureOffscreenTexture(for: view.drawableSize)
			guard let tex = offscreenTexture else { return }
			
			// réinitialise les compteurs GPU (si utilisés dans les shaders)
			//			statsBuffer.contents().initializeMemory(as: StatsGPU.self, repeating: StatsGPU(), count: 1)
			
			// 2) caméra + viewport
			updateCamera()
			var resolution = SIMD2<Float>(Float(tex.width), Float(tex.height))
			
			if makeStat {
				updateAutomaticCameraRotation(step: 0.01)
			}
			
			updateViewportIfNeeded(resolution: resolution)
			
			// 4) pousser plusieurs CB offscreen (pas de present)
			for _ in 0..<framesPerTick {
				let cb = commandQueue.makeCommandBuffer()!
				
				// RP vers offscreen texture
				let rp = MTLRenderPassDescriptor()
				rp.colorAttachments[0].texture = tex
				rp.colorAttachments[0].loadAction = .load     // .clear si tu veux remettre à zéro
				rp.colorAttachments[0].storeAction = .store
				
				// Encoder principal identique au chemin normal (mais sur `rp`)
				let enc = cb.makeRenderCommandEncoder(descriptor: rp)!
				enc.setRenderPipelineState(pipelineState)
				
				// Vertex
				enc.setVertexBytes(&resolution, length: MemoryLayout<SIMD2<Float>>.stride, index: 0)
				
				// Fragments
				var camPos = cameraPosition
				var accFalse = false
				var isRT = isRayTracing
				var betterRT = isBetterRayTracing
				var maxB = maxBounce
				var maxBP = maxBouncePreviews
				var rpp = raysPerPixel
				var tileOrigin = SIMD2<UInt32>(0, 0)
				var tileSizeVec = SIMD2<UInt32>(UInt32(resolution.x), UInt32(resolution.y))
				
				setCommonFragmentStateSafe(
					encoder: enc,
					resolution: &resolution,
					cameraPosition: &camPos,
					frameCount: &frameCount,
					isAccumulating: &accFalse,
					isRayTracing: &isRT,
					topLeft: &topLeft,
					vx: &vx,
					vy: &vy,
					tileOrigin: &tileOrigin,
					tileSizeVec: &tileSizeVec,
					maxBounce: &maxB,
					maxBouncePreviews: &maxBP,
					raysPerPixel: &rpp,
					isBetterRayTracing: &betterRT,
					accumulationTexture: tex
				)
				
				enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
				enc.endEncoding()
				
				// Timing + enregistrement stats (cadence > 60 possible)
				cb.addCompletedHandler { [weak self] cmd in
					guard let self = self else { return }
					self.handleCompletedCommandBuffer(cmd, appendStats: true)
					
					self.stats.onScreenTriangles = UInt32(10)
				}
				
				cb.commit()
			}
			return
		}
		
		// ─────────────────────────────────────────────────────────────
		// MODE NORMAL : ton code d’origine conservé
		// ─────────────────────────────────────────────────────────────
		guard !renderingFinished else { return }
		
		stats.onScreenTriangles += UInt32(1)
		
		let width  = Int(view.drawableSize.width)
		let height = Int(view.drawableSize.height)
		
		ensureAccumulationTexture(for: view.drawableSize)
		
		// reset des stats GPU (comme tu faisais)
		//		statsBuffer.contents().initializeMemory(as: StatsGPU.self, repeating: StatsGPU(), count: 1)
		
		// Caméra + éventuelle rotation auto pour CSV
		updateCamera()
		var resolution = SIMD2<Float>(Float(width), Float(height))
		
		if makeStat {
			updateAutomaticCameraRotation(step: 0.002)
		}
		
		updateViewportIfNeeded(resolution: resolution)
		
		guard let drawable = view.currentDrawable,
			  let descriptor = view.currentRenderPassDescriptor else { return }
		
		let commandBuffer = commandQueue.makeCommandBuffer()!
		
		// ─── CONFIGURATION DES TUILES POUR LE RENDU OFFLINE ───
		var tileOrigin = SIMD2<UInt32>(0, 0)
		var tileSizeVec = SIMD2<UInt32>(UInt32(width), UInt32(height))
		
		if isOfflineRender {
			let tileWidth  = min(tileSize, width  - tileX)
			let tileHeight = min(tileSize, height - tileY)
			
			if tileWidth <= 0 || tileHeight <= 0 {
				renderingFinished = true
				isOfflineRender = false
				print("Rendering completed")
				return
			}
			
			tileOrigin = SIMD2<UInt32>(UInt32(tileX), UInt32(tileY))
			tileSizeVec = SIMD2<UInt32>(UInt32(tileWidth), UInt32(tileHeight))
		}
		
		// ─── PREMIÈRE PASSE : RENDU PRINCIPAL ───
		let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor)!
		renderEncoder.setRenderPipelineState(pipelineState)
		
		// Vertex
		renderEncoder.setVertexBytes(&resolution, length: MemoryLayout<SIMD2<Float>>.stride, index: 0)
		
		// Fragments
		var camPos = cameraPosition
		var acc = isAccumulating
		var isRT = isRayTracing
		var betterRT = isBetterRayTracing
		var maxB = maxBounce
		var maxBP = maxBouncePreviews
		var rpp = raysPerPixel
		
		setCommonFragmentStateSafe(
			encoder: renderEncoder,
			resolution: &resolution,
			cameraPosition: &camPos,
			frameCount: &frameCount,
			isAccumulating: &acc,
			isRayTracing: &isRT,
			topLeft: &topLeft,
			vx: &vx,
			vy: &vy,
			tileOrigin: &tileOrigin,
			tileSizeVec: &tileSizeVec,
			maxBounce: &maxB,
			maxBouncePreviews: &maxBP,
			raysPerPixel: &rpp,
			isBetterRayTracing: &betterRT,
			accumulationTexture: accumulationTexture
		)
		
		renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
		renderEncoder.endEncoding()
		
		// ─── DEUXIÈME PASSE : AFFICHAGE (si accumulation / offline) ───
		if isAccumulating || isOfflineRender {
			let displayDescriptor = MTLRenderPassDescriptor()
			displayDescriptor.colorAttachments[0].texture = drawable.texture
			displayDescriptor.colorAttachments[0].loadAction = .dontCare
			displayDescriptor.colorAttachments[0].storeAction = .store
			
			let displayEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: displayDescriptor)!
			displayEncoder.setRenderPipelineState(pipelineStateDisplay)
			displayEncoder.setVertexBytes(&resolution, length: MemoryLayout<SIMD2<Float>>.stride, index: 0)
			displayEncoder.setFragmentTexture(accumulationTexture, index: 0)
			displayEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
			displayEncoder.endEncoding()
		}
		
		// Timing & enregistrement FPS/stats (cadence)
		commandBuffer.addCompletedHandler { [weak self] cmd in
			guard let self = self else { return }
			self.handleCompletedCommandBuffer(cmd, appendStats: true)
		}
		
		commandBuffer.present(drawable)
		commandBuffer.commit()
		
		// ─── OFFLINE TILING ───
		if isOfflineRender {
			currentOfflinePass += 1
			if currentOfflinePass >= maxOfflinePasses {
				currentOfflinePass = 0
				tileX += tileSize
				if tileX >= width {
					tileX = 0
					tileY += tileSize
				}
				if tileY >= height {
					renderingFinished = true
					isOfflineRender = false
					print("Offline rendering completed")
					DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
						self.takeScreenshot(view: view)
					}
				}
			}
		}
		
		// ─── INPUTS / TOGGLES ───
		handleInputToggles(view: view)
	}
	
	
	func _draw(in view: MTKView) {
		let startTime = CACurrentMediaTime()
		
		
		ensureAccumulationTexture(for: view.drawableSize)
		
		
		updateCamera()
		var resolution = SIMD2<Float>(Float(view.drawableSize.width), Float(view.drawableSize.height))
		updateViewportIfNeeded(resolution: resolution)
		
		
		guard let drawable = view.currentDrawable,
			  let descriptor = view.currentRenderPassDescriptor else { return }
		
		let commandBuffer = commandQueue.makeCommandBuffer()!
		let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor)!
		encoder.setRenderPipelineState(pipelineState)
		
		encoder.setFragmentBytes(&resolution, length: MemoryLayout<SIMD2<Float>>.stride, index: 0)
		
		var camPos = cameraPosition
		var acc = isAccumulating
		var isRT = isRayTracing
		var betterRT = isBetterRayTracing
		var maxB = maxBounce
		var maxBP = maxBouncePreviews
		var rpp = raysPerPixel
		var tileOrigin = SIMD2<UInt32>(0, 0)
		var tileSizeVec = SIMD2<UInt32>(UInt32(resolution.x), UInt32(resolution.y))
		
		setCommonFragmentStateSafe(
			encoder: encoder,
			resolution: &resolution,
			cameraPosition: &camPos,
			frameCount: &frameCount,
			isAccumulating: &acc,
			isRayTracing: &isRT,
			topLeft: &topLeft,
			vx: &vx,
			vy: &vy,
			tileOrigin: &tileOrigin,
			tileSizeVec: &tileSizeVec,
			maxBounce: &maxB,
			maxBouncePreviews: &maxBP,
			raysPerPixel: &rpp,
			isBetterRayTracing: &betterRT,
			accumulationTexture: accumulationTexture
		)
		
		
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
		
		let endTime = CACurrentMediaTime()
		let delta = endTime - startTime
		//		print("Frame time: \(delta * 1000.0) ms  FPS: \(1.0 / delta)")
		fps = (fps + 1.0 / delta) / 2
	}
	
	
	func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
		createAccumulationTexture(size: size)
		frameCount = 0
		needViewport = true
	}
}
