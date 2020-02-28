//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

public extension OWSConversationSettingsViewController {

    // MARK: - Dependencies

    private var messageProcessing: MessageProcessing {
        return SSKEnvironment.shared.messageProcessing
    }

    var databaseStorage: SDSDatabaseStorage {
    return .shared
    }

    // MARK: -

    @objc
    func updateDisappearingMessagesConfigurationObjc(_ dmConfiguration: OWSDisappearingMessagesConfiguration,
                                                     thread: TSThread) {

        // GroupsV2 TODO: Should we allow cancel here?
        ModalActivityIndicatorViewController.present(fromViewController: self,
                                                     canCancel: false) { modalActivityIndicator in
                                                        firstly {
                                                            self.updateDisappearingMessagesConfiguration(dmConfiguration,
                                                                                                         thread: thread)
                                                        }.done { _ in
                                                            modalActivityIndicator.dismiss {
                                                                self.navigationController?.popViewController(animated: true)
                                                            }
                                                        }.catch { error in
                                                            switch error {
                                                            case GroupsV2Error.redundantChange:
                                                                // Treat GroupsV2Error.redundantChange as a success.
                                                                modalActivityIndicator.dismiss {
                                                                    self.navigationController?.popViewController(animated: true)
                                                                }
                                                            default:
                                                                owsFailDebug("Could not update group: \(error)")

                                                                modalActivityIndicator.dismiss {
                                                                    UpdateGroupViewController.showUpdateErrorUI(error: error)
                                                                }
                                                            }
                                                        }.retainUntilComplete()
        }
    }
}

// MARK: -

extension OWSConversationSettingsViewController {
    func updateDisappearingMessagesConfiguration(_ dmConfiguration: OWSDisappearingMessagesConfiguration,
                                                 thread: TSThread) -> Promise<Void> {

        return firstly { () -> Promise<Void> in
            guard thread.isGroupV2Thread else {
                return Promise.value(())
            }
            // v2 group updates need to block on message processing.
            return firstly {
                messageProcessing.allMessageFetchingAndProcessingPromise()
            }.timeout(seconds: GroupManager.KGroupUpdateTimeoutDuration) {
                GroupsV2Error.timeout
            }
        }.map(on: .global()) {
            // We're sending a message, so we're accepting any pending message request.
            ThreadUtil.addToProfileWhitelistIfEmptyOrPendingRequestWithSneakyTransaction(thread: thread)
        }.then(on: .global()) {
            GroupManager.localUpdateDisappearingMessages(thread: thread,
                                                         disappearingMessageToken: dmConfiguration.asToken)
        }
    }
}
