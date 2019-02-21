//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation

/// Benchmark async code by calling the passed in block parameter when the work
/// is done.
///
///     BenchAsync(title: "my benchmark") { completeBenchmark in
///         foo {
///             // consider benchmarking of "foo" complete
///             completeBenchmark()
///
///             // call any completion handler foo might have
///             fooCompletion()
///         }
///     }
public func BenchAsync(title: String, block: (@escaping () -> Void) -> Void) {
    let startTime = CFAbsoluteTimeGetCurrent()

    block {
        let timeElapsed = CFAbsoluteTimeGetCurrent() - startTime
        let formattedTime = String(format: "%0.2fms", timeElapsed * 1000)
        Logger.debug("[Bench] title: \(title), duration: \(formattedTime)")
    }
}

public func Bench(title: String, block: () -> Void) {
    BenchAsync(title: title) { finish in
        block()
        finish()
    }
}

public func Bench(title: String, block: () throws -> Void) throws {
    var thrownError: Error?
    BenchAsync(title: title) { finish in
        do {
            try block()
        } catch {
            thrownError = error
        }
        finish()
    }
    if let errorToRethrow = thrownError {
        throw errorToRethrow
    }
}

/// When it's not convenient to retain the event completion handler, e.g. when the measured event
/// crosses multiple classes, you can use the BenchEvent tools
///
///     // in one class
///     let message = getMessage()
///     BenchEventStart(title: "message sending", eventId: message.id)
///
/// ...
///
///    // in another class
///    BenchEventComplete(title: "message sending", eventId: message.id)
///
/// Or in objc
///
///    [BenchManager startEventWithTitle:"message sending" eventId:message.id]
///    ...
///    [BenchManager startEventWithTitle:"message sending" eventId:message.id]
public func BenchEventStart(title: String, eventId: BenchmarkEventId) {
    BenchAsync(title: title) { finish in
        runningEvents[eventId] = Event(title: title, eventId: eventId, completion: finish)
    }
}

public func BenchEventComplete(eventId: BenchmarkEventId) {
    guard let event = runningEvents.removeValue(forKey: eventId) else {
        Logger.debug("no active event with id: \(eventId)")
        return
    }

    event.completion()
}

public typealias BenchmarkEventId = String

private struct Event {
    let title: String
    let eventId: BenchmarkEventId
    let completion: () -> Void
}

private var runningEvents: [BenchmarkEventId: Event] = [:]

@objc
public class BenchManager: NSObject {

    @objc
    public class func startEvent(title: String, eventId: BenchmarkEventId) {
        BenchEventStart(title: title, eventId: eventId)
    }

    @objc
    public class func completeEvent(eventId: BenchmarkEventId) {
        BenchEventComplete(eventId: eventId)
    }

    @objc
    public class func benchAsync(title: String, block: (@escaping () -> Void) -> Void) {
        BenchAsync(title: title, block: block)
    }

    @objc
    public class func bench(title: String, block: () -> Void) {
        Bench(title: title, block: block)
    }
}
