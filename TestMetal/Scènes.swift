//
//  Scènes.swift
//  TestMetal
//
//  Created by Nathanaël BONTOUX on 09/06/2025.
//

import Foundation
import Foundation
import simd

/// Clamps a value between a minimum and maximum.
func clamp<T: Comparable>(_ value: T, _ minValue: T, _ maxValue: T) -> T {
    return min(max(value, minValue), maxValue)
}

enum MaterialLoadingError: Error {
    case fileNotFound
}

// MARK: - Extensions utilitaires

extension SIMD3 where Scalar == Float {
	static let black = SIMD3(0, 0, 0)
	static let white = SIMD3(1, 1, 1)
	static let red = SIMD3(1, 0, 0)
	static let green = SIMD3(0, 1, 0)
	static let blue = SIMD3(0, 0, 1)
	static let gray = SIMD3(0.5, 0.5, 0.5)
	
	static func <=(lhs: SIMD3<Float>, rhs: SIMD3<Float>) -> Bool {
		return lhs.x <= rhs.x && lhs.y <= rhs.y && lhs.z <= rhs.z
	}
	
	static func >=(lhs: SIMD3<Float>, rhs: SIMD3<Float>) -> Bool {
		return lhs.x >= rhs.x && lhs.y >= rhs.y && lhs.z >= rhs.z
	}
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
	var smoothness: Float = 0
	var isTransparent: Bool = false
	var indice: Float = 1.0
	
	static let light = Material(color: .black, emitingColor: .white, emitingStrength: 5.0, smoothness: 0)
	static let white = Material(color: .white, emitingColor: .black, emitingStrength: 0.0, smoothness: 0)
	static let green = Material(color: .green, emitingColor: .black, emitingStrength: 0.0, smoothness: 0)
	static let red = Material(color: .red, emitingColor: .black, emitingStrength: 0.0, smoothness: 0)
	static let gray = Material(color: .gray, emitingColor: .black, emitingStrength: 0.0, smoothness: 0)
	static let blue = Material(color: .blue, emitingColor: .black, emitingStrength: 0.0, smoothness: 0)
	static let black = Material(color: .black, emitingColor: .black, emitingStrength: 0.0, smoothness: 0)
	
	static let mirror = Material(color: .white, emitingColor: .black, emitingStrength: 0, smoothness: 1)
	
	static let whiteGlass = Material(color: .white, emitingColor: .black, emitingStrength: 0, isTransparent: true, indice: 1.5)
	static let water = Material(color: .blue, emitingColor: .black, emitingStrength: 0, isTransparent: true, indice: 1.33)
	
	static func whiteReflective(smooth: Float) -> Material {
		return Material(color: .white, emitingColor: .black, emitingStrength: 0, smoothness: smooth)
	}
	
	static func coloredMirror(color: SIMD3<Float>) -> Material {
		return Material(color: color, emitingColor: .black, emitingStrength: 0, smoothness: 1)
	}
	
	static func tintedGlass(color: SIMD3<Float>) -> Material {
		return Material(color: color, emitingColor: .black, emitingStrength: 0, isTransparent: true, indice: 1.5)
	}
	
	static func tintedWater(color: SIMD3<Float>) -> Material {
		return Material(color: color, emitingColor: .black, emitingStrength: 0, isTransparent: true, indice: 1.33)
	}
}

// MARK: Structs
struct Triangle {
	var A: SIMD3<Float>
	var B: SIMD3<Float>
	var C: SIMD3<Float>
	var n: SIMD3<Float>
	var material: Material
	
	var baricenter: SIMD3<Float> { return (A + B + C) / 3.0 }
}

struct Sphere {
	var center: SIMD3<Float>
	var radius: Float
	var material: Material
}

struct Bounds {
	var boundMin: SIMD3<Float>
	var boundMax: SIMD3<Float>
	
	static let empty: Bounds = .init(boundMin: .init(repeating: 0.0), boundMax: .init(repeating: 0.0))
	
	mutating func growToInclude(_ point: SIMD3<Float>) {
		if (boundMin == Bounds.empty.boundMin && boundMax == Bounds.empty.boundMax) {
			boundMin = point
			boundMax = point
			return
		}
		if point.x < boundMin.x { boundMin.x = point.x }
		if point.y < boundMin.y { boundMin.y = point.y }
		if point.z < boundMin.z { boundMin.z = point.z }
		if point.x > boundMax.x { boundMax.x = point.x }
		if point.y > boundMax.y { boundMax.y = point.y }
		if point.z > boundMax.z { boundMax.z = point.z }
	}
}

struct MeshInfo: Equatable {
//	var name: String = ""
	var firstTriangleIndex: Int32 = Int32(0)
	var nbTriangles: Int32 = Int32(0)
	var boundMin: SIMD3<Float>
	var boundMax: SIMD3<Float>
	
	static func == (lhs: MeshInfo, rhs: MeshInfo) -> Bool {
		return lhs.firstTriangleIndex == rhs.firstTriangleIndex && lhs.nbTriangles == rhs.nbTriangles && lhs.boundMin == rhs.boundMin && lhs.boundMax == rhs.boundMax
	}
}


struct Node {
	var childIndex:    Int32
	var triangleIndex: Int32
	var nbTriangles:   Int32
	var depth:         Int32
	var bounds: Bounds
	
	var barycentre: SIMD3<Float> { return (bounds.boundMax + bounds.boundMin) / 2 }
}

//MARK: Split
func split(parent node: inout Node,
		   triangles: inout [Triangle],
		   nodes: inout [Node],
		   depth: Int,
		   maxDepth: Int)
{
	if depth >= maxDepth || node.nbTriangles <= 2 { return }
	
	let parentIndex = nodes.firstIndex { $0.triangleIndex == node.triangleIndex &&
		$0.nbTriangles  == node.nbTriangles &&
		$0.depth        == node.depth }!
	
	let start = Int(node.triangleIndex)
	let count = Int(node.nbTriangles)
	let end   = start + count
	
	let dx = node.bounds.boundMax.x - node.bounds.boundMin.x
	let dy = node.bounds.boundMax.y - node.bounds.boundMin.y
	let useX = dx >= dy
	let center = useX ? node.barycentre.x : node.barycentre.y
	
	var leftCount = 0
	for i in start..<end {
		let t = triangles[i]
		let goesLeft = useX ? (t.baricenter.x < center) : (t.baricenter.y < center)
		if goesLeft {
			triangles.swapAt(i, start + leftCount)
			leftCount += 1
		}
	}
	if leftCount == 0 || leftCount == count { return }
	
	let rightCount = count - leftCount
	
	var left = Node(childIndex:0,
					triangleIndex:Int32(start),
					nbTriangles: Int32(leftCount),
					depth: Int32(depth+1),
					bounds:.empty)
	
	var right = Node(childIndex:0,
					 triangleIndex:Int32(start+leftCount),
					 nbTriangles:Int32(rightCount),
					 depth:Int32(depth+1),
					 bounds:.empty)
	
	for i in start..<start+leftCount {
		let t = triangles[i]
		left.bounds.growToInclude(t.A); left.bounds.growToInclude(t.B); left.bounds.growToInclude(t.C)
	}
	for i in start+leftCount..<end {
		let t = triangles[i]
		right.bounds.growToInclude(t.A); right.bounds.growToInclude(t.B); right.bounds.growToInclude(t.C)
	}
	
	let leftIndex = nodes.count
	nodes.append(left); nodes.append(right)
	
	node.childIndex = Int32(leftIndex)
	nodes[parentIndex] = node   // ⬅︎ mise à jour réelle du parent
	
	split(parent:&left, triangles:&triangles, nodes:&nodes, depth:depth+1, maxDepth:maxDepth)
	split(parent:&right,triangles:&triangles,nodes:&nodes, depth:depth+1, maxDepth:maxDepth)
	
	nodes[leftIndex]   = left
	nodes[leftIndex+1] = right
}





struct SceneInfo {
	var spheres: [Sphere]
	var triangles: [Triangle]
	var meshes: [MeshInfo]
	var nodes: [Node]?
}



func pointInBounds(point p: SIMD3<Float>, bounds b: (min: SIMD3<Float>, max: SIMD3<Float>)) -> Bool {
	return p <= b.min && p >= b.max
}


func moveTriangles(triangles: [Triangle], move: SIMD3<Float>) -> [Triangle] {
	var newT: [Triangle] = []
	
	for t in triangles {
		newT.append(Triangle(A: t.A + move, B: t.B + move, C: t.C + move, n: t.n, material: t.material))
	}
	
	return newT
}

func getBarycentre(triangle t: Triangle) -> SIMD3<Float> {
	return (t.A + t.B + t.C) / 3
}

func getBarycentre(_ triangles: [Triangle]) -> SIMD3<Float> {
	var c = SIMD3<Float>(repeating: 0)
	
	for t in triangles {
		c += t.A + t.B + t.C
	}
	
	return c / (Float(triangles.count) * 3)
}

func getBarycentre(scene: SceneInfo, mesh index: Int) -> SIMD3<Float> {
	let mesh = scene.meshes[index]
	let start = Int(mesh.firstTriangleIndex)
	let end = start + Int(mesh.nbTriangles)
	let range = start..<end
	return getBarycentre(Array(scene.triangles[range]))
}

// MARK: Scale
func scaleTriangles(triangles: [Triangle], scale: Float) -> [Triangle] {
	return scaleTriangles(triangles: triangles, scale: scale, centre: getBarycentre(triangles))
}

func scaleTriangles(triangles: [Triangle], scale: Float, centre: SIMD3<Float>) -> [Triangle] {
	var newT: [Triangle] = []
	
	for t in triangles {
		let A = (t.A - centre) * scale + centre
		let B = (t.B - centre) * scale + centre
		let C = (t.C - centre) * scale + centre
		newT.append(Triangle(A: A, B: B, C: C, n: t.n, material: t.material))
	}
	
	return newT
}

func scaleMesh(scene: SceneInfo, mesh: MeshInfo, scale: Float) -> SceneInfo {
	print("start scale ---------------------------")
    let start = Int(mesh.firstTriangleIndex)
    let end = start + Int(mesh.nbTriangles)
	
	var nTriangles = Array(scene.triangles[start..<end])

	let center = getBarycentre(nTriangles)
	print(center)
	print(nTriangles.count)
	nTriangles = scaleTriangles(triangles: nTriangles, scale: scale, centre: center)
	print(nTriangles)
	let bounds = getBounds(triangles: nTriangles)
	var updatedMesh = mesh
	updatedMesh.boundMin = bounds.min
	updatedMesh.boundMax = bounds.max
	
	var newScene = scene
	newScene.triangles.replaceSubrange(start..<end, with: nTriangles)
	newScene.meshes[scene.meshes.firstIndex(where: { $0.self == mesh })!] = updatedMesh
	
	return newScene
}

func scaleTrianglesInPlace(_ triangles: inout [Triangle], range: Range<Int>, scale: Float, centre: SIMD3<Float>) {
	for i in range {
		let t = triangles[i]
		triangles[i] = Triangle(
			A: (t.A - centre) * scale + centre,
			B: (t.B - centre) * scale + centre,
			C: (t.C - centre) * scale + centre,
			n: t.n,
			material: t.material
		)
	}
}

func scaleMeshInPlace(scene: inout SceneInfo, meshIndex: Int, scale: Float) {
	var mesh = scene.meshes[meshIndex]
	let start = Int(mesh.firstTriangleIndex)
	let end = start + Int(mesh.nbTriangles)
	let triRange = start..<end
	
	let center = getBarycentre(Array(scene.triangles[triRange]))
	print(center)
	scaleTrianglesInPlace(&scene.triangles, range: triRange, scale: scale, centre: center)
	
	let bounds = getBounds(triangles: Array(scene.triangles[triRange]))
	mesh.boundMin = bounds.min
	mesh.boundMax = bounds.max
	scene.meshes[meshIndex] = mesh
}

// MARK: Rotate
func rotatePoint(_ point: SIMD3<Float>, around center: SIMD3<Float>, byX dx: Float, byY dy: Float, byZ dz: Float) -> SIMD3<Float> {
	let translated = point - center
	var P = simd_float3(translated)
	
	
	// Matrices de rotation
	var ct = cos(dx)
	var st = sin(dx)
	var Xa = simd_float3(x: 1, y: 0, z: 0)
	var Xb = simd_float3(x: 0, y: ct, z: -st)
	var Xc = simd_float3(x: 0, y: st, z: ct)
	var X = simd_float3x3(rows: [Xa, Xb, Xc])
	
	P = P * X
	
	ct = cos(dy)
	st = sin(dy)
	Xa = simd_float3(x: ct, y: 0, z: st)
	Xb = simd_float3(x: 0, y: 1, z: 0)
	Xc = simd_float3(x: -st, y: 0, z: ct)
	X = simd_float3x3(rows: [Xa, Xb, Xc])
	
	P = P * X
	
	ct = cos(dz)
	st = sin(dz)
	Xa = simd_float3(x: ct, y: -st, z: 0)
	Xb = simd_float3(x: st, y: ct, z: 0)
	Xc = simd_float3(x: 0, y: 0, z: 1)
	X = simd_float3x3(rows: [Xa, Xb, Xc])
	
	P = P * X
	
	return SIMD3<Float>(P) + center
	
}

func rotateTrianglesInPlace(
	_ triangles: inout [Triangle],
	around center: SIMD3<Float>,
	range: Range<Int>,
	byX dx: Float,
	byY dy: Float,
	byZ dz: Float
) {
	for i in range {
		triangles[i].A = rotatePoint(triangles[i].A, around: center, byX: dx, byY: dy, byZ: dz)
		triangles[i].B = rotatePoint(triangles[i].B, around: center, byX: dx, byY: dy, byZ: dz)
		triangles[i].C = rotatePoint(triangles[i].C, around: center, byX: dx, byY: dy, byZ: dz)
		triangles[i].n = rotatePoint(triangles[i].n, around: center, byX: dx, byY: dy, byZ: dz)
	}
}

func rotateMeshInPlace(scene: inout SceneInfo, meshIndex: Int, around center: SIMD3<Float>, byX dx: Float, byY dy: Float, byZ dz: Float) {
	print("rotating...")
	var mesh = scene.meshes[meshIndex]
	let start = Int(mesh.firstTriangleIndex)
	let end = start + Int(mesh.nbTriangles)
	let triRange = start..<end
	
	rotateTrianglesInPlace(&scene.triangles, around: center, range: triRange, byX: dx, byY: dy, byZ: dz)
	
	let bounds = getBounds(triangles: Array(scene.triangles[triRange]))
	mesh.boundMin = bounds.min
	mesh.boundMax = bounds.max
	scene.meshes[meshIndex] = mesh
	print("end")
}

func rotateMeshInPlace(scene: inout SceneInfo, meshIndex: Int, byX dx: Float, byY dy: Float, byZ dz: Float)
{
	var mesh = scene.meshes[meshIndex]
	let start = Int(mesh.firstTriangleIndex)
	let end = start + Int(mesh.nbTriangles)
	let triRange = start..<end
	
	let center = getBarycentre(Array(scene.triangles[triRange]))
	
	rotateMeshInPlace(scene: &scene, meshIndex: meshIndex, around: center, byX: dx, byY: dy, byZ: dz)
}

//MARK: Get bounds
func getBounds(triangle t: Triangle) -> (min: SIMD3<Float>, max: SIMD3<Float>) {
	var minv = SIMD3<Float>(repeating: Float.greatestFiniteMagnitude)
	var maxv = SIMD3<Float>(repeating: -Float.greatestFiniteMagnitude)
	
	minv = simd_min(minv, t.A)
	minv = simd_min(minv, t.B)
	minv = simd_min(minv, t.C)
	
	maxv = simd_max(maxv, t.A)
	maxv = simd_max(maxv, t.B)
	maxv = simd_max(maxv, t.C)
	
	return (minv, maxv)
}

func getBounds(_ triangles: [Triangle]) -> (min: SIMD3<Float>, max: SIMD3<Float>) {
	return getBounds(triangles: triangles)
}

func getBounds(triangles: [Triangle]) -> (min: SIMD3<Float>, max: SIMD3<Float>) {
	guard !triangles.isEmpty else {
		return (SIMD3<Float>(0, 0, 0), SIMD3<Float>(0, 0, 0))
	}
	
	var minv = SIMD3<Float>(repeating: Float.greatestFiniteMagnitude)
	var maxv = SIMD3<Float>(repeating: -Float.greatestFiniteMagnitude)
	
	for t in triangles {
		minv = simd_min(minv, t.A)
		minv = simd_min(minv, t.B)
		minv = simd_min(minv, t.C)
		
		maxv = simd_max(maxv, t.A)
		maxv = simd_max(maxv, t.B)
		maxv = simd_max(maxv, t.C)
	}
	
	return (minv, maxv)
}

//func expandBounds(point p: SIMD3<Float>, bounds b: (min: SIMD3<Float>, max: SIMD3<Float>)) -> (min: SIMD3<Float>, max: SIMD3<Float>) {
//	
//}


//MARK: loadMaterial
func loadMaterial(named name: String) throws -> [String: Material] {
	guard let url = Bundle.main.url(forResource: name, withExtension: "mtl"),
		  let content = try? String(contentsOf: url) else {
		throw MaterialLoadingError.fileNotFound
	}
	
	var materials: [String: Material] = [:]
	var currentName: String? = nil
	var currentMaterial: Material = .white
	
	for (lineIndex, line) in content.components(separatedBy: .newlines).enumerated() {
		let trimmedLine = line.trimmingCharacters(in: .whitespaces)
		if trimmedLine.isEmpty || trimmedLine.hasPrefix("#") { continue }
		
		let tokens = trimmedLine.split(separator: " ", omittingEmptySubsequences: true)
		guard let prefix = tokens.first else { continue }
		
		switch prefix {
		case "newmtl":
			if let currentName = currentName {
				materials[currentName] = currentMaterial
			}
			currentName = String(tokens.dropFirst().joined(separator: " "))
			currentMaterial = .white
			
		case "Kd": // Couleur
			let color = SIMD3<Float>(Float(tokens[1])!, Float(tokens[2])!, Float(tokens[3])!)
			currentMaterial.color = color
		
		case "Ke": // Lumière
			let color = SIMD3<Float>(Float(tokens[1])!, Float(tokens[2])!, Float(tokens[3])!)
			currentMaterial.emitingColor = color
			currentMaterial.emitingStrength = color == SIMD3<Float>(0, 0, 0) ? 0 : 1.0
			if color == SIMD3<Float>(0, 0, 0) {
				currentMaterial.color = .black
			}
		
		case "KeStrength":
			let value = Float(tokens[1])!
			currentMaterial.emitingStrength = value
		
		case "Ns": // Rugosité
			let nsValue = Double(tokens[1])! / 1000.0
//			currentMaterial.smoothness = 1.0 - Float(clamp(nsValue, 0.0, 1.0))
		
		case "Pm": // Métalitée
			let value = Float(tokens[1])!
			currentMaterial.smoothness = value
		
		case "Ni": // Indice optique
			currentMaterial.indice = Float(tokens[1])!
		
		case "illum":
			if Int(tokens[1])! == 9 {
				currentMaterial.isTransparent = true
			}
			
		default:
			break
		}
	}
	
	if let currentName = currentName {
		materials[currentName] = currentMaterial
	}
	
	return materials
}

// MARK: loadMesh
func loadMesh(named name: String) -> SceneInfo {
	print(name)
	var material: [String: Material] = [:]
	do {
		material = try loadMaterial(named: name)
	} catch {
		print("There is no .mtl file associated to this .obj")
	}
	
	return loadMesh(named: name, move: SIMD3<Float>(0, 0, 0), materials: material)
}

func loadMesh(named name: String, materials: [String: Material]) -> SceneInfo {
	return loadMesh(named: name, move: SIMD3<Float>(0, 0, 0), materials: materials)
}

func loadMesh(named name: String, move: SIMD3<Float>, materials: [String: Material]) -> SceneInfo {
	guard let url = Bundle.main.url(forResource: name, withExtension: "obj"),
		  let content = try? String(contentsOf: url) else {
		fatalError("Could not load OBJ file: \(name)")
	}
	
	var vertices: [SIMD3<Float>] = []
	var normals: [SIMD3<Float>] = []
	var triangles: [Triangle] = []
	var meshes: [MeshInfo] = []
	
	var currentMaterial: Material = .white
	var currentMesh = MeshInfo(firstTriangleIndex: 0, nbTriangles: 0, boundMin: .zero, boundMax: .zero)
	var nextFirstIndex = 0
	
	for (lineIndex, line) in content.components(separatedBy: .newlines).enumerated() {
		let trimmedLine = line.trimmingCharacters(in: .whitespaces)
		if trimmedLine.isEmpty || trimmedLine.hasPrefix("#") { continue }
		
		let tokens = trimmedLine.split(separator: " ", omittingEmptySubsequences: true)
		guard let prefix = tokens.first else { continue }
		
		switch prefix {
		case "v": // Point
			guard tokens.count >= 4,
				  let x = Float(tokens[1]),
				  let y = Float(tokens[2]),
				  let z = Float(tokens[3]) else {
				print("Skipping malformed vertex at line \(lineIndex + 1)")
				continue
			}
			vertices.append(SIMD3(x, y, z))
			
		case "vn": // Normale
			guard tokens.count >= 4,
				  let x = Float(tokens[1]),
				  let y = Float(tokens[2]),
				  let z = Float(tokens[3]) else {
				print("Skipping malformed normal at line \(lineIndex + 1)")
				continue
			}
			normals.append(normalize(SIMD3(x, y, z)))
			
		case "f": // Face
			guard tokens.count >= 4 else {
				print("Skipping malformed face at line \(lineIndex + 1)")
				continue
			}
			
			var faceVertices: [SIMD3<Float>] = []
			var faceNormales: [SIMD3<Float>] = []
			for i in 1..<tokens.count {
				let parts = tokens[i].split(separator: "/", omittingEmptySubsequences: false)
				guard let vertexIndex = Int(parts[0]), vertexIndex > 0, vertexIndex <= vertices.count else {
					print("Skipping malformed face index at line \(lineIndex + 1)")
					continue
				}
				let position = vertices[vertexIndex - 1]
				faceVertices.append(position)
				if parts.count == 3, let normalIndex = Int(parts[2]) {
					faceNormales.append(normals[normalIndex - 1])
				}
			}
			
			// Triangulation fan
			for i in 2..<faceVertices.count {
				let v0 = faceVertices[0]
				let v1 = faceVertices[i - 1]
				let v2 = faceVertices[i]
				let normal: SIMD3<Float>
				if faceNormales.count > 0 {
					var normalSum: SIMD3<Float> = .zero
					for n in faceNormales {
						normalSum += n
					}
					normal = normalize(normalSum)
				} else {
					normal = normalize(cross(v1 - v0, v2 - v0))
				}
				
				let triangle = Triangle(
					A: v0,
					B: v1,
					C: v2,
					n: normal,
					material: currentMaterial
				)
				triangles.append(triangle)
				currentMesh.nbTriangles += 1
			}
			
		case "o": // Objet
			if currentMesh.nbTriangles > 0 {
				let start = Int(currentMesh.firstTriangleIndex)
				let end = start + Int(currentMesh.nbTriangles)
				let bounds = getBounds(triangles: Array(triangles[start..<end]))
				currentMesh.boundMin = bounds.min + move
				currentMesh.boundMax = bounds.max + move
				meshes.append(currentMesh)
				
				nextFirstIndex = end
				currentMesh = MeshInfo(
					firstTriangleIndex: Int32(nextFirstIndex),
					nbTriangles: 0,
					boundMin: .zero,
					boundMax: .zero
				)
			}
		
		case "usemtl":
			currentMaterial = materials[String(tokens[1])] ?? .white
			
		default:
			continue
		}
	}
	
	// Add last mesh if necessary
	if currentMesh.nbTriangles > 0 {
		let start = Int(currentMesh.firstTriangleIndex)
		let end = start + Int(currentMesh.nbTriangles)
		let bounds = getBounds(triangles: Array(triangles[start..<end]))
		currentMesh.boundMin = bounds.min + move
		currentMesh.boundMax = bounds.max + move
		meshes.append(currentMesh)
	}
	
	return SceneInfo(spheres: [], triangles: moveTriangles(triangles: triangles, move: move), meshes: meshes)
}


// MARK: Scenes
func combineScenes(scene1: SceneInfo, scene2: SceneInfo) -> SceneInfo {
	var scene = scene1
	let offset = Int32(scene.triangles.count)
	
	scene.spheres += scene2.spheres
	scene.triangles += scene2.triangles
	
	for mesh in scene2.meshes {
		scene.meshes.append(MeshInfo(
			firstTriangleIndex: offset + mesh.firstTriangleIndex,
			nbTriangles: mesh.nbTriangles,
			boundMin: mesh.boundMin,
			boundMax: mesh.boundMax
		))
	}
	
	return scene
}

// MARK: Salle mirroirs
func loadTrianglesSalleMirroirs() -> [Triangle] {
	return [
		// MUR DROIT (ROUGE)
		Triangle(A: SIMD3<Float>(5,0,-5), B: SIMD3<Float>(5,10,-5), C: SIMD3<Float>(5,10,5), n: SIMD3<Float>(-1,0,0), material: .coloredMirror(color: .red)),
		Triangle(A: SIMD3<Float>(5,10,5), B: SIMD3<Float>(5,0,-5), C: SIMD3<Float>(5,0,5), n: SIMD3<Float>(-1,0,0), material: .coloredMirror(color: .red)),
		// MUR GAUCHE (BLUE)
		Triangle(A: SIMD3<Float>(-5,0,-5), B: SIMD3<Float>(-5,10,-5), C: SIMD3<Float>(-5,10,5), n: SIMD3<Float>(1,0,0), material: .coloredMirror(color: .blue)),
		Triangle(A: SIMD3<Float>(-5,10,5), B: SIMD3<Float>(-5,0,-5), C: SIMD3<Float>(-5,0,5), n: SIMD3<Float>(1,0,0), material: .coloredMirror(color: .blue)),
		// MUR DU FONC (BLANC)
		Triangle(A: SIMD3<Float>(-5,0,-5), B: SIMD3<Float>(-5,10,-5), C: SIMD3<Float>(5,0,-5), n: SIMD3<Float>(0,0,1), material: .mirror),
		Triangle(A: SIMD3<Float>(5,10,-5), B: SIMD3<Float>(-5,10,-5), C: SIMD3<Float>(5,0,-5), n: SIMD3<Float>(0,0,1), material: .mirror),
		// MUR DE DEVANT (BLANC)
		Triangle(A: SIMD3<Float>(-5,0,5), B: SIMD3<Float>(-5,10,5), C: SIMD3<Float>(5,0,5), n: SIMD3<Float>(0,0,-1), material: .mirror),
		Triangle(A: SIMD3<Float>(5,10,5), B: SIMD3<Float>(-5,10,5), C: SIMD3<Float>(5,0,5), n: SIMD3<Float>(0,0,-1), material: .mirror),
		// SOL (GRIS)
		Triangle(A: SIMD3<Float>(-5,0,-5), B: SIMD3<Float>(5,0,-5), C: SIMD3<Float>(5,0,5), n: SIMD3<Float>(0,1,0), material: .white),
		Triangle(A: SIMD3<Float>(-5,0,-5), B: SIMD3<Float>(-5,0,5), C: SIMD3<Float>(5,0,5), n: SIMD3<Float>(0,1,0), material: .white),
		// PLAFOND (GRIS)
		Triangle(A: SIMD3<Float>(-5,10,-5), B: SIMD3<Float>(5,10,-5), C: SIMD3<Float>(5,10,5), n: SIMD3<Float>(0,-1,0), material: .gray),
		Triangle(A: SIMD3<Float>(-5,10,-5), B: SIMD3<Float>(-5,10,5), C: SIMD3<Float>(5,10,5), n: SIMD3<Float>(0,-1,0), material: .gray),
		// LUMIÈRE
		Triangle(A: SIMD3<Float>(-3,9.9,-3), B: SIMD3<Float>(3,9.9,-3), C: SIMD3<Float>(3,9.9,3), n: SIMD3<Float>(0,-1,0), material: .light),
		Triangle(A: SIMD3<Float>(-3,9.9,-3), B: SIMD3<Float>(-3,9.9,3), C: SIMD3<Float>(3,9.9,3), n: SIMD3<Float>(0,-1,0), material: .light),
	]
}

func loadSpheresSalleMirroirs() -> [Sphere] {
	return [
		Sphere(center: [0, 5, -3], radius: 1.0, material: .tintedGlass(color: .red)),
//		Sphere(center: [2, 6, -4], radius: 0.8, material: .green),
		Sphere(center: [-2, 6, -4], radius: 1.0, material: .red),
		Sphere(center: [2, 6, -4], radius: 0.8, material: .whiteGlass)
		
	]
}

func loadSalleMirroirs() -> SceneInfo {
	var triangles = loadTrianglesSalleMirroirs()
	var spheres = loadSpheresSalleMirroirs()
	var meshes: [MeshInfo] = []
	
	for i in stride(from: 0, to: triangles.count, by: 2) {
		let bounds = getBounds(triangles: Array(triangles[i...(i+1)]))
		meshes.append(MeshInfo(
			firstTriangleIndex: Int32(i),
			nbTriangles: Int32(2),
			boundMin: bounds.min,
			boundMax: bounds.max
		))
	}
	
	return SceneInfo(spheres: spheres, triangles: triangles, meshes: meshes)
}

// MARK: Salle boules miroir
func loadTrianglesSalleBoulesMiroirs() -> [Triangle] {
	return [
		// MUR DROIT (ROUGE)
		Triangle(A: SIMD3<Float>(5,0,-5), B: SIMD3<Float>(5,10,-5), C: SIMD3<Float>(5,10,5), n: SIMD3<Float>(-1,0,0), material: .red),
		Triangle(A: SIMD3<Float>(5,10,5), B: SIMD3<Float>(5,0,-5), C: SIMD3<Float>(5,0,5), n: SIMD3<Float>(-1,0,0), material: .red),
		// MUR GAUCHE (BLUE)
		Triangle(A: SIMD3<Float>(-5,0,-5), B: SIMD3<Float>(-5,10,-5), C: SIMD3<Float>(-5,10,5), n: SIMD3<Float>(1,0,0), material: .blue),
		Triangle(A: SIMD3<Float>(-5,10,5), B: SIMD3<Float>(-5,0,-5), C: SIMD3<Float>(-5,0,5), n: SIMD3<Float>(1,0,0), material: .blue),
		// MUR DU FONC (BLANC)
		Triangle(A: SIMD3<Float>(-5,0,-5), B: SIMD3<Float>(-5,10,-5), C: SIMD3<Float>(5,0,-5), n: SIMD3<Float>(0,0,1), material: .white),
		Triangle(A: SIMD3<Float>(5,10,-5), B: SIMD3<Float>(-5,10,-5), C: SIMD3<Float>(5,0,-5), n: SIMD3<Float>(0,0,1), material: .white),
		// MUR DE DEVANT (BLANC)
		//		Triangle(A: SIMD3<Float>(-5,0,5), B: SIMD3<Float>(-5,10,5), C: SIMD3<Float>(5,0,5), n: SIMD3<Float>(0,0,-1), material: .mirror),
		//		Triangle(A: SIMD3<Float>(5,10,5), B: SIMD3<Float>(-5,10,5), C: SIMD3<Float>(5,0,5), n: SIMD3<Float>(0,0,-1), material: .mirror),
		// SOL (GRIS)
		Triangle(A: SIMD3<Float>(-5,0,-5), B: SIMD3<Float>(5,0,-5), C: SIMD3<Float>(5,0,5), n: SIMD3<Float>(0,1,0), material: .gray),
		Triangle(A: SIMD3<Float>(-5,0,-5), B: SIMD3<Float>(-5,0,5), C: SIMD3<Float>(5,0,5), n: SIMD3<Float>(0,1,0), material: .gray),
		// PLAFOND (GRIS)
		Triangle(A: SIMD3<Float>(-5,10,-5), B: SIMD3<Float>(5,10,-5), C: SIMD3<Float>(5,10,5), n: SIMD3<Float>(0,-1,0), material: .gray),
		Triangle(A: SIMD3<Float>(-5,10,-5), B: SIMD3<Float>(-5,10,5), C: SIMD3<Float>(5,10,5), n: SIMD3<Float>(0,-1,0), material: .gray),
		// LUMIÈRE
		Triangle(A: SIMD3<Float>(-2,9.9,-3), B: SIMD3<Float>(2,9.9,-3), C: SIMD3<Float>(2,9.9,3), n: SIMD3<Float>(0,-1,0), material: .light),
		Triangle(A: SIMD3<Float>(-2,9.9,-3), B: SIMD3<Float>(-2,9.9,3), C: SIMD3<Float>(2,9.9,3), n: SIMD3<Float>(0,-1,0), material: .light),
	]
}

func loadSpheresSalleBoulesMiroir() -> [Sphere] {
	return [
//		Sphere(center: [-10/6 * 3, 5, -3], radius: 0.5, material: .whiteReflective(smooth: 0)),
//		Sphere(center: [-10/6 * 2, 5, -3], radius: 0.5, material: .whiteReflective(smooth: 0.2)),
//		Sphere(center: [-10/6, 5, -3], radius: 0.5, material: .whiteReflective(smooth: 0.4)),
//		Sphere(center: [10/6, 5, -3], radius: 0.5, material: .whiteReflective(smooth: 0.6)),
//		Sphere(center: [10/6 * 2, 5, -3], radius: 0.5, material: .whiteReflective(smooth: 0.8)),
//		Sphere(center: [10/6 * 3, 5, -3], radius: 0.5, material: .whiteReflective(smooth: 1)),
		
//		Sphere(center: [0, 5, -3], radius: 1.0, material: .tintedGlass(color: .red)),
		Sphere(center: [-2, 6, -4], radius: 1.0, material: .mirror),
		Sphere(center: [2, 6, -4], radius: 0.8, material: .whiteGlass)
	]
}

func loadSalleBoules() -> SceneInfo {
	var triangles = loadTrianglesSalleBoulesMiroirs()
	var spheres = loadSpheresSalleBoulesMiroir()
	var meshes: [MeshInfo] = []
	
	for i in stride(from: 0, to: triangles.count, by: 2) {
		let bounds = getBounds(triangles: Array(triangles[i...(i+1)]))
		meshes.append(MeshInfo(
			firstTriangleIndex: Int32(i),
			nbTriangles: Int32(2),
			boundMin: bounds.min,
			boundMax: bounds.max
		))
	}
	
	return SceneInfo(spheres: spheres, triangles: triangles, meshes: meshes)
}

// MARK: Salle exposition
func loadTrianglesSalleExposition() -> [Triangle] {
	return [
		// MUR DROIT (ROUGE)
		Triangle(A: SIMD3<Float>(5,0,-5), B: SIMD3<Float>(5,10,-5), C: SIMD3<Float>(5,10,5), n: SIMD3<Float>(-1,0,0), material: .red),
		Triangle(A: SIMD3<Float>(5,10,5), B: SIMD3<Float>(5,0,-5), C: SIMD3<Float>(5,0,5), n: SIMD3<Float>(-1,0,0), material: .red),
		// MUR GAUCHE (BLUE)
		Triangle(A: SIMD3<Float>(-5,0,-5), B: SIMD3<Float>(-5,10,-5), C: SIMD3<Float>(-5,10,5), n: SIMD3<Float>(1,0,0), material: .blue),
		Triangle(A: SIMD3<Float>(-5,10,5), B: SIMD3<Float>(-5,0,-5), C: SIMD3<Float>(-5,0,5), n: SIMD3<Float>(1,0,0), material: .blue),
		// MUR DU FONC (BLANC)
		Triangle(A: SIMD3<Float>(-5,0,-5), B: SIMD3<Float>(-5,10,-5), C: SIMD3<Float>(5,0,-5), n: SIMD3<Float>(0,0,1), material: .white),
		Triangle(A: SIMD3<Float>(5,10,-5), B: SIMD3<Float>(-5,10,-5), C: SIMD3<Float>(5,0,-5), n: SIMD3<Float>(0,0,1), material: .white),
		// MUR DE DEVANT (BLANC)
		//		Triangle(A: SIMD3<Float>(-5,0,5), B: SIMD3<Float>(-5,10,5), C: SIMD3<Float>(5,0,5), n: SIMD3<Float>(0,0,-1), material: .mirror),
		//		Triangle(A: SIMD3<Float>(5,10,5), B: SIMD3<Float>(-5,10,5), C: SIMD3<Float>(5,0,5), n: SIMD3<Float>(0,0,-1), material: .mirror),
		// SOL (GRIS)
		Triangle(A: SIMD3<Float>(-5,0,-5), B: SIMD3<Float>(5,0,-5), C: SIMD3<Float>(5,0,5), n: SIMD3<Float>(0,1,0), material: .gray),
		Triangle(A: SIMD3<Float>(-5,0,-5), B: SIMD3<Float>(-5,0,5), C: SIMD3<Float>(5,0,5), n: SIMD3<Float>(0,1,0), material: .gray),
		// PLAFOND (GRIS)
		Triangle(A: SIMD3<Float>(-5,10,-5), B: SIMD3<Float>(5,10,-5), C: SIMD3<Float>(5,10,5), n: SIMD3<Float>(0,-1,0), material: .gray),
		Triangle(A: SIMD3<Float>(-5,10,-5), B: SIMD3<Float>(-5,10,5), C: SIMD3<Float>(5,10,5), n: SIMD3<Float>(0,-1,0), material: .gray),
		// LUMIÈRE (MUR DROIT)
//		Triangle(A: SIMD3<Float>(4.9,2.5,-2.5), B: SIMD3<Float>(4.9,7.5,-2.5), C: SIMD3<Float>(4.9,7.5,2.5), n: SIMD3<Float>(1,0,0), material: .light),
//		Triangle(A: SIMD3<Float>(4.9,7.5,2.5), B: SIMD3<Float>(4.9,2.5,-2.5), C: SIMD3<Float>(4.9,2.5,2.5), n: SIMD3<Float>(1,0,0), material: .light),
	]
}

func loadSpheresSalleExposition() -> [Sphere] {
	return [
		Sphere(center: [-10/6 * 3, 5, -3], radius: 0.5, material: .whiteReflective(smooth: 0)),
		Sphere(center: [-10/6 * 2, 5, -3], radius: 0.5, material: .whiteReflective(smooth: 0.2)),
		Sphere(center: [-10/6, 5, -3], radius: 0.5, material: .whiteReflective(smooth: 0.4)),
		Sphere(center: [10/6, 5, -3], radius: 0.5, material: .whiteReflective(smooth: 0.6)),
		Sphere(center: [10/6 * 2, 5, -3], radius: 0.5, material: .whiteReflective(smooth: 0.8)),
		Sphere(center: [10/6 * 3, 5, -3], radius: 0.5, material: .whiteReflective(smooth: 1)),
	]
}

func loadSalleExposition() -> SceneInfo {
	var triangles = loadTrianglesSalleExposition()
	var spheres: [Sphere] = []
	var meshes: [MeshInfo] = []
	
	for i in stride(from: 0, to: triangles.count, by: 2) {
		let bounds = getBounds(triangles: Array(triangles[i...(i+1)]))
		meshes.append(MeshInfo(
			firstTriangleIndex: Int32(i),
			nbTriangles: Int32(2),
			boundMin: bounds.min,
			boundMax: bounds.max
		))
	}
	
	return SceneInfo(spheres: spheres, triangles: triangles, meshes: meshes)
}


// MARK: Plan 200 boules
func loadTrianglesPlan200Boules() -> [Triangle] {
	return [
		Triangle(A: SIMD3<Float>(-50,0,-50), B: SIMD3<Float>(50,0,-50), C: SIMD3<Float>(50,0,50), n: SIMD3<Float>(0,1,0), material: .gray),
		Triangle(A: SIMD3<Float>(-50,0,-50), B: SIMD3<Float>(-50,0,50), C: SIMD3<Float>(50,0,50), n: SIMD3<Float>(0,1,0), material: .gray),
	]
}

func loadSpheresPlan200Boules() -> [Sphere] {
	return [
		// Soleil
		Sphere(center: SIMD3<Float>(0, 2000, 0), radius: 1000.0, material: .light),
		
		// 3 grandes sphères centrales
		Sphere(center: SIMD3<Float>(0, 1, 0), radius: 1.0, material: .whiteReflective(smooth: 1.0)),         // Miroir (au centre)
		Sphere(center: SIMD3<Float>(-4, 1, 0), radius: 1.0, material: .coloredMirror(color: SIMD3<Float>(0.8, 0.2, 0.1))),  // Métal brun
		Sphere(center: SIMD3<Float>(4, 1, 0), radius: 1.0, material: Material(color: SIMD3<Float>(0.4, 0.6, 0.9), emitingColor: .black, emitingStrength: 0, smoothness: 0.0)), // Diffus bleu clair
		
		// Petites sphères aléatoires
	] + (0..<200).compactMap { _ -> Sphere? in
		let a = Float.random(in: -11...11)
		let b = Float.random(in: -11...11)
		let center = SIMD3<Float>(a, 0.2, b)
		
		// On évite les sphères trop proches des grosses
		if simd_length(center - SIMD3<Float>(4, 0.2, 0)) < 1.0 || simd_length(center - SIMD3<Float>(0, 0.2, 0)) < 1.0 || simd_length(center - SIMD3<Float>(-4, 0.2, 0)) < 1.0 {
			return nil
		}
		
		let chooseMat = Float.random(in: 0...1)
		if chooseMat < 0.8 {
			// Diffuse
			let color = SIMD3<Float>(Float.random(in: 0.5...1.0), Float.random(in: 0.5...1.0), Float.random(in: 0.5...1.0))
			return Sphere(center: center, radius: 0.2, material: Material(color: color, emitingColor: .black, emitingStrength: 0, smoothness: 0))
		} else if chooseMat < 0.95 {
			// Métal
			let color = SIMD3<Float>(Float.random(in: 0.5...1.0), Float.random(in: 0.5...1.0), Float.random(in: 0.5...1.0))
			return Sphere(center: center, radius: 0.2, material: Material(color: color, emitingColor: .black, emitingStrength: 0, smoothness: 1.0))
		} else {
			// Transparent (on pourrait simuler du verre si ton moteur supporte)
			let color = SIMD3<Float>(1.0, 1.0, 1.0)
			return Sphere(center: center, radius: 0.2, material: Material(color: color, emitingColor: .black, emitingStrength: 0, smoothness: 1.0))
		}
	}
}

func loadScenePlan200Boules() -> SceneInfo {
    let triangles = loadTrianglesPlan200Boules()
    let spheres = loadSpheresPlan200Boules()
    var meshes: [MeshInfo] = []
    // Création d'un seul mesh contenant tous les triangles
    let bounds = getBounds(triangles: triangles)
    meshes.append(MeshInfo(
        firstTriangleIndex: 0,
        nbTriangles: Int32(triangles.count),
        boundMin: bounds.min,
        boundMax: bounds.max
    ))
    return SceneInfo(spheres: spheres, triangles: triangles, meshes: meshes)
}
