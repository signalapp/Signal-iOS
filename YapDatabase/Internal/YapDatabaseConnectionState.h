#import <Foundation/Foundation.h>
#import "YapAbstractDatabaseConnection.h"


@interface YapDatabaseConnectionState : NSObject {
@private
	dispatch_semaphore_t writeSemaphore;

@public
	__unsafe_unretained YapAbstractDatabaseConnection *connection;
	
	BOOL yapLevelSharedReadLock;
	BOOL sqlLevelSharedReadLock;
	BOOL yapLevelExclusiveWriteLock;
	BOOL waitingForWriteLock;
}

- (id)initWithConnection:(YapAbstractDatabaseConnection *)connection;

- (void)prepareWriteLock;

- (void)waitForWriteLock;
- (void)signalWriteLock;

@end