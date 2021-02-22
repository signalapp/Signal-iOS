//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "SSKEnvironment.h"
#import "AppContext.h"
#import "OWSPrimaryStorage.h"

NS_ASSUME_NONNULL_BEGIN

static SSKEnvironment *sharedSSKEnvironment;

@interface SSKEnvironment ()

@property (nonatomic) id<ProfileManagerProtocol> profileManager;
@property (nonatomic) OWSPrimaryStorage *primaryStorage;
@property (nonatomic) OWSBlockingManager *blockingManager;
@property (nonatomic) OWSIdentityManager *identityManager;
@property (nonatomic) TSAccountManager *tsAccountManager;
@property (nonatomic) OWSDisappearingMessagesJob *disappearingMessagesJob;
@property (nonatomic) OWSReadReceiptManager *readReceiptManager;
@property (nonatomic) OWSOutgoingReceiptManager *outgoingReceiptManager;
@property (nonatomic) id<SSKReachabilityManager> reachabilityManager;
@property (nonatomic) id<OWSTypingIndicators> typingIndicators;

@end

#pragma mark -

@implementation SSKEnvironment

@synthesize notificationsManager = _notificationsManager;
@synthesize objectReadWriteConnection = _objectReadWriteConnection;
@synthesize sessionStoreDBConnection = _sessionStoreDBConnection;
@synthesize migrationDBConnection = _migrationDBConnection;
@synthesize analyticsDBConnection = _analyticsDBConnection;

- (instancetype)initWithProfileManager:(id<ProfileManagerProtocol>)profileManager
                        primaryStorage:(OWSPrimaryStorage *)primaryStorage
                       blockingManager:(OWSBlockingManager *)blockingManager
                       identityManager:(OWSIdentityManager *)identityManager
                      tsAccountManager:(TSAccountManager *)tsAccountManager
               disappearingMessagesJob:(OWSDisappearingMessagesJob *)disappearingMessagesJob
                    readReceiptManager:(OWSReadReceiptManager *)readReceiptManager
                outgoingReceiptManager:(OWSOutgoingReceiptManager *)outgoingReceiptManager
                   reachabilityManager:(id<SSKReachabilityManager>)reachabilityManager
                      typingIndicators:(id<OWSTypingIndicators>)typingIndicators
{
    self = [super init];
    
    if (!self) {
        return self;
    }

    _profileManager = profileManager;
    _primaryStorage = primaryStorage;
    _blockingManager = blockingManager;
    _identityManager = identityManager;
    _tsAccountManager = tsAccountManager;
    _disappearingMessagesJob = disappearingMessagesJob;
    _readReceiptManager = readReceiptManager;
    _outgoingReceiptManager = outgoingReceiptManager;
    _reachabilityManager = reachabilityManager;
    _typingIndicators = typingIndicators;

    return self;
}

+ (instancetype)shared
{
    return sharedSSKEnvironment;
}

+ (void)setShared:(SSKEnvironment *)env
{
    sharedSSKEnvironment = env;
}

+ (void)clearSharedForTests
{
    sharedSSKEnvironment = nil;
}

#pragma mark - Mutable Accessors

- (nullable id<NotificationsProtocol>)notificationsManager
{
    @synchronized(self) {
        return _notificationsManager;
    }
}

- (void)setNotificationsManager:(nullable id<NotificationsProtocol>)notificationsManager
{
    @synchronized(self) {
        _notificationsManager = notificationsManager;
    }
}

- (BOOL)isComplete
{
    return self.notificationsManager != nil;
}

- (YapDatabaseConnection *)objectReadWriteConnection
{
    @synchronized(self) {
        if (!_objectReadWriteConnection) {
            _objectReadWriteConnection = self.primaryStorage.newDatabaseConnection;
        }
        return _objectReadWriteConnection;
    }
}

- (YapDatabaseConnection *)sessionStoreDBConnection {
    @synchronized(self) {
        if (!_sessionStoreDBConnection) {
            _sessionStoreDBConnection = self.primaryStorage.newDatabaseConnection;
        }
        return _sessionStoreDBConnection;
    }
}

- (YapDatabaseConnection *)migrationDBConnection {
    @synchronized(self) {
        if (!_migrationDBConnection) {
            _migrationDBConnection = self.primaryStorage.newDatabaseConnection;
        }
        return _migrationDBConnection;
    }
}

- (YapDatabaseConnection *)analyticsDBConnection {
    @synchronized(self) {
        if (!_analyticsDBConnection) {
            _analyticsDBConnection = self.primaryStorage.newDatabaseConnection;
        }
        return _analyticsDBConnection;
    }
}

@end

NS_ASSUME_NONNULL_END
