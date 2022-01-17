import UIKit

extension HomeVC: UISearchBarDelegate, GlobalSearchViewDelegate {
    
    func globalSearchViewWillBeginDragging() {
        
    }
    
    // MARK: UISearchBarDelegate
    
    func searchBarTextDidBeginEditing(_ searchBar: UISearchBar) {
        self.updateSearchResultsVisibility()
        self.ensureSearchBarCancelButton()
    }
    
    func searchBarTextDidEndEditing(_ searchBar: UISearchBar) {
        self.updateSearchResultsVisibility()
    }
    
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        self.updateSearchResultsVisibility()
        self.ensureSearchBarCancelButton()
    }
    
    func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
        searchBar.text = nil
        searchBar.resignFirstResponder()
        self.ensureSearchBarCancelButton()
    }
    
    func ensureSearchBarCancelButton() {
        let shouldShowCancelButton = searchBar.isFirstResponder || (searchBar.text ?? "").count > 0
        guard searchBar.showsCancelButton != shouldShowCancelButton else { return }
        self.searchBar.setShowsCancelButton(shouldShowCancelButton, animated: true)
    }
    
    func updateSearchResultsVisibility() {
        guard let searchText = searchBar.text?.ows_stripped() else { return }
        searchResultsController.searchText = searchText
        let isSearching = searchText.count > 0
        searchResultsController.view.isHidden = !isSearching
        tableView.isScrollEnabled = !isSearching
    }
}
