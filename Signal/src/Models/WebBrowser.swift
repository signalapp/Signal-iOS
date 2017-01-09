//
//  WebBrowser.swift
//  Signal
//
//  Created by Adam Kunicki on 1/8/17.
//  Copyright © 2017 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
class WebBrowser : NSObject {
    // class instead of struct so that it's accessible from objc code
    let label: String
    let scheme: String
    let index: Int
    
    init(label: String, scheme: String, index: Int) {
        self.label = label
        self.scheme = scheme
        self.index = index
    }
    
    func isInstalled() -> Bool {
        return schemeAvailable(scheme: scheme)
    }
    
    private func schemeAvailable(scheme: String) -> Bool {
        if let url = URL(string: scheme) {
            return UIApplication.shared.canOpenURL(url)
        }
        return false
    }
}
