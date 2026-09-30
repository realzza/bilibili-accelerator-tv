//
//  BLMotionCollectionViewCell.swift
//  BilibiliLive
//
//  Created by yicheng on 2022/10/23.
//

import TVUIKit
import UIKit

class BLMotionCollectionViewCell: UICollectionViewCell {
    private var motionEffectV: UIInterpolatingMotionEffect!
    private var motionEffectH: UIInterpolatingMotionEffect!
    var scaleFactor: CGFloat = 1.1

    /// The layer that casts the focus shadow. Cards override it so only the artwork casts one,
    /// not the text under it.
    var shadowLayer: CALayer {
        layer
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    func setup() {
        motionEffectV = UIInterpolatingMotionEffect(keyPath: "center.y", type: .tiltAlongVerticalAxis)
        motionEffectV.maximumRelativeValue = 8
        motionEffectV.minimumRelativeValue = -8
        motionEffectH = UIInterpolatingMotionEffect(keyPath: "center.x", type: .tiltAlongHorizontalAxis)
        motionEffectH.maximumRelativeValue = 8
        motionEffectH.minimumRelativeValue = -8
    }

    override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
        super.didUpdateFocus(in: context, with: coordinator)
        if isFocused {
            coordinator.addCoordinatedAnimations {
                self.updateTransform()
                self.addMotionEffect(self.motionEffectH)
                self.addMotionEffect(self.motionEffectV)
            }
        } else {
            coordinator.addCoordinatedAnimations {
                self.updateTransform()
                self.removeMotionEffect(self.motionEffectH)
                self.removeMotionEffect(self.motionEffectV)
            }
        }
    }

    func updateTransform() {
        let shadow = shadowLayer
        if isFocused {
            transform = CGAffineTransformMakeScale(scaleFactor, scaleFactor)
            let scaleDiff = (bounds.size.height * scaleFactor - bounds.size.height) / 2
            transform = CGAffineTransformTranslate(transform, 0, -scaleDiff)
            shadow.shadowColor = UIColor.black.cgColor
            shadow.shadowOffset = CGSizeMake(0, 22)
            shadow.shadowOpacity = 0.45
            shadow.shadowRadius = 26
        } else {
            transform = CGAffineTransformIdentity
            shadow.shadowOpacity = 0
            shadow.shadowOffset = CGSizeMake(0, 0)
        }
    }
}
