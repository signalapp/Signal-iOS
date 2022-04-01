
public extension Array where Element : CustomStringConvertible {

    var prettifiedDescription: String {
        return "[ " + map { $0.description }.joined(separator: ", ") + " ]"
    }
}

public extension Array {
    func appending(_ other: Element?) -> [Element] {
        guard let other: Element = other else { return self }
        
        var updatedArray: [Element] = self
        updatedArray.append(other)
        return updatedArray
    }
    
    func appending(contentsOf other: [Element]?) -> [Element] {
        guard let other: [Element] = other else { return self }
        
        var updatedArray: [Element] = self
        updatedArray.append(contentsOf: other)
        return updatedArray
    }
}


public extension Array where Element: Hashable {
    func asSet() -> Set<Element> {
        return Set(self)
    }
}
