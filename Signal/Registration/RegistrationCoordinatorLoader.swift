//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit

/// Loads a `RegistrationCoordinator`.
/// This class exists separately from the coordinator itself so that we separate
/// state which determines whether we _need_ a coordinator from the coordinator itself.
/// When we instantiate a coordinator, its because we intend to use it; its entire lifecycle
/// can assume this and be simpler as a result.
public protocol RegistrationCoordinatorLoader {

    /// If the return value is non-nil, the user had an in-progress registration that can (typically, must) be restored.
    func restoreLastMode(transaction: DBReadTransaction) -> RegistrationMode?

    /// `desiredMode` may not be the mode we end up in; for example if we
    /// were in the middle of re-registration and try to change number, that will
    /// be disallowed and we will fall back to re-registration.
    func coordinator(forDesiredMode: RegistrationMode, transaction: DBWriteTransaction) -> RegistrationCoordinator

    /// If true, message processing should be paused due to an in-progress change number.
    func hasPendingChangeNumber(transaction: DBReadTransaction) -> Bool
}

public class RegistrationCoordinatorLoaderImpl: RegistrationCoordinatorLoader {

    public enum Mode: Codable, Equatable {
        case registering(RegisteringState)
        case reRegistering(ReRegisteringState)
        case changingNumber(ChangeNumberState)

        public struct RegisteringState: Codable, Equatable {
            fileprivate init() {}
        }

        public struct ReRegisteringState: Codable, Equatable {
            public let e164: E164
            public let aci: UUID

            fileprivate init(e164: E164, aci: UUID) {
                self.e164 = e164
                self.aci = aci
            }
        }

        public struct ChangeNumberState: Codable, Equatable {
            public let oldE164: E164
            public let oldAuthToken: String
            public let localAci: UUID
            public let localAccountId: String
            public let localDeviceId: UInt32
            public let localUserAllDeviceIds: [UInt32]

            public struct PendingPniState: Equatable {
                public let newE164: E164
                public let pniIdentityKeyPair: ECKeyPair
                public let localDevicePniSignedPreKeyRecord: SignedPreKeyRecord
                public let localDevicePniPqLastResortPreKeyRecord: KyberPreKeyRecord?
                public let localDevicePniRegistrationId: UInt32
            }

            public fileprivate(set) var pniState: PendingPniState?

            fileprivate init(
                oldE164: E164,
                oldAuthToken: String,
                localAci: UUID,
                localAccountId: String,
                localDeviceId: UInt32,
                localUserAllDeviceIds: [UInt32],
                pniState: PendingPniState?
            ) {
                self.oldE164 = oldE164
                self.oldAuthToken = oldAuthToken
                self.localAci = localAci
                self.localAccountId = localAccountId
                self.localDeviceId = localDeviceId
                self.localUserAllDeviceIds = localUserAllDeviceIds
                self.pniState = pniState
            }
        }

        var hasPendingChangeNumber: Bool {
            switch self {
            case .registering, .reRegistering:
                return false
            case .changingNumber(let state):
                return state.pniState != nil
            }
        }
    }

    private lazy var kvStore: KeyValueStore = {
        deps.keyValueStoreFactory.keyValueStore(collection: Constants.collectionName)
    }()

    private let deps: RegistrationCoordinatorDependencies

    public init(dependencies: RegistrationCoordinatorDependencies) {
        self.deps = dependencies
    }

    public func restoreLastMode(transaction: DBReadTransaction) -> RegistrationMode? {
        return loadMode(transaction: transaction)?.asRegistrationMode()
    }

    public func coordinator(
        forDesiredMode desiredMode: RegistrationMode,
        transaction: DBWriteTransaction
    ) -> RegistrationCoordinator {
        let mode = loadMode(transaction: transaction) ?? desiredMode.asInternalMode()
        do {
            try self.kvStore.setCodable(mode, key: Constants.modeKey, transaction: transaction)
        } catch {
            owsFailDebug("Failed to write registration mode to disk: \(error)")
        }
        if mode.hasPendingChangeNumber {
            // This should happen on app startup, but do it here too to be safe.
            deps.messagePipelineSupervisor.suspendMessageProcessingWithoutHandle(for: .pendingChangeNumber)
        }
        let delegate = CoordinatorDelegate(loader: self)
        Logger.info("Starting registration, mode: \(mode.logString)")
        return RegistrationCoordinatorImpl(mode: mode, loader: delegate, dependencies: deps)
    }

    public func hasPendingChangeNumber(transaction: DBReadTransaction) -> Bool {
        return loadMode(transaction: transaction)?.hasPendingChangeNumber ?? false
    }

    private func loadMode(transaction: DBReadTransaction) -> Mode? {
        do {
            return try kvStore.getCodableValue(forKey: Constants.modeKey, transaction: transaction)
        } catch {
            // Failed to parse, even though we know there is something there.
            // This is BAD. We might've been in the middle of change number, which NEEDS to recover.
            owsFail("Unable to restore in-progress registration mode: \(error)")
        }
    }

    // Here we put methods from this loader impl class that we want to expose to
    // RegistrationCoordinatorImpl but not expose to anything else.
    // This misdirection only exists because we have one big package and `internal`
    // is meaningless; ideally RegistrationCoordinatorImpl and RegistrationCoordinatorLoaderImpl
    // would get to talk to each other in their own internal API and expose only public things
    // to the outside world.
    class CoordinatorDelegate: RegistrationCoordinatorLoaderDelegate {

        let loader: RegistrationCoordinatorLoaderImpl

        // Its important that this initializer be fileprivate; nothing outside of this
        // class should initialize one of these.
        fileprivate init(loader: RegistrationCoordinatorLoaderImpl) {
            self.loader = loader
        }

        func clearPersistedMode(transaction: DBWriteTransaction) {
            loader.kvStore.removeValue(forKey: Constants.modeKey, transaction: transaction)
        }

        func savePendingChangeNumber(
            oldState: Mode.ChangeNumberState,
            pniState: Mode.ChangeNumberState.PendingPniState?,
            transaction: DBWriteTransaction
        ) throws -> Mode.ChangeNumberState {
            var newState = oldState
            newState.pniState = pniState
            try loader.kvStore.setCodable(Mode.changingNumber(newState), key: Constants.modeKey, transaction: transaction)
            transaction.addAsyncCompletion(on: loader.deps.schedulers.main) { [messagePipelineSupervisor = loader.deps.messagePipelineSupervisor] in
                if Mode.changingNumber(newState).hasPendingChangeNumber {
                    messagePipelineSupervisor.suspendMessageProcessingWithoutHandle(for: .pendingChangeNumber)
                } else {
                    messagePipelineSupervisor.unsuspendMessageProcessing(for: .pendingChangeNumber)
                }
            }
            return newState
        }
    }

    enum Constants {
        static let collectionName = "RegistrationCoordinatorLoader"
        static let modeKey = "mode"
    }
}

// MARK: - Mode Transformers

extension RegistrationMode {

    fileprivate func asInternalMode() -> RegistrationCoordinatorLoaderImpl.Mode {
        switch self {
        case .registering:
            return .registering(.init())
        case .reRegistering(let params):
            return .reRegistering(.init(e164: params.e164, aci: params.aci))
        case .changingNumber(let params):
            return .changingNumber(.init(
                oldE164: params.oldE164,
                oldAuthToken: params.oldAuthToken,
                localAci: params.localAci,
                localAccountId: params.localAccountId,
                localDeviceId: params.localDeviceId,
                localUserAllDeviceIds: params.localUserAllDeviceIds,
                pniState: nil
            ))
        }
    }
}

extension RegistrationCoordinatorLoaderImpl.Mode {

    fileprivate func asRegistrationMode() -> RegistrationMode {
        switch self {
        case .registering:
            return .registering
        case .reRegistering(let state):
            return .reRegistering(.init(e164: state.e164, aci: state.aci))
        case .changingNumber(let state):
            return .changingNumber(.init(
                oldE164: state.oldE164,
                oldAuthToken: state.oldAuthToken,
                localAci: state.localAci,
                localAccountId: state.localAccountId,
                localDeviceId: state.localDeviceId,
                localUserAllDeviceIds: state.localUserAllDeviceIds
            ))
        }
    }

    fileprivate var logString: String {
        switch self {
        case .registering:
            return "initial registration"
        case .reRegistering(let reRegisteringState):
            return "re-registration aci:\(reRegisteringState.aci.uuidString) e164:\(reRegisteringState.e164.stringValue)"
        case .changingNumber(let changeNumberState):
            return "changing number: aci:\(changeNumberState.localAci.uuidString) old e164:\(changeNumberState.oldE164.stringValue)"
        }
    }
}

// MARK: - PNI state transformers

extension RegistrationCoordinatorLoaderImpl.Mode.ChangeNumberState.PendingPniState {

    func asPniState() -> ChangePhoneNumberPni.PendingState {
        return ChangePhoneNumberPni.PendingState(
            newE164: newE164,
            pniIdentityKeyPair: pniIdentityKeyPair,
            localDevicePniSignedPreKeyRecord: localDevicePniSignedPreKeyRecord,
            localDevicePniPqLastResortPreKeyRecord: localDevicePniPqLastResortPreKeyRecord,
            localDevicePniRegistrationId: localDevicePniRegistrationId
        )
    }
}

extension ChangePhoneNumberPni.PendingState {

    func asRegPniState() -> RegistrationCoordinatorLoaderImpl.Mode.ChangeNumberState.PendingPniState {
        return RegistrationCoordinatorLoaderImpl.Mode.ChangeNumberState.PendingPniState(
            newE164: newE164,
            pniIdentityKeyPair: pniIdentityKeyPair,
            localDevicePniSignedPreKeyRecord: localDevicePniSignedPreKeyRecord,
            localDevicePniPqLastResortPreKeyRecord: localDevicePniPqLastResortPreKeyRecord,
            localDevicePniRegistrationId: localDevicePniRegistrationId
        )
    }
}

// MARK: - PNI state Codable

extension RegistrationCoordinatorLoaderImpl.Mode.ChangeNumberState.PendingPniState: Codable {
    private enum CodingKeys: String, CodingKey {
        case newE164
        case pniIdentityKeyPair
        case localDevicePniSignedPreKeyRecord
        case localDevicePniPqLastResortPreKeyRecord
        case localDevicePniRegistrationId
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.newE164 = try container.decode(E164.self, forKey: .newE164)
        self.localDevicePniRegistrationId = try container.decode(UInt32.self, forKey: .localDevicePniRegistrationId)
        self.localDevicePniPqLastResortPreKeyRecord = try container.decodeIfPresent(KyberPreKeyRecord.self, forKey: .localDevicePniPqLastResortPreKeyRecord)

        guard
            let pniIdentityKeyPair: ECKeyPair = try Self.decodeKeyedArchive(
                fromDecodingContainer: container,
                forKey: .pniIdentityKeyPair
            ),
            let localDevicePniSignedPreKeyRecord: SignedPreKeyRecord = try Self.decodeKeyedArchive(
                fromDecodingContainer: container,
                forKey: .localDevicePniSignedPreKeyRecord
            )
        else {
            throw OWSAssertionError("Unable to deserialize NSKeyedArchiver fields!")
        }

        self.pniIdentityKeyPair = pniIdentityKeyPair
        self.localDevicePniSignedPreKeyRecord = localDevicePniSignedPreKeyRecord
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(newE164, forKey: .newE164)
        try container.encode(localDevicePniRegistrationId, forKey: .localDevicePniRegistrationId)
        try container.encode(localDevicePniPqLastResortPreKeyRecord, forKey: .localDevicePniPqLastResortPreKeyRecord)

        try Self.encodeKeyedArchive(
            value: pniIdentityKeyPair,
            toEncodingContainer: &container,
            forKey: .pniIdentityKeyPair
        )

        try Self.encodeKeyedArchive(
            value: localDevicePniSignedPreKeyRecord,
            toEncodingContainer: &container,
            forKey: .localDevicePniSignedPreKeyRecord
        )
    }

    // MARK: NSKeyed[Un]Archiver

    private static func decodeKeyedArchive<T: NSObject & NSSecureCoding>(
        fromDecodingContainer decodingContainer: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) throws -> T? {
        let data = try decodingContainer.decode(Data.self, forKey: key)

        return try NSKeyedUnarchiver.unarchivedObject(ofClass: T.self, from: data)
    }

    private static func encodeKeyedArchive<T: NSObject & NSSecureCoding>(
        value: T,
        toEncodingContainer encodingContainer: inout KeyedEncodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) throws {
        let data = try NSKeyedArchiver.archivedData(
            withRootObject: value,
            requiringSecureCoding: true
        )

        try encodingContainer.encode(data, forKey: key)
    }
}
