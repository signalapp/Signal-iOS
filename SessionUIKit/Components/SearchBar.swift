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
        tintColor = Colors.text // The cursor color
        let searchImage = #imageLiteral(resourceName: "searchbar_search").withTint(Colors.searchBarPlaceholder)!
        setImage(searchImage, for: .search, state: .normal)
        let clearImage = #imageLiteral(resourceName: "searchbar_clear").withTint(Colors.searchBarPlaceholder)!
        setImage(clearImage, for: .clear, state: .normal)
        let searchTextField: UITextField = self.searchTextField
        searchTextField.backgroundColor = Colors.searchBarBackground // The search bar background color
        searchTextField.textColor = Colors.text
        searchTextField.attributedPlaceholder = NSAttributedString(string: "Search", attributes: [ .foregroundColor : Colors.searchBarPlaceholder ])
        setPositionAdjustment(UIOffset(horizontal: 4, vertical: 0), for: UISearchBar.Icon.search)
        searchTextPositionAdjustment = UIOffset(horizontal: 2, vertical: 0)
        setPositionAdjustment(UIOffset(horizontal: -4, vertical: 0), for: UISearchBar.Icon.clear)
    }
    
    func setUpContactSearchStyle() {
        searchBarStyle = .minimal
        barStyle = .default
        tintColor = Colors.text
        let searchImage = #imageLiteral(resourceName: "searchbar_search").withTint(Colors.text)!
        setImage(searchImage, for: .search, state: .normal)
        let clearImage = #imageLiteral(resourceName: "searchbar_clear").withTint(Colors.text)!
        setImage(clearImage, for: .clear, state: .normal)
        let searchTextField: UITextField = self.searchTextField
        searchTextField.borderStyle = .none
        searchTextField.layer.cornerRadius = 18
        searchTextField.backgroundColor = .white // The search bar background color
        searchTextField.textColor = Colors.text
        searchTextField.attributedPlaceholder = NSAttributedString(string: "Search Contacts", attributes: [ .foregroundColor : Colors.searchBarPlaceholder ])
        setPositionAdjustment(UIOffset(horizontal: 4, vertical: 0), for: UISearchBar.Icon.search)
        searchTextPositionAdjustment = UIOffset(horizontal: 2, vertical: 0)
        setPositionAdjustment(UIOffset(horizontal: -4, vertical: 0), for: UISearchBar.Icon.clear)
    }
}
