
public enum BuildConfiguration {
    case debug, production
    
    public static let current: BuildConfiguration = {
        #if DEBUG
            return .debug
        #else
            return .production
        #endif
    }()
}
