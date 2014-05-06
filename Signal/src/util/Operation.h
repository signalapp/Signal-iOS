#import <Foundation/Foundation.h>
#import "DataUtil.h"
#import "StringUtil.h"
#import "DictionaryUtil.h"
#import "ArrayUtil.h"
#import "Future.h"

typedef void(^Action)(void);
typedef id(^Function)(void);

@interface Operation : NSObject

@property (nonatomic,readonly,copy) Action callback;

+(Operation*) operation:(Action)block;

+(void) asyncRun:(Action)action
        onThread:(NSThread*)thread;

+(void) asyncRunAndWaitUntilDone:(Action)action
                        onThread:(NSThread*)thread;

+(Future*) asyncEvaluate:(Function)function
                   onThread:(NSThread*)thread;

+(Future*) asyncEvaluateOnNewThread:(Function)function;

+(void) asyncRunOnNewThread:(Action)action;

-(void)run;

-(SEL) selectorToRun;

-(void) performOnNewThread;

-(void) performOnThread:(NSThread*)thread;

-(void) performOnThreadAndWaitUntilDone:(NSThread*)thread;

@end
