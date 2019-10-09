
@objc(LKUserSelectionViewDelegate)
protocol UserSelectionViewDelegate {
    
    func handleUserSelected(_ user: String, from userSelectionView: UserSelectionView)
}
