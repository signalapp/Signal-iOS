import CryptoSwift

public class PlaceholderIcon {
    private let seed: Int
    // Colour palette
    private var colours: [UIColor] = [
       0x5ff8b0,
       0x26cdb9,
       0xf3c615,
       0xfcac5a
    ].map { UIColor(hex: $0) }
    
    init(seed: Int, colours: [UIColor]? = nil) {
        self.seed = seed
        if let colours = colours { self.colours = colours }
    }
    
    convenience init(seed: String, colours: [UIColor]? = nil) {
        // Ensure we have a correct hash
        var hash = seed
        if (hash.matches("^[0-9A-Fa-f]+$") && hash.count >= 12) { hash = seed.sha512() }
        
        guard let number = Int(hash.substring(to: 12), radix: 16) else {
            owsFailDebug("Failed to generate number from seed string: \(seed).")
            self.init(seed: 0, colours: colours)
            return
        }
        
        self.init(seed: number, colours: colours)
    }
    
    public func generateLayer(with diameter: CGFloat, text: String) -> CALayer {
        let colour = self.colours[seed % self.colours.count].cgColor
        let base = getTextLayer(with: diameter, colour: colour, text: text)
        base.masksToBounds = true
        return base
    }
    
    private func getTextLayer(with diameter: CGFloat, colour: CGColor? = nil, text: String) -> CALayer {
        let text = text.capitalized
        let font = UIFont.boldSystemFont(ofSize: diameter / 2)
        let height = NSString(string: text).boundingRect(with: CGSize(width: diameter, height: CGFloat.greatestFiniteMagnitude),
            options: .usesLineFragmentOrigin, attributes: [ NSAttributedString.Key.font : font ], context: nil).height
        let frame = CGRect(x: 0, y: (diameter - height) / 2, width: diameter, height: height)
        
        let layer = CATextLayer()
        layer.frame = frame
        layer.foregroundColor = UIColor.white.cgColor
        layer.contentsScale = UIScreen.main.scale
        
        let fontName = font.fontName
        let fontRef = CGFont(fontName as CFString)
        layer.font = fontRef
        layer.fontSize = font.pointSize
        layer.alignmentMode = .center
        
        layer.string = text
        
        let base = CALayer()
        base.frame = CGRect(x: 0, y: 0, width: diameter, height: diameter)
        base.backgroundColor = colour
        base.addSublayer(layer)
        
        return base
    }
}

private extension String {
    
    func matches(_ regex: String) -> Bool {
        return self.range(of: regex, options: .regularExpression, range: nil, locale: nil) != nil
    }
}
