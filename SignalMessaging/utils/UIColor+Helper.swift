extension UIColor {
    public func adjust(hueBy degrees: CGFloat) -> UIColor {
        
        var currentHue: CGFloat = 0.0
        var currentSaturation: CGFloat = 0.0
        var currentBrigthness: CGFloat = 0.0
        var currentAlpha: CGFloat = 0.0
        
        if getHue(&currentHue, saturation: &currentSaturation, brightness: &currentBrigthness, alpha: &currentAlpha) {
            // Round values so we get closer values to Desktop
            let currentHueDegrees = (currentHue * 360.0).rounded()
            let normalizedDegrees = fmod(degrees, 360.0).rounded()
            
            // Make sure we're in the range 0 to 360
            var newHue = fmod(currentHueDegrees + normalizedDegrees, 360.0)
            if (newHue < 0) { newHue = 360 + newHue }
            
            let decimalHue = (currentHueDegrees + normalizedDegrees) / 360.0
            
            return UIColor(hue: decimalHue,
                           saturation: currentSaturation,
                           brightness: currentBrigthness,
                           alpha: 1.0)
        } else {
            return self
        }
    }
    
    convenience init(red: Int, green: Int, blue: Int, a: CGFloat = 1.0) {
        self.init(
            red: CGFloat(red) / 255.0,
            green: CGFloat(green) / 255.0,
            blue: CGFloat(blue) / 255.0,
            alpha: a
        )
    }
    
    convenience init(rgb: Int, a: CGFloat = 1.0) {
        self.init(
            red: (rgb >> 16) & 0xFF,
            green: (rgb >> 8) & 0xFF,
            blue: rgb & 0xFF,
            a: a
        )
    }
}
