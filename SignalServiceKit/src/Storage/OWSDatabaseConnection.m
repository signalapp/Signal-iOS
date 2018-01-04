//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSDatabaseConnection.h"
#import "AppContext.h"

NS_ASSUME_NONNULL_BEGIN

@interface YapDatabaseConnection ()

- (id)initWithDatabase:(YapDatabase *)database;

@end

#pragma mark -

@implementation OWSDatabaseConnection

- (id)initWithDatabase:(YapDatabase *)database delegate:(id<OWSDatabaseConnectionDelegate>)delegate
{
    self = [super initWithDatabase:database];

    if (!self) {
        return self;
    }

    OWSAssert(delegate);

    _delegate = delegate;

    return self;
}

#pragma mark - Read

- (void)readWithBlock:(void (^)(YapDatabaseReadTransaction *transaction))block
{
    id<OWSDatabaseConnectionDelegate> delegate = self.delegate;
    OWSAssert(delegate);
    OWSAssert(delegate.areSyncRegistrationsComplete);

    [delegate readTransactionWillBegin];
    [super readWithBlock:block];
    [delegate readTransactionDidComplete];
}

- (void)asyncReadWithBlock:(void (^)(YapDatabaseReadTransaction *transaction))block
{
    [self asyncReadWithBlock:block completionQueue:NULL completionBlock:nil];
}

- (void)asyncReadWithBlock:(void (^)(YapDatabaseReadTransaction *transaction))block
           completionBlock:(nullable dispatch_block_t)completionBlock
{
    [self asyncReadWithBlock:block completionQueue:NULL completionBlock:completionBlock];
}

- (void)asyncReadWithBlock:(void (^)(YapDatabaseReadTransaction *transaction))block
           completionQueue:(nullable dispatch_queue_t)completionQueue
           completionBlock:(nullable dispatch_block_t)completionBlock
{
    id<OWSDatabaseConnectionDelegate> delegate = self.delegate;
    OWSAssert(delegate);
    OWSAssert(delegate.areSyncRegistrationsComplete);

    [delegate readTransactionWillBegin];
    [super asyncReadWithBlock:block
              completionQueue:completionQueue
              completionBlock:^{
                  if (completionBlock) {
                      completionBlock();
                  }
                  [delegate readTransactionDidComplete];
              }];
}

#pragma mark - Read Write

// Assert that the database is in a ready state (specifically that any sync database
// view registrations have completed and any async registrations have been started)
// before creating write transactions.
//
// Creating write transactions before the _sync_ database views are registered
// causes YapDatabase to rebuild all of our database views, which is catastrophic.
// Specifically, it causes YDB's "view version" checks to fail.

- (void)readWriteWithBlock:(void (^)(YapDatabaseReadWriteTransaction *transaction))block
{
    id<OWSDatabaseConnectionDelegate> delegate = self.delegate;
    OWSAssert(delegate);
    OWSAssert(delegate.areSyncRegistrationsComplete);

#ifdef DEBUG
    if (!CurrentAppContext().isMainApp) {
        DDLogInfo(@"SAE is writing to database.");
    }
#endif

    [delegate readWriteTransactionWillBegin];
    [super readWriteWithBlock:block];
    [delegate readWriteTransactionDidComplete];
}

- (void)asyncReadWriteWithBlock:(void (^)(YapDatabaseReadWriteTransaction *transaction))block
{
    [self asyncReadWriteWithBlock:block completionQueue:NULL completionBlock:nil];
}

- (void)asyncReadWriteWithBlock:(void (^)(YapDatabaseReadWriteTransaction *transaction))block
                completionBlock:(nullable dispatch_block_t)completionBlock
{
    [self asyncReadWriteWithBlock:block completionQueue:NULL completionBlock:completionBlock];
}

- (void)asyncReadWriteWithBlock:(void (^)(YapDatabaseReadWriteTransaction *transaction))block
                completionQueue:(nullable dispatch_queue_t)completionQueue
                completionBlock:(nullable dispatch_block_t)completionBlock
{
    id<OWSDatabaseConnectionDelegate> delegate = self.delegate;
    OWSAssert(delegate);
    OWSAssert(delegate.areSyncRegistrationsComplete);

#ifdef DEBUG
    if (!CurrentAppContext().isMainApp) {
        DDLogInfo(@"SAE is writing to database.");
    }
#endif

    [delegate readWriteTransactionWillBegin];
    [super asyncReadWriteWithBlock:block
                   completionQueue:completionQueue
                   completionBlock:^{
                       if (completionBlock) {
                           completionBlock();
                       }
                       [delegate readWriteTransactionDidComplete];
                   }];
}

@end

NS_ASSUME_NONNULL_END
