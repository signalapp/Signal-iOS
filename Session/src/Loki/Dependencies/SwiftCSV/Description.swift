//
//  Description.swift
//  SwiftCSV
//
//  Created by Will Richardson on 11/04/16.
//  Copyright © 2016 Naoto Kaneko. All rights reserved.
//

import Foundation

extension CSV: CustomStringConvertible {
    public var description: String {
        let head = header.joined(separator: ",") + "\n"
        let cont = namedRows.map { row in
            return header.map { key -> String in
                let value = row[key]!
                
                // Add quotes if value contains a comma
                if value.contains(",") {
                    return "\"\(value)\""
                }
                return value
                
            }.joined(separator: ",")
            
        }.joined(separator: "\n")
        return head + cont
    }
}

