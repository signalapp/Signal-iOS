
public extension Array where Element : CustomStringConvertible {

    var prettifiedDescription: String {
        return "[ " + map { $0.description }.joined(separator: ", ") + " ]"
    }
}

public extension Array where Element: Hashable {
    func asSet() -> Set<Element> {
        return Set(self)
    }
}
