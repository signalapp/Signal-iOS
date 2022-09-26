// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit

public final class SearchBar : UISearchBar {
    
    public override init(frame: CGRect) {
        super.init(frame: frame)
        setUpSessionStyle()
    }
    
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUpSessionStyle()
    }
}

public final class ContactsSearchBar : UISearchBar {
    
    public override init(frame: CGRect) {
        super.init(frame: frame)
        setUpContactSearchStyle()
    }
    
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUpContactSearchStyle()
    }
}

public extension UISearchBar {
    
    func setUpSessionStyle() {
        searchBarStyle = .minimal // Hide the border around the search bar
        barStyle = .black // Use Apple's black design as a base
        themeTintColor = .textPrimary // The cursor color
        
        let searchImage: UIImage = #imageLiteral(resourceName: "searchbar_search").withRenderingMode(.alwaysTemplate)
        setImage(searchImage, for: .search, state: .normal)
        searchTextField.leftView?.themeTintColor = .textSecondary
        
        let clearImage: UIImage = #imageLiteral(resourceName: "searchbar_clear").withRenderingMode(.alwaysTemplate)
        setImage(clearImage, for: .clear, state: .normal)
        
        let searchTextField: UITextField = self.searchTextField
        searchTextField.themeBackgroundColor = .messageBubble_overlay // The search bar background color
        searchTextField.themeTextColor = .textPrimary
        setPositionAdjustment(UIOffset(horizontal: 4, vertical: 0), for: UISearchBar.Icon.search)
        searchTextPositionAdjustment = UIOffset(horizontal: 2, vertical: 0)
        setPositionAdjustment(UIOffset(horizontal: -4, vertical: 0), for: UISearchBar.Icon.clear)
        
        ThemeManager.onThemeChange(observer: searchTextField) { [weak searchTextField] theme, _ in
            guard let textColor: UIColor = theme.color(for: .textSecondary) else { return }
            
            searchTextField?.attributedPlaceholder = NSAttributedString(
                string: "Search",
                attributes: [
                    .foregroundColor: textColor
                ])
        }
    }
    
    func setUpContactSearchStyle() {
        searchBarStyle = .minimal
        barStyle = .default
        themeTintColor = .textPrimary
        
        let searchImage = #imageLiteral(resourceName: "searchbar_search").withRenderingMode(.alwaysTemplate)
        setImage(searchImage, for: .search, state: .normal)
        searchTextField.leftView?.themeTintColor = .textSecondary
        
        let clearImage = #imageLiteral(resourceName: "searchbar_clear").withRenderingMode(.alwaysTemplate)
        setImage(clearImage, for: .clear, state: .normal)
        
        let searchTextField: UITextField = self.searchTextField
        searchTextField.borderStyle = .none
        searchTextField.layer.cornerRadius = 18
        searchTextField.themeBackgroundColor = .backgroundPrimary
        searchTextField.themeTextColor = .textPrimary
        setPositionAdjustment(UIOffset(horizontal: 4, vertical: 0), for: UISearchBar.Icon.search)
        searchTextPositionAdjustment = UIOffset(horizontal: 2, vertical: 0)
        setPositionAdjustment(UIOffset(horizontal: -4, vertical: 0), for: UISearchBar.Icon.clear)
        
        ThemeManager.onThemeChange(observer: searchTextField) { [weak searchTextField] theme, _ in
            guard let textColor: UIColor = theme.color(for: .textSecondary) else { return }
            
            searchTextField?.attributedPlaceholder = NSAttributedString(
                string: "Search Contacts",
                attributes: [
                    .foregroundColor: textColor
                ]
            )
        }
    }
}
