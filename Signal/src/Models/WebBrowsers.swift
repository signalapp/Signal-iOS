//
//  WebBrowsers.swift
//  Signal
//
//  Created by Adam Kunicki on 1/8/17.
//  Copyright © 2017 Open Whisper Systems. All rights reserved.
//

import Foundation

let Safari = WebBrowser(label: "Safari", scheme: "http://", index: 0)
let Chrome = WebBrowser(label: "Google Chrome", scheme: "googlechrome://", index: 1)
let Firefox = WebBrowser(label: "Firefox", scheme: "firefox://", index: 2)
let Brave = WebBrowser(label: "Brave", scheme: "brave://", index: 3)

@objc
class WebBrowsers : NSObject {
    override private init() {}
    
    class func all() -> [WebBrowser] {
        return [
            Safari,
            Chrome,
            Firefox,
            Brave
        ]
    }
    
    class func safari() -> WebBrowser {
        return Safari
    }
    
    class func chrome() -> WebBrowser {
        return Chrome
    }
    
    class func firefox() -> WebBrowser {
        return Firefox
    }
    
    class func brave() -> WebBrowser {
        return Brave
    }
}
