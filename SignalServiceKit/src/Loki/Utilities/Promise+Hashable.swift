import PromiseKit

extension Promise : Hashable {
    
    public func hash(into hasher: inout Hasher) {
        let reference = ObjectIdentifier(self).hashValue
        hasher.combine(reference)
    }
    
    public static func == (lhs: Promise, rhs: Promise) -> Bool {
        return ObjectIdentifier(lhs) == ObjectIdentifier(rhs)
    }
}
