//
//  Renderer.swift
//  TestMetal
//
//  Created by Nathanaël BONTOUX on 03/06/2025.
//
/*

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
}


func makeDefaultScene() -> SceneInfo {
	print("la")
//	var scene = loadMesh(named: "dragon_80k")
//	var scene = loadSalleMirroirs()
	var scene = loadMesh(named: "SalleCheval")
//	var scene = loadSalleBoules()
	
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
	private var frameCount: Int = 0
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
		
		let meshesData = meshesBuffer.contents()
		let meshesPtr = meshesData.bindMemory(to: MeshInfo.self, capacity: meshes.count)
		
		self.cameraPosition = camera.position
		self.cameraRotation = .zero // Initialize cameraRotation
		
		self.pipelineState = try! device.makeRenderPipelineState(descriptor: pipelineDescriptor)
		
		self.stats = StatsGPU()
		statsBuffer = device.makeBuffer(length: MemoryLayout<StatsGPU>.stride, options: .storageModeShared)
		
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
		if keyZ { camera.position += forward * cameraSpeed ; needViewport = true }
		if keyS { camera.position -= forward * cameraSpeed ; needViewport = true }
		if keyQ { camera.position -= right * cameraSpeed ; needViewport = true }
		if keyD { camera.position += right * cameraSpeed ; needViewport = true }
		if keyL { yaw -= cameraSpeed * 0.5 ; needViewport = true }
		if keyR { yaw += cameraSpeed * 0.5 ; needViewport = true}
		if keyUp { yaz += cameraSpeed * 0.5 ; needViewport = true}
		if keyDown { yaz -= cameraSpeed * 0.5 ; needViewport = true}
		
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
	
	// MARK: Draw
	@MainActor
	func draw(in view: MTKView) {
		// ─────────────────────────────────────────────────────────────
		// MODE BENCHMARK : multi-command buffers offscreen par tick UI
		// ─────────────────────────────────────────────────────────────
		if benchmarking {
			// 1) textures / stats
			if offscreenTexture == nil ||
				offscreenTexture!.width  != Int(view.drawableSize.width) ||
				offscreenTexture!.height != Int(view.drawableSize.height) {
				createOffscreenTexture(size: view.drawableSize)
			}
			guard let tex = offscreenTexture else { return }
			
			// réinitialise les compteurs GPU (si utilisés dans les shaders)
//			statsBuffer.contents().initializeMemory(as: StatsGPU.self, repeating: StatsGPU(), count: 1)
			
			// 2) caméra + viewport
			updateCamera()
			var resolution = SIMD2<Float>(Float(tex.width), Float(tex.height))
			initViewport(camera: camera, resolution: resolution, yaw: yaw, topLeft: &topLeft, vx: &vx, vy: &vy)
			
			// 3) éventuellement rotation auto pour le logging CSV
			if makeStat {
				camera.position = rotatePoint(camera.position, around: getBarycentre(scene: scene, mesh: 0), byX: 0.0, byY: 0.01, byZ: 0.0)
				let target = getBarycentre(scene: scene, mesh: 0)
				let direction = simd_normalize(target - camera.position)
				yaw = atan2(direction.x, -direction.z)
				yaz = asin(direction.y / simd_length(direction))
				cameraRotation = SIMD3<Float>(yaz, yaw, 0)
				
				currentCameraRotation += 0.01
				if currentCameraRotation >= 6.28 {
					makeStat = false
					currentCameraRotation = 0.0
					writeRecordStats()
				}
			}
			
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
				enc.setFragmentBytes(&resolution, length: MemoryLayout<SIMD2<Float>>.stride, index: 0)
				enc.setFragmentBytes(&cameraPosition, length: MemoryLayout<SIMD3<Float>>.stride, index: 1)
				enc.setFragmentBuffer(materialsBuffer, offset: 0, index: 23)
				var nbMaterialsU32: UInt32 = UInt32(materials.count)
				enc.setFragmentBytes(&nbMaterialsU32, length: MemoryLayout<UInt32>.stride, index: 24)
				enc.setFragmentBuffer(spheresBuffer, offset: 0, index: 2)
				var nbSpheresU32: UInt32 = UInt32(spheres.count)
				enc.setFragmentBytes(&nbSpheresU32, length: MemoryLayout<UInt32>.stride, index: 3)
				enc.setFragmentBuffer(trianglesBuffer, offset: 0, index: 4)
				var nbTrianglesU32: UInt32 = UInt32(triangles.count)
				enc.setFragmentBytes(&nbTrianglesU32, length: MemoryLayout<UInt32>.stride, index: 5)
				enc.setFragmentBuffer(meshesBuffer, offset: 0, index: 6)
				var nbMeshesU32: UInt32 = UInt32(meshes.count)
				enc.setFragmentBytes(&nbMeshesU32, length: MemoryLayout<UInt32>.stride, index: 7)
				enc.setFragmentBuffer(nodesBuffer, offset: 0, index: 8)
				var nbNodesU32: UInt32 = UInt32(nodes.count)
				enc.setFragmentBytes(&nbNodesU32, length: MemoryLayout<UInt32>.stride, index: 9)
				enc.setFragmentBytes(&frameCount, length: MemoryLayout<UInt32>.stride, index: 10)
				var accFalse = false
				enc.setFragmentBytes(&accFalse, length: MemoryLayout<Bool>.stride, index: 11) // pas d'accumulation en bench
				enc.setFragmentBytes(&isRayTracing, length: MemoryLayout<Bool>.stride, index: 12)
				enc.setFragmentBytes(&topLeft, length: MemoryLayout<SIMD3<Float>>.stride, index: 13)
				enc.setFragmentBytes(&vx, length: MemoryLayout<SIMD3<Float>>.stride, index: 14)
				enc.setFragmentBytes(&vy, length: MemoryLayout<SIMD3<Float>>.stride, index: 15)
				
				enc.setFragmentTexture(tex, index: 0)
				
				var tileOrigin = SIMD2<UInt32>(0, 0)
				var tileSizeVec = SIMD2<UInt32>(UInt32(resolution.x), UInt32(resolution.y))
				enc.setFragmentBytes(&tileOrigin, length: MemoryLayout<SIMD2<UInt32>>.stride, index: 16)
				enc.setFragmentBytes(&tileSizeVec, length: MemoryLayout<SIMD2<UInt32>>.stride, index: 17)
				
				enc.setFragmentBytes(&maxBounce, length: MemoryLayout<Int>.stride, index: 18)
				enc.setFragmentBytes(&maxBouncePreviews, length: MemoryLayout<Int>.stride, index: 19)
				enc.setFragmentBytes(&raysPerPixel, length: MemoryLayout<Int>.stride, index: 20)
				enc.setFragmentBytes(&isBetterRayTracing, length: MemoryLayout<Bool>.stride, index: 21)
				enc.setFragmentBuffer(statsBuffer, offset: 0, index: 22)
				
				enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
				enc.endEncoding()
				
				// Timing + enregistrement stats (cadence > 60 possible)
				cb.addCompletedHandler { [weak self] cmd in
					guard let self = self else { return }
					let s = cmd.gpuStartTime, e = cmd.gpuEndTime
					guard s > 0, e > 0 else { return }
					
					var cadenceMs = (e - s) * 1000.0
					if let prev = self.lastGPUEndTime {
						cadenceMs = (e - prev) * 1000.0
					}
					self.lastGPUEndTime = e
					
					let instFPS = 1000.0 / max(cadenceMs, 0.001)
					self.emaFPS = self.emaFPS == 0 ? instFPS : (self.alpha * instFPS + (1 - self.alpha) * self.emaFPS)
					
					// log CSV si demandé (au bon moment : fin GPU)
					if self.makeStat {
						let angle = self.currentCameraRotation         // rad si tu préfères
						let sample: (Float, CGFloat) = (angle, CGFloat(self.emaFPS))
						DispatchQueue.main.async {
							self.recordStats.append(sample)
						}
					}
					
					stats.onScreenTriangles = UInt32(10)
					
					DispatchQueue.main.async {
						self.gpuMsPerFrame = cadenceMs
						self.fps = self.emaFPS
					}
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
		
		if accumulationTexture == nil ||
			width  != accumulationTexture.width ||
			height != accumulationTexture.height {
			createAccumulationTexture(size: view.drawableSize)
			frameCount = 0
		}
		
		// reset des stats GPU (comme tu faisais)
//		statsBuffer.contents().initializeMemory(as: StatsGPU.self, repeating: StatsGPU(), count: 1)
		
		// Caméra + éventuelle rotation auto pour CSV
		updateCamera()
		var resolution = SIMD2<Float>(Float(width), Float(height))
		
		if makeStat {
			camera.position = rotatePoint(camera.position, around: getBarycentre(scene: scene, mesh: 0),
										  byX: 0.0, byY: 0.01, byZ: 0.0)
			
			let target = getBarycentre(scene: scene, mesh: 0)
			let direction = simd_normalize(target - camera.position)
			yaw = atan2(direction.x, -direction.z)
			yaz = asin(direction.y / simd_length(direction))
			cameraRotation = SIMD3<Float>(yaz, yaw, 0)
			
			currentCameraRotation += 0.002
			if currentCameraRotation >= 6.28 {
				makeStat = false
				currentCameraRotation = 0.0
				writeRecordStats()
			}
		}
		
		initViewport(camera: camera, resolution: resolution, yaw: yaw, topLeft: &topLeft, vx: &vx, vy: &vy)
		
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
		renderEncoder.setFragmentBytes(&resolution, length: MemoryLayout<SIMD2<Float>>.stride, index: 0)
		renderEncoder.setFragmentBytes(&cameraPosition, length: MemoryLayout<SIMD3<Float>>.stride, index: 1)
		renderEncoder.setFragmentBuffer(materialsBuffer, offset: 0, index: 23)
		var nbMaterialsU32: UInt32 = UInt32(materials.count)
		renderEncoder.setFragmentBytes(&nbMaterialsU32, length: MemoryLayout<UInt32>.stride, index: 24)
		renderEncoder.setFragmentBuffer(spheresBuffer, offset: 0, index: 2)
		var nbSpheresU32: UInt32 = UInt32(spheres.count)
		renderEncoder.setFragmentBytes(&nbSpheresU32, length: MemoryLayout<UInt32>.stride, index: 3)
		renderEncoder.setFragmentBuffer(trianglesBuffer, offset: 0, index: 4)
		var nbTrianglesU32: UInt32 = UInt32(triangles.count)
		renderEncoder.setFragmentBytes(&nbTrianglesU32, length: MemoryLayout<UInt32>.stride, index: 5)
		renderEncoder.setFragmentBuffer(meshesBuffer, offset: 0, index: 6)
		var nbMeshesU32: UInt32 = UInt32(meshes.count)
		renderEncoder.setFragmentBytes(&nbMeshesU32, length: MemoryLayout<UInt32>.stride, index: 7)
		renderEncoder.setFragmentBuffer(nodesBuffer, offset: 0, index: 8)
		var nbNodesU32: UInt32 = UInt32(nodes.count)
		renderEncoder.setFragmentBytes(&nbNodesU32, length: MemoryLayout<UInt32>.stride, index: 9)
		renderEncoder.setFragmentBytes(&frameCount, length: MemoryLayout<UInt32>.stride, index: 10)
		renderEncoder.setFragmentBytes(&isAccumulating, length: MemoryLayout<Bool>.stride, index: 11)
		renderEncoder.setFragmentBytes(&isRayTracing, length: MemoryLayout<Bool>.stride, index: 12)
		renderEncoder.setFragmentBytes(&topLeft, length: MemoryLayout<SIMD3<Float>>.stride, index: 13)
		renderEncoder.setFragmentBytes(&vx, length: MemoryLayout<SIMD3<Float>>.stride, index: 14)
		renderEncoder.setFragmentBytes(&vy, length: MemoryLayout<SIMD3<Float>>.stride, index: 15)
		renderEncoder.setFragmentTexture(accumulationTexture, index: 0)
		renderEncoder.setFragmentBytes(&tileOrigin, length: MemoryLayout<SIMD2<UInt32>>.stride, index: 16)
		renderEncoder.setFragmentBytes(&tileSizeVec, length: MemoryLayout<SIMD2<UInt32>>.stride, index: 17)
		renderEncoder.setFragmentBytes(&maxBounce, length: MemoryLayout<Int>.stride, index: 18)
		renderEncoder.setFragmentBytes(&maxBouncePreviews, length: MemoryLayout<Int>.stride, index: 19)
		renderEncoder.setFragmentBytes(&raysPerPixel, length: MemoryLayout<Int>.stride, index: 20)
		renderEncoder.setFragmentBytes(&isBetterRayTracing, length: MemoryLayout<Bool>.stride, index: 21)
		renderEncoder.setFragmentBuffer(statsBuffer, offset: 0, index: 22)
		
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
			let start = cmd.gpuStartTime
			let end   = cmd.gpuEndTime
			guard start > 0, end > 0 else { return }
			
			let workMs = (end - start) * 1000.0
			var cadenceMs = workMs
			if let prevEnd = self.lastGPUEndTime {
				cadenceMs = (end - prevEnd) * 1000.0
			}
			self.lastGPUEndTime = end
			
			let instFPS = 1000.0 / max(cadenceMs, 0.001)
			self.emaFPS = self.emaFPS == 0 ? instFPS : (self.alpha * instFPS + (1 - self.alpha) * self.emaFPS)
			
			// Log CSV au bon moment
			if self.makeStat {
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
		if keyA { toggleAccumulation(); keyA = false }
		if keyC { takeScreenshot(view: view); keyC = false }
		if keyr { startOfflineRender(); keyr = false }
		if isAccumulating { frameCount += 1 }
	}

	
	func _draw(in view: MTKView) {
		let startTime = CACurrentMediaTime()
		
		
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
		
		encoder.setFragmentBytes(&resolution, length: MemoryLayout<SIMD2<Float>>.stride, index: 0)
		encoder.setFragmentBytes(&cameraPosition, length: MemoryLayout<SIMD3<Float>>.stride, index: 1)
		encoder.setFragmentBuffer(spheresBuffer, offset: 0, index: 2)
		var nbSpheresVarU32: UInt32 = UInt32(spheres.count)
		encoder.setFragmentBytes(&nbSpheresVarU32, length: MemoryLayout<UInt32>.stride, index: 3)
		encoder.setFragmentBuffer(trianglesBuffer, offset: 0, index: 4)
		var nbTrianglesVarU32: UInt32 = UInt32(triangles.count)
		encoder.setFragmentBytes(&nbTrianglesVarU32, length: MemoryLayout<UInt32>.stride, index: 5)
		encoder.setFragmentBuffer(meshesBuffer, offset: 0, index: 6)
		var nbMeshesVarU32: UInt32 = UInt32(meshes.count)
		encoder.setFragmentBytes(&nbMeshesVarU32, length: MemoryLayout<UInt32>.stride, index: 7)
		encoder.setFragmentBytes(&frameCount, length: MemoryLayout<UInt32>.stride, index: 8)
		encoder.setFragmentBytes(&isAccumulating, length: MemoryLayout<Bool>.stride, index: 9)
		encoder.setFragmentBytes(&isRayTracing, length: MemoryLayout<Bool>.stride, index: 10)
		encoder.setFragmentBytes(&topLeft, length: MemoryLayout<SIMD3<Float>>.stride, index: 11)
		encoder.setFragmentBytes(&vx, length: MemoryLayout<SIMD3<Float>>.stride, index: 12)
		encoder.setFragmentBytes(&vy, length: MemoryLayout<SIMD3<Float>>.stride, index: 13)
		
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
		
		let endTime = CACurrentMediaTime()
		let delta = endTime - startTime
		//		print("Frame time: \(delta * 1000.0) ms  FPS: \(1.0 / delta)")
		fps = (fps + 1.0 / delta) / 2
	}
	
	
	func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
		createAccumulationTexture(size: size)
		frameCount = 0
	}
}

*/
