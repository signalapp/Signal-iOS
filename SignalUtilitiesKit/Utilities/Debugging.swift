
// For some reason NSLog doesn't seem to work from SignalServiceKit. This is a workaround to still allow debugging from Obj-C.

@objc(LKLogger)
public final class ObjC_Logger : NSObject {
    
    private override init() { }
    
    @objc public static func print(_ message: String) {
        Swift.print(message)
    }
}
