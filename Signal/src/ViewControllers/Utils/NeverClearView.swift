// Created by Fredrik Lillejordet on 04.03.2018.
// Copyright © 2018 Open Whisper Systems. All rights reserved.

@objc class NeverClearUIView: UIView {
    override var backgroundColor: UIColor? {
        didSet {
            if backgroundColor != nil && backgroundColor!.cgColor.alpha == 0 {
                backgroundColor = oldValue
            }
        }
    }
}
