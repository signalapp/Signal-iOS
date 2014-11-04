#import "AnonymousTerminator.h"
#import "Constraints.h"

@interface AnonymousTerminator ()

@property BOOL alreadyCalled;
@property (nonatomic, readwrite, copy) void (^terminateBlock)(void);

@end

@implementation AnonymousTerminator

- (instancetype)initWithTerminator:(void (^)(void))terminate {
    if (self = [super init]) {
        require(terminate != nil);
        self.terminateBlock = terminate;
    }
    
    return self;
}

#pragma mark Terminable

- (void)terminate {
    if (self.alreadyCalled) return;
    self.alreadyCalled = YES;
    self.terminateBlock();
}

@end
