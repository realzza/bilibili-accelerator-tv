//
//  VideoPlayerRouteInfoViewController.swift
//  BilibiliLive
//

import BiliAccelerator
import SnapKit
import UIKit

/// The 线路 tab of the player's info panel: how playback is going, which host serves the
/// video, the rate and buffer, and a button that races the next fragment on two other hosts.
final class VideoPlayerRouteInfoViewController: UIViewController {
    private let dot = UIView()
    private let healthLabel = UILabel()
    private let hostLabel = UILabel()
    private let switchesLabel = UILabel()
    private let rateLabel = UILabel()
    private let bufferLabel = UILabel()
    private let sparkline = SparklineView()
    private let testButton = UIButton(configuration: .capsule())
    private let testCaption = UILabel()
    private let content = UIStackView()
    private let messageLabel = UILabel()
    private var timer: Timer?
    private var status: RouteStatus?

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
        preferredContentSize = CGSize(width: 0, height: 250)
        view.backgroundColor = .clear

        dot.layer.cornerRadius = 7
        dot.snp.makeConstraints { make in
            make.size.equalTo(14)
        }
        healthLabel.font = .systemFont(ofSize: 34, weight: .bold)
        healthLabel.textColor = Theme.textPrimary
        let healthRow = UIStackView(arrangedSubviews: [dot, healthLabel])
        healthRow.spacing = 14
        healthRow.alignment = .center
        hostLabel.font = .systemFont(ofSize: 26)
        hostLabel.textColor = Theme.textSecondary
        switchesLabel.font = .systemFont(ofSize: 22)
        switchesLabel.textColor = Theme.textTertiary
        let statusColumn = UIStackView(arrangedSubviews: [healthRow, hostLabel, switchesLabel])
        statusColumn.axis = .vertical
        statusColumn.alignment = .leading
        statusColumn.spacing = 12

        let rateTitle = UILabel()
        rateTitle.text = "实时网速"
        rateTitle.font = .systemFont(ofSize: 22)
        rateTitle.textColor = Theme.textTertiary
        bufferLabel.font = .systemFont(ofSize: 22)
        bufferLabel.textColor = Theme.textTertiary
        bufferLabel.textAlignment = .right
        let rateHeader = UIStackView(arrangedSubviews: [rateTitle, bufferLabel])
        rateHeader.distribution = .equalSpacing
        rateLabel.textColor = Theme.textPrimary
        sparkline.snp.makeConstraints { make in
            make.height.equalTo(44)
        }
        let rateStack = UIStackView(arrangedSubviews: [rateHeader, rateLabel, sparkline])
        rateStack.axis = .vertical
        rateStack.spacing = 8
        let rateCard = UIView()
        rateCard.backgroundColor = UIColor(white: 1, alpha: 0.08)
        rateCard.layer.cornerRadius = 26
        rateCard.layer.cornerCurve = .continuous
        rateCard.addSubview(rateStack)
        rateStack.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(UIEdgeInsets(top: 20, left: 26, bottom: 20, right: 26))
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

        let statusWrapper = Self.centeredVertically(statusColumn)
        let actionWrapper = Self.centeredVertically(actionColumn)
        content.addArrangedSubview(statusWrapper)
        content.addArrangedSubview(rateCard)
        content.addArrangedSubview(actionWrapper)
        content.axis = .horizontal
        content.distribution = .fillEqually
        content.spacing = 40
        view.addSubview(content)
        content.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(40)
            make.top.bottom.equalToSuperview().inset(16)
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
            dot.backgroundColor = .systemOrange
            healthLabel.text = "正在缓冲"
        } else if let mbps = status.mbps, let required = status.requiredMbps, mbps < required * 1.2,
                  (status.bufferSeconds ?? 0) < 30
        {
            dot.backgroundColor = .systemYellow
            healthLabel.text = "网速偏慢"
        } else {
            dot.backgroundColor = .systemGreen
            healthLabel.text = "播放流畅"
        }
        hostLabel.text = status.isIssuedHost ? "原生线路 · \(name)" : "已切换到 \(name)"
        switchesLabel.text = status.switches == 0 ? "本视频未切换线路" : "本视频切换了 \(status.switches) 次线路"

        let rate = NSMutableAttributedString(string: status.mbps.map { String(format: "%.1f", $0) } ?? "—",
                                             attributes: [.font: UIFont.systemFont(ofSize: 44, weight: .bold)])
        rate.append(NSAttributedString(string: " Mbps", attributes: [.font: UIFont.systemFont(ofSize: 24, weight: .semibold),
                                                                     .foregroundColor: Theme.textSecondary]))
        rateLabel.attributedText = rate
        bufferLabel.text = status.bufferSeconds.map { "缓冲 \(Int($0.rounded())) 秒" }
        sparkline.update(values: status.recentMbps, reference: status.requiredMbps)

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
            make.leading.trailing.equalToSuperview()
            make.centerY.equalToSuperview()
            make.top.greaterThanOrEqualToSuperview()
        }
        return wrapper
    }
}

/// Recent fragment rates as a line, with the video's bitrate as a dashed line for scale.
private final class SparklineView: UIView {
    private let line = CAShapeLayer()
    private let reference = CAShapeLayer()
    private var values: [Double] = []
    private var referenceValue: Double?

    override init(frame: CGRect) {
        super.init(frame: frame)
        reference.strokeColor = UIColor(white: 1, alpha: 0.3).cgColor
        reference.lineWidth = 2
        reference.lineDashPattern = [6, 6]
        reference.fillColor = nil
        layer.addSublayer(reference)
        line.strokeColor = Theme.textPrimary.cgColor
        line.lineWidth = 3
        line.lineJoin = .round
        line.lineCap = .round
        line.fillColor = nil
        layer.addSublayer(line)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(values: [Double], reference: Double?) {
        self.values = values
        referenceValue = reference
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        line.frame = bounds
        reference.frame = bounds
        let top = max(values.max() ?? 0, (referenceValue ?? 0) * 1.5, 1)
        let height = bounds.height - 4
        func y(_ value: Double) -> CGFloat {
            bounds.height - 2 - CGFloat(min(value, top) / top) * height
        }
        let path = UIBezierPath()
        if values.count > 1 {
            let step = bounds.width / CGFloat(values.count - 1)
            for (index, value) in values.enumerated() {
                let point = CGPoint(x: CGFloat(index) * step, y: y(value))
                index == 0 ? path.move(to: point) : path.addLine(to: point)
            }
        }
        line.path = path.cgPath
        let dashed = UIBezierPath()
        if let referenceValue, referenceValue > 0 {
            dashed.move(to: CGPoint(x: 0, y: y(referenceValue)))
            dashed.addLine(to: CGPoint(x: bounds.width, y: y(referenceValue)))
        }
        reference.path = dashed.cgPath
    }
}
