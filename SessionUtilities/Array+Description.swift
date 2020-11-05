
public extension Array where Element : CustomStringConvertible {

    var prettifiedDescription: String {
        return "[ " + map { $0.description }.joined(separator: ", ") + " ]"
    }
}
