#import "AnonymousConditionLogger.h"
#import "Constraints.h"

@interface AnonymousConditionLogger ()

@property (nonatomic, readwrite, copy) void (^logNoticeBlock)(id details);
@property (nonatomic, readwrite, copy) void (^logWarningBlock)(id details);
@property (nonatomic, readwrite, copy) void (^logErrorBlock)(id details);

@end

@implementation AnonymousConditionLogger

- (instancetype)initWithLogNotice:(void(^)(id details))logNotice
                    andLogWarning:(void(^)(id details))logWarning
                      andLogError:(void(^)(id details))logError {
    self = [super init];
	
    if (self) {
        require(logNotice != nil);
        require(logWarning != nil);
        require(logError != nil);
        
        self.logErrorBlock = logError;
        self.logWarningBlock = logWarning;
        self.logNoticeBlock = logNotice;
    }
    
    return self;
}

#pragma mark ConditionLogger

- (void)logError:(id)details {
    self.logErrorBlock(details);
}

- (void)logWarning:(id)details {
    self.logWarningBlock(details);
}

- (void)logNotice:(id)details {
    self.logNoticeBlock(details);
}

@end
