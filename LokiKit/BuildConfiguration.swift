
enum BuildConfiguration {
    case debug, production
    
    static let current: BuildConfiguration = {
        #if DEBUG
            return .debug
        #else
            return .production
        #endif
    }()
}
