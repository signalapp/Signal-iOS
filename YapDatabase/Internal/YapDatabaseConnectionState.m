#import "YapDatabaseConnectionState.h"

#if ! __has_feature(objc_arc)
#warning This file must be compiled with ARC. Use -fobjc-arc flag (or convert project to ARC).
#endif

/**
 * Does ARC support support GCD objects?
 * It does if the minimum deployment target is iOS 6+ or Mac OS X 10.8+
**/
#if TARGET_OS_IPHONE

  // Compiling for iOS

  #if __IPHONE_OS_VERSION_MIN_REQUIRED >= 60000 // iOS 6.0 or later
    #define NEEDS_DISPATCH_RETAIN_RELEASE 0
  #else                                         // iOS 5.X or earlier
    #define NEEDS_DISPATCH_RETAIN_RELEASE 1
  #endif

#else

  // Compiling for Mac OS X

  #if MAC_OS_X_VERSION_MIN_REQUIRED >= 1080     // Mac OS X 10.8 or later
    #define NEEDS_DISPATCH_RETAIN_RELEASE 0
  #else
    #define NEEDS_DISPATCH_RETAIN_RELEASE 1     // Mac OS X 10.7 or earlier
  #endif

#endif


@implementation YapDatabaseConnectionState

@synthesize connection;
@synthesize yapLevelSharedReadLock;
@synthesize sqlLevelSharedReadLock;
@synthesize yapLevelExclusiveWriteLock;
@synthesize waitingForWriteLock;

- (id)initWithConnection:(YapAbstractDatabaseConnection *)inConnection
{
	if ((self = [super init]))
	{
		connection = inConnection;
	}
	return self;
}

- (void)dealloc
{
#if NEEDS_DISPATCH_RETAIN_RELEASE
	if (writeSemaphore)
		dispatch_release(writeSemaphore);
#endif
}

- (void)prepareWriteLock
{
	if (writeSemaphore == NULL)
		writeSemaphore = dispatch_semaphore_create(0);
}

- (void)waitForWriteLock
{
	if (writeSemaphore) {
		dispatch_semaphore_wait(writeSemaphore, DISPATCH_TIME_FOREVER);
	}
}

- (void)signalWriteLock
{
	if (writeSemaphore) {
		dispatch_semaphore_signal(writeSemaphore);
	}
}

@end
