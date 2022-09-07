// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit
import Combine

// MARK: -

public extension UIBarButtonItem {
    final class Subscription<SubscriberType: Subscriber, Input: UIBarButtonItem>: Combine.Subscription where SubscriberType.Input == Input {
        private var subscriber: SubscriberType?
        private let input: Input
        
        // MARK: - Initialization
        
        public init(subscriber: SubscriberType, input: Input) {
            self.subscriber = subscriber
            self.input = input
            
            input.target = self
            input.action = #selector(eventHandler)
        }
        
        // MARK: - Subscriber
        
        // Do nothing as we only want to send events when they occur
        public func request(_ demand: Subscribers.Demand) {}
        
        // MARK: - Cancellable
        
        public func cancel() {
            subscriber = nil
        }
        
        // MARK: - Internal Functions
        
        @objc private func eventHandler() {
            _ = subscriber?.receive(input)
        }
    }

    // MARK: -

    struct Publisher<Output: UIBarButtonItem>: Combine.Publisher {
        public typealias Output = Output
        public typealias Failure = Never
        
        let output: Output
        
        // MARK: - Initialization
        
        public init(output: Output) {
            self.output = output
        }
        
        // MARK: - Publisher
        
        public func receive<S>(subscriber: S) where S : Subscriber, Never == S.Failure, Output == S.Input {
            let subscription: Subscription = Subscription(subscriber: subscriber, input: output)
            subscriber.receive(subscription: subscription)
        }
    }
}

// MARK: - CombineCompatible

extension UIBarButtonItem: CombineCompatible {}

extension CombineCompatible where Self: UIBarButtonItem {
    public var tapPublisher: UIBarButtonItem.Publisher<Self> {
        return UIBarButtonItem.Publisher(output: self)
    }
}
