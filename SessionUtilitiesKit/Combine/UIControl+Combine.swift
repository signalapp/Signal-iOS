// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit
import Combine

// MARK: -

public extension UIControl {
    final class Subscription<SubscriberType: Subscriber, Input: UIControl>: Combine.Subscription where SubscriberType.Input == Input {
        private var subscriber: SubscriberType?
        private let input: Input
        
        // MARK: - Initialization
        
        public init(subscriber: SubscriberType, input: Input, event: UIControl.Event) {
            self.subscriber = subscriber
            self.input = input
            
            input.addTarget(self, action: #selector(eventHandler), for: event)
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

    struct Publisher<Output: UIControl>: Combine.Publisher {
        public typealias Output = Output
        public typealias Failure = Never
        
        let output: Output
        let controlEvents: UIControl.Event
        
        // MARK: - Initialization
        
        public init(output: Output, events: UIControl.Event) {
            self.output = output
            self.controlEvents = events
        }
        
        // MARK: - Publisher
        
        public func receive<S>(subscriber: S) where S : Subscriber, Never == S.Failure, Output == S.Input {
            let subscription: Subscription = Subscription(subscriber: subscriber, input: output, event: controlEvents)
            subscriber.receive(subscription: subscription)
        }
    }
}

// MARK: - CombineCompatible

extension CombineCompatible where Self: UIControl {
    public func publisher(for events: UIControl.Event) -> UIControl.Publisher<Self> {
        return UIControl.Publisher(output: self, events: events)
    }
}
