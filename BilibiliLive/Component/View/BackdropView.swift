//
//  BackdropView.swift
//  BilibiliLive
//

import UIKit

/// Key art that fades into the ground on its left and bottom edges, so text can sit over it.
final class BackdropView: UIView {
    let imageView = UIImageView()
    private let sideScrim = CAGradientLayer()
    private let bottomScrim = CAGradientLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        clipsToBounds = true
        addSubview(imageView)
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true

        sideScrim.colors = [Theme.background.cgColor,
                            Theme.background.withAlphaComponent(0.72).cgColor,
                            Theme.background.withAlphaComponent(0).cgColor]
        sideScrim.locations = [0, 0.3, 0.72]
        sideScrim.startPoint = CGPoint(x: 0, y: 0.5)
        sideScrim.endPoint = CGPoint(x: 1, y: 0.5)
        layer.addSublayer(sideScrim)
        bottomScrim.colors = [Theme.background.withAlphaComponent(0).cgColor, Theme.background.cgColor]
        bottomScrim.locations = [0.55, 1]
        layer.addSublayer(bottomScrim)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        imageView.frame = bounds
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        sideScrim.frame = bounds
        bottomScrim.frame = bounds
        CATransaction.commit()
    }
}
