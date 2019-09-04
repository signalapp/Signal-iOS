
@objc(LKAnalytics)
public final class Analytics : NSObject {
    @objc public var trackImplementation: ((String) -> Void)! // Set in AppDelegate.m
    
    @objc public static let shared = Analytics()
    
    @objc public func track(_ event: String) {
        trackImplementation(event)
    }
}
