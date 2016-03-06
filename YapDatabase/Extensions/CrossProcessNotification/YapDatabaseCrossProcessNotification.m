#import "YapDatabaseCrossProcessNotification.h"
#import "YapDatabaseCrossProcessNotificationPrivate.h"

#import "YapDatabasePrivate.h"
#import "YapDatabaseExtensionPrivate.h"

#import "YapDatabaseLogging.h"

#include <notify.h>

#if ! __has_feature(objc_arc)
#warning This file must be compiled with ARC. Use -fobjc-arc flag (or convert project to ARC).
#endif

/**
 * Define log level for this file: OFF, ERROR, WARN, INFO, VERBOSE
 * See YapDatabaseLogging.h for more information.
 **/
#if DEBUG
  static const int ydbLogLevel = YDB_LOG_LEVEL_WARN;
#else
  static const int ydbLogLevel = YDB_LOG_LEVEL_WARN;
#endif
#pragma unused(ydbLogLevel)

static pid_t currentPid() {
    static dispatch_once_t onceToken;
    static pid_t pid;
    dispatch_once(&onceToken, ^{
        pid = getpid();
    });
    return pid;
}

@interface YapDatabaseCrossProcessNotification () {
    int notifyToken;
}

@property (nonatomic, strong) NSString* identifier;

@end


@implementation YapDatabaseCrossProcessNotification

+ (void)dropTablesForRegisteredName:(NSString *)registeredName
                    withTransaction:(YapDatabaseReadWriteTransaction *)transaction
                      wasPersistent:(BOOL __unused)wasPersistent
{
    // nothing to do
}

- (BOOL)isPersistent {
    return NO;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Instance
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (id)initWithIdentifier:(NSString *)identifier {
    self = [super init];
    if (self) {
        self.identifier = identifier;
    }
    return self;
}

- (void)dealloc {
    NSLog(@"DEALLOC!");
    [self stop];
}

- (void)start {
    [self stop];
    
    const char* name = [[self channel] cStringUsingEncoding:NSUTF8StringEncoding];
    
    NSLog(@"register: %s", name);
    __weak YapDatabaseCrossProcessNotification* wSelf = self;
    
    notify_register_dispatch(name, &notifyToken, dispatch_get_main_queue(), ^(int token) {
        uint64_t fromPid;
        notify_get_state(token, &fromPid);
        BOOL isExternal = fromPid != currentPid();
        if (isExternal)
        {
            NSLog(@"received external modification from %llu", fromPid);
            [[NSNotificationCenter defaultCenter] postNotificationName:YapDatabaseModifiedExternallyNotification object:[wSelf registeredDatabase]];
        }
        
    });
}

- (void)stop {
    if (notify_is_valid_token(notifyToken))
    {
        notify_cancel(notifyToken);
        notifyToken = 0;
    }
}

/**
 * Subclasses may OPTIONALLY implement this method.
 *
 * This is a simple hook method to let the extension now that it's been registered with the database.
 * This method is invoked after the readWriteTransaction (that registered the extension) has been committed.
 *
 * Important:
 *   This method is invoked within the writeQueue.
 *   So either don't do anything expensive/time-consuming in this method, or dispatch_async to do it in another queue.
**/
- (void)didRegisterWithDatabase:(YapDatabase __unused *)database
{
	// only start dispatching notifications once the extension is registered to a database
	[self start];
}

- (YapDatabaseExtensionConnection *)newConnection:(YapDatabaseConnection *)databaseConnection
{
    return [[YapDatabaseCrossProcessNotificationConnection alloc] initWithParent:self];
}

- (void)notifyChanged {
    
    const char* name = [[self channel] cStringUsingEncoding:NSUTF8StringEncoding];
    
    notify_set_state(notifyToken, currentPid());
    notify_post(name);
}

-(NSString*)channel {
    return [NSString stringWithFormat:@"com.deusty.YapDatabase.YapDatabaseModifiedExternally.%@", self.identifier];
}

@end
