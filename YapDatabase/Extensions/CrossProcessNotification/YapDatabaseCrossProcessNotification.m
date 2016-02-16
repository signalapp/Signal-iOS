#import "YapDatabaseCrossProcessNotification.h"
#import "YapDatabaseCrossProcessNotificationPrivate.h"

#import "YapDatabasePrivate.h"
#import "YapDatabaseExtensionPrivate.h"

#import "YapDatabaseLogging.h"

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
    [self stop];
}

- (void)start {
    [self stop];
    
    const char* name = [[self channel] cStringUsingEncoding:NSUTF8StringEncoding];
    
    notify_register_dispatch(name, &notifyToken, dispatch_get_main_queue(), ^(int token) {
        NSLog(@"received external change");
        [[NSNotificationCenter defaultCenter] postNotificationName:YapDatabaseModifiedExternallyNotification object:self.registeredDatabase];
    });
}

- (void)stop {
    if (notifyToken) // my guess is that there is no "zero token"
    {
        notify_cancel(notifyToken);
        notifyToken = 0;
    }
}

- (void)setRegisteredDatabase:(YapDatabase *)registeredDatabase {
    [super setRegisteredDatabase:registeredDatabase];
    
    // only start dispatching notifications once the extension is registered to a database
    [self start];
}

- (YapDatabaseExtensionConnection *)newConnection:(YapDatabaseConnection *)databaseConnection
{
    return [[YapDatabaseCrossProcessNotificationConnection alloc] initWithParent:self];
}

- (void)notifyChanged {
    NSLog(@"notify !!!");
    const char* name = [[self channel] cStringUsingEncoding:NSUTF8StringEncoding];
    notify_post(name);
}

-(NSString*)channel {
    return [NSString stringWithFormat:@"com.deusty.YapDatabase.YapDatabaseModifiedExternally.%@", self.identifier];
}

@end
