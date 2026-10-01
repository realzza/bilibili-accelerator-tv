//
//  ContentStateView.swift
//  BilibiliLive
//

import SnapKit
import UIKit

/// What a list shows when it has nothing to show: a spinner while it loads, a note when it is
/// empty, or what went wrong and a way out when it failed.
final class ContentStateView: UIView {
    enum State {
        case loading
        case empty(EmptyContent)
        case failed(Error)
    }

    struct EmptyContent {
        var title: String
        var message: String?
        var symbol: String = "tray"

        static let generic = EmptyContent(title: "暂无内容")
    }

    /// Called by 重试.
    var onRetry: (() -> Void)?

    private let spinner = UIActivityIndicatorView(style: .large)
    private let symbolView = UIImageView()
    private let titleLabel = UILabel()
    private let messageLabel = UILabel()
    private let retryButton = ContentStateView.makeButton(title: "重试", symbol: "arrow.clockwise")
    private let loginButton = ContentStateView.makeButton(title: "重新登录", symbol: "qrcode")
    private let buttons = UIStackView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var state: State? {
        didSet { render() }
    }

    override var preferredFocusEnvironments: [UIFocusEnvironment] {
        buttons.arrangedSubviews.filter { !$0.isHidden }
    }

    /// Whether there is a button to focus, so a screen can hand focus here.
    var hasActions: Bool {
        !isHidden && buttons.arrangedSubviews.contains { !$0.isHidden }
    }

    private func setup() {
        isHidden = true
        spinner.color = Theme.textSecondary
        symbolView.tintColor = Theme.textTertiary
        symbolView.contentMode = .scaleAspectFit
        symbolView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 64, weight: .regular)
        titleLabel.font = .systemFont(ofSize: 34, weight: .semibold)
        titleLabel.textColor = Theme.textPrimary
        titleLabel.textAlignment = .center
        messageLabel.font = .systemFont(ofSize: 26)
        messageLabel.textColor = Theme.textSecondary
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 3

        retryButton.addAction(UIAction { [weak self] _ in self?.onRetry?() }, for: .primaryActionTriggered)
        loginButton.addAction(UIAction { _ in AppDelegate.shared.showLogin() }, for: .primaryActionTriggered)
        buttons.addArrangedSubview(retryButton)
        buttons.addArrangedSubview(loginButton)
        buttons.spacing = 24

        let stack = UIStackView(arrangedSubviews: [spinner, symbolView, titleLabel, messageLabel, buttons])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 18
        stack.setCustomSpacing(28, after: symbolView)
        stack.setCustomSpacing(40, after: messageLabel)
        addSubview(stack)
        stack.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.leading.greaterThanOrEqualToSuperview().offset(80)
            make.width.lessThanOrEqualTo(960)
        }
    }

    private func render() {
        guard let state else {
            isHidden = true
            spinner.stopAnimating()
            return
        }
        isHidden = false
        switch state {
        case .loading:
            spinner.startAnimating()
            spinner.isHidden = false
            [symbolView, titleLabel, messageLabel, buttons].forEach { $0.isHidden = true }
        case let .empty(content):
            show(symbol: content.symbol, title: content.title, message: content.message)
            buttons.isHidden = true
        case let .failed(error):
            let presentation = ErrorPresentation(error)
            show(symbol: presentation.symbol, title: presentation.title, message: presentation.message)
            buttons.isHidden = false
            loginButton.isHidden = !presentation.needsLogin
        }
    }

    private func show(symbol: String, title: String, message: String?) {
        spinner.stopAnimating()
        spinner.isHidden = true
        symbolView.image = UIImage(systemName: symbol)
        symbolView.isHidden = false
        titleLabel.text = title
        titleLabel.isHidden = false
        messageLabel.text = message
        messageLabel.isHidden = (message ?? "").isEmpty
    }

    private static func makeButton(title: String, symbol: String) -> UIButton {
        var config = UIButton.Configuration.capsule()
        config.title = title
        config.image = UIImage(systemName: symbol)
        config.imagePadding = 12
        config.contentInsets = NSDirectionalEdgeInsets(top: 18, leading: 36, bottom: 18, trailing: 36)
        config.setTitleFont(.systemFont(ofSize: 26, weight: .semibold))
        return UIButton(configuration: config)
    }
}

/// An error as the viewer should read it: what happened, what to do, and whether signing in
/// again would help.
struct ErrorPresentation {
    var title: String
    var message: String
    var symbol: String
    var needsLogin = false

    init(_ error: Error) {
        switch error {
        case let RequestError.statusFail(code, message):
            switch code {
            case -101:
                self.init(title: "需要登录", message: "登录已失效，请重新登录后再试。",
                          symbol: "person.crop.circle.badge.exclamationmark", needsLogin: true)
            case -352, -412:
                self.init(title: "请求太频繁", message: "B 站暂时拦截了请求，请稍后再试。", symbol: "hourglass")
            case -404, 62002, 62004:
                self.init(title: "内容不存在", message: "内容可能已被删除或设为不可见。", symbol: "eye.slash")
            default:
                let detail = message.isEmpty ? "错误码 \(code)" : "\(message)（\(code)）"
                self.init(title: "加载失败", message: detail, symbol: "exclamationmark.triangle")
            }
        case RequestError.networkFail, is URLError:
            self.init(title: "网络连接失败", message: "请检查网络连接后重试。", symbol: "wifi.exclamationmark")
        case RequestError.decodeFail:
            self.init(title: "数据异常", message: "B 站返回的数据无法识别，接口可能有变化。", symbol: "exclamationmark.triangle")
        default:
            self.init(title: "加载失败", message: error.localizedDescription, symbol: "exclamationmark.triangle")
        }
    }

    private init(title: String, message: String, symbol: String, needsLogin: Bool = false) {
        self.title = title
        self.message = message
        self.symbol = symbol
        self.needsLogin = needsLogin
    }
}
