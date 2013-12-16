#import <Foundation/Foundation.h>
#import "YapDatabaseConnection.h"


@interface YapDatabaseConnectionState : NSObject {
@private
	dispatch_semaphore_t writeSemaphore;

@public
	__weak YapDatabaseConnection *connection;
	
	BOOL yapLevelSharedReadLock;
	BOOL sqlLevelSharedReadLock;
	BOOL longLivedReadTransaction;
	
	BOOL yapLevelExclusiveWriteLock;
	BOOL waitingForWriteLock;
	
	uint64_t lastKnownSnapshot;
}

- (id)initWithConnection:(YapDatabaseConnection *)connection;

- (void)prepareWriteLock;

- (void)waitForWriteLock;
- (void)signalWriteLock;

@end