#import <Foundation/Foundation.h>
#import "NSData+Util.h"
#import "NSString+Util.h"
#import "NSDictionary+Util.h"
#import "NSArray+Util.h"

typedef void(^Action)(void);
typedef id(^Function)(void);

@interface Operation : NSObject

@property (nonatomic, readonly, copy) Action callback;

- (instancetype)initWithAction:(Action)block;

+ (void)asyncRun:(Action)action
        onThread:(NSThread*)thread;

+ (void)asyncRunAndWaitUntilDone:(Action)action
                        onThread:(NSThread*)thread;

+ (void)asyncRunOnNewThread:(Action)action;

- (void)run;

- (SEL)selectorToRun;

- (void)performOnNewThread;

- (void)performOnThread:(NSThread*)thread;

- (void)performOnThreadAndWaitUntilDone:(NSThread*)thread;

@end
