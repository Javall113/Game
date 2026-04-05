import SpriteKit
import AudioToolbox
import UIKit

final class GameScene: SKScene, SKPhysicsContactDelegate {

    private enum PhysicsMask {
        static let none: UInt32 = 0
        static let player: UInt32 = 1 << 0
        static let good: UInt32 = 1 << 1
        static let bad: UInt32 = 1 << 2
    }

    private enum GameMode: String {
        case easy = "Easy"
        case normal = "Normal"
        case hard = "Hard"

        var spawnInterval: TimeInterval {
            switch self {
            case .easy: return 0.85
            case .normal: return 0.6
            case .hard: return 0.42
            }
        }

        var badChance: Int {
            switch self {
            case .easy: return 24
            case .normal: return 38
            case .hard: return 52
            }
        }

        var baseSpeed: CGFloat {
            switch self {
            case .easy: return 260
            case .normal: return 340
            case .hard: return 440
            }
        }
    }

    private enum Skin: String, CaseIterable {
        case neonGreen
        case skyBlue
        case violet

        var title: String {
            switch self {
            case .neonGreen: return "Neon Green"
            case .skyBlue: return "Sky Blue"
            case .violet: return "Violet"
            }
        }

        var color: UIColor {
            switch self {
            case .neonGreen: return .systemGreen
            case .skyBlue: return .systemTeal
            case .violet: return .systemPurple
            }
        }

        var price: Int {
            switch self {
            case .neonGreen: return 0
            case .skyBlue: return 80
            case .violet: return 160
            }
        }

        var id: String { rawValue }
    }

    private enum StorageKey {
        static let totalCoins = "totalCoins"
        static let selectedSkin = "selectedSkin"
        static let ownedSkins = "ownedSkins"
        static let bestScore = "bestScore"
    }

    private let laneCount = 5
    private var laneXPositions: [CGFloat] = []
    private var currentLane = 2

    private var player = SKShapeNode(circleOfRadius: 22)
    private let scoreLabel = SKLabelNode(fontNamed: "AvenirNext-Bold")
    private let coinLabel = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
    private let modeLabel = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
    private let statusLabel = SKLabelNode(fontNamed: "AvenirNext-Medium")

    private var score = 0
    private var coinsInRun = 0
    private var totalCoins = 0 {
        didSet {
            UserDefaults.standard.set(totalCoins, forKey: StorageKey.totalCoins)
            updateCurrencyLabels()
        }
    }
    private var bestScore = 0 {
        didSet {
            UserDefaults.standard.set(bestScore, forKey: StorageKey.bestScore)
        }
    }
    private var level = 1
    private var isGameOver = false
    private var isInMenu = true

    private var selectedMode: GameMode = .normal
    private var soundsEnabled = true
    private var vibrationEnabled = true

    private var selectedSkin: Skin = .neonGreen {
        didSet {
            UserDefaults.standard.set(selectedSkin.id, forKey: StorageKey.selectedSkin)
            applySelectedSkin()
        }
    }
    private var ownedSkins = Set<Skin>([.neonGreen])

    private var spawnTimer: Timer?

    private let menuContainer = SKNode()
    private let settingsContainer = SKNode()
    private let shopContainer = SKNode()

    override func didMove(to view: SKView) {
        removeAllChildren()
        removeAllActions()

        physicsWorld.gravity = .zero
        physicsWorld.contactDelegate = self

        loadProgress()

        backgroundColor = .black
        setupNebulaBackground()
        setupLanes()
        setupTopHUD()
        setupPlayer()
        setupMenu()
        setupSettings()
        setupShop()
        showMenu()
    }

    private func loadProgress() {
        let defaults = UserDefaults.standard
        totalCoins = defaults.integer(forKey: StorageKey.totalCoins)
        bestScore = defaults.integer(forKey: StorageKey.bestScore)

        if let selectedSkinRaw = defaults.string(forKey: StorageKey.selectedSkin),
           let loadedSkin = Skin(rawValue: selectedSkinRaw) {
            selectedSkin = loadedSkin
        }

        if let skinIds = defaults.array(forKey: StorageKey.ownedSkins) as? [String] {
            let parsed = skinIds.compactMap(Skin.init(rawValue:))
            if !parsed.isEmpty {
                ownedSkins = Set(parsed)
            }
        }

        ownedSkins.insert(.neonGreen)
    }

    private func saveOwnedSkins() {
        UserDefaults.standard.set(ownedSkins.map(\.id), forKey: StorageKey.ownedSkins)
    }

    private func setupNebulaBackground() {
        let sky = SKShapeNode(rectOf: CGSize(width: size.width * 1.2, height: size.height * 1.2))
        sky.fillColor = SKColor(red: 0.05, green: 0.03, blue: 0.14, alpha: 1)
        sky.strokeColor = .clear
        sky.position = CGPoint(x: frame.midX, y: frame.midY)
        sky.zPosition = -20
        addChild(sky)

        for _ in 0..<80 {
            let star = SKShapeNode(circleOfRadius: CGFloat.random(in: 1.2...3.2))
            star.fillColor = .white
            star.strokeColor = .clear
            star.alpha = CGFloat.random(in: 0.2...0.95)
            star.position = CGPoint(x: CGFloat.random(in: frame.minX...frame.maxX),
                                    y: CGFloat.random(in: frame.minY...frame.maxY))
            star.zPosition = -10
            let pulse = SKAction.sequence([
                .fadeAlpha(to: CGFloat.random(in: 0.1...0.35), duration: Double.random(in: 0.5...1.4)),
                .fadeAlpha(to: CGFloat.random(in: 0.45...1.0), duration: Double.random(in: 0.5...1.4))
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
            beam.fillColor = SKColor.cyan.withAlphaComponent(0.17)
            beam.strokeColor = .clear
            beam.position = CGPoint(x: laneX, y: frame.midY)
            beam.zPosition = -5
            addChild(beam)
        }
    }

    private func setupTopHUD() {
        scoreLabel.text = "Score: 0"
        scoreLabel.fontSize = 26
        scoreLabel.fontColor = .white
        scoreLabel.horizontalAlignmentMode = .left
        scoreLabel.position = CGPoint(x: frame.minX + 20, y: frame.maxY - 58)
        scoreLabel.zPosition = 40
        addChild(scoreLabel)

        coinLabel.text = "Coins: 0"
        coinLabel.fontSize = 22
        coinLabel.fontColor = .systemYellow
        coinLabel.horizontalAlignmentMode = .center
        coinLabel.position = CGPoint(x: frame.midX, y: frame.maxY - 56)
        coinLabel.zPosition = 40
        addChild(coinLabel)

        modeLabel.text = "Mode: \(selectedMode.rawValue)"
        modeLabel.fontSize = 20
        modeLabel.fontColor = SKColor.cyan.withAlphaComponent(0.9)
        modeLabel.horizontalAlignmentMode = .right
        modeLabel.position = CGPoint(x: frame.maxX - 20, y: frame.maxY - 56)
        modeLabel.zPosition = 40
        addChild(modeLabel)

        statusLabel.text = ""
        statusLabel.fontSize = 21
        statusLabel.fontColor = SKColor.white.withAlphaComponent(0.88)
        statusLabel.position = CGPoint(x: frame.midX, y: frame.minY + 56)
        statusLabel.zPosition = 40
        addChild(statusLabel)

        updateCurrencyLabels()
    }

    private func setupPlayer() {
        player.removeFromParent()
        player = SKShapeNode(circleOfRadius: 22)
        player.fillColor = selectedSkin.color
        player.strokeColor = .white
        player.lineWidth = 3
        currentLane = laneCount / 2
        player.position = CGPoint(x: laneXPositions[currentLane], y: frame.minY + 130)
        player.zPosition = 20
        player.alpha = 0

        let aura = SKShapeNode(circleOfRadius: 38)
        aura.fillColor = .clear
        aura.strokeColor = selectedSkin.color.withAlphaComponent(0.25)
        aura.lineWidth = 3
        aura.name = "playerAura"
        player.addChild(aura)

        let body = SKPhysicsBody(circleOfRadius: 22)
        body.isDynamic = false
        body.categoryBitMask = PhysicsMask.player
        body.contactTestBitMask = PhysicsMask.good | PhysicsMask.bad
        body.collisionBitMask = PhysicsMask.none
        player.physicsBody = body
        addChild(player)
    }

    private func applySelectedSkin() {
        player.fillColor = selectedSkin.color
        if let aura = player.childNode(withName: "playerAura") as? SKShapeNode {
            aura.strokeColor = selectedSkin.color.withAlphaComponent(0.25)
        }
        refreshShopLabels()
    }

    private func setupMenu() {
        menuContainer.removeAllChildren()
        menuContainer.zPosition = 120

        let panel = SKShapeNode(rectOf: CGSize(width: size.width * 0.86, height: size.height * 0.58), cornerRadius: 32)
        panel.fillColor = SKColor(red: 0.08, green: 0.08, blue: 0.16, alpha: 0.92)
        panel.strokeColor = SKColor.cyan.withAlphaComponent(0.4)
        panel.lineWidth = 2
        panel.position = CGPoint(x: frame.midX, y: frame.midY)
        menuContainer.addChild(panel)

        let title = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        title.text = "⚡️ Core Runner"
        title.fontSize = 40
        title.position = CGPoint(x: frame.midX, y: frame.midY + 160)
        title.zPosition = 121
        menuContainer.addChild(title)

        menuContainer.addChild(makeButton(title: "Play", name: "menuStart", y: frame.midY + 70))
        menuContainer.addChild(makeButton(title: "Shop", name: "menuShop", y: frame.midY + 15))
        menuContainer.addChild(makeButton(title: "Settings", name: "menuSettings", y: frame.midY - 40))
        menuContainer.addChild(makeButton(title: "Difficulty: \(selectedMode.rawValue)", name: "menuMode", y: frame.midY - 95))

        let best = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
        best.text = "Best: \(bestScore)"
        best.fontSize = 24
        best.fontColor = .systemYellow
        best.name = "menuBestScore"
        best.position = CGPoint(x: frame.midX, y: frame.midY - 168)
        best.zPosition = 121
        menuContainer.addChild(best)

        addChild(menuContainer)
    }

    private func setupSettings() {
        settingsContainer.removeAllChildren()
        settingsContainer.zPosition = 130

        let panel = SKShapeNode(rectOf: CGSize(width: size.width * 0.82, height: size.height * 0.52), cornerRadius: 26)
        panel.fillColor = SKColor(red: 0.06, green: 0.07, blue: 0.15, alpha: 0.96)
        panel.strokeColor = SKColor.systemPurple.withAlphaComponent(0.55)
        panel.lineWidth = 2
        panel.position = CGPoint(x: frame.midX, y: frame.midY)
        settingsContainer.addChild(panel)

        let title = SKLabelNode(fontNamed: "AvenirNext-Bold")
        title.text = "Settings"
        title.fontSize = 34
        title.position = CGPoint(x: frame.midX, y: frame.midY + 130)
        settingsContainer.addChild(title)

        settingsContainer.addChild(makeButton(title: toggleText(prefix: "Sound", enabled: soundsEnabled), name: "toggleSound", y: frame.midY + 42))
        settingsContainer.addChild(makeButton(title: toggleText(prefix: "Vibration", enabled: vibrationEnabled), name: "toggleVibration", y: frame.midY - 16))
        settingsContainer.addChild(makeButton(title: "Back", name: "settingsBack", y: frame.midY - 100))

        settingsContainer.isHidden = true
        addChild(settingsContainer)
    }

    private func setupShop() {
        shopContainer.removeAllChildren()
        shopContainer.zPosition = 130

        let panel = SKShapeNode(rectOf: CGSize(width: size.width * 0.88, height: size.height * 0.68), cornerRadius: 26)
        panel.fillColor = SKColor(red: 0.07, green: 0.08, blue: 0.16, alpha: 0.96)
        panel.strokeColor = SKColor.systemYellow.withAlphaComponent(0.55)
        panel.lineWidth = 2
        panel.position = CGPoint(x: frame.midX, y: frame.midY)
        shopContainer.addChild(panel)

        let title = SKLabelNode(fontNamed: "AvenirNext-Bold")
        title.text = "Shop"
        title.fontSize = 34
        title.position = CGPoint(x: frame.midX, y: frame.midY + 190)
        shopContainer.addChild(title)

        let balance = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
        balance.name = "shopBalance"
        balance.fontSize = 22
        balance.fontColor = .systemYellow
        balance.position = CGPoint(x: frame.midX, y: frame.midY + 152)
        shopContainer.addChild(balance)

        for (index, skin) in Skin.allCases.enumerated() {
            let y = frame.midY + 80 - CGFloat(index) * 76
            shopContainer.addChild(makeSkinRow(for: skin, y: y))
        }

        shopContainer.addChild(makeButton(title: "Back", name: "shopBack", y: frame.midY - 190))
        shopContainer.isHidden = true
        addChild(shopContainer)
        refreshShopLabels()
    }

    private func makeSkinRow(for skin: Skin, y: CGFloat) -> SKNode {
        let row = SKNode()
        row.position = CGPoint(x: frame.midX, y: y)

        let container = SKShapeNode(rectOf: CGSize(width: size.width * 0.74, height: 60), cornerRadius: 14)
        container.fillColor = SKColor(red: 0.14, green: 0.17, blue: 0.29, alpha: 0.88)
        container.strokeColor = SKColor.white.withAlphaComponent(0.2)
        container.lineWidth = 1.2
        row.addChild(container)

        let colorDot = SKShapeNode(circleOfRadius: 12)
        colorDot.fillColor = skin.color
        colorDot.strokeColor = .white
        colorDot.lineWidth = 1.4
        colorDot.position = CGPoint(x: -size.width * 0.3, y: 0)
        row.addChild(colorDot)

        let nameLabel = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
        nameLabel.text = skin.title
        nameLabel.horizontalAlignmentMode = .left
        nameLabel.fontSize = 18
        nameLabel.position = CGPoint(x: -size.width * 0.25, y: -7)
        row.addChild(nameLabel)

        let actionButton = SKShapeNode(rectOf: CGSize(width: 120, height: 38), cornerRadius: 12)
        actionButton.fillColor = SKColor(red: 0.19, green: 0.22, blue: 0.36, alpha: 0.95)
        actionButton.strokeColor = .white.withAlphaComponent(0.25)
        actionButton.lineWidth = 1
        actionButton.name = "skinButton_\(skin.id)"
        actionButton.position = CGPoint(x: size.width * 0.24, y: 0)
        row.addChild(actionButton)

        let actionLabel = SKLabelNode(fontNamed: "AvenirNext-Bold")
        actionLabel.fontSize = 16
        actionLabel.verticalAlignmentMode = .center
        actionLabel.name = "skinLabel_\(skin.id)"
        actionLabel.position = CGPoint(x: 0, y: 0)
        actionButton.addChild(actionLabel)

        return row
    }

    private func refreshShopLabels() {
        if let balance = shopContainer.childNode(withName: "//shopBalance") as? SKLabelNode {
            balance.text = "Balance: \(totalCoins) coins"
        }

        for skin in Skin.allCases {
            if let label = shopContainer.childNode(withName: "//skinLabel_\(skin.id)") as? SKLabelNode {
                if selectedSkin == skin {
                    label.text = "Selected"
                } else if ownedSkins.contains(skin) {
                    label.text = "Use"
                } else {
                    label.text = "Buy \(skin.price)"
                }
            }
        }
    }

    private func showMenu() {
        isInMenu = true
        isGameOver = false
        player.alpha = 0
        statusLabel.text = ""
        menuContainer.isHidden = false
        settingsContainer.isHidden = true
        shopContainer.isHidden = true
        updateMenuLabels()
    }

    private func startGame() {
        isInMenu = false
        isGameOver = false
        score = 0
        coinsInRun = 0
        level = 1
        updateScoreLabel()
        updateCurrencyLabels()

        enumerateChildNodes(withName: "//*") { node, _ in
            if node.name == "bad" || node.name == "good" {
                node.removeFromParent()
            }
        }

        setupPlayer()
        player.alpha = 1
        statusLabel.text = "Tap left/right"
        modeLabel.text = "Mode: \(selectedMode.rawValue)"
        menuContainer.isHidden = true
        settingsContainer.isHidden = true
        shopContainer.isHidden = true

        spawnTimer?.invalidate()
        spawnTimer = Timer.scheduledTimer(withTimeInterval: selectedMode.spawnInterval, repeats: true) { [weak self] _ in
            self?.spawnObject()
        }

        run(.repeatForever(.sequence([
            .wait(forDuration: 1.0),
            .run { [weak self] in
                self?.tickScore()
            }
        ])), withKey: "passiveScore")
    }

    private func tickScore() {
        guard !isGameOver && !isInMenu else { return }
        score += 1 + level / 2
        let newLevel = (score / 35) + 1
        if newLevel > level {
            level = newLevel
            statusLabel.text = "Level \(level)"
            playFeedback(isPositive: true)
        }
        updateScoreLabel()
    }

    private func spawnObject() {
        guard !isGameOver && !isInMenu else { return }

        let dynamicBadChance = min(78, selectedMode.badChance + level * 2)
        let isBad = Int.random(in: 0..<100) < dynamicBadChance
        let radius: CGFloat = isBad ? CGFloat.random(in: 19...24) : CGFloat.random(in: 12...16)

        let node = SKShapeNode(circleOfRadius: radius)
        node.fillColor = isBad ? .systemRed : .systemYellow
        node.strokeColor = isBad ? .white : .orange
        node.lineWidth = 2

        let lane = Int.random(in: 0..<laneCount)
        node.position = CGPoint(x: laneXPositions[lane], y: frame.maxY + 50)
        node.zPosition = 15
        node.name = isBad ? "bad" : "good"

        let body = SKPhysicsBody(circleOfRadius: radius)
        body.affectedByGravity = false
        body.categoryBitMask = isBad ? PhysicsMask.bad : PhysicsMask.good
        body.contactTestBitMask = PhysicsMask.player
        body.collisionBitMask = PhysicsMask.none
        let speedBoost = CGFloat(level - 1) * 18
        let randomSpread: CGFloat = isBad ? 70 : 40
        body.velocity = CGVector(dx: 0, dy: -(selectedMode.baseSpeed + speedBoost + CGFloat.random(in: 0...randomSpread)))
        body.linearDamping = 0
        node.physicsBody = body

        if isBad && level > 2 && Bool.random() {
            let warning = SKShapeNode(circleOfRadius: radius + 10)
            warning.strokeColor = SKColor.red.withAlphaComponent(0.35)
            warning.fillColor = .clear
            warning.lineWidth = 2
            warning.name = "halo"
            node.addChild(warning)
            warning.run(.repeatForever(.sequence([
                .scale(to: 1.12, duration: 0.2),
                .scale(to: 1.0, duration: 0.2)
            ])))
        }

        addChild(node)

        node.run(.sequence([
            .wait(forDuration: 4.6),
            .removeFromParent()
        ]))
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)

        if isInMenu {
            handleMenuTap(at: location)
            return
        }

        if isGameOver {
            showMenu()
            return
        }

        if location.x < frame.midX {
            currentLane = max(0, currentLane - 1)
        } else {
            currentLane = min(laneCount - 1, currentLane + 1)
        }

        let move = SKAction.moveTo(x: laneXPositions[currentLane], duration: 0.1)
        move.timingMode = .easeOut
        player.run(move)

        let tilt = SKAction.sequence([
            .scaleX(to: 1.08, y: 0.92, duration: 0.05),
            .scaleX(to: 1.0, y: 1.0, duration: 0.05)
        ])
        player.run(tilt)
    }

    private func handleMenuTap(at point: CGPoint) {
        let tappedNodes = nodes(at: point)
        let names = tappedNodes.compactMap { $0.name }

        if names.contains("menuStart") {
            playTapSound()
            startGame()
        } else if names.contains("menuShop") {
            playTapSound()
            menuContainer.isHidden = true
            shopContainer.isHidden = false
            settingsContainer.isHidden = true
            refreshShopLabels()
        } else if names.contains("menuSettings") {
            playTapSound()
            menuContainer.isHidden = true
            settingsContainer.isHidden = false
            shopContainer.isHidden = true
        } else if names.contains("menuMode") {
            playTapSound()
            cycleMode()
        } else if names.contains("settingsBack") {
            playTapSound()
            settingsContainer.isHidden = true
            menuContainer.isHidden = false
            updateMenuLabels()
        } else if names.contains("shopBack") {
            playTapSound()
            shopContainer.isHidden = true
            menuContainer.isHidden = false
            updateMenuLabels()
        } else if names.contains("toggleSound") {
            soundsEnabled.toggle()
            playTapSound()
            updateSettingsLabels()
        } else if names.contains("toggleVibration") {
            vibrationEnabled.toggle()
            playTapSound()
            updateSettingsLabels()
        } else if let selectedSkinId = names.first(where: { $0.hasPrefix("skinButton_") }) {
            playTapSound()
            handleSkinAction(buttonName: selectedSkinId)
        }
    }

    private func handleSkinAction(buttonName: String) {
        let skinId = buttonName.replacingOccurrences(of: "skinButton_", with: "")
        guard let skin = Skin(rawValue: skinId) else { return }

        if ownedSkins.contains(skin) {
            selectedSkin = skin
            return
        }

        guard totalCoins >= skin.price else {
            statusLabel.text = "Not enough coins"
            playFeedback(isPositive: false)
            return
        }

        totalCoins -= skin.price
        ownedSkins.insert(skin)
        saveOwnedSkins()
        selectedSkin = skin
        statusLabel.text = "\(skin.title) unlocked"
        playFeedback(isPositive: true)
    }

    private func cycleMode() {
        switch selectedMode {
        case .easy: selectedMode = .normal
        case .normal: selectedMode = .hard
        case .hard: selectedMode = .easy
        }
        updateMenuLabels()
    }

    private func updateMenuLabels() {
        if let modeLabel = menuContainer.childNode(withName: "//menuModeLabel") as? SKLabelNode {
            modeLabel.text = "Difficulty: \(selectedMode.rawValue)"
        }
        if let best = menuContainer.childNode(withName: "//menuBestScore") as? SKLabelNode {
            best.text = "Best: \(bestScore)"
        }
        modeLabel.text = "Mode: \(selectedMode.rawValue)"
        refreshShopLabels()
    }

    private func updateSettingsLabels() {
        if let soundLabel = settingsContainer.childNode(withName: "//toggleSoundLabel") as? SKLabelNode {
            soundLabel.text = toggleText(prefix: "Sound", enabled: soundsEnabled)
        }
        if let vibroLabel = settingsContainer.childNode(withName: "//toggleVibrationLabel") as? SKLabelNode {
            vibroLabel.text = toggleText(prefix: "Vibration", enabled: vibrationEnabled)
        }
    }

    func didBegin(_ contact: SKPhysicsContact) {
        let masks = contact.bodyA.categoryBitMask | contact.bodyB.categoryBitMask
        guard masks & PhysicsMask.player != 0 else { return }

        let otherBody = contact.bodyA.categoryBitMask == PhysicsMask.player ? contact.bodyB : contact.bodyA
        otherBody.node?.removeFromParent()

        if otherBody.categoryBitMask == PhysicsMask.good {
            score += 8 + level
            coinsInRun += 1
            updateScoreLabel()
            updateCurrencyLabels()
            player.run(.sequence([.scale(to: 1.25, duration: 0.07), .scale(to: 1.0, duration: 0.1)]))
            playFeedback(isPositive: true)
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

        bestScore = max(bestScore, score)

        let scoreReward = score / 20
        let totalReward = coinsInRun + scoreReward
        totalCoins += totalReward

        player.fillColor = .gray
        player.run(.repeat(.sequence([.fadeAlpha(to: 0.2, duration: 0.12), .fadeAlpha(to: 1.0, duration: 0.12)]), count: 4))

        statusLabel.text = "Game over • +\(totalReward) coins"
        playFeedback(isPositive: false)
        updateMenuLabels()
    }

    private func updateScoreLabel() {
        scoreLabel.text = "Score: \(score)"
    }

    private func updateCurrencyLabels() {
        if isInMenu || isGameOver {
            coinLabel.text = "Coins: \(totalCoins)"
        } else {
            coinLabel.text = "Coins: \(totalCoins) (+\(coinsInRun))"
        }
    }

    private func makeButton(title: String, name: String, y: CGFloat) -> SKNode {
        let container = SKNode()
        container.name = name
        container.position = CGPoint(x: frame.midX, y: y)

        let button = SKShapeNode(rectOf: CGSize(width: size.width * 0.62, height: 48), cornerRadius: 14)
        button.fillColor = SKColor(red: 0.14, green: 0.17, blue: 0.29, alpha: 0.9)
        button.strokeColor = SKColor.white.withAlphaComponent(0.25)
        button.lineWidth = 1.4
        button.name = name
        container.addChild(button)

        let label = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
        label.text = title
        label.fontSize = 20
        label.verticalAlignmentMode = .center
        label.name = "\(name)Label"
        container.addChild(label)

        return container
    }

    private func playTapSound() {
        guard soundsEnabled else { return }
        AudioServicesPlaySystemSound(1104)
    }

    private func playFeedback(isPositive: Bool) {
        if soundsEnabled {
            AudioServicesPlaySystemSound(isPositive ? 1110 : 1025)
        }
        guard vibrationEnabled else { return }

        if isPositive {
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
        } else {
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.error)
        }
    }

    private func toggleText(prefix: String, enabled: Bool) -> String {
        "\(prefix): \(enabled ? \"ON\" : \"OFF\")"
    }

    deinit {
        spawnTimer?.invalidate()
    }
}
