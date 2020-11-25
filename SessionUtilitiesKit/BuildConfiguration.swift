
public enum BuildConfiguration : String, CustomStringConvertible {
    case debug, production
    
    public static let current: BuildConfiguration = {
        #if DEBUG
            return .debug
        #else
            return .production
        #endif
    }()
    
    public var description: String { return rawValue }
}

@objc public final class LKBuildConfiguration : NSObject {
    
    override private init() { }
    
    @objc public static var current: String { return BuildConfiguration.current.description }
}
