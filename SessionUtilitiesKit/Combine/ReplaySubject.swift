// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Combine

/// A subject that stores the last `bufferSize` emissions and emits them for every new subscriber
///
/// Note: This implementation was found here: https://github.com/sgl0v/OnSwiftWings
public final class ReplaySubject<Output, Failure: Error>: Subject {
    private var buffer: [Output] = [Output]()
    private let bufferSize: Int
    private let lock: NSRecursiveLock = NSRecursiveLock()
    
    private var subscriptions = [ReplaySubjectSubscription<Output, Failure>]()
    private var completion: Subscribers.Completion<Failure>?
    
    // MARK: - Initialization

    init(_ bufferSize: Int = 0) {
        self.bufferSize = bufferSize
    }
    
    // MARK: - Subject Methods
    
    /// Sends a value to the subscriber
    public func send(_ value: Output) {
        lock.lock(); defer { lock.unlock() }
        
        buffer.append(value)
        buffer = buffer.suffix(bufferSize)
        subscriptions.forEach { $0.receive(value) }
    }
    
    /// Sends a completion signal to the subscriber
    public func send(completion: Subscribers.Completion<Failure>) {
        lock.lock(); defer { lock.unlock() }
        
        self.completion = completion
        subscriptions.forEach { subscription in subscription.receive(completion: completion) }
    }
    
    /// Provides this Subject an opportunity to establish demand for any new upstream subscriptions
    public func send(subscription: Subscription) {
        lock.lock(); defer { lock.unlock() }
        
        subscription.request(.unlimited)
    }
    
    /// This function is called to attach the specified `Subscriber` to the`Publisher
    public func receive<S>(subscriber: S) where S: Subscriber, Failure == S.Failure, Output == S.Input {
        lock.lock(); defer { lock.unlock() }
        
        let subscription = ReplaySubjectSubscription<Output, Failure>(downstream: AnySubscriber(subscriber))
        subscriber.receive(subscription: subscription)
        subscriptions.append(subscription)
        subscription.replay(buffer, completion: completion)
    }
}

// MARK: -

public final class ReplaySubjectSubscription<Output, Failure: Error>: Subscription {
    private let downstream: AnySubscriber<Output, Failure>
    private var isCompleted: Bool = false
    private var demand: Subscribers.Demand = .none
    
    // MARK: - Initialization

    init(downstream: AnySubscriber<Output, Failure>) {
        self.downstream = downstream
    }
    
    // MARK: - Subscription

    public func request(_ newDemand: Subscribers.Demand) {
        demand += newDemand
    }

    public func cancel() {
        isCompleted = true
    }
    
    // MARK: - Functions

    public func receive(_ value: Output) {
        guard !isCompleted, demand > 0 else { return }

        demand += downstream.receive(value)
        demand -= 1
    }

    public func receive(completion: Subscribers.Completion<Failure>) {
        guard !isCompleted else { return }
        
        isCompleted = true
        downstream.receive(completion: completion)
    }

    public func replay(_ values: [Output], completion: Subscribers.Completion<Failure>?) {
        guard !isCompleted else { return }
        
        values.forEach { value in receive(value) }
        
        if let completion = completion {
            receive(completion: completion)
        }
    }
}
