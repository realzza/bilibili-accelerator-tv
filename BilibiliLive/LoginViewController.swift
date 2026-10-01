//
//  LoginViewController.swift
//  BilibiliLive
//
//  Created by Etan Chen on 2021/3/28.
//

import Alamofire
import Foundation
import SnapKit
import SwiftyJSON
import UIKit

class LoginViewController: UIViewController {
    private let ciContext = CIContext()

    private let qrcodeImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        return imageView
    }()

    /// The code sits on white, as a phone camera reads it best, with a margin of quiet zone.
    private let qrCard: UIView = {
        let view = UIView()
        view.backgroundColor = .white
        view.layer.cornerRadius = 32
        view.layer.cornerCurve = .continuous
        return view
    }()

    private let statusLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 26, weight: .medium)
        label.textColor = Theme.textSecondary
        label.textAlignment = .center
        return label
    }()

    private let regenerateButton: UIButton = {
        var config = UIButton.Configuration.capsule()
        config.title = "刷新二维码"
        config.image = UIImage(systemName: "arrow.clockwise")
        config.imagePadding = 12
        config.contentInsets = NSDirectionalEdgeInsets(top: 18, leading: 36, bottom: 18, trailing: 36)
        config.setTitleFont(.systemFont(ofSize: 26, weight: .semibold))
        return UIButton(configuration: config)
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.text = "扫码登录"
        label.font = .systemFont(ofSize: 64, weight: .bold)
        label.textColor = Theme.textPrimary
        return label
    }()

    private let subtitleLabel: UILabel = {
        let label = UILabel()
        label.text = "用哔哩哔哩手机客户端登录这台 Apple TV"
        label.font = .systemFont(ofSize: 28)
        label.textColor = Theme.textSecondary
        return label
    }()

    var currentLevel: Int = 0, finalLevel: Int = 200
    var timer: Timer?
    var oauthKey: String = ""

    static func create() -> LoginViewController {
        LoginViewController()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        initValidation()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        qrcodeImageView.image = nil
        stopValidationTimer()
    }

    func generateQRCode(from string: String) -> UIImage? {
        guard
            let data = string.data(using: .ascii),
            let filter = CIFilter(name: "CIQRCodeGenerator")
        else {
            return nil
        }

        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("H", forKey: "inputCorrectionLevel")

        guard let outputImage = filter.outputImage else { return nil }
        let extent = outputImage.extent.integral
        guard !extent.isEmpty else { return nil }

        let targetSize: CGFloat = 540
        let scale = max(1, floor(targetSize / max(extent.width, extent.height)))
        let width = Int(extent.width * scale)
        let height = Int(extent.height * scale)

        guard
            let cgImage = ciContext.createCGImage(outputImage, from: extent),
            let bitmapContext = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            )
        else {
            return nil
        }

        bitmapContext.interpolationQuality = .none
        bitmapContext.scaleBy(x: scale, y: scale)
        bitmapContext.draw(cgImage, in: extent)

        guard let scaledImage = bitmapContext.makeImage() else { return nil }
        return UIImage(cgImage: scaledImage)
    }

    func initValidation() {
        timer?.invalidate()
        ApiRequest.requestLoginQR { [weak self] code, url in
            guard let self else { return }
            let image = self.generateQRCode(from: url)
            self.qrcodeImageView.image = image
            self.oauthKey = code
            self.setStatus("等待扫码", highlighted: false)
            self.startValidationTimer()
        }
    }

    func startValidationTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.currentLevel += 1
            if self.currentLevel > self.finalLevel {
                self.stopValidationTimer()
            }
            self.loopValidation()
        }
    }

    func stopValidationTimer() {
        timer?.invalidate()
        timer = nil
    }

    func didValidationSuccess() {
        qrcodeImageView.image = nil
        AppDelegate.shared.showTabBar()
        stopValidationTimer()
    }

    func loopValidation() {
        ApiRequest.verifyLoginQR(code: oauthKey) {
            [weak self] state in
            guard let self = self else { return }
            switch state {
            case .expire:
                self.setStatus("二维码已过期，正在刷新", highlighted: false)
                self.initValidation()
            case .waiting:
                break
            case .scanned:
                self.setStatus("已扫码，请在手机上确认登录", highlighted: true)
            case let .success(token, cookies):
                print(token)
                AccountManager.shared.registerAccount(token: token, cookies: cookies) { [weak self] _ in
                    self?.didValidationSuccess()
                }
            case .fail:
                break
            }
        }
    }

    @objc private func actionStart() {
        initValidation()
    }

    private func setStatus(_ text: String, highlighted: Bool) {
        statusLabel.text = text
        statusLabel.textColor = highlighted ? Theme.accent : Theme.textSecondary
    }

    private func setupUI() {
        view.backgroundColor = Theme.background
        regenerateButton.addTarget(self, action: #selector(actionStart), for: .primaryActionTriggered)

        qrCard.addSubview(qrcodeImageView)
        qrcodeImageView.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(32)
            make.size.equalTo(460)
        }
        let codeColumn = UIStackView(arrangedSubviews: [qrCard, statusLabel, regenerateButton])
        codeColumn.axis = .vertical
        codeColumn.alignment = .center
        codeColumn.spacing = 28
        codeColumn.setCustomSpacing(36, after: statusLabel)

        let steps = UIStackView(arrangedSubviews: [
            Self.makeStep(1, "打开哔哩哔哩手机客户端"),
            Self.makeStep(2, "用「扫一扫」扫描左侧二维码"),
            Self.makeStep(3, "在手机上确认登录"),
        ])
        steps.axis = .vertical
        steps.spacing = 28
        let guide = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel, steps])
        guide.axis = .vertical
        guide.alignment = .leading
        guide.spacing = 16
        guide.setCustomSpacing(64, after: subtitleLabel)

        let columns = UIStackView(arrangedSubviews: [codeColumn, guide])
        columns.alignment = .center
        columns.spacing = 140
        view.addSubview(columns)
        columns.snp.makeConstraints { make in
            make.center.equalToSuperview()
        }
    }

    /// A numbered step: the number in a pink circle, then what to do.
    private static func makeStep(_ number: Int, _ text: String) -> UIView {
        let badge = UILabel()
        badge.text = "\(number)"
        badge.font = .systemFont(ofSize: 26, weight: .bold)
        badge.textColor = Theme.onAccent
        badge.backgroundColor = Theme.accent
        badge.textAlignment = .center
        badge.layer.cornerRadius = 24
        badge.clipsToBounds = true
        badge.snp.makeConstraints { make in
            make.size.equalTo(48)
        }
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 32, weight: .medium)
        label.textColor = Theme.textPrimary
        let row = UIStackView(arrangedSubviews: [badge, label])
        row.spacing = 22
        row.alignment = .center
        return row
    }
}
