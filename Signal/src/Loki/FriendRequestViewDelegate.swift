
@objc protocol FriendRequestViewDelegate {
    /// Implementations of this method should update the thread's friend request status
    /// and send a friend request accepted message.
    @objc func acceptFriendRequest(_ friendRequest: TSIncomingMessage)
    /// Implementations of this method should update the thread's friend request status
    /// and remove the prekeys associated with the contact.
    @objc func declineFriendRequest(_ friendRequest: TSIncomingMessage)
}
