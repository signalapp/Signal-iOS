
public enum Hex {
    
    public static func isValid(_ string: String) -> Bool {
        let allowedCharacters = CharacterSet(charactersIn: "0123456789ABCDEF")
        return string.uppercased().unicodeScalars.allSatisfy { allowedCharacters.contains($0) }
    }
}
