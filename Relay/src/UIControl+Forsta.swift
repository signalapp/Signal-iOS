//
//  UIControl+Forsta.swift
//  Relay
//
//  Created by Mark Descalzo on 11/26/18.
//  Copyright © 2018 Open Whisper Systems. All rights reserved.
//

import Foundation

extension UIControl {
    func enable() {
        DispatchMainThreadSafe({
            self.isEnabled = true
            self.alpha = 1.0
        })
    }
    
    func disable() {
        DispatchMainThreadSafe({
            self.isEnabled = false
            self.alpha = 0.5
        })
    }
}
