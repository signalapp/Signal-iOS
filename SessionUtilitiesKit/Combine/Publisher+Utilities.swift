// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Combine

public protocol CombineCompatible {}

public extension Publisher {
    /// Provides a subject that shares a single subscription to the upstream publisher and replays at most
    /// `bufferSize` items emitted by that publisher
    /// - Parameter bufferSize: limits the number of items that can be replayed
    func shareReplay(_ bufferSize: Int) -> AnyPublisher<Output, Failure> {
        return multicast(subject: ReplaySubject(bufferSize))
            .autoconnect()
            .eraseToAnyPublisher()
    }
    
    func sink(into subject: PassthroughSubject<Output, Failure>, includeCompletions: Bool = false) -> AnyCancellable {
        return sink(
            receiveCompletion: { completion in
                guard includeCompletions else { return }
                
                subject.send(completion: completion)
            },
            receiveValue: { value in subject.send(value) }
        )
    }
    
    /// The standard `.receive(on: DispatchQueue.main)` seems to ocassionally dispatch to the
    /// next run loop before emitting data, this method checks if it's running on the main thread already and
    /// if so just emits directly rather than routing via `.receive(on:)`
    func receiveOnMain(immediately receiveImmediately: Bool = false) -> AnyPublisher<Output, Failure> {
        guard receiveImmediately else {
            return self.receive(on: DispatchQueue.main)
                .eraseToAnyPublisher()
        }
        
        return self
            .flatMap { value -> AnyPublisher<Output, Failure> in
                guard Thread.isMainThread else {
                    return Just(value)
                        .setFailureType(to: Failure.self)
                        .receive(on: DispatchQueue.main)
                        .eraseToAnyPublisher()
                }
                
                return Just(value)
                    .setFailureType(to: Failure.self)
                    .eraseToAnyPublisher()
            }
            .eraseToAnyPublisher()
    }
}

// MARK: - Convenience

public extension Publisher {
    func sink(into subject: PassthroughSubject<Output, Failure>?, includeCompletions: Bool = false) -> AnyCancellable {
        guard let targetSubject: PassthroughSubject<Output, Failure> = subject else { return AnyCancellable {} }
        
        return sink(into: targetSubject, includeCompletions: includeCompletions)
    }
}
