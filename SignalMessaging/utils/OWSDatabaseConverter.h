//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

// Used to convert YapDatabase/SQLCipher databases whose header is encrypted
// to databases whose first 32 bytes are unencrypted so that iOS can determine
// that this is a SQLite database using WAL and therefore not terminate the app
// when it is suspended.
@interface OWSDatabaseConverter : NSObject

- (instancetype)init NS_UNAVAILABLE;

+ (nullable NSError *)convertDatabaseIfNecessary;
+ (nullable NSError *)convertDatabaseIfNecessary:(NSString *)databaseFilePath
                                databasePassword:(NSData *)databasePassword;

@end

NS_ASSUME_NONNULL_END
