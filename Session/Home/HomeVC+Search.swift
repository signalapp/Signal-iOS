import UIKit

extension HomeVC: UISearchBarDelegate, GlobalSearchViewDelegate {
    
    func GlobalSearchViewWillBeginDragging() {
        
    }
    
    // MARK: UISearchBarDelegate
    
    func searchBarTextDidBeginEditing(_ searchBar: UISearchBar) {
        self.ensureSearchBarCancelButton()
    }
    
    func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
        searchBar.text = nil
        searchBar.resignFirstResponder()
        self.ensureSearchBarCancelButton()
    }
    
    func ensureSearchBarCancelButton() {
        let shouldShowCancelButton = searchBar.isFirstResponder
        guard searchBar.showsCancelButton != shouldShowCancelButton else { return }
        self.searchBar.setShowsCancelButton(shouldShowCancelButton, animated: true)
    }
}
