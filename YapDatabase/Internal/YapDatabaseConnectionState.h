#import <Foundation/Foundation.h>
#import "YapAbstractDatabaseConnection.h"


@interface YapDatabaseConnectionState : NSObject {
@private
	dispatch_semaphore_t writeSemaphore;
}

- (id)initWithConnection:(YapAbstractDatabaseConnection *)connection;

@property (nonatomic, readonly, unsafe_unretained) YapAbstractDatabaseConnection *connection;

@property (nonatomic, readwrite, assign) BOOL yapLevelSharedReadLock;
@property (nonatomic, readwrite, assign) BOOL sqlLevelSharedReadLock;
@property (nonatomic, readwrite, assign) BOOL yapLevelExclusiveWriteLock;
@property (nonatomic, readwrite, assign) BOOL waitingForWriteLock;

- (void)prepareWriteLock;

- (void)waitForWriteLock;
- (void)signalWriteLock;

@end