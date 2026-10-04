//
//  VideoPlayerRouteInfoViewController.swift
//  BilibiliLive
//

import BiliAccelerator
import SnapKit
import UIKit

/// The 线路 tab of the player's info panel, after the accelerator userscript's panel: how
/// playback is going beside a status dot, a download speed card with a smooth chart, and a
/// button that races the next fragment on two other hosts.
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
    private var status: RouteStatus?
    /// The speed shown, eased toward each new reading as the userscript does, so it doesn't jump.
    private var shownMbps: Double?
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
        refresh()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        timer?.invalidate()
        timer = nil
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
            return
        }
        content.isHidden = false
        messageLabel.isHidden = true

        let name = Self.name(of: status.host)
        if status.isStalled {
            statusDot.tone = .warning
            healthLabel.text = "正在缓冲"
        } else if let mbps = status.sustainedMbps, let required = status.requiredMbps, mbps < required * 1.2,
                  (status.bufferSeconds ?? 0) < 30
        {
            statusDot.tone = .warning
            healthLabel.text = "网速偏慢"
        } else {
            statusDot.tone = .good
            healthLabel.text = "播放流畅"
        }
        hostLabel.text = status.isIssuedHost ? "原生线路 · \(name)" : "已切换到 \(name)"
        switchesLabel.text = status.switches == 0 ? "本视频未切换线路" : "本视频切换了 \(status.switches) 次线路"

        // Ease toward the new reading, as the userscript's display does.
        if let reading = status.currentMbps ?? status.sustainedMbps {
            shownMbps = shownMbps.map { $0 + (reading - $0) * 0.45 } ?? reading
        }
        peakMbps = max(peakMbps, status.recentMbps.max() ?? 0, status.currentMbps ?? 0)
        let value = NSMutableAttributedString(string: shownMbps.map { String(format: "%.1f", $0) } ?? "—",
                                              attributes: [.font: UIFont.monospacedDigitSystemFont(ofSize: 52, weight: .bold),
                                                           .foregroundColor: Theme.accent])
        value.append(NSAttributedString(string: " Mbps", attributes: [.font: UIFont.systemFont(ofSize: 24, weight: .semibold),
                                                                      .foregroundColor: Theme.textTertiary]))
        speedValueLabel.attributedText = value
        peakLabel.text = peakMbps > 0 ? String(format: "峰值 %.1f Mbps", peakMbps) : nil
        bufferLabel.text = status.bufferSeconds.map { "缓冲 \(Int($0.rounded())) 秒" }
        chart.update(values: status.recentMbps, reference: status.requiredMbps)

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

/// The status dot: a colored dot in a soft halo of the same color.
private final class StatusDotView: UIView {
    enum Tone {
        case good
        case warning
    }

    private static let good = UIColor(red: 46 / 255, green: 211 / 255, blue: 160 / 255, alpha: 1)
    private static let warning = UIColor(red: 240 / 255, green: 168 / 255, blue: 56 / 255, alpha: 1)

    var tone = Tone.good {
        didSet { updateColors() }
    }

    private let dot = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.cornerRadius = 40
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

    private func updateColors() {
        let color = tone == .good ? Self.good : Self.warning
        dot.backgroundColor = color
        backgroundColor = color.withAlphaComponent(0.18)
    }
}

/// The download speed over the last 30 seconds, drawn as the userscript draws it: a 3-point
/// moving average through a monotone cubic curve, a gradient fill under it, a dot on the latest
/// value, and a y-axis that eases toward a round maximum. The video's bitrate is dashed for scale.
private final class SpeedChartView: UIView {
    private let fill = CAGradientLayer()
    private let fillMask = CAShapeLayer()
    private let line = CAShapeLayer()
    private let reference = CAShapeLayer()
    private let leadDot = CAShapeLayer()
    private let referenceLabel = UILabel()
    private let waitingLabel = UILabel()
    private var values: [Double] = []
    private var referenceValue: Double?
    /// The y-axis maximum shown, eased toward a round ceiling so rescaling glides.
    private var shownMax: Double = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        let accent = Theme.accent
        fill.colors = [accent.withAlphaComponent(0.32).cgColor, accent.withAlphaComponent(0.02).cgColor]
        fill.mask = fillMask
        layer.addSublayer(fill)
        reference.strokeColor = UIColor(white: 1, alpha: 0.28).cgColor
        reference.lineWidth = 2
        reference.lineDashPattern = [6, 6]
        reference.fillColor = nil
        layer.addSublayer(reference)
        line.strokeColor = accent.cgColor
        line.lineWidth = 4
        line.lineJoin = .round
        line.lineCap = .round
        line.fillColor = nil
        layer.addSublayer(line)
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

    func update(values: [Double], reference: Double?) {
        self.values = Self.smoothed(values)
        referenceValue = reference
        let dataMax = max(self.values.max() ?? 0, (reference ?? 0) * 1.25, 1)
        let target = Self.niceCeil(dataMax)
        shownMax = shownMax > 0 ? shownMax + (target - shownMax) * 0.25 : target
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        for sublayer in [fill, line, reference, leadDot] as [CALayer] {
            sublayer.frame = bounds
        }
        fillMask.frame = bounds

        let hasData = values.count >= 2
        waitingLabel.isHidden = hasData
        [fill, line, leadDot].forEach { $0.isHidden = !hasData }
        guard hasData, bounds.width > 0 else {
            reference.path = nil
            referenceLabel.isHidden = true
            return
        }
        let top = max(shownMax, 1)
        let padTop: CGFloat = 10
        let padBottom: CGFloat = 4
        let height = bounds.height - padTop - padBottom
        func y(_ value: Double) -> CGFloat {
            bounds.height - padBottom - CGFloat(min(value, top) / top) * height
        }
        // While the series fills, it stretches across the width; once full, it slides.
        let step = bounds.width / CGFloat(values.count - 1)
        let xs = values.indices.map { CGFloat($0) * step }
        let ys = values.map(y)
        let curve = Self.monotonePath(xs: xs, ys: ys)
        line.path = curve.cgPath

        let area = curve.copy() as! UIBezierPath
        area.addLine(to: CGPoint(x: xs[xs.count - 1], y: bounds.height))
        area.addLine(to: CGPoint(x: xs[0], y: bounds.height))
        area.close()
        fillMask.path = area.cgPath

        let last = CGPoint(x: xs[xs.count - 1], y: ys[ys.count - 1])
        leadDot.path = UIBezierPath(arcCenter: last, radius: 7, startAngle: 0, endAngle: .pi * 2, clockwise: true).cgPath

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

    /// A curve through every point with no overshoot (Fritsch–Carlson monotone cubic tangents).
    private static func monotonePath(xs: [CGFloat], ys: [CGFloat]) -> UIBezierPath {
        let path = UIBezierPath()
        path.move(to: CGPoint(x: xs[0], y: ys[0]))
        let n = xs.count
        guard n >= 2 else { return path }
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
        for i in 0..<(n - 1) {
            let dx = (xs[i + 1] - xs[i]) / 3
            path.addCurve(to: CGPoint(x: xs[i + 1], y: ys[i + 1]),
                          controlPoint1: CGPoint(x: xs[i] + dx, y: ys[i] + tangents[i] * dx),
                          controlPoint2: CGPoint(x: xs[i + 1] - dx, y: ys[i + 1] - tangents[i + 1] * dx))
        }
        return path
    }
}
