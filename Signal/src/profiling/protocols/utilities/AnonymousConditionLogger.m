#import "AnonymousConditionLogger.h"
#import "Constraints.h"

@implementation AnonymousConditionLogger

+ (AnonymousConditionLogger *)anonymousConditionLoggerWithLogNotice:(void (^)(id details))logNotice
                                                      andLogWarning:(void (^)(id details))logWarning
                                                        andLogError:(void (^)(id details))logError {
    ows_require(logNotice != nil);
    ows_require(logWarning != nil);
    ows_require(logError != nil);

    AnonymousConditionLogger *a = [AnonymousConditionLogger new];
    a->_logErrorBlock           = logError;
    a->_logWarningBlock         = logWarning;
    a->_logNoticeBlock          = logNotice;
    return a;
}

- (void)logError:(id)details {
    _logErrorBlock(details);
}
- (void)logWarning:(id)details {
    _logWarningBlock(details);
}
- (void)logNotice:(id)details {
    _logNoticeBlock(details);
}

@end
