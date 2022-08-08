
@objc final class SNAppearance : NSObject {

    @objc static func switchToSessionAppearance() {
        UINavigationBar.appearance().barTintColor = Colors.navigationBarBackground
        UINavigationBar.appearance().isTranslucent = false
        UINavigationBar.appearance().tintColor = Colors.text
        UIToolbar.appearance().barTintColor = Colors.navigationBarBackground
        UIToolbar.appearance().isTranslucent = false
        UIToolbar.appearance().tintColor = Colors.text
        UISwitch.appearance().onTintColor = Colors.accent
        UINavigationBar.appearance().titleTextAttributes = [ NSAttributedString.Key.foregroundColor : Colors.text ]
    }

    @objc static func switchToImagePickerAppearance() {
        UINavigationBar.appearance().barTintColor = .white
        UINavigationBar.appearance().isTranslucent = false
        UINavigationBar.appearance().tintColor = .black
        UINavigationBar.appearance().titleTextAttributes = [ NSAttributedString.Key.foregroundColor : UIColor.black ]
    }

    @objc static func switchToDocumentPickerAppearance() {
        let textColor: UIColor = isDarkMode ? .white : .black
        UINavigationBar.appearance().tintColor = textColor
        UINavigationBar.appearance().titleTextAttributes = [ NSAttributedString.Key.foregroundColor : textColor ]
    }
}
