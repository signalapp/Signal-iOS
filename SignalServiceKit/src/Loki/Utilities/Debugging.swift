
// For some reason NSLog doesn't seem to work. This is a workaround to still allow debugging from Obj-C.

@objc(LKLogger)
public final class Objc_Logger : NSObject {
    
    private override init() { }
    
    @objc public static func print(_ message: String) {
        Swift.print(message)
    }
}
