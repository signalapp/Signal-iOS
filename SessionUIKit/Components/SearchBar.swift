import UIKit

public final class SearchBar : UISearchBar {
    
    public override init(frame: CGRect) {
        super.init(frame: frame)
        setUpStyle()
    }
    
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUpStyle()
    }
    
    private func setUpStyle() {
        searchBarStyle = .minimal // Hide the border around the search bar
        barStyle = .black // Use Apple's black design as a base
        tintColor = Colors.accent // The cursor color
        let searchImage = #imageLiteral(resourceName: "searchbar_search").withTint(Colors.searchBarPlaceholder)!
        setImage(searchImage, for: .search, state: .normal)
        let clearImage = #imageLiteral(resourceName: "searchbar_clear").withTint(Colors.searchBarPlaceholder)!
        setImage(clearImage, for: .clear, state: .normal)
        let searchTextField: UITextField
        if #available(iOS 13, *) {
            searchTextField = self.searchTextField
        } else {
            searchTextField = self.value(forKey: "_searchField") as! UITextField
        }
        searchTextField.backgroundColor = Colors.searchBarBackground // The search bar background color
        searchTextField.textColor = Colors.text
        searchTextField.attributedPlaceholder = NSAttributedString(string: NSLocalizedString("Search", comment: ""), attributes: [ .foregroundColor : Colors.searchBarPlaceholder ])
        setPositionAdjustment(UIOffset(horizontal: 4, vertical: 0), for: UISearchBar.Icon.search)
        searchTextPositionAdjustment = UIOffset(horizontal: 2, vertical: 0)
        setPositionAdjustment(UIOffset(horizontal: -4, vertical: 0), for: UISearchBar.Icon.clear)
    }
}
