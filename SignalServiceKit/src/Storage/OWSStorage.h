//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import <YapDatabase/YapDatabaseConnection.h>

// TODO: Remove this import.
#import "YapDatabaseConnection+OWS.h"

// TODO: Remove this import.
#import <YapDatabase/YapDatabase.h>

NS_ASSUME_NONNULL_BEGIN

@protocol OWSDatabaseConnectionDelegate <NSObject>

- (BOOL)isDatabaseInitialized;

@end

#pragma mark -

@interface OWSStorage : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initStorage NS_DESIGNATED_INITIALIZER;

- (void)setDatabaseInitialized;

+ (void)resetAllStorage;

// TODO: Deprecate?
- (nullable YapDatabaseConnection *)newDatabaseConnection;

// TODO: Deprecate.
@property (nullable, nonatomic, readonly) YapDatabaseConnection *dbReadConnection;
@property (nullable, nonatomic, readonly) YapDatabaseConnection *dbReadWriteConnection;

#pragma mark - Password

/**
 * Returns NO if:
 *
 * - Keychain is locked because device has just been restarted.
 * - Password could not be retrieved because of a keychain error.
 */
+ (BOOL)isDatabasePasswordAccessible;

@end

NS_ASSUME_NONNULL_END
