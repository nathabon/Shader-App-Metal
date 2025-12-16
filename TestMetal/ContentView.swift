//
//  ContentView.swift
//  TestMetal
//
//  Created by Nathanaël BONTOUX on 03/06/2025.
//

import SwiftUI
import MetalKit
import AppKit

struct BlenderNumberField: View {
	@Binding var value: Double
	var stepPerPixel: Double = 1.0
	var range: ClosedRange<Double> = -100...100
	var width: CGFloat = 80
	var format: FloatingPointFormatStyle<Double> = .number
	
	@State private var editing = false
	@FocusState private var focused: Bool
	@State private var lastX: CGFloat? = nil
	
	var body: some View {
		ZStack {
			if editing {
				// Vrai champ uniquement en mode édition
				TextField("", value: $value, format: format)
					.frame(width: width)
					.textFieldStyle(.roundedBorder)
					.focused($focused)
					.onAppear { DispatchQueue.main.async { focused = true } }
					.onSubmit { editing = false }
					.onChange(of: focused) { new in
						if !new { editing = false }
					}
			} else {
				// Faux champ : look de TextField mais pas de focus => parfait pour le drag
				RoundedRectangle(cornerRadius: 6, style: .continuous)
					.fill(Color(NSColor.textBackgroundColor))
					.overlay(
						RoundedRectangle(cornerRadius: 6, style: .continuous)
							.stroke(Color.secondary.opacity(0.35), lineWidth: 1)
					)
					.frame(width: width, height: 24)
					.overlay(
						Text(value, format: format)
							.frame(width: width - 8, alignment: .trailing)
							.monospacedDigit()
							.padding(.horizontal, 4)
					)
					.onHover { hovering in
						if hovering { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
					}
					.onTapGesture(count: 2) {
						editing = true
					}
					.gesture(
						DragGesture(minimumDistance: 0)
							.onChanged { g in
								if let lx = lastX {
									let dx = g.location.x - lx
									var mult = 1.0
									// Modificateurs à la Blender : ⇧ = x10, ⌥ = x0.1
									let flags = NSEvent.modifierFlags
									if flags.contains(.shift) { mult *= 10 }
									if flags.contains(.option) { mult *= 0.1 }
									let newVal = value + Double(dx) * stepPerPixel * mult
									value = newVal.clamped(to: range)
								}
								lastX = g.location.x
							}
							.onEnded { _ in lastX = nil }
					)
					
			}
		}
	}
}

// Extension pour clamp
extension Comparable {
	func clamped(to limits: ClosedRange<Self>) -> Self {
		min(max(self, limits.lowerBound), limits.upperBound)
	}
}


// MARK: - Vue principale ------------------------------------------------------

struct ContentView: View {
	
	// ──────────────── State / App model ────────────────
	@State private var renderer: Renderer? = nil           // moteur Metal
	@State private var showStats = false
	
	// ──────────────── Body ────────────────
	var body: some View {
//		ZStack(alignment: .leading) {
			NavigationSplitView {
				if let r = renderer {
					ControlPanel(renderer: r)
				}
			} detail: {
				ZStack {
					if let r = renderer {
						MetalView(renderer: r)
							.ignoresSafeArea()
					} else {
						Color.black.ignoresSafeArea()
					}
					
					if let r = renderer {
						HUD(renderer: r)
					}

				}
				
			}

		.task { await loadRenderer() }
	}
	
	// MARK: - Chargement asynchrone du Renderer
	@MainActor
	private func loadRenderer() async {
		guard renderer == nil else { return }

		
		// —— MTKView configurée « headless » ——
		let mtkView = MTKView()
		mtkView.device                = MTLCreateSystemDefaultDevice()
		mtkView.colorPixelFormat      = .bgra8Unorm
		mtkView.framebufferOnly       = false
		mtkView.isPaused              = false
		mtkView.enableSetNeedsDisplay = false
		
		renderer = Renderer(metalView: mtkView)
	}
}

struct HUD: View {
	@ObservedObject var renderer: Renderer
	var body: some View {
		VStack {
			HStack {
				Text("GPU Time: \(Int(renderer.gpuTime)) ms")
				Spacer()
			}
			
			HStack {
				Text("FPS: \(1000 / renderer.gpuTime)")
				Spacer()
			}
			
			HStack {
				Text("FPS: \(renderer.fps)")
				Spacer()
			}
			
			HStack {
				Text("Rotation: \(renderer.currentCameraRotation * 180.0 / Float.pi) °")
				Spacer()
			}
			
			Spacer()
		}
	}
}


// MARK: - Panneau de contrôle

struct ControlPanel: View {
	
	@ObservedObject var renderer: Renderer
	
	var body: some View {
		ScrollView {
			VStack(alignment: .leading, spacing: 16) {
				DisclosureGroup("Caméra") {
					VStack(alignment: .leading) {
						Text("Position")
							.font(.callout)
						HStack {
							Spacer()
							Text("X :")
							BlenderNumberField(
								value: Binding<Double>(
									get: { Double(renderer.cameraPosition.x) },
									set: { renderer.cameraPosition.x = Float($0) }
								), stepPerPixel: 0.05, range: -100...100, width: 90, format: .number.precision(.fractionLength(2))
							)
						}
						
						HStack {
							Spacer()
							Text("Y :")
							BlenderNumberField(
								value: Binding<Double>(
									get: { Double(renderer.cameraPosition.y) },
									set: { renderer.cameraPosition.y = Float($0) }
								), stepPerPixel: 0.05, range: -100...100, width: 90, format: .number.precision(.fractionLength(2))
							)
						}
						
						HStack {
							Spacer()
							Text("Z :")
							BlenderNumberField(
								value: Binding<Double>(
									get: { Double(renderer.cameraPosition.z) },
									set: { renderer.cameraPosition.z = Float($0) }
								), stepPerPixel: 0.05, range: -100...100, width: 90, format: .number.precision(.fractionLength(2))
							)
						}
						Button("Placer en (0, 4, 14)") {
							renderer.cameraPosition = SIMD3<Float>(0, 4, 14)
						}
						
						Text("Rotation")
						HStack {
							Spacer()
							Text("X :")
							BlenderNumberField(
								value: Binding<Double>(
									get: { Double(renderer.cameraRotation.x) * 180.0 / Double.pi },
									set: { renderer.cameraRotation.x = Float($0) * Float.pi / 180.0 }
								), stepPerPixel: 0.5, range: -180...180, width: 90, format: .number.precision(.fractionLength(1))
							)
						}
						
						HStack {
							Spacer()
							Text("Y :")
							BlenderNumberField(
								value: Binding<Double>(
									get: { Double(renderer.cameraRotation.y) * 180.0 / Double.pi },
									set: { renderer.cameraRotation.y = Float($0) * Float.pi / 180.0 }
								), stepPerPixel: 0.5, range: -180...180, width: 90, format: .number.precision(.fractionLength(1))
							)
						}
						
						HStack {
							Spacer()
							Toggle("Stats", isOn: $renderer.makeStat)
								.toggleStyle(.switch)
						}
						
						HStack {
							Spacer()
							Text("FOV :")
							BlenderNumberField(
								value: Binding<Double>(
									get: { Double(renderer.camera.fovy) },
									set: { renderer.camera.fovy = Float($0) }
								), stepPerPixel: 0.05, range: 0...180, width: 90
							)
						}
						
						HStack {
							Spacer()
							Text("Speed :")
							BlenderNumberField(
								value: Binding<Double>(
									get: { Double(renderer.cameraSpeed) },
									set: { renderer.cameraSpeed = Float($0) }
								), stepPerPixel: 0.005, range: 0...1, width: 90, format: .number.precision(.fractionLength(4))
							)
						}
						
					}
					
				}
				
				Divider()
				
				DisclosureGroup("Rendu 3D") {
					VStack(alignment: .leading) {
						HStack {
							Spacer()
							Text("Max bounce :")
							BlenderNumberField(
								value: Binding<Double>(
									get: { Double(renderer.maxBounce) },
									set: { renderer.maxBounce = Int(round($0)) }
								),
								stepPerPixel: 0.1,
								range: 1...50,
								width: 90,
								format: .number.rounded()
							)
						}
						HStack {
							Spacer()
							Text("Rays per pixel :")
							BlenderNumberField(
								value: Binding<Double>(
									get: { Double(renderer.raysPerPixel) },
									set: { renderer.raysPerPixel = Int(round($0)) }
								),
								stepPerPixel: 0.2,
								range: 1...200,
								width: 90,
								format: .number.rounded()
							)
						}
						HStack {
							Spacer()
							Text("Max bounce preview :")
							BlenderNumberField(
								value: Binding<Double>(
									get: { Double(renderer.maxBouncePreviews) },
									set: { renderer.maxBouncePreviews = Int(round($0)) }
								),
								stepPerPixel: 0.05,
								range: 1...10,
								width: 90,
								format: .number.rounded()
							)
						}
						HStack {
							Spacer()
							Text("Tile size :")
							BlenderNumberField(
								value: Binding<Double>(
									get: { Double(renderer.tileSize) },
									set: { renderer.tileSize = Int($0) }
								),
								stepPerPixel: 0.5,
								range: 1...1000,
								width: 90,
								format: .number.rounded()
							)
						}
						
						HStack {
							Spacer()
							Text("Nb passes :")
							BlenderNumberField(
								value: Binding<Double>(
									get: { Double(renderer.maxOfflinePasses) },
									set: { renderer.maxOfflinePasses = Int($0) }
								),
								stepPerPixel: 0.5,
								range: 1...1000,
								width: 90,
								format: .number.rounded()
							)
						}
					}
				}
				
				Divider()
				
				DisclosureGroup("Objets") {
					DisclosureGroup("Monkey") {}
					DisclosureGroup("Sphère 1") {}
				}
				
				Divider()
				
				DisclosureGroup("Statistiques") {
					HStack {
						Spacer()
						Text("Frames per tick :")
						BlenderNumberField(
							value: Binding<Double>(
								get: { Double(renderer.framesPerTick) },
								set: { renderer.framesPerTick = Int($0) }
							),
							stepPerPixel: 0.1,
							range: 1...1000,
							width: 90,
							format: .number.rounded()
						)
					}
					
					
					Toggle("Mode Benchmark (multi-CB)", isOn: $renderer.benchmarking)
						.toggleStyle(.switch)
					
					HStack {
						Text("FPS mesuré :")
						Spacer()
						Text(String(format: "%.1f", renderer.fps))
							.monospacedDigit()
					}
					
					HStack {
						Text("Cadence (ms/frame) :")
						Spacer()
						Text(String(format: "%.2f", renderer.gpuMsPerFrame))
							.monospacedDigit()
					}
					
					HStack {
						Text("GPU Work (ms) :")
						Spacer()
						Text(String(format: "%.2f", renderer.GPUTime))
							.monospacedDigit()
					}
				}
				
				Divider()
				
				Button("Render") {
					renderer.isRayTracing = true
					renderer.startOfflineRender()
					renderer.toggleAccumulation()
					renderer.isBetterRayTracing = true
					renderer.startOfflineRender()
				}
				
				Button("Toggle accumulation") { renderer.toggleAccumulation() }
				
				Toggle("Accumulation", isOn: Binding<Bool> (
					get: { renderer.isAccumulating },
					set: {
						if $0 { renderer.toggleAccumulation() }
						else { renderer.isAccumulating = false }
					}
				))
				.toggleStyle(.switch)
				
				Text("\(renderer.stats)")
				
				if renderer.isAccumulating {
					Button("Reset accumulation") { renderer.toggleAccumulation() }
				}
				
				Toggle("RayTracing", isOn: $renderer.isRayTracing)
					.toggleStyle(.switch)
				Toggle("Better RayTracing", isOn: $renderer.isBetterRayTracing)
					.toggleStyle(.switch)
					.disabled(!renderer.isRayTracing)
				
				Spacer()
			}
			.padding()
			.frame(maxWidth: .infinity, alignment: .topLeading)
		}
		.frame(minWidth: 280, maxWidth: 350)
		
		
		.onChange(of: renderer.isRayTracing) {
			if !renderer.isRayTracing { renderer.isBetterRayTracing = false }
		}
	}
}
