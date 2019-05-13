
@objc protocol FriendRequestViewDelegate {
    @objc func acceptFriendRequest(_ friendRequest: TSIncomingMessage)
    @objc func declineFriendRequest(_ friendRequest: TSIncomingMessage)
}
