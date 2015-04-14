#import "YapDatabaseConnectionState.h"

#if ! __has_feature(objc_arc)
#warning This file must be compiled with ARC. Use -fobjc-arc flag (or convert project to ARC).
#endif


@implementation YapDatabaseConnectionState

- (id)initWithConnection:(YapDatabaseConnection *)inConnection
{
	if ((self = [super init]))
	{
		connection = inConnection;
	}
	return self;
}

- (void)dealloc
{
#if !OS_OBJECT_USE_OBJC
	if (writeSemaphore)
		dispatch_release(writeSemaphore);
#endif
}

- (void)prepareWriteLock
{
	if (writeSemaphore == NULL) {
		writeSemaphore = dispatch_semaphore_create(0);
	}
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
