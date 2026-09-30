//
//  PersonalViewController.swift
//  BilibiliLive
//
//  Created by yicheng on 2022/8/20.
//

import Alamofire
import Kingfisher
import SnapKit
import SwiftyJSON
import UIKit

class PersonalViewController: UIViewController, BLTabBarContentVCProtocol {
    struct CellModel {
        let title: String
        var autoSelect: Bool? = true
        var contentVC: UIViewController? = nil
        var action: (() -> Void)? = nil
    }

    static func create() -> PersonalViewController {
        return PersonalViewController()
    }

    private let leftContainerView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let profileContainerView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let contentView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private static let avatarSide: CGFloat = 96
    /// The sidebar's width, from the screen's safe margin.
    private static let sidebarWidth: CGFloat = 400
    /// Room around the menu rows for their focus scale, which the collection view would clip.
    private static let menuOutset: CGFloat = 20

    private let avatarImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.backgroundColor = Theme.groupedFill
        imageView.tintColor = Theme.textTertiary
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private let usernameLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 30, weight: .bold)
        label.textColor = Theme.textPrimary
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let vipLabel: PillLabel = {
        let label = PillLabel()
        label.insets = UIEdgeInsets(top: 3, left: 12, bottom: 3, right: 12)
        label.font = .systemFont(ofSize: 18, weight: .bold)
        label.textColor = Theme.onAccent
        label.backgroundColor = Theme.accent
        label.layer.cornerRadius = 10
        label.clipsToBounds = true
        label.isHidden = true
        return label
    }()

    private let leftCollectionView: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.minimumLineSpacing = 4
        layout.minimumInteritemSpacing = 4
        layout.itemSize = CGSize(width: PersonalViewController.sidebarWidth, height: 64)
        let outset = PersonalViewController.menuOutset
        layout.sectionInset = UIEdgeInsets(top: 10, left: outset, bottom: 40, right: outset)
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .clear
        collectionView.contentInsetAdjustmentBehavior = .never
        return collectionView
    }()

    weak var currentViewController: UIViewController?

    var cellModels = [CellModel]()
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupData()
        leftCollectionView.reloadData()
        avatarImageView.layer.cornerRadius = Self.avatarSide / 2
        leftCollectionView.register(BLSettingLineCollectionViewCell.self, forCellWithReuseIdentifier: "cell")
        leftCollectionView.selectItem(at: IndexPath(row: 0, section: 0), animated: false, scrollPosition: .top)
        collectionView(leftCollectionView, didSelectItemAt: IndexPath(row: 0, section: 0))
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(handleAccountUpdate),
                                               name: AccountManager.didUpdateNotification,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(handleTabBarPagesDidChange),
                                               name: .tabBarPagesDidChange,
                                               object: nil)
        updateAccountInfo()
        AccountManager.shared.refreshActiveAccountProfile()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func setupData() {
        cellModels.removeAll()

        let setting = CellModel(title: "设置", contentVC: SettingsViewController())
        cellModels.append(setting)
        cellModels.append(CellModel(title: "账号切换", autoSelect: false, action: { [weak self] in
            let controller = AccountSwitcherViewController()
            controller.modalPresentationStyle = .overFullScreen
            self?.present(controller, animated: true)
        }))

        for page in Settings.personalPages {
            if let model = makeCellModel(for: page) {
                cellModels.append(model)
            }
        }

        let logout = CellModel(title: "登出", autoSelect: false) {
            [weak self] in
            self?.actionLogout()
        }
        cellModels.append(logout)
    }

    private func makeCellModel(for page: TabBarPage) -> CellModel? {
        let vc = TabBarPageVCFactory.createVC(for: page)
        if page.requirePresentInPersonalPage {
            return CellModel(title: page.title) { [weak self] in
                self?.present(vc, animated: true)
            }
        }

        return CellModel(title: page.title, contentVC: vc)
    }

    func setViewController(vc: UIViewController) {
        currentViewController?.willMove(toParent: nil)
        currentViewController?.view.removeFromSuperview()
        currentViewController?.removeFromParent()

        currentViewController = vc
        addChild(vc)
        contentView.addSubview(vc.view)
        vc.view.makeConstraintsToBindToSuperview()
        vc.didMove(toParent: self)
    }

    func reloadData() {
        (currentViewController as? BLTabBarContentVCProtocol)?.reloadData()
    }

    func actionLogout() {
        let alert = UIAlertController(title: "确定登出？", message: nil, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "确定", style: .default) {
            _ in
            WebRequest.logout {
                ApiRequest.logout { hasRemainingAccount in
                    if hasRemainingAccount {
                        AccountManager.shared.refreshActiveAccountProfile()
                    } else {
                        AppDelegate.shared.showLogin()
                    }
                }
            }
        })
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        present(alert, animated: true)
    }

    @objc private func handleAccountUpdate() {
        updateAccountInfo()
    }

    @objc private func handleTabBarPagesDidChange() {
        setupData()
        leftCollectionView.reloadData()
        let firstIndexPath = IndexPath(item: 0, section: 0)
        leftCollectionView.selectItem(at: firstIndexPath, animated: false, scrollPosition: .top)
        collectionView(leftCollectionView, didSelectItemAt: firstIndexPath)
    }

    private func updateAccountInfo() {
        guard let account = AccountManager.shared.activeAccount else {
            usernameLabel.text = "未登录"
            avatarImageView.image = nil
            vipLabel.isHidden = true
            return
        }
        usernameLabel.text = account.profile.username
        vipLabel.text = account.profile.vipLabel
        vipLabel.isHidden = account.profile.vipLabel == nil
        if let url = URL(string: account.profile.avatar), !account.profile.avatar.isEmpty {
            avatarImageView.kf.setImage(with: url)
        } else {
            avatarImageView.image = UIImage(systemName: "person.crop.circle.fill")
        }
    }

    private func setupUI() {
        view.addSubview(leftContainerView)
        view.addSubview(contentView)

        leftContainerView.addSubview(profileContainerView)
        leftContainerView.addSubview(leftCollectionView)

        let nameStack = UIStackView(arrangedSubviews: [usernameLabel, vipLabel])
        nameStack.axis = .vertical
        nameStack.alignment = .leading
        nameStack.spacing = 8
        profileContainerView.addSubview(avatarImageView)
        profileContainerView.addSubview(nameStack)

        leftCollectionView.delegate = self
        leftCollectionView.dataSource = self

        // The avatar and the menu rows start at the safe margin, as the cards of other tabs do.
        leftContainerView.snp.makeConstraints { make in
            make.leading.equalTo(view.safeAreaLayoutGuide.snp.leading)
            make.top.equalTo(view.safeAreaLayoutGuide.snp.top).offset(20)
            make.bottom.equalToSuperview()
            make.width.equalTo(Self.sidebarWidth)
        }

        contentView.snp.makeConstraints { make in
            make.leading.equalTo(leftContainerView.snp.trailing).offset(40)
            make.top.equalTo(view.safeAreaLayoutGuide.snp.top)
            make.trailing.bottom.equalToSuperview()
        }

        profileContainerView.snp.makeConstraints { make in
            make.leading.top.trailing.equalToSuperview()
            make.height.equalTo(Self.avatarSide)
        }

        avatarImageView.snp.makeConstraints { make in
            make.leading.top.bottom.equalToSuperview()
            make.width.equalTo(avatarImageView.snp.height)
        }

        nameStack.snp.makeConstraints { make in
            make.leading.equalTo(avatarImageView.snp.trailing).offset(22)
            make.trailing.lessThanOrEqualToSuperview()
            make.centerY.equalTo(avatarImageView.snp.centerY)
        }

        leftCollectionView.clipsToBounds = false
        leftCollectionView.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(-Self.menuOutset)
            make.trailing.equalToSuperview().offset(Self.menuOutset)
            make.bottom.equalToSuperview()
            make.top.equalTo(profileContainerView.snp.bottom).offset(18)
        }
    }
}

extension PersonalViewController: UICollectionViewDataSource {
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath) as! BLSettingLineCollectionViewCell
        cell.titleLabel.text = cellModels[indexPath.item].title
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return cellModels.count
    }
}

extension PersonalViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let model = cellModels[indexPath.item]
        if let vc = model.contentVC {
            setViewController(vc: vc)
        }
        model.action?()
    }

    func collectionView(_ collectionView: UICollectionView, didUpdateFocusIn context: UICollectionViewFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
        if Settings.sideMenuAutoSelectChange == false {
            return
        }
        // 检查新的焦点是否是UICollectionViewCell
        guard let nextFocusedIndexPath = context.nextFocusedIndexPath else {
            return
        }
        let model = cellModels[nextFocusedIndexPath.item]
        if model.autoSelect == false {
            // 不自动选中
            return
        }
        collectionView.selectItem(at: nextFocusedIndexPath, animated: true, scrollPosition: .centeredHorizontally)
        if let vc = model.contentVC {
            setViewController(vc: vc)
        }
        model.action?()
    }
}

class EmptyViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        let label = UILabel()
        label.text = "Nothing Here"
        view.addSubview(label)
        label.makeConstraintsBindToCenterOfSuperview()
    }
}
