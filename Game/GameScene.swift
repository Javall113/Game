import SpriteKit

final class GameScene: SKScene, SKPhysicsContactDelegate {

    private enum PhysicsMask {
        static let none: UInt32 = 0
        static let player: UInt32 = 1 << 0
        static let good: UInt32 = 1 << 1
        static let bad: UInt32 = 1 << 2
    }

    private let laneCount = 5
    private var laneXPositions: [CGFloat] = []
    private var currentLane = 2

    private var player = SKShapeNode(circleOfRadius: 22)
    private var scoreLabel = SKLabelNode(fontNamed: "AvenirNext-Bold")
    private var statusLabel = SKLabelNode(fontNamed: "AvenirNext-Medium")

    private var score = 0
    private var isGameOver = false

    private var spawnTimer: Timer?

    override func didMove(to view: SKView) {
        removeAllChildren()
        removeAllActions()

        physicsWorld.gravity = .zero
        physicsWorld.contactDelegate = self

        backgroundColor = .black
        setupNebulaBackground()
        setupLanes()
        setupUI()
        setupPlayer()
        startGameLoop()
    }

    private func setupNebulaBackground() {
        let sky = SKShapeNode(rectOf: CGSize(width: size.width * 1.2, height: size.height * 1.2))
        sky.fillColor = SKColor(red: 0.07, green: 0.04, blue: 0.15, alpha: 1)
        sky.strokeColor = .clear
        sky.position = CGPoint(x: frame.midX, y: frame.midY)
        sky.zPosition = -20
        addChild(sky)

        for _ in 0..<60 {
            let star = SKShapeNode(circleOfRadius: CGFloat.random(in: 1.2...3.0))
            star.fillColor = .white
            star.strokeColor = .clear
            star.alpha = CGFloat.random(in: 0.25...0.9)
            star.position = CGPoint(x: CGFloat.random(in: frame.minX...frame.maxX),
                                    y: CGFloat.random(in: frame.minY...frame.maxY))
            star.zPosition = -10
            let pulse = SKAction.sequence([
                .fadeAlpha(to: CGFloat.random(in: 0.1...0.4), duration: Double.random(in: 0.6...1.4)),
                .fadeAlpha(to: CGFloat.random(in: 0.5...1.0), duration: Double.random(in: 0.6...1.4))
            ])
            star.run(.repeatForever(pulse))
            addChild(star)
        }
    }

    private func setupLanes() {
        laneXPositions = (0..<laneCount).map { lane in
            let sectionWidth = size.width / CGFloat(laneCount + 1)
            return frame.minX + sectionWidth * CGFloat(lane + 1)
        }

        for laneX in laneXPositions {
            let beam = SKShapeNode(rectOf: CGSize(width: 4, height: size.height * 1.1), cornerRadius: 2)
            beam.fillColor = SKColor.cyan.withAlphaComponent(0.14)
            beam.strokeColor = .clear
            beam.position = CGPoint(x: laneX, y: frame.midY)
            beam.zPosition = -5
            addChild(beam)
        }
    }

    private func setupUI() {
        scoreLabel.text = "Энергия: 0"
        scoreLabel.fontSize = 30
        scoreLabel.fontColor = .white
        scoreLabel.horizontalAlignmentMode = .left
        scoreLabel.position = CGPoint(x: frame.minX + 20, y: frame.maxY - 58)
        scoreLabel.zPosition = 30
        addChild(scoreLabel)

        statusLabel.text = "Тап слева/справа, чтобы смещать ядро"
        statusLabel.fontSize = 21
        statusLabel.fontColor = SKColor.white.withAlphaComponent(0.85)
        statusLabel.position = CGPoint(x: frame.midX, y: frame.minY + 56)
        statusLabel.zPosition = 30
        addChild(statusLabel)
    }

    private func setupPlayer() {
        player.removeFromParent()
        player = SKShapeNode(circleOfRadius: 22)
        player.fillColor = .systemGreen
        player.strokeColor = .white
        player.lineWidth = 3
        currentLane = laneCount / 2
        player.position = CGPoint(x: laneXPositions[currentLane], y: frame.minY + 130)
        player.zPosition = 20

        let body = SKPhysicsBody(circleOfRadius: 22)
        body.isDynamic = false
        body.categoryBitMask = PhysicsMask.player
        body.contactTestBitMask = PhysicsMask.good | PhysicsMask.bad
        body.collisionBitMask = PhysicsMask.none
        player.physicsBody = body
        addChild(player)
    }

    private func startGameLoop() {
        isGameOver = false
        score = 0
        updateScoreLabel()

        spawnTimer?.invalidate()
        spawnTimer = Timer.scheduledTimer(withTimeInterval: 0.65, repeats: true) { [weak self] _ in
            self?.spawnObject()
        }

        run(.repeatForever(.sequence([
            .wait(forDuration: 1.0),
            .run { [weak self] in
                self?.score += 1
                self?.updateScoreLabel()
            }
        ])), withKey: "passiveScore")
    }

    private func spawnObject() {
        guard !isGameOver else { return }

        let isBad = Int.random(in: 0..<100) < 35
        let radius: CGFloat = isBad ? 20 : 14
        let node = SKShapeNode(circleOfRadius: radius)
        node.fillColor = isBad ? .systemRed : .systemYellow
        node.strokeColor = isBad ? .white : .orange
        node.lineWidth = 2

        let lane = Int.random(in: 0..<laneCount)
        node.position = CGPoint(x: laneXPositions[lane], y: frame.maxY + 40)
        node.zPosition = 15
        node.name = isBad ? "bad" : "good"

        let body = SKPhysicsBody(circleOfRadius: radius)
        body.affectedByGravity = false
        body.categoryBitMask = isBad ? PhysicsMask.bad : PhysicsMask.good
        body.contactTestBitMask = PhysicsMask.player
        body.collisionBitMask = PhysicsMask.none
        body.velocity = CGVector(dx: 0, dy: -CGFloat.random(in: 260...360))
        body.linearDamping = 0
        node.physicsBody = body

        addChild(node)

        node.run(.sequence([
            .wait(forDuration: 4.5),
            .removeFromParent()
        ]))
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard !isGameOver, let touch = touches.first else {
            if isGameOver {
                restartGame()
            }
            return
        }

        let location = touch.location(in: self)
        if location.x < frame.midX {
            currentLane = max(0, currentLane - 1)
        } else {
            currentLane = min(laneCount - 1, currentLane + 1)
        }

        let move = SKAction.moveTo(x: laneXPositions[currentLane], duration: 0.12)
        move.timingMode = .easeOut
        player.run(move)
    }

    func didBegin(_ contact: SKPhysicsContact) {
        let masks = contact.bodyA.categoryBitMask | contact.bodyB.categoryBitMask
        guard masks & PhysicsMask.player != 0 else { return }

        let otherBody = contact.bodyA.categoryBitMask == PhysicsMask.player ? contact.bodyB : contact.bodyA
        otherBody.node?.removeFromParent()

        if otherBody.categoryBitMask == PhysicsMask.good {
            score += 5
            updateScoreLabel()
            player.run(.sequence([.scale(to: 1.2, duration: 0.08), .scale(to: 1.0, duration: 0.08)]))
        } else if otherBody.categoryBitMask == PhysicsMask.bad {
            triggerGameOver()
        }
    }

    private func triggerGameOver() {
        guard !isGameOver else { return }
        isGameOver = true

        spawnTimer?.invalidate()
        spawnTimer = nil
        removeAction(forKey: "passiveScore")

        player.fillColor = .gray
        player.run(.repeat(.sequence([.fadeAlpha(to: 0.2, duration: 0.12), .fadeAlpha(to: 1.0, duration: 0.12)]), count: 4))

        statusLabel.text = "💥 Перегрев! Счёт: \(score). Нажми для рестарта"
    }

    private func restartGame() {
        enumerateChildNodes(withName: "//*") { node, _ in
            if node.name == "bad" || node.name == "good" {
                node.removeFromParent()
            }
        }

        statusLabel.text = "Тап слева/справа, чтобы смещать ядро"
        player.alpha = 1
        player.fillColor = .systemGreen
        setupPlayer()
        startGameLoop()
    }

    private func updateScoreLabel() {
        scoreLabel.text = "Энергия: \(score)"
    }

    deinit {
        spawnTimer?.invalidate()
    }
}
