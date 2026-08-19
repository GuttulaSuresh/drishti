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
    private let glow = SKSpriteNode()
    private let smokeEmitter = SKEmitterNode()

    private var springVelocity = CGVector.zero
    private var lastUpdateTime: TimeInterval = 0
    private var lastPointerPosition = CGPoint.zero

    private var impactSound: NSSound?
    private var debrisNodes: [SKNode] = []

    // Tuning — intentionally no visible settings UI.
    private let displayWidth: CGFloat = 250
    private let springStrength: CGFloat = 26
    private let springDamping: CGFloat = 7.2
    private let attachHitScale: CGFloat = 0.43
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
        setupGlow()
        setupSmoke()
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

    private func loadImpactSound() {
        if let url = Bundle.main.url(forResource: "impact_crack", withExtension: "wav") {
            impactSound = NSSound(contentsOf: url, byReference: false)
        }
    }

    private func globalPointerInScene() -> CGPoint {
        guard let screen = NSScreen.main else { return lastPointerPosition }
        let global = NSEvent.mouseLocation
        return CGPoint(x: global.x - screen.frame.origin.x,
                       y: global.y - screen.frame.origin.y)
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

        if state == .waitingForTouch || state == .attached {
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
        // Spring-damper follow gives the pumpkin weight and a slight lag.
        let dx = pointer.x - pumpkin.position.x
        let dy = pointer.y - pumpkin.position.y

        springVelocity.dx += dx * springStrength * dt
        springVelocity.dy += dy * springStrength * dt

        let damping = CGFloat(Foundation.exp(Double(-springDamping * dt)))
        springVelocity.dx *= damping
        springVelocity.dy *= damping

        pumpkin.position.x += springVelocity.dx * dt
        pumpkin.position.y += springVelocity.dy * dt

        // Keep the object visible while the user moves it around.
        let halfW = pumpkin.size.width * 0.36
        let halfH = pumpkin.size.height * 0.33
        pumpkin.position.x = min(max(pumpkin.position.x, halfW), size.width - halfW)
        pumpkin.position.y = min(max(pumpkin.position.y, halfH), size.height - halfH)

        let desiredTilt = max(-0.22, min(0.22, -springVelocity.dx * 0.00075))
        pumpkin.zRotation += (desiredTilt - pumpkin.zRotation) * min(1, dt * 7.5)
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
        smokeEmitter.run(.fadeOut(withDuration: 0.16))
        glow.run(.fadeOut(withDuration: 0.12))

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
        // Asset contains the photographic flame; these subtle effects only add life.
        glow.position = CGPoint(x: pumpkin.position.x,
                                y: pumpkin.position.y + pumpkin.size.height * 0.31)
        glow.zRotation = 0

        smokeEmitter.position = CGPoint(x: pumpkin.position.x + 2,
                                        y: pumpkin.position.y + pumpkin.size.height * 0.39)
    }

    private func updateFlameFlicker(_ time: TimeInterval) {
        let t = CGFloat(time)
        glow.alpha = 0.20 + 0.06 * (0.5 + 0.5 * sin(t * 17.0))
        let scale = 0.96 + 0.07 * (0.5 + 0.5 * sin(t * 13.0 + 1.1))
        glow.setScale(scale)
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
