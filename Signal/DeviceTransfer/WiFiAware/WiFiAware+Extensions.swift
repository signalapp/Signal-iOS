//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import Network
import SignalServiceKit
public import WiFiAware

@available(iOS 26.0, *)
enum WiFiAware {
    enum Constants {
        static let deviceTransferServiceName = "_sgnl-transfer._tcp"
        static let appPerformanceMode: WAPerformanceMode = .bulk
        static let appAccessCategory: WAAccessCategory = .bestEffort
        static let appServiceClass: NWParameters.ServiceClass = appAccessCategory.serviceClass
    }

    enum NetworkEvent: Codable, Sendable {
        case done
        case appBackgrounded
        case resourceBegin(file: String, size: UInt64)
        case resourceData(file: String, data: Data)
        case resourceEnd(file: String)
        case transferFailed
    }

    static func createPeerDiscoveryObserver(logger: PrefixedLogger) -> (
        discoveredPeersStream: AsyncThrowingStream<[any DeviceTransfer.Peer], any Error>,
        peerDiscoveryTask: Task<Void, Never>,
    ) {
        var knownDeviceSet = Set<WADeviceTransferPeer>()
        struct State {
            let sink: AsyncThrowingStream<[any DeviceTransfer.Peer], any Error>.Continuation
        }
        let (stream, _sink) = AsyncThrowingStream<[any DeviceTransfer.Peer], any Error>.makeStream(
            bufferingPolicy: .bufferingNewest(1),
        )
        let state = SeriallyAccessedState(State(sink: _sink))

        func reduceDevicesList(_ updatedDeviceList: Dictionary<UInt64, WAPairedDevice>) -> [WADeviceTransferPeer] {
            let newDevices = updatedDeviceList.values
            let pairedDevices = newDevices.reduce(into: [String: WADeviceTransferPeer]()) { devices, device in
                let peer = WADeviceTransferPeer(pairedDevice: device)
                if let existingPeer = devices[peer.displayName] {
                    logger.debug("Discovered existing peer \(device)")
                    if peer.pairedDevice.id > existingPeer.pairedDevice.id {
                        devices[peer.displayName] = peer
                    }
                } else {
                    logger.debug("Discovered new peer \(device)")
                    devices[peer.displayName] = peer
                }
            }
            logger.info("Discovered \(pairedDevices.count) peers")
            return pairedDevices.values.sorted { $0.pairedDevice.id > $1.pairedDevice.id }
        }

        let notification = NotificationCenter.default.addObserver(name: .OWSApplicationWillEnterForeground) { _ in
            state.enqueueUpdate {
                guard let updatedDevices = try? await WAPairedDevice.allDevices.current() else { return }
                let deviceList = reduceDevicesList(updatedDevices)
                logger.debug("Known devices on foreground \(updatedDevices)")
                knownDeviceSet = Set(deviceList)
                $0.sink.yield(deviceList)
            }
        }

        let task = Task {
            defer {
                NotificationCenter.default.removeObserver(notification)
            }
            do {
                let currentDeviceSnapshot = try await WAPairedDevice.allDevices.current()
                if (currentDeviceSnapshot ?? [:]).isEmpty {
                    // If the current device snapshot is empty, send an initial value since the
                    // loop below won't initially fire.
                    logger.debug("No peers found")
                    state.enqueueUpdate {
                        knownDeviceSet.removeAll()
                        $0.sink.yield([])
                    }
                }
                for try await updatedDeviceList in WAPairedDevice.allDevices {
                    let pairedDevices = reduceDevicesList(updatedDeviceList)
                    let pairedDeviceSet = Set(pairedDevices)
                    let differences = pairedDeviceSet.symmetricDifference(knownDeviceSet)
                    if !differences.isEmpty {
                        state.enqueueUpdate {
                            logger.debug("Devices after update \(pairedDevices)")
                            knownDeviceSet = pairedDeviceSet
                            $0.sink.yield(pairedDevices)
                        }
                    }
                }
            } catch is CancellationError {
                state.enqueueUpdate { $0.sink.finish() }
            } catch {
                state.enqueueUpdate { $0.sink.finish(throwing: error) }
            }
        }
        return (stream, task)
    }
}

@available(iOS 26.0, *)
typealias WiFiAwareConnection = NetworkConnection<Coder<WiFiAware.NetworkEvent, WiFiAware.NetworkEvent, NetworkJSONCoder>>

@available(iOS 26.0, *)
extension WAPublishableService {
    public static var deviceTransferService: WAPublishableService {
        allServices[WiFiAware.Constants.deviceTransferServiceName]!
    }
}

@available(iOS 26.0, *)
extension WASubscribableService {
    public static var deviceTransferService: WASubscribableService {
        allServices[WiFiAware.Constants.deviceTransferServiceName]!
    }
}

@available(iOS 26.0, *)
extension WAAccessCategory {
    var serviceClass: NWParameters.ServiceClass {
        switch self {
        case .bestEffort: .bestEffort
        case .background: .background
        case .interactiveVideo: .interactiveVideo
        case .interactiveVoice: .interactiveVoice
        default: .bestEffort
        }
    }
}

@available(iOS 26.0, *)
extension WAPairedDevice {
    var displayName: String {
        return self.name ?? self.pairingInfo?.pairingName ?? ""
    }
}
