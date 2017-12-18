//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import <YapDatabase/YapDatabaseConnection.h>

NS_ASSUME_NONNULL_BEGIN

@protocol OWSDatabaseConnectionDelegate <NSObject>

- (BOOL)isDatabaseInitialized;

@end

#pragma mark -

@class YapDatabaseExtension;

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

- (BOOL)registerExtension:(YapDatabaseExtension *)extension withName:(NSString *)extensionName;
- (void)asyncRegisterExtension:(YapDatabaseExtension *)extension
                      withName:(NSString *)extensionName
               completionBlock:(nullable void (^)(BOOL ready))completionBlock;
- (nullable id)registeredExtension:(NSString *)extensionName;

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
