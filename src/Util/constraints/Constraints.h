#import <CocoaLumberjack/CocoaLumberjack.h>
#import "BadArgument.h"
#import "BadState.h"
#import "OperationFailed.h"
#import "SecurityFailure.h"
/// 'require(X)' is used to indicate parameter-related preconditions that callers must satisfy.
/// Failure to satisfy indicates a bug in the caller.
#define ows_require(expr)                                                                                \
    if (!(expr)) {                                                                                       \
        NSString *reason =                                                                               \
            [NSString stringWithFormat:@"require %@ (in %s at line %d)", (@ #expr), __FILE__, __LINE__]; \
        DDLogError(@"%@", reason);                                                                       \
        [BadArgument raise:reason];                                                                      \
    };

/// 'requireState(X)' is used to indicate callee-state-related preconditions that callers must satisfy.
/// Failure to satisfy indicates a stateful bug in either the caller or the callee.
#define requireState(expr) \
    if (!(expr))           \
    [BadState raise:[NSString stringWithFormat:@"required state: %@ (in %s at line %d)", (@ #expr), __FILE__, __LINE__]]

/// 'checkOperation(X)' is used to throw exceptions if operations fail.
/// Failure does not indicate a bug.
/// Methods may throw these exceptions for callers to catch as a 'returned error' result.
#define checkOperation(expr)                                                                                      \
    if (!(expr)) {                                                                                                \
        NSString *reason = [NSString                                                                              \
            stringWithFormat:@"Operation failed. Expected: %@(in %s at line %d)", (@ #expr), __FILE__, __LINE__]; \
        [OperationFailed raise:reason];                                                                           \
    }

/// 'checkOperationDescribe(X, Desc)' is used to throw exceptions if operations fail, and describe the problem.
/// Failure does not indicate a bug.
/// Methods may throw these exceptions for callers to catch as a 'returned error' result.
#define checkOperationDescribe(expr, desc)                                                                    \
    if (!(expr))                                                                                              \
    [OperationFailed raise:[NSString stringWithFormat:@"Operation failed: %@ Expected: %@(in %s at line %d)", \
                                                      (desc),                                                 \
                                                      (@ #expr),                                              \
                                                      __FILE__,                                               \
                                                      __LINE__]]

/// 'checkSecurityOperation(X, Desc)' is used to throw exceptions if operations fail due to authentication or other
/// crypto failures, and describe the problem.
/// Failure does not indicate a bug.
/// Methods may throw these exceptions for callers to catch as a 'returned error' result.
#define checkSecurityOperation(expr, desc)                                                                            \
    if (!(expr))                                                                                                      \
    [SecurityFailure raise:[NSString stringWithFormat:@"Security related failure: %@ Expected: %@(in %s at line %d)", \
                                                      (desc),                                                         \
                                                      (@ #expr),                                                      \
                                                      __FILE__,                                                       \
                                                      __LINE__]]
