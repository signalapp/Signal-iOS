// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit
import Combine

// MARK: -

public extension UIView {
    final class Subscription<SubscriberType: Subscriber, Input: UIView>: Combine.Subscription where SubscriberType.Input == Input {
        private var subscriber: SubscriberType?
        private var tapGestureRecognizer: UITapGestureRecognizer?
        private let input: Input
        
        // MARK: - Initialization
        
        public init(subscriber: SubscriberType, input: Input) {
            self.subscriber = subscriber
            self.input = input
            
            let tapGestureRecognizer: UITapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(eventHandler))
            self.tapGestureRecognizer = tapGestureRecognizer
            input.addGestureRecognizer(tapGestureRecognizer)
        }
        
        // MARK: - Subscriber
        
        // Do nothing as we only want to send events when they occur
        public func request(_ demand: Subscribers.Demand) {}
        
        // MARK: - Cancellable
        
        public func cancel() {
            if let tapGestureRecognizer: UITapGestureRecognizer = self.tapGestureRecognizer {
                input.removeGestureRecognizer(tapGestureRecognizer)
            }
            
            subscriber = nil
            tapGestureRecognizer = nil
        }
        
        // MARK: - Internal Functions
        
        @objc private func eventHandler() {
            _ = subscriber?.receive(input)
        }
    }

    // MARK: -

    struct Publisher<Output: UIView>: Combine.Publisher {
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

extension UIView: CombineCompatible {}

extension CombineCompatible where Self: UIView {
    public var tapPublisher: UIView.Publisher<Self> {
        return UIView.Publisher(output: self)
    }
}
