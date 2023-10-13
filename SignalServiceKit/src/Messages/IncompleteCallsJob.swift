//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalCoreKit

public class IncompleteCallsJob {
    private var count: UInt = 0
    private let cutoffTimestamp = CurrentAppContext().appLaunchTime.ows_millisecondsSince1970
    public init() {}

    public func runSync(databaseStorage: SDSDatabaseStorage) {
        databaseStorage.write { writeTx in
            InteractionFinder.incompleteCallIds(transaction: writeTx).forEach { incompleteCallId in
                // Since we can't directly mutate the enumerated "incomplete" calls, we store only their ids in hopes
                // of saving a little memory and then enumerate the (larger) TSCall objects one at a time.
                autoreleasepool {
                    updateIncompleteCallIfNecessary(incompleteCallId, transaction: writeTx)
                }
            }
        }
        Logger.info("Finished job. Updated \(count) incomplete calls")
    }

    private func updateIncompleteCallIfNecessary(
        _ uniqueId: String,
        transaction writeTx: SDSAnyWriteTransaction
    ) {
        // Preconditions: Must be a valid call that started before the app launched.
        guard
            let call = TSCall.anyFetchCall(uniqueId: uniqueId, transaction: writeTx),
            let callRowId = call.grdbId?.int64Value,
            let contactThread = call.thread(tx: writeTx) as? TSContactThread
        else {
            owsFailDebug("Missing call or thread!")
            return
        }
        guard call.timestamp < cutoffTimestamp else {
            Logger.info("Ignoring new call: \(call.uniqueId)")
            return
        }

        // Update
        let targetCallType: RPRecentCallType
        switch call.callType {
        case .outgoingIncomplete:
            targetCallType = .outgoingMissed
        case .incomingIncomplete:
            targetCallType = .incomingMissed
        default:
            owsFailDebug("Call has unexpected type: \(call.callType)")
            return
        }

        DependenciesBridge.shared.individualCallRecordManager
            .updateInteractionTypeAndRecordIfExists(
                individualCallInteraction: call,
                individualCallInteractionRowId: callRowId,
                contactThread: contactThread,
                newCallInteractionType: targetCallType,
                tx: writeTx.asV2Write
            )
        count += 1

        // Log if appropriate
        switch count {
        case ...3:
            Logger.info("marked call as missed: \(call.uniqueId) \(call.timestamp)")
        case 4:
            Logger.info("eliding logs for further incomplete calls. final update count will be reported once complete.")
        default:
            break
        }

        // Postcondition: Should be some kind of missed call
        let validFinalStates: [RPRecentCallType] = [.incomingMissed, .outgoingMissed]
        owsAssertDebug(validFinalStates.contains(call.callType))
    }
}
