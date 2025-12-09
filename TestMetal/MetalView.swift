//
//  MetalView.swift
//  TestMetal
//
//  Created by Nathanaël BONTOUX on 03/06/2025.
//

import SwiftUI
import MetalKit

struct MetalView: NSViewRepresentable {
	@ObservedObject var renderer: Renderer
	
	func makeNSView(context: Context) -> MTKView {
		let mtkView = MetalHostingView()
		mtkView.device = MTLCreateSystemDefaultDevice()
		mtkView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
		mtkView.colorPixelFormat = .bgra8Unorm
		mtkView.framebufferOnly = false
		mtkView.preferredFramesPerSecond = 120
		mtkView.isPaused = false
		mtkView.enableSetNeedsDisplay = false
		
		mtkView.renderer = renderer
		mtkView.delegate = renderer
		
		return mtkView
	}
	
	func updateNSView(_ nsView: MTKView, context: Context) {}
}


class MetalHostingView: MTKView {
	override var acceptsFirstResponder: Bool { true }
	var renderer: Renderer?
	
	override func keyDown(with event: NSEvent) {
		switch event.charactersIgnoringModifiers {
		case "z": renderer?.keyZ = true
		case "s": renderer?.keyS = true
		case "q": renderer?.keyQ = true
		case "d": renderer?.keyD = true
		case "a": renderer?.keyA = true
		case "c": renderer?.keyC = true
//		case "r": renderer?.keyr = true
		default: break
		}
		
		switch event.keyCode {
		case 123: renderer?.keyL = true //gauche
		case 124: renderer?.keyR = true //droit
		case 125: renderer?.keyUp = true
		case 126: renderer?.keyDown = true
		default: break
		}
	}
	
	override func keyUp(with event: NSEvent) {
		switch event.charactersIgnoringModifiers {
		case "z": renderer?.keyZ = false
		case "s": renderer?.keyS = false
		case "q": renderer?.keyQ = false
		case "d": renderer?.keyD = false
		case "a": renderer?.keyA = false
		case "c": renderer?.keyC = false
//		case "r": renderer?.keyr = false
		default: break
			
		}
		
		switch event.keyCode {
		case 123: renderer?.keyL = false //gauche
		case 124: renderer?.keyR = false //droit
		case 125: renderer?.keyUp = false
		case 126: renderer?.keyDown = false
		default:
			break
		}
	}

}


