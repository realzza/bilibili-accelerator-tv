//
//  VideoPlayerRouteInfoViewController.swift
//  BilibiliLive
//

import BiliAccelerator
import SnapKit
import UIKit

/// The 线路 tab of the player's info panel, after the accelerator userscript's panel (v0.5.1): how
/// playback is going beside a status dot, a download speed card with a smooth chart, and a
/// button that races the next fragment on two other hosts. While the tab is on screen it moves as
/// the panel does: the dot shows what is in progress, and the chart glides between samples.
final class VideoPlayerRouteInfoViewController: UIViewController {
    private let statusDot = StatusDotView()
    private let healthLabel = UILabel()
    private let hostLabel = UILabel()
    private let switchesLabel = UILabel()

    private let speedTitleLabel = UILabel()
    private let speedValueLabel = UILabel()
    private let chart = SpeedChartView()
    private let peakLabel = UILabel()
    private let bufferLabel = UILabel()

    private let testButton = UIButton(configuration: .capsule())
    private let testCaption = UILabel()
    private let content = UIStackView()
    /// The info panel draws no background behind a custom tab, and the gray text needs one over
    /// a bright picture.
    private let card = UIVisualEffectView(effect: UIBlurEffect(style: .dark))
    private let messageLabel = UILabel()
    private var timer: Timer?
    /// Redraws the chart and the readout every frame while the tab is on screen.
    private var displayLink: CADisplayLink?
    private var isShowing = false
    private var status: RouteStatus?
    /// The speed shown, eased toward each new sample as the userscript does, and the value before
    /// it: the readout counts from one to the other over the first 0.6 s of a sample.
    private var shownMbps: Double?
    private var previousMbps: Double?
    private var sampleCount: Int?
    private var sampleAt: CFTimeInterval = 0
    private var shownText: String?
    private var peakMbps: Double = 0

    init() {
        super.init(nibName: nil, bundle: nil)
        title = "线路"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var preferredFocusEnvironments: [UIFocusEnvironment] {
        [testButton]
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        preferredContentSize = CGSize(width: 0, height: 290)
        view.backgroundColor = .clear

        // Status: the dot in a soft halo, then what it means.
        healthLabel.font = .systemFont(ofSize: 36, weight: .bold)
        healthLabel.textColor = Theme.textPrimary
        hostLabel.font = .systemFont(ofSize: 25)
        hostLabel.textColor = Theme.textSecondary
        switchesLabel.font = .systemFont(ofSize: 22)
        switchesLabel.textColor = Theme.textTertiary
        let statusText = UIStackView(arrangedSubviews: [healthLabel, hostLabel, switchesLabel])
        statusText.axis = .vertical
        statusText.alignment = .leading
        statusText.spacing = 8
        statusText.setCustomSpacing(12, after: healthLabel)
        let statusRow = UIStackView(arrangedSubviews: [statusDot, statusText])
        statusRow.spacing = 26
        statusRow.alignment = .center

        // Speed card: title and the number in the accent, the chart, the peak and the buffer.
        speedTitleLabel.text = "下载速度"
        speedTitleLabel.font = .systemFont(ofSize: 24, weight: .semibold)
        speedTitleLabel.textColor = Theme.textSecondary
        speedValueLabel.textAlignment = .right
        let speedTop = UIStackView(arrangedSubviews: [speedTitleLabel, speedValueLabel])
        speedTop.alignment = .lastBaseline
        speedTop.distribution = .equalSpacing
        peakLabel.font = .systemFont(ofSize: 21)
        peakLabel.textColor = Theme.textTertiary
        bufferLabel.font = .systemFont(ofSize: 21)
        bufferLabel.textColor = Theme.textTertiary
        bufferLabel.textAlignment = .right
        let speedFoot = UIStackView(arrangedSubviews: [peakLabel, bufferLabel])
        speedFoot.distribution = .equalSpacing
        let speedStack = UIStackView(arrangedSubviews: [speedTop, chart, speedFoot])
        speedStack.axis = .vertical
        speedStack.spacing = 10
        chart.snp.makeConstraints { make in
            make.height.equalTo(96)
        }
        let speedCard = UIView()
        speedCard.backgroundColor = UIColor(white: 1, alpha: 0.07)
        speedCard.layer.cornerRadius = 26
        speedCard.layer.cornerCurve = .continuous
        speedCard.layer.borderWidth = 1
        speedCard.layer.borderColor = UIColor(white: 1, alpha: 0.1).cgColor
        speedCard.addSubview(speedStack)
        speedStack.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(UIEdgeInsets(top: 18, left: 28, bottom: 16, right: 28))
        }

        var config = testButton.configuration
        config?.title = "测试其他线路"
        config?.image = UIImage(systemName: "arrow.triangle.2.circlepath")
        config?.imagePadding = 12
        config?.contentInsets = NSDirectionalEdgeInsets(top: 20, leading: 36, bottom: 20, trailing: 36)
        config?.setTitleFont(.systemFont(ofSize: 26, weight: .semibold))
        testButton.configuration = config
        testButton.addAction(UIAction { [weak self] _ in self?.runTest() }, for: .primaryActionTriggered)
        testCaption.font = .systemFont(ofSize: 21)
        testCaption.textColor = Theme.textTertiary
        testCaption.numberOfLines = 2
        let actionColumn = UIStackView(arrangedSubviews: [testButton, testCaption])
        actionColumn.axis = .vertical
        actionColumn.alignment = .leading
        actionColumn.spacing = 14

        let statusWrapper = Self.centeredVertically(statusRow)
        let actionWrapper = Self.centeredVertically(actionColumn)
        content.addArrangedSubview(statusWrapper)
        content.addArrangedSubview(speedCard)
        content.addArrangedSubview(actionWrapper)
        content.axis = .horizontal
        content.spacing = 48
        statusWrapper.snp.makeConstraints { make in
            make.width.equalTo(actionWrapper).multipliedBy(1.25)
        }
        speedCard.snp.makeConstraints { make in
            make.width.equalTo(actionWrapper).multipliedBy(1.9)
        }
        card.layer.cornerRadius = 36
        card.layer.cornerCurve = .continuous
        card.clipsToBounds = true
        view.addSubview(card)
        card.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        card.contentView.addSubview(content)
        content.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(40)
            make.top.bottom.equalToSuperview().inset(22)
        }

        messageLabel.font = .systemFont(ofSize: 28, weight: .medium)
        messageLabel.textColor = Theme.textSecondary
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 2
        view.addSubview(messageLabel)
        messageLabel.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.leading.greaterThanOrEqualToSuperview().offset(40)
        }
        render(nil)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        isShowing = true
        refresh()
        timer?.invalidate()
        // Samples come once a second; reading four times as often starts each one's motion soon
        // after it arrives.
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        isShowing = false
        timer?.invalidate()
        timer = nil
        syncMotion()
    }

    private func refresh() {
        Accelerator.shared.routeStatus { [weak self] status in
            self?.render(status)
        }
    }

    private func runTest() {
        guard status?.test != .pending else { return }
        Accelerator.shared.testOtherHosts()
        refresh()
    }

    private func render(_ status: RouteStatus?) {
        self.status = status
        guard let status else {
            content.isHidden = true
            messageLabel.isHidden = false
            messageLabel.text = Settings.acceleratorEnabled ? "暂无线路数据" : "线路加速已关闭，可在设置中打开"
            syncMotion()
            return
        }
        content.isHidden = false
        messageLabel.isHidden = true

        let name = Self.name(of: status.host)
        if status.test == .pending {
            statusDot.state = .testing
            healthLabel.text = "正在测试其他线路…"
        } else if status.isStalled {
            statusDot.state = .buffering
            healthLabel.text = "正在缓冲"
        } else if let mbps = status.sustainedMbps, let required = status.requiredMbps, mbps < required * 1.2,
                  (status.bufferSeconds ?? 0) < 30
        {
            statusDot.state = .slow
            healthLabel.text = "网速偏慢"
        } else {
            statusDot.state = .smooth
            healthLabel.text = "播放流畅"
        }
        hostLabel.text = status.isIssuedHost ? "原生线路 · \(name)" : "已切换到 \(name)"
        switchesLabel.text = status.switches == 0 ? "本视频未切换线路" : "本视频切换了 \(status.switches) 次线路"

        // On each new sample, ease toward the reading, as the userscript's display does.
        let reading = status.currentMbps ?? status.sustainedMbps
        if status.sampleCount != sampleCount {
            sampleCount = status.sampleCount
            sampleAt = CACurrentMediaTime()
            previousMbps = shownMbps
            if let reading {
                shownMbps = shownMbps.map { $0 + (reading - $0) * 0.45 } ?? reading
            }
        } else if shownMbps == nil, let reading {
            shownMbps = reading
        }
        peakMbps = max(peakMbps, status.recentMbps.max() ?? 0, status.currentMbps ?? 0)
        peakLabel.text = peakMbps > 0 ? String(format: "峰值 %.1f Mbps", peakMbps) : nil
        bufferLabel.text = status.bufferSeconds.map { "缓冲 \(Int($0.rounded())) 秒" }
        chart.update(values: status.recentMbps, reference: status.requiredMbps, sampleAt: sampleAt)
        syncMotion()
        updateReadout()

        switch status.test {
        case .none:
            testButton.configuration?.title = "测试其他线路"
            testCaption.text = "只在明显更快时切换，不保存设置"
        case .pending:
            testButton.configuration?.title = "正在测试…"
            testCaption.text = "下一段视频由两条其他线路同时下载"
        case .moved:
            testButton.configuration?.title = "测试其他线路"
            testCaption.text = "已换到更快的线路"
        case .stayed:
            testButton.configuration?.title = "测试其他线路"
            testCaption.text = "没有明显更快的线路，保持不变"
        }
    }

    /// Runs the frame loop while the tab is on screen, as the userscript does while its panel is
    /// open, and never with Reduce Motion on. The dot moves only while something is in progress:
    /// smooth playback, a test, or the player waiting for data. A slow network is a standing
    /// condition and stays still.
    private func syncMotion() {
        let run = isShowing && status != nil && !UIAccessibility.isReduceMotionEnabled
        let state = statusDot.state
        let live = run && status?.isPlaying == true && state == .smooth
        statusDot.isMoving = live || (run && (state == .testing || state == .buffering))
        chart.isLive = live
        if run, displayLink == nil {
            let link = CADisplayLink(target: FrameTarget(self), selector: #selector(FrameTarget.frame))
            link.add(to: .main, forMode: .common)
            displayLink = link
        } else if !run, let displayLink {
            displayLink.invalidate()
            self.displayLink = nil
        }
        chart.isRunning = displayLink != nil
    }

    fileprivate func frame() {
        chart.redraw()
        updateReadout()
    }

    /// The speed counts up or down to the new sample over the first 0.6 s of it instead of
    /// jumping. Without the frame loop it shows the new value at once.
    private func updateReadout() {
        var mbps = shownMbps
        if displayLink != nil, let target = shownMbps, let previous = previousMbps {
            let k = min(1, (CACurrentMediaTime() - sampleAt) / 0.6)
            mbps = previous + (target - previous) * (1 - pow(1 - k, 3))
        }
        let text = mbps.map { String(format: "%.1f", $0) } ?? "—"
        guard text != shownText else { return }
        shownText = text
        let value = NSMutableAttributedString(string: text,
                                              attributes: [.font: UIFont.monospacedDigitSystemFont(ofSize: 52, weight: .bold),
                                                           .foregroundColor: Theme.accent])
        value.append(NSAttributedString(string: " Mbps", attributes: [.font: UIFont.systemFont(ofSize: 24, weight: .semibold),
                                                                      .foregroundColor: Theme.textTertiary]))
        speedValueLabel.attributedText = value
    }

    /// `大陆 · 阿里云` for a mirror, the first label of the name for a host it doesn't know.
    static func name(of host: String) -> String {
        let lower = host.lowercased()
        let vendor: String
        if lower.contains("akam") {
            vendor = "Akamai"
        } else if lower.contains("ali") || lower.contains("oss") {
            vendor = "阿里云"
        } else if lower.contains("cos") || lower.contains("-tx") {
            vendor = "腾讯云"
        } else if lower.contains("hw") {
            vendor = "华为云"
        } else if lower.contains("bd") || lower.contains("bos") {
            vendor = "百度云"
        } else if lower.hasPrefix("cn-") || lower.contains("mcdn") {
            vendor = "边缘节点"
        } else {
            vendor = lower.split(separator: ".").first.map(String.init) ?? lower
        }
        return "\(RouteStatus.isOverseas(host) ? "海外" : "大陆") · \(vendor)"
    }

    private static func centeredVertically(_ view: UIView) -> UIView {
        let wrapper = UIView()
        wrapper.addSubview(view)
        view.snp.makeConstraints { make in
            make.leading.equalToSuperview()
            make.trailing.lessThanOrEqualToSuperview()
            make.centerY.equalToSuperview()
            make.top.greaterThanOrEqualToSuperview()
        }
        return wrapper
    }
}

/// A display link holds its target strongly; this one lets the controller go.
private final class FrameTarget {
    private weak var owner: VideoPlayerRouteInfoViewController?

    init(_ owner: VideoPlayerRouteInfoViewController) {
        self.owner = owner
    }

    @objc func frame() {
        owner?.frame()
    }
}

/// The status dot: a colored dot in a soft halo of the same color. While `isMoving`, it shows what
/// is in progress as the userscript's dot does: two rings ripple out while playback is smooth, an
/// arc circles it during a test, and a ring closes in while the player buffers.
private final class StatusDotView: UIView {
    enum State {
        case smooth
        case testing
        case buffering
        case slow
    }

    private static let good = UIColor(red: 46 / 255, green: 211 / 255, blue: 160 / 255, alpha: 1)
    private static let warning = UIColor(red: 240 / 255, green: 168 / 255, blue: 56 / 255, alpha: 1)

    var state = State.smooth {
        didSet {
            guard state != oldValue else { return }
            UIView.animate(withDuration: 0.3) { self.updateColors() }
            updateMotion()
        }
    }

    var isMoving = false {
        didSet { updateMotion() }
    }

    private let dot = UIView()
    private let rings = [CALayer(), CALayer()]
    private let arc = CAGradientLayer()
    private let arcMask = CAShapeLayer()
    /// The motion on screen, so it is only rebuilt when it changes or the system dropped it.
    private var shownMotion: State?

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.cornerRadius = 40
        for ring in rings {
            ring.cornerRadius = 40
            ring.opacity = 0
            layer.addSublayer(ring)
        }
        // A conic gradient that fades in toward its head, cut to a thin ring just outside the halo.
        arc.type = .conic
        arc.startPoint = CGPoint(x: 0.5, y: 0.5)
        arc.endPoint = CGPoint(x: 0.5, y: 0)
        arc.locations = [0, 0.25, 1]
        arcMask.fillColor = nil
        arcMask.strokeColor = UIColor.black.cgColor
        arcMask.lineWidth = 4.5
        arc.mask = arcMask
        arc.isHidden = true
        layer.addSublayer(arc)
        dot.layer.cornerRadius = 12
        addSubview(dot)
        snp.makeConstraints { make in
            make.size.equalTo(80)
        }
        dot.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.size.equalTo(24)
        }
        updateColors()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        for ring in rings {
            ring.frame = bounds
        }
        arc.frame = bounds.insetBy(dx: -7, dy: -7)
        arcMask.frame = arc.bounds
        arcMask.path = UIBezierPath(ovalIn: arc.bounds.insetBy(dx: arcMask.lineWidth / 2, dy: arcMask.lineWidth / 2)).cgPath
    }

    private func updateColors() {
        let color = state == .smooth ? Self.good : Self.warning
        dot.backgroundColor = color
        backgroundColor = color.withAlphaComponent(0.18)
    }

    private func updateMotion() {
        let motion = isMoving && state != .slow ? state : nil
        let running = layer.animation(forKey: "motion") != nil
        guard motion != shownMotion || (motion != nil && !running) else { return }
        shownMotion = motion
        layer.removeAnimation(forKey: "motion")
        dot.layer.removeAllAnimations()
        rings.forEach { $0.removeAllAnimations() }
        arc.removeAllAnimations()
        arc.isHidden = true
        guard let motion else { return }
        // A marker for whether the system dropped the motion, as it does when the app leaves the
        // foreground.
        let marker = CABasicAnimation(keyPath: "zPosition")
        marker.duration = .infinity
        layer.add(marker, forKey: "motion")

        let now = layer.convertTime(CACurrentMediaTime(), from: nil)
        switch motion {
        case .smooth:
            // Two rings leave the dot half a cycle apart while the dot breathes.
            let outward = CAMediaTimingFunction(controlPoints: 0.2, 0.6, 0.35, 1)
            for (index, ring) in rings.enumerated() {
                ring.backgroundColor = Self.good.cgColor
                let ripple = Self.loop(duration: 2.8, [
                    Self.keyframes("opacity", [0.42, 0, 0], at: [0, 0.75, 1], timing: [outward, .linear]),
                    Self.keyframes("transform.scale", [0.3, 1.3, 1.3], at: [0, 0.75, 1], timing: [outward, .linear]),
                ])
                ripple.beginTime = now + 1.4 * Double(index)
                ring.add(ripple, forKey: "ripple")
            }
            dot.layer.add(Self.loop(duration: 2.8, [
                Self.keyframes("transform.scale", [1, 1.14, 1], at: [0, 0.5, 1], timing: [.easeInEaseOut, .easeInEaseOut]),
            ]), forKey: "breathe")
        case .testing:
            // An arc circles the dot, as a spinner would.
            arc.colors = [UIColor.clear.cgColor, UIColor.clear.cgColor, Self.warning.cgColor]
            arc.isHidden = false
            let spin = CABasicAnimation(keyPath: "transform.rotation.z")
            spin.fromValue = 0
            spin.toValue = Double.pi * 2
            spin.duration = 1
            spin.repeatCount = .infinity
            arc.add(spin, forKey: "spin")
        case .buffering:
            // A ring closes in on the dot, the smooth ripple in reverse, and the dot dims until
            // it arrives.
            let inward = CAMediaTimingFunction(controlPoints: 0.45, 0, 0.85, 0.6)
            rings[0].backgroundColor = Self.warning.cgColor
            rings[0].add(Self.loop(duration: 1.5, [
                Self.keyframes("opacity", [0, 0.34, 0.12], at: [0, 0.25, 1], timing: [inward, inward]),
                Self.keyframes("transform.scale", [1.2, 0.3], at: [0, 1], timing: [inward]),
            ]), forKey: "gather")
            dot.layer.add(Self.loop(duration: 1.5, [
                Self.keyframes("opacity", [1, 0.5, 1], at: [0, 0.55, 1], timing: [.easeInEaseOut, .easeInEaseOut]),
            ]), forKey: "dim")
        case .slow:
            break
        }
    }

    private static func keyframes(_ keyPath: String, _ values: [Double], at times: [Double],
                                  timing: [CAMediaTimingFunction]) -> CAKeyframeAnimation
    {
        let animation = CAKeyframeAnimation(keyPath: keyPath)
        animation.values = values
        animation.keyTimes = times.map { NSNumber(value: $0) }
        animation.timingFunctions = timing
        return animation
    }

    private static func loop(duration: CFTimeInterval, _ animations: [CAAnimation]) -> CAAnimationGroup {
        let group = CAAnimationGroup()
        group.animations = animations
        animations.forEach { $0.duration = duration }
        group.duration = duration
        group.repeatCount = .infinity
        return group
    }
}

fileprivate extension CAMediaTimingFunction {
    static let linear = CAMediaTimingFunction(name: .linear)
    static let easeInEaseOut = CAMediaTimingFunction(name: .easeInEaseOut)
}

/// The download speed over the last 30 seconds, drawn as the userscript draws it: a 3-point
/// moving average through a monotone cubic curve, a gradient fill under it, a dot on the latest
/// value, and a y-axis that eases toward a round maximum. The video's bitrate is dashed for scale.
///
/// While `isRunning`, the chart is redrawn every frame and glides between the one-second samples:
/// the curve ends at a point that travels from the previous sample to the newest one, and the
/// oldest sample slides out on the left. While `isLive` (smooth playback) a highlight runs along
/// the line and the endpoint sends out a fading ring.
private final class SpeedChartView: UIView {
    /// Samples across the chart once it is full. The status keeps one more, which slides out.
    private static let shownSamples = 30
    private static let glintPeriod: CFTimeInterval = 3.2
    private static let pulsePeriod: CFTimeInterval = 2
    private static let dotRadius: CGFloat = 7
    /// Room right of the plot for the endpoint dot.
    private static let endRoom: CGFloat = 12
    /// Half the width of the highlight's glow.
    private static let glintBand: CGFloat = 92

    /// Clips the curve, its fill and the highlight to the plot.
    private let plot = CALayer()
    private let fill = CAGradientLayer()
    private let fillMask = CAShapeLayer()
    private let line = CAShapeLayer()
    /// The highlight: a wide accent glow under a white core, each a gradient cut to the line.
    private let glow = CAGradientLayer()
    private let glowMask = CAShapeLayer()
    private let core = CAGradientLayer()
    private let coreMask = CAShapeLayer()
    private let reference = CAShapeLayer()
    private let pulse = CAShapeLayer()
    private let leadDot = CAShapeLayer()
    private let referenceLabel = UILabel()
    private let waitingLabel = UILabel()
    private var rawValues: [Double] = []
    private var referenceValue: Double?
    /// When the newest sample arrived.
    private var sampleAt: CFTimeInterval = 0
    /// The y-axis maximum shown, eased toward a round ceiling so rescaling glides.
    private var shownMax: Double = 0
    private var maxEasedAt: CFTimeInterval = 0

    var isRunning = false
    var isLive = false {
        didSet {
            guard isLive != oldValue else { return }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            [glow, core, pulse].forEach { $0.isHidden = !isLive }
            CATransaction.commit()
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        let accent = Theme.accent
        plot.masksToBounds = true
        layer.addSublayer(plot)
        fill.colors = [accent.withAlphaComponent(0.32).cgColor, accent.withAlphaComponent(0.02).cgColor]
        fill.mask = fillMask
        plot.addSublayer(fill)
        reference.strokeColor = UIColor(white: 1, alpha: 0.28).cgColor
        reference.lineWidth = 2
        reference.lineDashPattern = [6, 6]
        reference.fillColor = nil
        layer.insertSublayer(reference, below: plot)
        line.strokeColor = accent.cgColor
        line.lineWidth = 4
        line.lineJoin = .round
        line.lineCap = .round
        line.fillColor = nil
        plot.addSublayer(line)
        for (gradient, mask, color, alpha, width) in [(glow, glowMask, accent, 0.38, 12.0), (core, coreMask, UIColor.white, 0.6, 4.0)] {
            gradient.colors = [color.withAlphaComponent(0).cgColor, color.withAlphaComponent(alpha).cgColor, color.withAlphaComponent(0).cgColor]
            mask.fillColor = nil
            mask.strokeColor = UIColor.black.cgColor
            mask.lineWidth = width
            mask.lineJoin = .round
            mask.lineCap = .round
            gradient.mask = mask
            gradient.isHidden = true
            plot.addSublayer(gradient)
        }
        pulse.isHidden = true
        layer.addSublayer(pulse)
        leadDot.fillColor = accent.cgColor
        leadDot.strokeColor = UIColor(white: 0.12, alpha: 1).cgColor
        leadDot.lineWidth = 3
        layer.addSublayer(leadDot)
        referenceLabel.font = .systemFont(ofSize: 18, weight: .medium)
        referenceLabel.textColor = UIColor(white: 1, alpha: 0.45)
        addSubview(referenceLabel)
        waitingLabel.text = "等待播放…"
        waitingLabel.font = .systemFont(ofSize: 22)
        waitingLabel.textColor = Theme.textTertiary
        waitingLabel.textAlignment = .center
        addSubview(waitingLabel)
        waitingLabel.snp.makeConstraints { make in
            make.center.equalToSuperview()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(values: [Double], reference: Double?, sampleAt: CFTimeInterval) {
        rawValues = values
        referenceValue = reference
        self.sampleAt = sampleAt
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        redraw()
    }

    /// How far the newest sample's second has run, 0...1. Without the frame loop it is 1: the
    /// newest sample sits on the right edge and the chart moves once a second.
    private func tickPhase(_ now: CFTimeInterval) -> CGFloat {
        guard isRunning else { return 1 }
        return CGFloat(max(0, min(1, now - sampleAt)))
    }

    func redraw() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        let plotWidth = max(bounds.width - Self.endRoom, 1)
        plot.frame = CGRect(x: 0, y: 0, width: plotWidth, height: bounds.height)
        for sublayer in [fill, fillMask, line, glow, glowMask, core, coreMask] as [CALayer] {
            sublayer.frame = plot.bounds
        }
        for sublayer in [reference, pulse, leadDot] as [CALayer] {
            sublayer.frame = bounds
        }

        let raw = rawValues
        var values = Self.smoothed(raw)
        let n = values.count
        let hasData = n >= 2
        waitingLabel.isHidden = hasData
        [plot, leadDot].forEach { $0.isHidden = !hasData }
        pulse.isHidden = !hasData || !isLive
        guard hasData, bounds.width > 0 else {
            reference.path = nil
            referenceLabel.isHidden = true
            return
        }
        let now = CACurrentMediaTime()
        let p = tickPhase(now)
        // A new sample turns the previous endpoint into an interior point, which the moving
        // average would shift at once. Blend that in over the second so the endpoint leaves from
        // exactly where it was.
        if n >= 3 {
            values[n - 2] = raw[n - 2] + (values[n - 2] - raw[n - 2]) * Double(p)
        }

        // The rate is per second, so it holds whatever the frame rate is.
        let dataMax = max(values.max() ?? 0, (referenceValue ?? 0) * 1.25, 1)
        let target = Self.niceCeil(dataMax)
        let elapsed = maxEasedAt > 0 ? min(1, now - maxEasedAt) : 1
        maxEasedAt = now
        shownMax = shownMax > 0 ? shownMax + (target - shownMax) * (1 - pow(0.75, elapsed)) : target
        let top = max(shownMax, 1)
        let padTop: CGFloat = 10
        let padBottom: CGFloat = 4
        let height = bounds.height - padTop - padBottom
        func y(_ value: Double) -> CGFloat {
            bounds.height - padBottom - CGFloat(min(value, top) / top) * height
        }
        // The curve ends where the last segment crosses the plot's right edge, which moves from
        // the previous sample to the newest one over the second. While the series fills, it
        // stretches across the width; once it holds one sample more than the chart shows, the
        // window slides instead.
        let left: CGFloat = n > Self.shownSamples ? p : 0
        let right = max(CGFloat(n - 2) + p, 0)
        let step = plotWidth / max(right - left, 0.05)
        let xs = values.indices.map { (CGFloat($0) - left) * step }
        let ys = values.map(y)
        let tangents = Self.monotoneTangents(xs: xs, ys: ys)
        let curve = Self.curve(xs: xs, ys: ys, tangents: tangents)
        line.path = curve.cgPath

        let area = curve.copy() as! UIBezierPath
        area.addLine(to: CGPoint(x: xs[n - 1], y: bounds.height))
        area.addLine(to: CGPoint(x: xs[0], y: bounds.height))
        area.close()
        fillMask.path = area.cgPath

        // The last segment at p: x is linear in the Bézier parameter here, so this is the plot's edge.
        var end = CGPoint(x: plotWidth, y: ys[n - 1])
        if p < 1 {
            let dx = step / 3
            let c0 = ys[n - 2] + tangents[n - 2] * dx
            let c1 = ys[n - 1] - tangents[n - 1] * dx
            let q = 1 - p
            end.y = q * q * q * ys[n - 2] + 3 * q * q * p * c0 + 3 * q * p * p * c1 + p * p * p * ys[n - 1]
        }
        leadDot.path = UIBezierPath(arcCenter: end, radius: Self.dotRadius, startAngle: 0, endAngle: .pi * 2, clockwise: true).cgPath

        if isLive {
            // A highlight runs along the line toward the endpoint.
            let band = Self.glintBand
            let gx = -band + CGFloat(now.truncatingRemainder(dividingBy: Self.glintPeriod) / Self.glintPeriod) * (plotWidth + band * 2)
            for (gradient, mask, half) in [(glow, glowMask, band), (core, coreMask, band / 2)] {
                mask.path = curve.cgPath
                gradient.startPoint = CGPoint(x: (gx - half) / plotWidth, y: 0.5)
                gradient.endPoint = CGPoint(x: (gx + half) / plotWidth, y: 0.5)
            }
            // The endpoint sends out a fading ring.
            let k = now.truncatingRemainder(dividingBy: Self.pulsePeriod) / Self.pulsePeriod
            let eased = CGFloat(1 - pow(1 - k, 3))
            pulse.path = UIBezierPath(arcCenter: end, radius: Self.dotRadius * (1 + 1.125 * eased),
                                      startAngle: 0, endAngle: .pi * 2, clockwise: true).cgPath
            pulse.fillColor = Theme.accent.withAlphaComponent(0.4 * (1 - eased)).cgColor
        }

        if let referenceValue, referenceValue > 0 {
            let ry = y(referenceValue)
            let dashed = UIBezierPath()
            dashed.move(to: CGPoint(x: 0, y: ry))
            dashed.addLine(to: CGPoint(x: bounds.width, y: ry))
            reference.path = dashed.cgPath
            referenceLabel.text = String(format: "码率 %.1f", referenceValue)
            referenceLabel.sizeToFit()
            referenceLabel.frame.origin = CGPoint(x: 0, y: max(0, ry - referenceLabel.bounds.height - 2))
            referenceLabel.isHidden = false
        } else {
            reference.path = nil
            referenceLabel.isHidden = true
        }
    }

    /// Light 3-point moving average, to calm per-second jitter before the curve.
    private static func smoothed(_ values: [Double]) -> [Double] {
        guard values.count >= 3 else { return values }
        var out = values
        for i in 1..<(values.count - 1) {
            out[i] = (values[i - 1] + values[i] * 2 + values[i + 1]) / 4
        }
        return out
    }

    /// Rounds up to 1, 2 or 5 times a power of ten.
    private static func niceCeil(_ value: Double) -> Double {
        guard value > 0 else { return 1 }
        let power = pow(10, floor(log10(value)))
        let n = value / power
        let step: Double = n <= 1 ? 1 : n <= 2 ? 2 : n <= 5 ? 5 : 10
        return step * power
    }

    /// Tangents for a curve through every point with no overshoot (Fritsch–Carlson monotone cubic).
    private static func monotoneTangents(xs: [CGFloat], ys: [CGFloat]) -> [CGFloat] {
        let n = xs.count
        guard n >= 2 else { return [CGFloat](repeating: 0, count: n) }
        var slopes = [CGFloat](repeating: 0, count: n - 1)
        for i in 0..<(n - 1) {
            slopes[i] = (ys[i + 1] - ys[i]) / (xs[i + 1] - xs[i])
        }
        var tangents = [CGFloat](repeating: 0, count: n)
        tangents[0] = slopes[0]
        tangents[n - 1] = slopes[n - 2]
        if n > 2 {
            for i in 1..<(n - 1) {
                tangents[i] = slopes[i - 1] * slopes[i] <= 0 ? 0 : (slopes[i - 1] + slopes[i]) / 2
            }
        }
        for i in 0..<(n - 1) {
            if slopes[i] == 0 {
                tangents[i] = 0
                tangents[i + 1] = 0
                continue
            }
            let a = tangents[i] / slopes[i]
            let b = tangents[i + 1] / slopes[i]
            let s = a * a + b * b
            if s > 9 {
                let tau = 3 / sqrt(s)
                tangents[i] = tau * a * slopes[i]
                tangents[i + 1] = tau * b * slopes[i]
            }
        }
        return tangents
    }

    private static func curve(xs: [CGFloat], ys: [CGFloat], tangents: [CGFloat]) -> UIBezierPath {
        let path = UIBezierPath()
        path.move(to: CGPoint(x: xs[0], y: ys[0]))
        for i in 0..<(xs.count - 1) {
            let dx = (xs[i + 1] - xs[i]) / 3
            path.addCurve(to: CGPoint(x: xs[i + 1], y: ys[i + 1]),
                          controlPoint1: CGPoint(x: xs[i] + dx, y: ys[i] + tangents[i] * dx),
                          controlPoint2: CGPoint(x: xs[i + 1] - dx, y: ys[i + 1] - tangents[i + 1] * dx))
        }
        return path
    }
}
