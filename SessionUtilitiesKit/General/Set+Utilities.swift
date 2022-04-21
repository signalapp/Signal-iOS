// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation

public extension Set {
    func inserting(_ value: Element?) -> Set<Element> {
        guard let value: Element = value else { return self }
        
        var updatedSet: Set<Element> = self
        updatedSet.insert(value)
        
        return updatedSet
    }
    
    func removing(_ value: Element?) -> Set<Element> {
        guard let value: Element = value else { return self }
        
        var updatedSet: Set<Element> = self
        updatedSet.remove(value)
        
        return updatedSet
    }
}
