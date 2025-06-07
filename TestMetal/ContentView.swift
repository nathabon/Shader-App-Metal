//
//  ContentView.swift
//  TestMetal
//
//  Created by Nathanaël BONTOUX on 03/06/2025.
//

import SwiftUI
import MetalKit

struct ContentView: View {
	@StateObject var renderer: Renderer
	
	init() {
		// Création du MTKView bien configuré
		let metalView = MTKView()
		metalView.device = MTLCreateSystemDefaultDevice()
		metalView.colorPixelFormat = .bgra8Unorm
		metalView.framebufferOnly = false
		metalView.preferredFramesPerSecond = 0
		metalView.isPaused = false
		metalView.enableSetNeedsDisplay = false
		
		// Création du Renderer avec ce view déjà prêt
		let r = Renderer(metalView: metalView)
		_renderer = StateObject(wrappedValue: r)
	}
	
	var body: some View {
		ZStack(alignment: .topLeading) {
			MetalView(renderer: renderer)
				.ignoresSafeArea()
			
		}
	}
}



#Preview {
    ContentView()
}
