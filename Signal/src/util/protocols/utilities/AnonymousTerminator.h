#import <Foundation/Foundation.h>
#import "Terminable.h"

@interface AnonymousTerminator : NSObject <Terminable>

@property (readonly,nonatomic,copy) void (^terminateBlock)(void);

+ (AnonymousTerminator*)cancellerWithCancel:(void (^)(void))terminate;

@end
