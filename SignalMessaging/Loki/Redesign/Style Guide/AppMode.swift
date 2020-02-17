
public enum AppMode {
    case light, dark
    
    public static var current: AppMode = .light
}

public var isLightMode: Bool {
    return AppMode.current == .light
}
