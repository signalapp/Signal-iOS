//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSStorage.h"
#import "AppContext.h"
#import "NSData+Base64.h"
#import "TSAttachmentStream.h"
#import "TSStorageManager.h"
#import <Curve25519Kit/Randomness.h>
#import <SAMKeychain/SAMKeychain.h>

NS_ASSUME_NONNULL_BEGIN

NSString *const OWSStorageExceptionName_DatabasePasswordInaccessibleWhileBackgrounded
    = @"OWSStorageExceptionName_DatabasePasswordInaccessibleWhileBackgrounded";
NSString *const OWSStorageExceptionName_DatabasePasswordUnwritable
    = @"OWSStorageExceptionName_DatabasePasswordUnwritable";
NSString *const OWSStorageExceptionName_NoDatabase = @"OWSStorageExceptionName_NoDatabase";

static NSString *keychainService = @"TSKeyChainService";
static NSString *keychainDBPassAccount = @"TSDatabasePass";

#pragma mark -

@interface YapDatabaseConnection ()

- (id)initWithDatabase:(YapDatabase *)database;

@end

#pragma mark -

@interface OWSDatabaseConnection : YapDatabaseConnection

@property (atomic, weak) id<OWSDatabaseConnectionDelegate> delegate;

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithDatabase:(YapDatabase *)database
                        delegate:(id<OWSDatabaseConnectionDelegate>)delegate NS_DESIGNATED_INITIALIZER;

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

// This clobbers the superclass implementation to include an assert which
// ensures that the database is in a ready state before creating write transactions.
//
// Creating write transactions before the _sync_ database views are registered
// causes YapDatabase to rebuild all of our database views, which is catastrophic.
// We're not sure why, but it causes YDB's "view version" checks to fail.
- (void)readWriteWithBlock:(void (^)(YapDatabaseReadWriteTransaction *transaction))block
{
    id<OWSDatabaseConnectionDelegate> delegate = self.delegate;
    OWSAssert(delegate);
    OWSAssert(delegate.isDatabaseInitialized);

    [super readWriteWithBlock:block];
}

- (void)asyncReadWriteWithBlock:(void (^)(YapDatabaseReadWriteTransaction *transaction))block
{
    id<OWSDatabaseConnectionDelegate> delegate = self.delegate;
    OWSAssert(delegate);
    OWSAssert(delegate.isDatabaseInitialized);

    [super asyncReadWriteWithBlock:block];
}

- (void)asyncReadWriteWithBlock:(void (^)(YapDatabaseReadWriteTransaction *transaction))block
                completionBlock:(nullable dispatch_block_t)completionBlock
{
    id<OWSDatabaseConnectionDelegate> delegate = self.delegate;
    OWSAssert(delegate);
    OWSAssert(delegate.isDatabaseInitialized);

    [super asyncReadWriteWithBlock:block completionBlock:completionBlock];
}

- (void)asyncReadWriteWithBlock:(void (^)(YapDatabaseReadWriteTransaction *transaction))block
                completionQueue:(nullable dispatch_queue_t)completionQueue
                completionBlock:(nullable dispatch_block_t)completionBlock
{
    id<OWSDatabaseConnectionDelegate> delegate = self.delegate;
    OWSAssert(delegate);
    OWSAssert(delegate.isDatabaseInitialized);

    [super asyncReadWriteWithBlock:block completionQueue:completionQueue completionBlock:completionBlock];
}

@end

#pragma mark -

// This class is only used in DEBUG builds.
@interface YapDatabase ()

- (void)addConnection:(YapDatabaseConnection *)connection;

@end

#pragma mark -

@interface OWSDatabase : YapDatabase

@property (atomic, weak) id<OWSDatabaseConnectionDelegate> delegate;

- (instancetype)init NS_UNAVAILABLE;
- (id)initWithPath:(NSString *)inPath
        serializer:(nullable YapDatabaseSerializer)inSerializer
      deserializer:(YapDatabaseDeserializer)inDeserializer
           options:(YapDatabaseOptions *)inOptions
          delegate:(id<OWSDatabaseConnectionDelegate>)delegate NS_DESIGNATED_INITIALIZER;

@end

#pragma mark -

@implementation OWSDatabase

- (id)initWithPath:(NSString *)inPath
        serializer:(nullable YapDatabaseSerializer)inSerializer
      deserializer:(YapDatabaseDeserializer)inDeserializer
           options:(YapDatabaseOptions *)inOptions
          delegate:(id<OWSDatabaseConnectionDelegate>)delegate
{
    self = [super initWithPath:inPath serializer:inSerializer deserializer:inDeserializer options:inOptions];

    if (!self) {
        return self;
    }

    OWSAssert(delegate);

    _delegate = delegate;

    return self;
}

// This clobbers the superclass implementation to include asserts which
// ensure that the database is in a ready state before creating write transactions.
//
// See comments in OWSDatabaseConnection.
- (YapDatabaseConnection *)newConnection
{
    id<OWSDatabaseConnectionDelegate> delegate = self.delegate;
    OWSAssert(delegate);

    OWSDatabaseConnection *connection = [[OWSDatabaseConnection alloc] initWithDatabase:self delegate:delegate];
    [self addConnection:connection];
    return connection;
}

@end

#pragma mark -

@interface OWSUnknownDBObject : NSObject <NSCoding>

@end

#pragma mark -

/**
 * A default object to return when we can't deserialize an object from YapDB. This can prevent crashes when
 * old objects linger after their definition file is removed. The danger is that, the objects can lay in wait
 * until the next time a DB extension is added and we necessarily enumerate the entire DB.
 */
@implementation OWSUnknownDBObject

- (nullable instancetype)initWithCoder:(NSCoder *)aDecoder
{
    return nil;
}

- (void)encodeWithCoder:(NSCoder *)aCoder
{
}

@end

#pragma mark -

@interface OWSUnarchiverDelegate : NSObject <NSKeyedUnarchiverDelegate>

@end

#pragma mark -

@implementation OWSUnarchiverDelegate

- (nullable Class)unarchiver:(NSKeyedUnarchiver *)unarchiver
    cannotDecodeObjectOfClassName:(NSString *)name
                  originalClasses:(NSArray<NSString *> *)classNames
{
    DDLogError(@"%@ Could not decode object: %@", self.logTag, name);
    OWSProdError([OWSAnalyticsEvents storageErrorCouldNotDecodeClass]);
    return [OWSUnknownDBObject class];
}

@end

#pragma mark -

@interface OWSStorage () <OWSDatabaseConnectionDelegate>

@property (atomic, nullable) YapDatabase *database;
@property (atomic) BOOL isDatabaseInitialized;

@end

#pragma mark -

@implementation OWSStorage

- (instancetype)initStorage
{
    self = [super init];

    if (![self tryToLoadDatabase]) {
        // Failing to load the database is catastrophic.
        //
        // The best we can try to do is to discard the current database
        // and behave like a clean install.
        OWSProdCritical([OWSAnalyticsEvents storageErrorCouldNotLoadDatabase]);

        // Try to reset app by deleting database.
        // Disabled resetting storage until we have better data on why this happens.
        // [self resetAllStorage];

        if (![self tryToLoadDatabase]) {
            OWSProdCritical([OWSAnalyticsEvents storageErrorCouldNotLoadDatabaseSecondAttempt]);

            // Sleep to give analytics events time to be delivered.
            [NSThread sleepForTimeInterval:15.0f];

            [NSException raise:OWSStorageExceptionName_NoDatabase format:@"Failed to initialize database."];
        }

        OWSSingletonAssert();
    }

    return self;
}

- (void)setDatabaseInitialized
{
    OWSAssert(!self.isDatabaseInitialized);

    self.isDatabaseInitialized = YES;
}

- (BOOL)tryToLoadDatabase
{

    // We determine the database password first, since a side effect of
    // this can be deleting any existing database file (if we're recovering
    // from a corrupt keychain).
    NSData *databasePassword = [self databasePassword];

    YapDatabaseOptions *options = [[YapDatabaseOptions alloc] init];
    options.corruptAction = YapDatabaseCorruptAction_Fail;
    options.cipherKeyBlock = ^{
        return databasePassword;
    };
    options.enableMultiProcessSupport = YES;

    OWSDatabase *database = [[OWSDatabase alloc] initWithPath:[self dbPath]
                                                   serializer:nil
                                                 deserializer:[[self class] logOnFailureDeserializer]
                                                      options:options
                                                     delegate:self];

    if (!database) {
        return NO;
    }

    _database = database;
    _dbReadConnection = self.newDatabaseConnection;
    _dbReadWriteConnection = self.newDatabaseConnection;

    return YES;
}

/**
 * NSCoding sometimes throws exceptions killing our app. We want to log that exception.
 **/
+ (YapDatabaseDeserializer)logOnFailureDeserializer
{
    OWSUnarchiverDelegate *unarchiverDelegate = [OWSUnarchiverDelegate new];

    return ^id(NSString __unused *collection, NSString __unused *key, NSData *data) {
        if (!data || data.length <= 0) {
            return nil;
        }

        @try {
            NSKeyedUnarchiver *unarchiver = [[NSKeyedUnarchiver alloc] initForReadingWithData:data];
            unarchiver.delegate = unarchiverDelegate;
            return [unarchiver decodeObjectForKey:@"root"];
        } @catch (NSException *exception) {
            // Sync log in case we bail.
            OWSProdError([OWSAnalyticsEvents storageErrorDeserialization]);
            @throw exception;
        }
    };
}

- (nullable YapDatabaseConnection *)newDatabaseConnection
{
    return self.database.newConnection;
}

- (BOOL)registerExtension:(YapDatabaseExtension *)extension withName:(NSString *)extensionName
{
    return [self.database registerExtension:extension withName:extensionName];
}

- (void)asyncRegisterExtension:(YapDatabaseExtension *)extension
                      withName:(NSString *)extensionName
               completionBlock:(nullable void (^)(BOOL ready))completionBlock
{
    [self.database asyncRegisterExtension:extension withName:extensionName completionBlock:completionBlock];
}

- (nullable id)registeredExtension:(NSString *)extensionName
{
    return [self.database registeredExtension:extensionName];
}

#pragma mark - Password

- (void)deleteDatabaseFile
{
    NSError *error;
    [[NSFileManager defaultManager] removeItemAtPath:[self dbPath] error:&error];
    if (error) {
        DDLogError(@"Failed to delete database: %@", error.description);
    }
}

- (void)resetStorage
{
    self.database = nil;

    _dbReadConnection = nil;
    _dbReadWriteConnection = nil;

    [self deleteDatabaseFile];
}

+ (void)resetAllStorage
{
    [[TSStorageManager sharedManager] resetStorage];

    [self deletePasswordFromKeychain];

    if (CurrentAppContext().isMainApp) {
        [TSAttachmentStream deleteAttachments];
    }

    // TODO: Delete Profiles on Disk?
}

#pragma mark - Password

- (NSString *)dbPath
{
    OWS_ABSTRACT_METHOD();

    return @"";
}

#pragma mark - Password

+ (BOOL)isDatabasePasswordAccessible
{
    [SAMKeychain setAccessibilityType:kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly];
    NSError *error;
    NSString *dbPassword = [SAMKeychain passwordForService:keychainService account:keychainDBPassAccount error:&error];

    if (dbPassword && !error) {
        return YES;
    }

    if (error) {
        DDLogWarn(@"Database password couldn't be accessed: %@", error.localizedDescription);
    }

    return NO;
}

- (NSData *)databasePassword
{
    [SAMKeychain setAccessibilityType:kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly];

    NSError *keyFetchError;
    NSString *dbPassword =
        [SAMKeychain passwordForService:keychainService account:keychainDBPassAccount error:&keyFetchError];

    if (keyFetchError) {
        NSString *errorDescription =
            [NSString stringWithFormat:@"Database password inaccessible. No unlock since device restart? Error: %@",
                      keyFetchError];
        if (CurrentAppContext().isMainApp) {
            UIApplicationState applicationState = CurrentAppContext().mainApplicationState;
            errorDescription =
                [errorDescription stringByAppendingFormat:@", ApplicationState: %d", (int)applicationState];
        }
        DDLogError(@"%@ %@", self.logTag, errorDescription);
        [DDLog flushLog];

        if (CurrentAppContext().isMainApp) {
            UIApplicationState applicationState = CurrentAppContext().mainApplicationState;
            if (applicationState == UIApplicationStateBackground) {
                // TODO: Rather than crash here, we should detect the situation earlier
                // and exit gracefully - (in the app delegate?). See the `
                // This is a last ditch effort to avoid blowing away the user's database.
                [self backgroundedAppDatabasePasswordInaccessibleWithErrorDescription:errorDescription];
            }
        } else {
            [self backgroundedAppDatabasePasswordInaccessibleWithErrorDescription:
                      @"Password inaccessible; not main app."];
        }

        // At this point, either this is a new install so there's no existing password to retrieve
        // or the keychain has become corrupt.  Either way, we want to get back to a
        // "known good state" and behave like a new install.

        BOOL shouldHavePassword = [NSFileManager.defaultManager fileExistsAtPath:[self dbPath]];
        if (shouldHavePassword) {
            OWSProdCritical([OWSAnalyticsEvents storageErrorCouldNotLoadDatabaseSecondAttempt]);
        }

        // Try to reset app by deleting database.
        [OWSStorage resetAllStorage];

        dbPassword = [self createAndSetNewDatabasePassword];
    }

    return [dbPassword dataUsingEncoding:NSUTF8StringEncoding];
}

- (NSString *)createAndSetNewDatabasePassword
{
    NSString *newDBPassword = [[Randomness generateRandomBytes:30] base64EncodedString];
    NSError *keySetError;
    [SAMKeychain setPassword:newDBPassword forService:keychainService account:keychainDBPassAccount error:&keySetError];
    if (keySetError) {
        OWSProdCritical([OWSAnalyticsEvents storageErrorCouldNotStoreDatabasePassword]);

        [OWSStorage deletePasswordFromKeychain];

        // Sleep to give analytics events time to be delivered.
        [NSThread sleepForTimeInterval:15.0f];

        [NSException raise:OWSStorageExceptionName_DatabasePasswordUnwritable
                    format:@"Setting DB password failed with error: %@", keySetError];
    } else {
        DDLogWarn(@"Succesfully set new DB password.");
    }

    return newDBPassword;
}

- (void)backgroundedAppDatabasePasswordInaccessibleWithErrorDescription:(NSString *)errorDescription
{
    OWSAssert(
        CurrentAppContext().isMainApp && CurrentAppContext().mainApplicationState == UIApplicationStateBackground);

    // Sleep to give analytics events time to be delivered.
    [NSThread sleepForTimeInterval:5.0f];

    // Presumably this happened in response to a push notification. It's possible that the keychain is corrupted
    // but it could also just be that the user hasn't yet unlocked their device since our password is
    // kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    [NSException raise:OWSStorageExceptionName_DatabasePasswordInaccessibleWhileBackgrounded
                format:@"%@", errorDescription];
}

+ (void)deletePasswordFromKeychain
{
    [SAMKeychain deletePasswordForService:keychainService account:keychainDBPassAccount];
}

@end

NS_ASSUME_NONNULL_END
