//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit

#if USE_DEBUG_UI

class DebugUIMessagesAction: Dependencies {

    typealias Completion = (Result<Void, Error>) -> Void

    let label: String

    fileprivate init(label: String) {
        self.label = label
    }

    fileprivate func nextActionToPerform() -> DebugUIMessagesSingleAction {
        return self as! DebugUIMessagesSingleAction
    }

    fileprivate func prepare(completion: @escaping Completion) {
        completion(.success(()))
    }

    func prepareAndPerformNTimes(_ count: UInt) {
        prepare { result in
            switch result {
            case .success:
                self.performNTimes(count, completion: { _ in })
            case .failure:
                break
            }
        }
    }

    private func performNTimes(_ count: UInt, completion: @escaping Completion) {
        Logger.info("\(label) performNTimes: \(count)")
        Logger.flush()

        guard count > 0 else {
            completion(.success(()))
            return
        }

        var runCount = count
        databaseStorage.write { transaction in
            var batchSize = 0
            while runCount > 0 {
                let index = runCount

                let action = nextActionToPerform()
                if let staggeredAction = action.staggeredAction {
                    owsAssertDebug(action.unstaggeredAction == nil)
                    staggeredAction(index, transaction, { result in
                        switch result {
                        case .success:
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                                Logger.info("\(self.label) performNTimes success: \(runCount)")
                                self.performNTimes(runCount - 1, completion: completion)
                            }
                        case .failure(let error):
                            completion(.failure(error))
                        }
                    })
                    break
                } else if let unstaggeredAction = action.unstaggeredAction {
                    // TODO: We could check result for failure.
                    unstaggeredAction(index, transaction)

                    let maxBatchSize = 2500
                    batchSize += 1
                    if batchSize >= maxBatchSize {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                            Logger.info("\(self.label) performNTimes success: \(runCount)")
                            self.performNTimes(runCount - 1, completion: completion)
                        }
                        break
                    }
                    runCount -= 1
                } else {
                    owsFailDebug("No staggeredActionBlock / unstaggeredActionBlock")
                }
            }
        }
    }
}

class DebugUIMessagesSingleAction: DebugUIMessagesAction {

    typealias StaggeredAction = (UInt, SDSAnyWriteTransaction, @escaping Completion) -> Void
    typealias UnstaggeredAction = (UInt, SDSAnyWriteTransaction) -> Void

    private(set) var prepare: ((@escaping Completion) -> Void)?
    private(set) var staggeredAction: StaggeredAction?
    private(set) var unstaggeredAction: UnstaggeredAction?

    init(label: String, staggeredAction: @escaping StaggeredAction, prepare: ((@escaping Completion) -> Void)? = nil) {
        super.init(label: label)
        self.staggeredAction = staggeredAction
        self.prepare = prepare
    }

    init(label: String, unstaggeredAction: @escaping UnstaggeredAction, prepare: ((@escaping Completion) -> Void)? = nil) {
        super.init(label: label)
        self.unstaggeredAction = unstaggeredAction
        self.prepare = prepare
    }

    override func prepare(completion: @escaping Completion) {
        guard let prepare else {
            completion(.success(()))
            return
        }
        prepare(completion)
    }
}

class DebugUIMessagesGroupAction: DebugUIMessagesAction {

    enum SubactionMode {
        case random
        case ordered
    }
    let mode: SubactionMode
    let subactions: [DebugUIMessagesAction]
    private var subactionIndex: Array.Index = 0

    private init(label: String, subactions: [DebugUIMessagesAction], mode: SubactionMode) {
        self.subactions = subactions
        self.mode = mode
        super.init(label: label)
        subactionIndex = subactions.startIndex
    }

    // Given a group of subactions, perform a single random subaction each time.
    final class func randomGroupActionWithLabel(_ label: String, subactions: [DebugUIMessagesAction]) -> DebugUIMessagesAction {
        return DebugUIMessagesGroupAction(label: label, subactions: subactions, mode: .random)
    }

    // Given a group of subactions, perform the subactions in order.
    //
    // If prepareAndPerformNTimes: is called with count == subactions.count, all of the subactions
    // are performed exactly once.
    final class func allGroupActionWithLabel(_ label: String, subactions: [DebugUIMessagesAction]) -> DebugUIMessagesAction {
        return DebugUIMessagesGroupAction(label: label, subactions: subactions, mode: .ordered)
    }

    override func nextActionToPerform() -> DebugUIMessagesSingleAction {
        let subaction: DebugUIMessagesAction = {
            switch mode {
            case .random:
                return subactions.randomElement()!

            case .ordered:
                let subaction = subactions[subactionIndex]
                if subactionIndex < subactions.endIndex {
                    subactionIndex = subactions.index(after: subactionIndex)
                } else {
                    subactionIndex = subactions.startIndex
                }
                return subaction
            }
        }()
        return subaction.nextActionToPerform()
    }

    override func prepare(completion: @escaping Completion) {
        DebugUIMessagesGroupAction.prepareSubactions(subactions, completion: completion)
    }

    private static func prepareSubactions(_ subactions: [DebugUIMessagesAction], completion: @escaping Completion) {
        guard !subactions.isEmpty else {
            completion(.success(()))
            return
        }

        var unpreparedSubactions = subactions
        let nextAction = unpreparedSubactions.popLast()!
        Logger.info("Preparing: \(nextAction.label)")
        Logger.flush()
        nextAction.prepare { result in
            switch result {
            case .success:
                self.prepareSubactions(unpreparedSubactions, completion: completion)

            case .failure:
                break
            }
        }
    }

}

#endif
