#import <Foundation/Foundation.h>
#import "Terminable.h"

@interface AnonymousTerminator : NSObject <Terminable>

@property (nonatomic, readonly, copy) void (^terminateBlock)(void);

- (instancetype)initWithTerminator:(void (^)(void))terminate;

// Conform to Terminable
- (void)terminate;

@end
