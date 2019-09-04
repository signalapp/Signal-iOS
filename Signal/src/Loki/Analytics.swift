import Mixpanel

@objc(LKAnalytics)
final class Analytics : NSObject {
    
    @objc static func track(_ event: String) {
        Mixpanel.sharedInstance()?.track(event, properties: [ "configuration" : BuildConfiguration.current.description ])
    }
}
