#import <Foundation/Foundation.h>
#import "YapDatabaseConnection.h"


@interface YapDatabaseConnectionState : NSObject {
@private
	dispatch_semaphore_t writeSemaphore;

@public
	__weak YapDatabaseConnection *connection;
	
	BOOL activeReadTransaction;
	BOOL longLivedReadTransaction;
	BOOL sqlLevelSharedReadLock;
	
	BOOL activeWriteTransaction;
	BOOL waitingForWriteLock;
	
	uint64_t lastTransactionSnapshot;
	uint64_t lastTransactionTime;
}

- (id)initWithConnection:(YapDatabaseConnection *)connection;

- (void)prepareWriteLock;

- (void)waitForWriteLock;
- (void)signalWriteLock;

@end