// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation

public extension Set {
    func inserting(_ value: Element?) -> Set<Element> {
        guard let value: Element = value else { return self }
        
        var updatedSet: Set<Element> = self
        updatedSet.insert(value)
        
        return updatedSet
    }
    
    func inserting(contentsOf value: Set<Element>?) -> Set<Element> {
        guard let value: Set<Element> = value else { return self }
        
        var updatedSet: Set<Element> = self
        value.forEach { updatedSet.insert($0) }
        
        return updatedSet
    }
    
    func removing(_ value: Element?) -> Set<Element> {
        guard let value: Element = value else { return self }
        
        var updatedSet: Set<Element> = self
        updatedSet.remove(value)
        
        return updatedSet
    }
}
