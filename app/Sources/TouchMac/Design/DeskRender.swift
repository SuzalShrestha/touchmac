import AppKit
import SceneKit
import simd

/// The MacBook on its desk, rendered in 3D (SceneKit, offscreen) once per appearance and cached.
/// The window shows this still picture with SwiftUI overlays at the projected zone positions,
/// so an idle window costs no GPU time. Light mode is an oak desk by day with a silver
/// MacBook; dark mode is a walnut desk under a warm lamp with a space black one.
enum DeskRender {
    static let pixelSize = CGSize(width: 2400, height: 1300)
    static var aspect: CGFloat { pixelSize.width / pixelSize.height }

    /// Zone spots on the desk, in scene units (1 unit = 10 cm), origin under the middle of the MacBook.
    static let spots: [String: SIMD3<Float>] = [
        "L2": [-2.45, 0, -0.75], "L1": [-2.45, 0, 0.65],
        "R2": [2.45, 0, -0.75], "R1": [2.45, 0, 0.65],
        "F1": [-0.72, 0, 1.8], "F2": [0.72, 0, 1.8],
    ]

    struct Output: @unchecked Sendable {
        let image: CGImage
        /// The same picture for SwiftUI: an NSImage also draws in offscreen captures.
        let nsImage: NSImage
        /// Normalised positions (0...1, origin top left) of each spot centre.
        let centers: [String: CGPoint]
        /// A circle of `ringRadius` around each spot, as the camera sees it.
        let rings: [String: [CGPoint]]
        /// One point per calibration tap, in a circle around each spot.
        let dots: [String: [CGPoint]]
    }

    static let ringRadius: Float = 0.42
    private static let rimOnly = 2
    static let dotCount = 10

    @MainActor private static var cache: [Bool: Output] = [:]

    @MainActor static func output(dark: Bool) async -> Output? {
        if let hit = cache[dark] { return hit }
        let out = await Task.detached(priority: .userInitiated) { render(dark: dark) }.value
        cache[dark] = out
        return out
    }

    @MainActor static func cached(dark: Bool) -> Output? { cache[dark] }

    @MainActor static func prime(_ out: Output, dark: Bool) { cache[dark] = out }

    static func render(dark: Bool, size: CGSize = pixelSize) -> Output? {
        let (scene, camera) = buildScene(dark: dark)
        let renderer = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)
        renderer.scene = scene
        renderer.pointOfView = camera
        renderer.autoenablesDefaultLighting = false
        let snapshot = renderer.snapshot(atTime: 0, with: size, antialiasingMode: .multisampling4X)
        guard let image = snapshot.cgImage(forProposedRect: nil, context: nil, hints: nil),
            let cam = camera.camera
        else { return nil }

        let viewProj = simd_float4x4(cam.projectionTransform(withViewportSize: size)) * camera.simdWorldTransform.inverse
        func project(_ p: SIMD3<Float>) -> CGPoint {
            let c = viewProj * SIMD4(p, 1)
            return CGPoint(x: CGFloat((c.x / c.w + 1) / 2), y: CGFloat((1 - c.y / c.w) / 2))
        }
        func circle(_ center: SIMD3<Float>, radius: Float, count: Int, phase: Float = 0) -> [CGPoint] {
            (0..<count).map { i in
                let a = phase + Float(i) / Float(count) * 2 * .pi
                return project(center + SIMD3(radius * sin(a), 0, -radius * cos(a)))
            }
        }
        return Output(
            image: image,
            nsImage: NSImage(cgImage: image, size: size),
            centers: spots.mapValues(project),
            rings: spots.mapValues { circle($0, radius: ringRadius, count: 64) },
            dots: spots.mapValues { circle($0, radius: 0.62, count: dotCount) })
    }

    // MARK: - Scene

    private static func buildScene(dark: Bool) -> (SCNScene, SCNNode) {
        let scene = SCNScene()
        scene.background.contents = NSColor(hex: dark ? 0x141517 : 0xD9DCDF)
        scene.lightingEnvironment.contents = Texture.environment(dark: dark)
        scene.lightingEnvironment.intensity = dark ? 0.9 : 1.1
        let root = scene.rootNode

        // desk top, slightly lacquered
        let deskBox = SCNBox(width: 26, height: 0.5, length: 30, chamferRadius: 0)
        let wood = pbr(diffuse: Texture.wood(dark: dark), roughness: dark ? 0.46 : 0.55)
        wood.clearCoat.contents = dark ? 0.35 : 0.2
        wood.clearCoatRoughness.contents = 0.25
        deskBox.materials = [wood]
        let desk = SCNNode(geometry: deskBox)
        desk.simdPosition = [0, -0.25, -8]  // deep enough that its far edge stays out of frame
        root.addChildNode(desk)

        let laptop = macBook(dark: dark)
        laptop.enumerateHierarchy { node, _ in node.categoryBitMask = 1 | rimOnly }
        root.addChildNode(laptop)
        for (id, p) in spots { root.addChildNode(spot(id, at: p)) }

        // key light: daylight from a window, or a warm desk lamp at night
        let key = SCNLight()
        key.type = .directional
        key.intensity = dark ? 900 : 1150
        key.temperature = dark ? 3300 : 5600
        key.castsShadow = true
        key.shadowMode = .forward
        key.shadowMapSize = CGSize(width: 4096, height: 4096)
        key.shadowSampleCount = 32
        key.shadowRadius = 9
        key.shadowColor = NSColor(white: 0, alpha: dark ? 0.62 : 0.42)
        key.automaticallyAdjustsShadowProjection = true
        let keyNode = SCNNode()
        keyNode.light = key
        keyNode.simdPosition = dark ? [-5, 9, 2] : [-4, 10, 4]
        keyNode.simdLook(at: [0, 0, 0])
        root.addChildNode(keyNode)

        // rim light from behind: draws the MacBook's outline, which a space black one needs at night
        let rim = SCNLight()
        rim.type = .directional
        rim.intensity = dark ? 650 : 250
        rim.temperature = dark ? 6500 : 6000
        rim.categoryBitMask = rimOnly  // the lacquered desk would show it as a hotspot
        let rimNode = SCNNode()
        rimNode.light = rim
        rimNode.simdPosition = [1.5, 3, -9]
        rimNode.simdLook(at: [0, 0.5, 0])
        root.addChildNode(rimNode)

        let cam = SCNCamera()
        cam.projectionDirection = .horizontal
        cam.fieldOfView = 39
        cam.zNear = 0.1
        cam.zFar = 60
        cam.wantsHDR = true
        cam.wantsExposureAdaptation = false
        cam.exposureOffset = dark ? -0.15 : 0.1
        cam.vignettingPower = 0.6
        cam.vignettingIntensity = dark ? 0.9 : 0.45
        cam.bloomIntensity = dark ? 0.3 : 0.15
        cam.bloomThreshold = 0.85
        cam.bloomBlurRadius = 12
        let camNode = SCNNode()
        camNode.camera = cam
        camNode.simdPosition = [0, 6.7, 9.9]
        camNode.simdLook(at: [0, 0.95, 0.1])
        cam.screenSpaceAmbientOcclusionIntensity = 1.2
        cam.screenSpaceAmbientOcclusionRadius = 0.35
        cam.wantsDepthOfField = true
        cam.focusDistance = CGFloat(simd_distance(camNode.simdPosition, [0, 0.3, 0.4]))
        cam.fStop = 3.2
        cam.apertureBladeCount = 9
        root.addChildNode(camNode)
        return (scene, camNode)
    }

    private static func macBook(dark: Bool) -> SCNNode {
        let node = SCNNode()
        let metal = pbr(diffuse: NSColor(hex: dark ? 0x2E3033 : 0xC8CBCF), metalness: 1, roughness: dark ? 0.42 : 0.34)
        let (w, d, h): (CGFloat, CGFloat, CGFloat) = (3.13, 2.21, 0.155)

        let baseBox = SCNBox(width: w, height: h, length: d, chamferRadius: 0.07)
        baseBox.materials = [metal]
        let base = SCNNode(geometry: baseBox)
        base.simdPosition = [0, Float(h / 2), 0]
        node.addChildNode(base)

        let (keys, mask) = Texture.keyboard(chassis: dark ? 0x2A2C2F : 0xBFC2C6)
        let keyboard = flatPlane(width: 2.8, height: 1.19, material: pbr(diffuse: keys, metalness: mask, roughness: 0.75))
        keyboard.simdPosition = [0, Float(h) + 0.0012, -0.34]
        node.addChildNode(keyboard)

        let glass = pbr(diffuse: NSColor(hex: dark ? 0x26282B : 0xB9BCC0), metalness: 0.6, roughness: 0.22)
        let trackpad = flatPlane(width: 1.36, height: 0.84, material: glass, corner: 0.06)
        trackpad.simdPosition = [0, Float(h) + 0.0012, 0.57]
        node.addChildNode(trackpad)

        // lid, opened 112° about the hinge at the back edge
        let hinge = SCNNode()
        hinge.simdPosition = [0, Float(h), -Float(d / 2)]
        hinge.eulerAngles.x = -112 * .pi / 180
        node.addChildNode(hinge)

        let lidBox = SCNBox(width: w, height: 0.06, length: d - 0.03, chamferRadius: 0.03)
        lidBox.materials = [metal]
        let lid = SCNNode(geometry: lidBox)
        lid.simdPosition = [0, 0.03, Float(d / 2)]
        hinge.addChildNode(lid)

        let black = constant(NSColor(hex: 0x050505))
        let bezel = SCNNode(geometry: SCNPlane(width: w - 0.06, height: d - 0.08))
        bezel.geometry?.materials = [black]
        bezel.simdPosition = [0, -0.0015, Float(d / 2)]
        bezel.eulerAngles.x = .pi / 2
        hinge.addChildNode(bezel)

        let display = SCNNode(geometry: SCNPlane(width: 2.99, height: 1.95))
        display.geometry?.materials = [constant(Texture.wallpaper(dark: dark))]
        display.simdPosition = [0, -0.0025, Float(d / 2) + 0.03]
        display.eulerAngles.x = .pi / 2
        hinge.addChildNode(display)

        let notch = SCNNode(geometry: SCNPlane(width: 0.2, height: 0.034))
        notch.geometry?.materials = [black]
        notch.simdPosition = [0, -0.0035, Float(d / 2) + 0.03 + 0.975 - 0.017]
        notch.eulerAngles.x = .pi / 2
        hinge.addChildNode(notch)
        return node
    }

    /// A zone spot: a pool of light in the zone's hue, a hairline ring and a small dot, inlaid in the desk.
    private static func spot(_ id: String, at p: SIMD3<Float>) -> SCNNode {
        let hue = NSColor(hex: ZoneHue.hex(id))
        let node = SCNNode()
        node.simdPosition = p

        let glowMaterial = constant(Texture.glow(hue))
        glowMaterial.blendMode = .add
        glowMaterial.writesToDepthBuffer = false
        let glow = flatPlane(width: 1.1, height: 1.1, material: glowMaterial)
        glow.simdPosition.y = 0.003
        node.addChildNode(glow)

        let ring = SCNNode(geometry: SCNTorus(ringRadius: CGFloat(ringRadius) * 0.62, pipeRadius: 0.009))
        ring.geometry?.materials = [constant(hue.withAlphaComponent(0.9))]
        ring.simdPosition.y = 0.006
        node.addChildNode(ring)

        let dot = SCNNode(geometry: SCNCylinder(radius: 0.045, height: 0.01))
        dot.geometry?.materials = [constant(hue.blended(withFraction: 0.35, of: .white) ?? hue)]
        dot.simdPosition.y = 0.004
        node.addChildNode(dot)
        return node
    }

    // MARK: - Helpers

    private static func pbr(diffuse: Any, metalness: Any = 0.0, roughness: Any) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = diffuse
        m.metalness.contents = metalness
        m.roughness.contents = roughness
        return m
    }

    private static func constant(_ contents: Any) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = contents
        return m
    }

    /// A plane lying on the desk, its texture's top edge pointing away from the viewer.
    private static func flatPlane(width: CGFloat, height: CGFloat, material: SCNMaterial, corner: CGFloat = 0) -> SCNNode {
        let plane = SCNPlane(width: width, height: height)
        plane.cornerRadius = corner
        plane.materials = [material]
        let node = SCNNode(geometry: plane)
        node.eulerAngles.x = -.pi / 2
        return node
    }
}

// MARK: - Procedural textures

/// Every texture is drawn in code: no image assets to license or keep in sync.
enum Texture {
    static func wood(dark: Bool) -> CGImage {
        let (w, h) = (2048, 1024)
        // oak by day, walnut at night
        let low: SIMD3<Double> = dark ? [0.16, 0.1, 0.066] : [0.67, 0.575, 0.47]
        let high: SIMD3<Double> = dark ? [0.34, 0.215, 0.14] : [0.81, 0.725, 0.62]
        var seed: UInt64 = 0x9E37_79B9_7F4A_7C15
        func noise() -> Double {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double(seed >> 33) / Double(1 << 31)
        }
        // streaks: per-row noise, smoothed, so fibres run the length of the board
        var streak = (0..<h).map { _ in noise() }
        for _ in 0..<3 { streak = streak.indices.map { (streak[max($0 - 1, 0)] + streak[$0] + streak[min($0 + 1, h - 1)]) / 3 } }
        let octaves: [(freq: Double, amp: Double, phase: Double, bend: Double)] =
            [(31, 0.5, 0.3, 0.006), (67, 0.3, 1.7, 0.004), (149, 0.2, 2.9, 0.002)]
        return bitmap(w, h) { px in
            for y in 0..<h {
                let fy = Double(y) / Double(h)
                for x in 0..<w {
                    let fx = Double(x) / Double(w)
                    var g = 0.0
                    for o in octaves {
                        let bend = o.bend * sin(2 * .pi * (fx * 1.3 + o.phase)) + o.bend * 0.5 * sin(2 * .pi * fx * 3.1)
                        g += o.amp * sin(2 * .pi * (o.freq * (fy + bend) + o.phase))
                    }
                    var t = pow(0.5 + 0.5 * g, 1.8) * 0.55 + streak[y] * 0.2 + noise() * 0.05
                    t += 0.06 * sin(fx * 2.4 + 0.5)  // a slow tone change across the board
                    let c = low + (high - low) * min(max(t, 0), 1)
                    let i = (y * w + x) * 4
                    px[i] = UInt8(c.x * 255); px[i + 1] = UInt8(c.y * 255); px[i + 2] = UInt8(c.z * 255); px[i + 3] = 255
                }
            }
        }
    }

    /// A soft studio: bright sky with two softboxes, a mid horizon and a darker floor.
    static func environment(dark: Bool) -> CGImage {
        draw(1024, 512) { ctx, size in
            let colors =
                dark
                ? [NSColor(hex: 0x6B5A48), NSColor(hex: 0x2A2724), NSColor(hex: 0x0E0E0F)]
                : [NSColor(hex: 0xFFFFFF), NSColor(hex: 0xC9CED4), NSColor(hex: 0x6D727A)]
            let gradient = CGGradient(
                colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                colors: colors.map(\.cgColor) as CFArray, locations: [0, 0.5, 1])!
            ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: size.height), end: .zero, options: [])
            ctx.setFillColor(NSColor(white: 1, alpha: dark ? 0.55 : 0.95).cgColor)
            ctx.fill(CGRect(x: 180, y: 380, width: 220, height: 80))
            ctx.fill(CGRect(x: 640, y: 360, width: 140, height: 110))
        }
    }

    static func keyboard(chassis: UInt32) -> (CGImage, CGImage) {
        let (w, h) = (1400, 595)
        let rows: [[Double]] = [
            Array(repeating: 1.0357, count: 14),
            Array(repeating: 1, count: 13) + [1.5],
            [1.5] + Array(repeating: 1, count: 13),
            [1.8] + Array(repeating: 1, count: 11) + [1.7],
            [2.3] + Array(repeating: 1, count: 10) + [2.2],
            [1, 1, 1, 1.25, 5, 1.25, 1, 1, 1, 1],
        ]
        let unit = Double(w) / 14.5
        let gap = unit * 0.11
        func eachKey(_ body: (CGRect) -> Void) {
            var top = Double(h)
            for (r, row) in rows.enumerated() {
                let rowH = r == 0 ? unit * 0.62 : unit
                var x = 0.0
                for keyW in row {
                    body(CGRect(x: x + gap / 2, y: top - rowH + gap / 2, width: keyW * unit - gap, height: rowH - gap))
                    x += keyW * unit
                }
                top -= rowH
            }
        }
        let keys = draw(w, h) { ctx, size in
            ctx.setFillColor(NSColor(hex: chassis).cgColor)
            ctx.fill(CGRect(origin: .zero, size: size))
            eachKey { rect in
                ctx.setFillColor(NSColor(hex: 0x0B0B0C).cgColor)
                ctx.addPath(CGPath(roundedRect: rect, cornerWidth: 9, cornerHeight: 9, transform: nil))
                ctx.fillPath()
                ctx.setFillColor(NSColor(white: 1, alpha: 0.05).cgColor)
                ctx.addPath(
                    CGPath(
                        roundedRect: rect.insetBy(dx: 3, dy: 3).offsetBy(dx: 0, dy: 2),
                        cornerWidth: 7, cornerHeight: 7, transform: nil))
                ctx.fillPath()
            }
        }
        let mask = draw(w, h) { ctx, size in
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.fill(CGRect(origin: .zero, size: size))
            ctx.setFillColor(NSColor.black.cgColor)
            eachKey { ctx.fill($0) }
        }
        return (keys, mask)
    }

    /// The MacBook's screen: the TouchMac mark, ripples in the six zone hues.
    static func wallpaper(dark: Bool) -> CGImage {
        draw(1500, 978) { ctx, size in
            let colors =
                dark
                ? [NSColor(hex: 0x161A2E), NSColor(hex: 0x0B0D16)]
                : [NSColor(hex: 0x3A4A7A), NSColor(hex: 0x1C2340)]
            let gradient = CGGradient(
                colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                colors: colors.map(\.cgColor) as CFArray, locations: [0, 1])!
            ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: size.height), end: CGPoint(x: size.width, y: 0), options: [])
            let center = CGPoint(x: size.width * 0.5, y: size.height * 0.46)
            for (i, id) in calibrationOrder.enumerated() {
                let r = 70 + CGFloat(i) * 62
                ctx.setStrokeColor(NSColor(hex: ZoneHue.hex(id), alpha: 0.85 - CGFloat(i) * 0.11).cgColor)
                ctx.setLineWidth(10 - CGFloat(i) * 1.1)
                ctx.strokeEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r))
            }
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.fillEllipse(in: CGRect(x: center.x - 26, y: center.y - 26, width: 52, height: 52))
            // menu bar
            ctx.setFillColor(NSColor(white: 1, alpha: 0.12).cgColor)
            ctx.fill(CGRect(x: 0, y: size.height - 30, width: size.width, height: 30))
        }
    }

    static func glow(_ hue: NSColor) -> CGImage {
        draw(256, 256) { ctx, size in
            let gradient = CGGradient(
                colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                colors: [
                    hue.withAlphaComponent(0.75).cgColor, hue.withAlphaComponent(0.22).cgColor,
                    hue.withAlphaComponent(0).cgColor,
                ] as CFArray,
                locations: [0, 0.35, 1])!
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            ctx.drawRadialGradient(gradient, startCenter: c, startRadius: 0, endCenter: c, endRadius: size.width / 2, options: [])
        }
    }

    // MARK: drawing

    private static func context(_ w: Int, _ h: Int) -> CGContext {
        CGContext(
            data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    }

    static func draw(_ w: Int, _ h: Int, _ body: (CGContext, CGSize) -> Void) -> CGImage {
        let ctx = context(w, h)
        body(ctx, CGSize(width: w, height: h))
        return ctx.makeImage()!
    }

    /// Per-pixel RGBA8, rows top to bottom.
    private static func bitmap(_ w: Int, _ h: Int, _ fill: (inout [UInt8]) -> Void) -> CGImage {
        var px = [UInt8](repeating: 0, count: w * h * 4)
        fill(&px)
        let provider = CGDataProvider(data: Data(px) as CFData)!
        return CGImage(
            width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)!
    }
}
