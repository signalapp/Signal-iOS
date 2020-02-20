//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

@objc
public extension NewGroupViewController {
    // GroupsV2 TODO: Convert avatarImage to avatarData.    
    func createGroupThread(name: String?,
                           avatarImage: UIImage?,
                           members: [SignalServiceAddress],
                           newGroupSeed: NewGroupSeed) {

        // GroupsV2 TODO: Should we allow cancel here?
        ModalActivityIndicatorViewController.present(fromViewController: self,
                                                     canCancel: false) { modalActivityIndicator in
                                                        firstly {
                                                            GroupManager.localCreateNewGroup(members: members,
                                                                                             groupId: nil,
                                                                                             name: name,
                                                                                             avatarImage: avatarImage,
                                                                                             newGroupSeed: newGroupSeed,
                                                                                             shouldSendMessage: true)
                                                        }.done { groupThread in
                                                            modalActivityIndicator.dismiss {
                                                                SignalApp.shared().presentConversation(for: groupThread,
                                                                                                       action: .compose,
                                                                                                       animated: false)
                                                            }
                                                        }.catch { error in
                                                            owsFailDebug("Could not create group: \(error)")

                                                            modalActivityIndicator.dismiss {
                                                                NewGroupViewController.showCreateErrorUI(error: error)
                                                            }
                                                        }.retainUntilComplete()
        }
    }

    class func showCreateErrorUI(error: Error) {
        AssertIsOnMainThread()

        let showUpdateNetworkErrorUI = {
            OWSActionSheets.showActionSheet(title: NSLocalizedString("NEW_GROUP_CREATION_FAILED_DUE_TO_NETWORK",
                                                                     comment: "Error indicating that a new group could not be created due to network connectivity problems."))
        }

        if error.isNetworkConnectivityFailure {
            return showUpdateNetworkErrorUI()
        }

        switch error {
        case GroupsV2Error.timeout:
            return showUpdateNetworkErrorUI()
        default:
            OWSActionSheets.showActionSheet(title: NSLocalizedString("NEW_GROUP_CREATION_FAILED",
                                                                     comment: "Error indicating that a new group could not be created."))
        }
    }
}
