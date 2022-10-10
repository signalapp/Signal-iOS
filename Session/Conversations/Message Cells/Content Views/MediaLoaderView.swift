// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit
import SessionUIKit

final class MediaLoaderView: UIView {
    private let bar = UIView()
    
    private lazy var barLeftConstraint = bar.pin(.left, to: .left, of: self)
    private lazy var barRightConstraint = bar.pin(.right, to: .right, of: self)
    
    // MARK: - Lifecycle
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        setUpViewHierarchy()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUpViewHierarchy()
    }
    
    private func setUpViewHierarchy() {
        bar.themeBackgroundColor = .primary
        bar.set(.height, to: 8)
        addSubview(bar)
        
        barLeftConstraint.isActive = true
        bar.pin(.top, to: .top, of: self)
        barRightConstraint.isActive = true
        bar.pin(.bottom, to: .bottom, of: self)
        step1()
    }
    
    // MARK: - Animation
    
    func step1() {
        barRightConstraint.constant = -bounds.width
        UIView.animate(withDuration: 0.5, animations: { [weak self] in
            guard let self = self else { return }
            self.barRightConstraint.constant = 0
            self.layoutIfNeeded()
        }, completion: { [weak self] _ in
            self?.step2()
        })
    }
    
    func step2() {
        barLeftConstraint.constant = 0
        UIView.animate(withDuration: 0.5, animations: { [weak self] in
            guard let self = self else { return }
            self.barLeftConstraint.constant = self.bounds.width
            self.layoutIfNeeded()
        }, completion: { [weak self] _ in
            Timer.scheduledTimer(withTimeInterval: 0.25, repeats: false) { _ in
                self?.step3()
            }
        })
    }
    
    func step3() {
        barLeftConstraint.constant = bounds.width
        UIView.animate(withDuration: 0.5, animations: { [weak self] in
            guard let self = self else { return }
            self.barLeftConstraint.constant = 0
            self.layoutIfNeeded()
        }, completion: { [weak self] _ in
            self?.step4()
        })
    }
    
    func step4() {
        barRightConstraint.constant = 0
        UIView.animate(withDuration: 0.5, animations: { [weak self] in
            guard let self = self else { return }
            self.barRightConstraint.constant = -self.bounds.width
            self.layoutIfNeeded()
        }, completion: { [weak self] _ in
            Timer.scheduledTimer(withTimeInterval: 0.25, repeats: false) { _ in
                self?.step1()
            }
        })
    }
}
