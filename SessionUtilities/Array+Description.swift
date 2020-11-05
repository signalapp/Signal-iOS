
public extension Array where Element : CustomStringConvertible {

    public var prettifiedDescription: String {
        return "[ " + map { $0.description }.joined(separator: ", ") + " ]"
    }
}
