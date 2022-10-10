// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation

public extension NSAttributedString {
    static func with(_ attrStrings: [NSAttributedString]) -> NSAttributedString {
        let mutableString: NSMutableAttributedString = NSMutableAttributedString()
        
        for attrString in attrStrings {
            mutableString.append(attrString)
        }
        
        return mutableString
    }
    
    func appending(_ attrString: NSAttributedString) -> NSAttributedString {
        let mutableString: NSMutableAttributedString = NSMutableAttributedString(attributedString: self)
        mutableString.append(attrString)

        return mutableString
    }
    
    func appending(string: String, attributes: [Key: Any]? = nil) -> NSAttributedString {
        return appending(NSAttributedString(string: string, attributes: attributes))
    }
    
    func adding(attributes: [Key: Any], range: NSRange) -> NSAttributedString {
        let mutableString: NSMutableAttributedString = NSMutableAttributedString(attributedString: self)
        mutableString.addAttributes(attributes, range: range)

        return mutableString
    }

    // The actual Swift implementation of 'uppercased' is pretty nuts (see
    // https://github.com/apple/swift/blob/main/stdlib/public/core/String.swift#L901)
    // this approach is definitely less efficient but is much simpler and less likely to break
    private enum CharacterCasing {
        static let map: [UTF16.CodeUnit: String.UTF16View] = [
            "a": "A", "b": "B", "c": "C", "d": "D", "e": "E", "f": "F", "g": "G",
            "h": "H", "i": "I", "j": "J", "k": "K", "l": "L", "m": "M", "n": "N",
            "o": "O", "p": "P", "q": "Q", "r": "R", "s": "S", "t": "T", "u": "U",
            "v": "V", "w": "W", "x": "X", "y": "Y", "z": "Z"
        ]
        .reduce(into: [:]) { prev, next in
            prev[next.key.utf16.first ?? UTF16.CodeUnit()] = next.value.utf16
        }
    }
    
    func uppercased() -> NSAttributedString {
        let result = NSMutableAttributedString(attributedString: self)
        let uppercasedCharacters = result.string.utf16.map { utf16Char in
            // Try convert the individual utf16 character to it's uppercase variant
            // or fallback to the original character
            (CharacterCasing.map[utf16Char]?.first ?? utf16Char)
        }
        
        result.replaceCharacters(
            in: NSRange(location: 0, length: length),
            with: String(utf16CodeUnits: uppercasedCharacters, count: length)
        )

        return result
    }
}
