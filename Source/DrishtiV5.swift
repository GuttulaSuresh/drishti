import Cocoa
import SpriteKit
import AVFoundation

private struct PhysicsCategory {
    static let floor: UInt32 = 1 << 0
    static let pumpkin: UInt32 = 1 << 1
    static let debris: UInt32 = 1 << 2
}

final class RitualScene: SKScene, SKPhysicsContactDelegate {

    enum State {
        case waitingForTouch
        case attached
        case falling
        case shattered
        case finished
    }

    private var state: State = .waitingForTouch

    private let pumpkin = SKSpriteNode(imageNamed: "pumpkin_camphor")
    private let liveFlame = SKSpriteNode(imageNamed: "camphor_flame_live")
    private let glow = SKSpriteNode()
    private let smokeEmitter = SKEmitterNode()
    private let emberEmitter = SKEmitterNode()

    private var springVelocity = CGVector.zero
    private var lastUpdateTime: TimeInterval = 0
    private var lastPointerPosition = CGPoint.zero
    private var attachOffset = CGPoint.zero

    private var impactSound: NSSound?
    private var debrisNodes: [SKNode] = []

    // Tuning — intentionally no visible settings UI.
    private let displayWidth: CGFloat = 250
    // High responsiveness: follows the pointer closely without looking mechanically locked.
    private let followResponsiveness: CGFloat = 72
    private let attachHitScale: CGFloat = 0.47
    private let fallReleaseDistance: CGFloat = 72
    private let debrisHoldTime: TimeInterval = 3.0
    private let debrisFadeTime: TimeInterval = 0.42

    override func didMove(to view: SKView) {
        backgroundColor = .clear
        scaleMode = .resizeFill

        physicsWorld.gravity = CGVector(dx: 0, dy: -1550)
        physicsWorld.contactDelegate = self

        setupFloor()
        setupPumpkin()
        setupLiveFlame()
        setupGlow()
        setupSmoke()
        setupEmbers()
        loadImpactSound()
    }

    private func setupFloor() {
        let floor = SKNode()
        floor.position = CGPoint(x: 0, y: 4)
        floor.physicsBody = SKPhysicsBody(edgeFrom: CGPoint(x: 0, y: 0),
                                          to: CGPoint(x: size.width, y: 0))
        floor.physicsBody?.categoryBitMask = PhysicsCategory.floor
        floor.physicsBody?.collisionBitMask = PhysicsCategory.pumpkin | PhysicsCategory.debris
        floor.physicsBody?.contactTestBitMask = PhysicsCategory.pumpkin
        floor.physicsBody?.friction = 0.95
        addChild(floor)
    }

    private func setupPumpkin() {
        let textureSize = pumpkin.texture?.size() ?? CGSize(width: 1024, height: 1024)
        let ratio = textureSize.height / max(textureSize.width, 1)
        pumpkin.size = CGSize(width: displayWidth, height: displayWidth * ratio)
        pumpkin.position = CGPoint(x: size.width * 0.74, y: size.height * 0.69)
        pumpkin.zPosition = 30
        pumpkin.alpha = 1
        addChild(pumpkin)
    }

    private func setupLiveFlame() {
        // This layer comes from the same real photographed camphor flame used in
        // the pumpkin asset. It is separated so the flame can move/flicker
        // independently instead of looking frozen onto the pumpkin.
        let sourceWidth: CGFloat = 1254
        let sourceHeight: CGFloat = 1254
        let cropWidth: CGFloat = 420
        let cropHeight: CGFloat = 300

        liveFlame.size = CGSize(
            width: pumpkin.size.width * (cropWidth / sourceWidth),
            height: pumpkin.size.height * (cropHeight / sourceHeight)
        )
        liveFlame.zPosition = 34
        liveFlame.alpha = 0.68
        liveFlame.blendMode = .alpha
        addChild(liveFlame)
        syncEffectsToPumpkin()
    }

    private func setupGlow() {
        glow.texture = makeGlowTexture(size: CGSize(width: 170, height: 170))
        glow.size = CGSize(width: 170, height: 170)
        glow.alpha = 0.25
        glow.blendMode = .add
        glow.zPosition = 28
        addChild(glow)
        syncEffectsToPumpkin()
    }

    private func setupSmoke() {
        smokeEmitter.particleBirthRate = 7
        smokeEmitter.particleLifetime = 1.7
        smokeEmitter.particleLifetimeRange = 0.35
        smokeEmitter.particlePositionRange = CGVector(dx: 12, dy: 4)
        smokeEmitter.particleSpeed = 28
        smokeEmitter.particleSpeedRange = 11
        smokeEmitter.emissionAngle = .pi / 2
        smokeEmitter.emissionAngleRange = 0.22
        smokeEmitter.particleAlpha = 0.16
        smokeEmitter.particleAlphaRange = 0.08
        smokeEmitter.particleAlphaSpeed = -0.075
        smokeEmitter.particleScale = 0.20
        smokeEmitter.particleScaleRange = 0.09
        smokeEmitter.particleScaleSpeed = 0.16
        smokeEmitter.particleRotationRange = .pi
        smokeEmitter.particleColor = NSColor(calibratedWhite: 0.85, alpha: 0.50)
        smokeEmitter.particleColorBlendFactor = 1.0
        smokeEmitter.particleTexture = makeSmokeTexture()
        smokeEmitter.zPosition = 31
        addChild(smokeEmitter)
        syncEffectsToPumpkin()
    }

    private func setupEmbers() {
        emberEmitter.particleBirthRate = 2.4
        emberEmitter.particleLifetime = 0.72
        emberEmitter.particleLifetimeRange = 0.26
        emberEmitter.particlePositionRange = CGVector(dx: 12, dy: 5)
        emberEmitter.particleSpeed = 22
        emberEmitter.particleSpeedRange = 17
        emberEmitter.emissionAngle = .pi / 2
        emberEmitter.emissionAngleRange = 1.05
        emberEmitter.particleAlpha = 0.85
        emberEmitter.particleAlphaRange = 0.12
        emberEmitter.particleAlphaSpeed = -1.05
        emberEmitter.particleScale = 0.055
        emberEmitter.particleScaleRange = 0.025
        emberEmitter.particleScaleSpeed = -0.035
        emberEmitter.particleColor = NSColor(calibratedRed: 1.0, green: 0.33, blue: 0.04, alpha: 1)
        emberEmitter.particleColorBlendFactor = 1.0
        emberEmitter.particleTexture = makeGlowTexture(size: CGSize(width: 24, height: 24))
        emberEmitter.zPosition = 35
        addChild(emberEmitter)
        syncEffectsToPumpkin()
    }

    private func loadImpactSound() {
        if let url = Bundle.main.url(forResource: "impact_crack", withExtension: "wav") {
            impactSound = NSSound(contentsOf: url, byReference: false)
        }
    }

    private func globalPointerInScene() -> CGPoint {
        guard let screen = self.view?.window?.screen ?? NSScreen.main else {
            return lastPointerPosition
        }
        let global = NSEvent.mouseLocation
        return CGPoint(x: global.x - screen.frame.minX,
                       y: global.y - screen.frame.minY)
    }

    override func update(_ currentTime: TimeInterval) {
        guard state != .finished else { return }

        let dt: CGFloat
        if lastUpdateTime == 0 {
            dt = 1.0 / 60.0
        } else {
            dt = CGFloat(min(currentTime - lastUpdateTime, 1.0 / 20.0))
        }
        lastUpdateTime = currentTime

        let pointer = globalPointerInScene()
        lastPointerPosition = pointer

        switch state {
        case .waitingForTouch:
            if pointerTouchesPumpkin(pointer) {
                attachOffset = CGPoint(
                    x: pumpkin.position.x - pointer.x,
                    y: pumpkin.position.y - pointer.y
                )
                springVelocity = .zero
                state = .attached
            }

        case .attached:
            updateAttachedMotion(pointer: pointer, dt: dt)

            let floorTrigger = pumpkin.size.height * 0.33 + fallReleaseDistance
            if pumpkin.position.y <= floorTrigger {
                beginFalling()
            }

        case .falling:
            syncEffectsToPumpkin()

        case .shattered:
            break

        case .finished:
            break
        }

        if state == .waitingForTouch || state == .attached || state == .falling {
            updateFlameFlicker(currentTime)
            syncEffectsToPumpkin()
        }
    }

    private func pointerTouchesPumpkin(_ p: CGPoint) -> Bool {
        let radius = min(pumpkin.size.width, pumpkin.size.height) * attachHitScale
        let dx = p.x - pumpkin.position.x
        let dy = p.y - pumpkin.position.y
        return (dx * dx + dy * dy) <= radius * radius
    }

    private func updateAttachedMotion(pointer: CGPoint, dt: CGFloat) {
        // Preserve the exact point the cursor touched on the pumpkin.
        // This prevents the old "center chasing the pointer" sensation.
        let target = CGPoint(
            x: pointer.x + attachOffset.x,
            y: pointer.y + attachOffset.y
        )

        let previous = pumpkin.position

        // Frame-rate-independent exponential smoothing.
        // At normal display rates this closes most of the distance every frame,
        // leaving only a tiny amount of physical weight.
        let response = 1.0 - CGFloat(
            Foundation.exp(Double(-followResponsiveness * dt))
        )

        pumpkin.position.x += (target.x - pumpkin.position.x) * response
        pumpkin.position.y += (target.y - pumpkin.position.y) * response

        let halfW = pumpkin.size.width * 0.36
        let halfH = pumpkin.size.height * 0.33
        pumpkin.position.x = min(max(pumpkin.position.x, halfW), size.width - halfW)
        pumpkin.position.y = min(max(pumpkin.position.y, halfH), size.height - halfH)

        if dt > 0.0001 {
            springVelocity.dx = (pumpkin.position.x - previous.x) / dt
            springVelocity.dy = (pumpkin.position.y - previous.y) / dt
        }

        // Small natural tilt only. The pointer tracking remains tight.
        let desiredTilt = max(-0.16, min(0.16, -springVelocity.dx * 0.00032))
        pumpkin.zRotation += (desiredTilt - pumpkin.zRotation) * min(1, dt * 15.0)
    }

    private func beginFalling() {
        guard state == .attached else { return }
        state = .falling

        let bodyRadius = min(pumpkin.size.width, pumpkin.size.height) * 0.31
        let body = SKPhysicsBody(circleOfRadius: bodyRadius)
        body.mass = 0.95
        body.restitution = 0.10
        body.friction = 0.88
        body.linearDamping = 0.16
        body.angularDamping = 0.42
        body.categoryBitMask = PhysicsCategory.pumpkin
        body.collisionBitMask = PhysicsCategory.floor
        body.contactTestBitMask = PhysicsCategory.floor
        body.velocity = CGVector(dx: springVelocity.dx * 0.55,
                                 dy: min(springVelocity.dy * 0.45, -120))
        body.angularVelocity = -springVelocity.dx * 0.0015
        pumpkin.physicsBody = body
    }

    func didBegin(_ contact: SKPhysicsContact) {
        guard state == .falling else { return }

        let a = contact.bodyA.categoryBitMask
        let b = contact.bodyB.categoryBitMask
        let hitFloor = (a == PhysicsCategory.pumpkin && b == PhysicsCategory.floor) ||
                       (b == PhysicsCategory.pumpkin && a == PhysicsCategory.floor)

        if hitFloor {
            shatter(at: contact.contactPoint)
        }
    }

    private func shatter(at point: CGPoint) {
        guard state == .falling else { return }
        state = .shattered

        impactSound?.play()

        smokeEmitter.particleBirthRate = 0
        emberEmitter.particleBirthRate = 0
        smokeEmitter.run(.fadeOut(withDuration: 0.18))
        emberEmitter.run(.fadeOut(withDuration: 0.10))
        liveFlame.run(.fadeOut(withDuration: 0.08))
        glow.run(.fadeOut(withDuration: 0.10))

        let sourceTexture = pumpkin.texture
        let originalPosition = pumpkin.position
        let originalRotation = pumpkin.zRotation

        pumpkin.physicsBody = nil
        pumpkin.removeFromParent()

        createFragments(from: sourceTexture,
                        center: originalPosition,
                        rotation: originalRotation)

        createSeeds(around: CGPoint(x: originalPosition.x, y: max(28, originalPosition.y)))

        // Let everything collide, bounce, and settle naturally.
        run(.sequence([
            .wait(forDuration: debrisHoldTime),
            .run { [weak self] in self?.fadeAndQuit() }
        ]))
    }

    private func createFragments(from texture: SKTexture?, center: CGPoint, rotation: CGFloat) {
        guard let texture = texture else { return }

        // Crop mainly the pumpkin body. The top flame/smoke portion is omitted
        // so the flame visually extinguishes at impact.
        let cols = 5
        let rows = 4
        let bodyY: CGFloat = 0.02
        let bodyHeight: CGFloat = 0.75

        let visibleWidth = pumpkin.size.width * 0.78
        let visibleHeight = pumpkin.size.height * 0.67

        for row in 0..<rows {
            for col in 0..<cols {
                let unitW = 1.0 / CGFloat(cols)
                let unitH = bodyHeight / CGFloat(rows)

                let rect = CGRect(
                    x: CGFloat(col) * unitW,
                    y: bodyY + CGFloat(row) * unitH,
                    width: unitW,
                    height: unitH
                )

                let sub = SKTexture(rect: rect, in: texture)
                let node = SKSpriteNode(texture: sub)

                let fragW = visibleWidth / CGFloat(cols) * CGFloat.random(in: 0.90...1.18)
                let fragH = visibleHeight / CGFloat(rows) * CGFloat.random(in: 0.88...1.16)
                node.size = CGSize(width: fragW, height: fragH)

                let localX = (CGFloat(col) - CGFloat(cols - 1) / 2.0) * (visibleWidth / CGFloat(cols))
                let localY = (CGFloat(row) - CGFloat(rows - 1) / 2.0) * (visibleHeight / CGFloat(rows)) - 18

                node.position = CGPoint(x: center.x + localX, y: center.y + localY)
                node.zRotation = rotation + CGFloat.random(in: -0.18...0.18)
                node.zPosition = 20 + CGFloat.random(in: 0...4)
                node.alpha = 0.98

                let physicsSize = CGSize(width: max(8, fragW * 0.72),
                                         height: max(8, fragH * 0.65))
                node.physicsBody = SKPhysicsBody(rectangleOf: physicsSize)
                node.physicsBody?.mass = 0.045 + CGFloat.random(in: 0...0.06)
                node.physicsBody?.restitution = CGFloat.random(in: 0.08...0.24)
                node.physicsBody?.friction = CGFloat.random(in: 0.72...0.96)
                node.physicsBody?.linearDamping = 0.62
                node.physicsBody?.angularDamping = 0.50
                node.physicsBody?.categoryBitMask = PhysicsCategory.debris
                node.physicsBody?.collisionBitMask = PhysicsCategory.floor | PhysicsCategory.debris
                node.physicsBody?.contactTestBitMask = 0

                let outwardX = localX * CGFloat.random(in: 3.4...5.0)
                let upward = CGFloat.random(in: 180...520)
                node.physicsBody?.velocity = CGVector(dx: outwardX + CGFloat.random(in: -120...120),
                                                      dy: upward)
                node.physicsBody?.angularVelocity = CGFloat.random(in: -8.0...8.0)

                addChild(node)
                debrisNodes.append(node)
            }
        }
    }

    private func createSeeds(around center: CGPoint) {
        for _ in 0..<18 {
            let seed = SKShapeNode(ellipseOf: CGSize(width: CGFloat.random(in: 5.5...8.5),
                                                     height: CGFloat.random(in: 2.4...4.3)))
            seed.fillColor = NSColor(calibratedRed: 0.87, green: 0.76, blue: 0.54, alpha: 1)
            seed.strokeColor = NSColor(calibratedRed: 0.67, green: 0.56, blue: 0.36, alpha: 0.9)
            seed.lineWidth = 0.6
            seed.position = CGPoint(x: center.x + CGFloat.random(in: -22...22),
                                    y: center.y + CGFloat.random(in: 4...30))
            seed.zPosition = 28
            seed.zRotation = CGFloat.random(in: 0...(2 * .pi))

            let body = SKPhysicsBody(rectangleOf: CGSize(width: 6, height: 3))
            body.mass = 0.006
            body.restitution = 0.22
            body.friction = 0.76
            body.linearDamping = 0.35
            body.angularDamping = 0.40
            body.categoryBitMask = PhysicsCategory.debris
            body.collisionBitMask = PhysicsCategory.floor | PhysicsCategory.debris
            body.velocity = CGVector(dx: CGFloat.random(in: -210...210),
                                     dy: CGFloat.random(in: 160...420))
            body.angularVelocity = CGFloat.random(in: -12...12)
            seed.physicsBody = body

            addChild(seed)
            debrisNodes.append(seed)
        }
    }

    private func fadeAndQuit() {
        guard state == .shattered else { return }
        state = .finished

        for node in debrisNodes {
            node.physicsBody = nil
            node.run(.fadeOut(withDuration: debrisFadeTime))
        }

        run(.sequence([
            .wait(forDuration: debrisFadeTime + 0.08),
            .run {
                NSApp.terminate(nil)
            }
        ]))
    }

    private func syncEffectsToPumpkin() {
        // Alignment of the separated flame crop relative to the original
        // 1254x1254 photographic asset.
        let scale = pumpkin.size.width / 1254.0

        // Crop center in original image: (640, 220) with top-left coordinates.
        // Convert it to an offset from the full-image center in SpriteKit space.
        let localX: CGFloat = (640.0 - 627.0) * scale
        let localY: CGFloat = ((1254.0 - 220.0) - 627.0) * scale

        let c = cos(pumpkin.zRotation)
        let sn = sin(pumpkin.zRotation)
        let rotatedX = localX * c - localY * sn
        let rotatedY = localX * sn + localY * c

        liveFlame.position = CGPoint(
            x: pumpkin.position.x + rotatedX,
            y: pumpkin.position.y + rotatedY
        )

        // Real flames remain more vertical than the pumpkin body while moving.
        let motionLean = max(-0.13, min(0.13, -springVelocity.dx * 0.00020))
        liveFlame.zRotation = pumpkin.zRotation * 0.20 + motionLean

        glow.position = CGPoint(
            x: liveFlame.position.x,
            y: liveFlame.position.y - 9
        )
        glow.zRotation = 0

        smokeEmitter.position = CGPoint(
            x: liveFlame.position.x + 7,
            y: liveFlame.position.y + liveFlame.size.height * 0.28
        )

        emberEmitter.position = CGPoint(
            x: liveFlame.position.x,
            y: liveFlame.position.y - liveFlame.size.height * 0.30
        )
    }

    private func updateFlameFlicker(_ time: TimeInterval) {
        let t = CGFloat(time)

        // Multiple non-matching frequencies avoid a repetitive "GIF" look.
        let fast = sin(t * 19.7)
        let mid = sin(t * 12.3 + 0.8)
        let slow = sin(t * 7.1 + 2.2)

        liveFlame.alpha = 0.64 + 0.12 * (0.5 + 0.5 * fast)
        liveFlame.xScale = 0.98 + 0.035 * mid
        liveFlame.yScale = 0.98 + 0.075 * fast + 0.020 * slow

        glow.alpha = 0.19 + 0.08 * (0.5 + 0.5 * mid)
        let glowScale = 0.94 + 0.10 * (0.5 + 0.5 * slow)
        glow.setScale(glowScale)

        emberEmitter.particleBirthRate = 1.8 + 1.6 * (0.5 + 0.5 * fast)
    }

    private func makeGlowTexture(size: CGSize) -> SKTexture {
        let image = NSImage(size: size)
        image.lockFocus()
        guard let ctx = NSGraphicsContext.current?.cgContext else {
            image.unlockFocus()
            return SKTexture(image: image)
        }

        let colors = [
            NSColor(calibratedRed: 1.0, green: 0.38, blue: 0.08, alpha: 0.45).cgColor,
            NSColor(calibratedRed: 1.0, green: 0.62, blue: 0.12, alpha: 0.16).cgColor,
            NSColor(calibratedRed: 1.0, green: 0.62, blue: 0.12, alpha: 0.0).cgColor
        ] as CFArray
        let locs: [CGFloat] = [0.0, 0.42, 1.0]
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                     colors: colors,
                                     locations: locs) {
            ctx.drawRadialGradient(gradient,
                                   startCenter: CGPoint(x: size.width/2, y: size.height/2),
                                   startRadius: 0,
                                   endCenter: CGPoint(x: size.width/2, y: size.height/2),
                                   endRadius: size.width/2,
                                   options: [])
        }
        image.unlockFocus()
        return SKTexture(image: image)
    }

    private func makeSmokeTexture() -> SKTexture {
        let size = CGSize(width: 64, height: 64)
        let image = NSImage(size: size)
        image.lockFocus()
        guard let ctx = NSGraphicsContext.current?.cgContext else {
            image.unlockFocus()
            return SKTexture(image: image)
        }

        let colors = [
            NSColor(calibratedWhite: 0.96, alpha: 0.32).cgColor,
            NSColor(calibratedWhite: 0.86, alpha: 0.11).cgColor,
            NSColor(calibratedWhite: 0.80, alpha: 0.0).cgColor
        ] as CFArray
        let locs: [CGFloat] = [0, 0.45, 1]
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                     colors: colors,
                                     locations: locs) {
            ctx.drawRadialGradient(gradient,
                                   startCenter: CGPoint(x: 32, y: 32),
                                   startRadius: 0,
                                   endCenter: CGPoint(x: 32, y: 32),
                                   endRadius: 32,
                                   options: [])
        }
        image.unlockFocus()
        return SKTexture(image: image)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var window: NSWindow?
    private var skView: SKView?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let screen = NSScreen.main else {
            NSApp.terminate(nil)
            return
        }

        let frame = screen.frame

        let window = NSWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.setFrame(frame, display: false)

        window.level = .floating
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        window.isReleasedWhenClosed = false

        let skView = SKView(frame: CGRect(origin: .zero, size: frame.size))
        skView.allowsTransparency = true
        skView.wantsLayer = true
        skView.layer?.backgroundColor = NSColor.clear.cgColor
        skView.ignoresSiblingOrder = true
        skView.preferredFramesPerSecond = 120

        let scene = RitualScene(size: frame.size)
        scene.scaleMode = .resizeFill
        skView.presentScene(scene)

        window.contentView = skView
        window.orderFrontRegardless()

        self.window = window
        self.skView = skView

        NSApp.setActivationPolicy(.accessory)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
