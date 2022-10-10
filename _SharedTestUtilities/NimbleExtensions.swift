// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import Nimble
import SessionUtilitiesKit

public enum CallAmount {
    case atLeast(times: Int)
    case exactly(times: Int)
    case noMoreThan(times: Int)
}

fileprivate func timeStr(_ value: Int) -> String {
    return "\(value) time\(value == 1 ? "" : "s")"
}

/// Validates whether the function called in `functionBlock` has been called according to the parameter constraints
///
/// - Parameters:
///  - amount: An enum constraining the number of times the function can be called (Default is `.atLeast(times: 1)`
///
///  - matchingParameters: A boolean indicating whether the parameters for the function call need to match exactly
///
///  - exclusive: A boolean indicating whether no other functions should be called
///
///  - functionBlock: A closure in which the function to be validated should be called
public func call<M, T, R>(
    _ amount: CallAmount = .atLeast(times: 1),
    matchingParameters: Bool = false,
    exclusive: Bool = false,
    functionBlock: @escaping (inout T) throws -> R
) -> Predicate<M> where M: Mock<T> {
    return Predicate.define { actualExpression in
        let callInfo: CallInfo = generateCallInfo(actualExpression, functionBlock)
        let matchingParameterRecords: [String] = callInfo.desiredFunctionCalls
            .filter { !matchingParameters || callInfo.hasMatchingParameters($0) }
        let exclusiveCallsValid: Bool = (!exclusive || callInfo.allFunctionsCalled.count <= 1)  // '<=' to support '0' case
        let (numParamMatchingCallsValid, timesError): (Bool, String?) = {
            switch amount {
                case .atLeast(let times):
                    return (
                        (matchingParameterRecords.count >= times),
                        (times <= 1 ? nil : "at least \(timeStr(times))")
                    )
                
                case .exactly(let times):
                    return (
                        (matchingParameterRecords.count == times),
                        "exactly \(timeStr(times))"
                    )
                    
                case .noMoreThan(let times):
                    return (
                        (matchingParameterRecords.count <= times),
                        (times <= 0 ? nil : "no more than \(timeStr(times))")
                    )
            }
        }()
        
        let result = (
            numParamMatchingCallsValid &&
            exclusiveCallsValid
        )
        let matchingParametersError: String? = (matchingParameters ?
            "matching the parameters\(callInfo.desiredParameters.map { ": \($0)" } ?? "")" :
            nil
        )
        let distinctParameterCombinations: Set<String> = Set(callInfo.desiredFunctionCalls)
        let actualMessage: String
        
        if callInfo.caughtException != nil {
            actualMessage = "a thrown assertion (might not have been called or has no mocked return value)"
        }
        else if callInfo.function == nil {
            actualMessage = "no call details"
        }
        else if callInfo.desiredFunctionCalls.isEmpty {
            actualMessage = "no calls"
        }
        else if !exclusiveCallsValid {
            let otherFunctionsCalled: [String] = callInfo.allFunctionsCalled.filter { $0 != callInfo.functionName }
            
            actualMessage = "calls to other functions: [\(otherFunctionsCalled.joined(separator: ", "))]"
        }
        else {
            let onlyMadeMatchingCalls: Bool = (matchingParameterRecords.count == callInfo.desiredFunctionCalls.count)
            
            switch (numParamMatchingCallsValid, onlyMadeMatchingCalls, distinctParameterCombinations.count) {
                case (false, false, 1):
                    // No calls with the matching parameter requirements but only one parameter combination
                    // so include the param info
                    actualMessage = "called \(timeStr(callInfo.desiredFunctionCalls.count)) with different parameters: \(callInfo.desiredFunctionCalls[0])"
                    
                case (false, true, _):
                    actualMessage = "called \(timeStr(callInfo.desiredFunctionCalls.count))"
                    
                case (false, false, _):
                    let distinctSetterCombinations: Set<String> = distinctParameterCombinations.filter { $0 != "[]" }
                    
                    // A getter/setter combo will have function calls split between no params and the set value
                    // if the setter didn't match then we still want to show the incorrect parameters
                    if distinctSetterCombinations.count == 1, let paramCombo: String = distinctSetterCombinations.first {
                        actualMessage = "called with: \(paramCombo)"
                    }
                    else {
                        actualMessage = "called \(timeStr(matchingParameterRecords.count)) with matching parameters, \(timeStr(callInfo.desiredFunctionCalls.count)) total"
                    }
                
                default: actualMessage = "\(exclusive ? " exclusive " : "")call to '\(callInfo.functionName)'"
            }
        }
        
        return PredicateResult(
            bool: result,
            message: .expectedCustomValueTo(
                [
                    "call '\(callInfo.functionName)'\(exclusive ? " exclusively" : "")",
                    timesError,
                    matchingParametersError
                ]
                .compactMap { $0 }
                .joined(separator: " "),
                actual: actualMessage
            )
        )
    }
}

// MARK: - Shared Code

fileprivate struct CallInfo {
    let didError: Bool
    let caughtException: BadInstructionException?
    let function: MockFunction?
    let allFunctionsCalled: [String]
    let desiredFunctionCalls: [String]
    
    var functionName: String { "\((function?.name).map { "\($0)" } ?? "a function")" }
    var desiredParameters: String? { function?.parameterSummary }
    
    static var error: CallInfo {
        CallInfo(
            didError: true,
            caughtException: nil,
            function: nil,
            allFunctionsCalled: [],
            desiredFunctionCalls: []
        )
    }
    
    init(
        didError: Bool = false,
        caughtException: BadInstructionException?,
        function: MockFunction?,
        allFunctionsCalled: [String],
        desiredFunctionCalls: [String]
    ) {
        self.didError = didError
        self.caughtException = caughtException
        self.function = function
        self.allFunctionsCalled = allFunctionsCalled
        self.desiredFunctionCalls = desiredFunctionCalls
    }
    
    func hasMatchingParameters(_ parameters: String) -> Bool {
        return (parameters == (function?.parameterSummary ?? "FALLBACK_NOT_FOUND"))
    }
}

fileprivate func generateCallInfo<M, T, R>(_ actualExpression: Expression<M>, _ functionBlock: @escaping (inout T) throws -> R) -> CallInfo where M: Mock<T> {
    var maybeFunction: MockFunction?
    var allFunctionsCalled: [String] = []
    var desiredFunctionCalls: [String] = []
    let builderCreator: ((M) -> MockFunctionBuilder<T, R>) = { validInstance in
        let builder: MockFunctionBuilder<T, R> = MockFunctionBuilder(functionBlock, mockInit: type(of: validInstance).init)
        builder.returnValueGenerator = { name, parameterSummary in
            validInstance.functionConsumer
                .firstFunction(for: name, matchingParameterSummaryIfPossible: parameterSummary)?
                .returnValue as? R
        }
        
        return builder
    }
    
    #if (arch(x86_64) || arch(arm64)) && (canImport(Darwin) || canImport(Glibc))
    var didError: Bool = false
    let caughtException: BadInstructionException? = catchBadInstruction {
        do {
            guard let validInstance: M = try actualExpression.evaluate() else {
                didError = true
                return
            }
            
            allFunctionsCalled = Array(validInstance.functionConsumer.calls.wrappedValue.keys)
            
            // Only check for the specific function calls if there was at least a single
            // call (if there weren't any this will likely throw errors when attempting
            // to build)
            if !allFunctionsCalled.isEmpty {
                let builder: MockFunctionBuilder<T, R> = builderCreator(validInstance)
                validInstance.functionConsumer.trackCalls = false
                maybeFunction = try? builder.build()
                desiredFunctionCalls = validInstance.functionConsumer.calls
                    .wrappedValue[maybeFunction?.name ?? ""]
                    .defaulting(to: [])
                validInstance.functionConsumer.trackCalls = true
            }
            else {
                desiredFunctionCalls = []
            }
        }
        catch {
            didError = true
        }
    }
    
    // Make sure to switch this back on in case an assertion was thrown (which would meant this
    // wouldn't have been reset)
    (try? actualExpression.evaluate())?.functionConsumer.trackCalls = true
    
    guard !didError else { return CallInfo.error }
    #else
    let caughtException: BadInstructionException? = nil
    
    // Just hope for the best and if there is a force-cast there's not much we can do
    guard let validInstance: M = try? actualExpression.evaluate() else { return CallInfo.error }
    
    allFunctionsCalled = Array(validInstance.functionConsumer.calls.wrappedValue.keys)
    
    // Only check for the specific function calls if there was at least a single
    // call (if there weren't any this will likely throw errors when attempting
    // to build)
    if !allFunctionsCalled.isEmpty {
        let builder: MockExpectationBuilder<T, R> = builderCreator(validInstance)
        validInstance.functionConsumer.trackCalls = false
        maybeFunction = try? builder.build()
        desiredFunctionCalls = validInstance.functionConsumer.calls
            .wrappedValue[maybeFunction?.name ?? ""]
            .defaulting(to: [])
        validInstance.functionConsumer.trackCalls = true
    }
    else {
        desiredFunctionCalls = []
    }
    #endif
    
    return CallInfo(
        caughtException: caughtException,
        function: maybeFunction,
        allFunctionsCalled: allFunctionsCalled,
        desiredFunctionCalls: desiredFunctionCalls
    )
}
