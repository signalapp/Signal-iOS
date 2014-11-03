#import "AnonymousTerminator.h"
#import "Constraints.h"

@interface AnonymousTerminator ()

@property BOOL alreadyCalled;
@property (readwrite,nonatomic,copy) void (^terminateBlock)(void);

@end

@implementation AnonymousTerminator

+ (AnonymousTerminator*)cancellerWithCancel:(void (^)(void))terminate {
    require(terminate != nil);
    AnonymousTerminator* anonTerminator = [[AnonymousTerminator alloc] init];
    anonTerminator.terminateBlock = terminate;
    return anonTerminator;
}

- (void)terminate {
    if (self.alreadyCalled) return;
    self.alreadyCalled = YES;
    self.terminateBlock();
}

@end
