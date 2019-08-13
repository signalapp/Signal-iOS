//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "YDBLegacyMigration.h"
#import <SignalCoreKit/NSData+OWS.h>
#import <SignalMessaging/OWSPreferences.h>
#import <SignalServiceKit/AppReadiness.h>
#import <SignalServiceKit/NSUserDefaults+OWS.h>
#import <SignalServiceKit/OWSBackgroundTask.h>
#import <SignalServiceKit/OWSError.h>
#import <SignalServiceKit/OWSFileSystem.h>
#import <SignalServiceKit/OWSPrimaryStorage.h>
#import <SignalServiceKit/OWSUserProfile.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>
#import <SignalServiceKit/TSAttachmentStream.h>
#import <YapDatabase/YapDatabaseCryptoUtils.h>

NS_ASSUME_NONNULL_BEGIN

@implementation YDBLegacyMigration

+ (void)appDidBecomeReady
{
    if (CurrentAppContext().isMainApp) {
        // Disable the SAE until the main app has:
        //
        // * Successfully completed launch process at least once in the post-SAE world.
        // * Successfully completed launch process at least once in the post-GRDB world.
        [OWSPreferences setIsYdbReadyForAppExtensions];
        if (SSKFeatureFlags.storageMode == StorageModeGrdb) {
            [OWSPreferences setIsGrdbReadyForAppExtensions];
        }
    }
}

+ (BOOL)ensureIsYDBReadyForAppExtensions:(NSError **)errorHandle
{
    OWSAssertDebug(errorHandle != nil);

    [AppReadiness runNowOrWhenAppDidBecomeReady:^{
        [self appDidBecomeReady];
    }];

    if ([OWSPreferences isReadyForAppExtensions]) {
        return YES;
    }

    OWSBackgroundTask *_Nullable backgroundTask = [OWSBackgroundTask backgroundTaskWithLabelStr:__PRETTY_FUNCTION__];
    SUPPRESS_DEADSTORE_WARNING(backgroundTask);

    NSError *_Nullable error = [self convertDatabaseIfNecessary];

    if (!error) {
        [NSUserDefaults migrateToSharedUserDefaults];
    }

    if (!error) {
        error = [OWSPrimaryStorage migrateToSharedData];
    }
    if (!error) {
        error = [OWSUserProfile migrateToSharedData];
    }
    if (!error) {
        error = [TSAttachmentStream migrateToSharedData];
    }

    if (error) {
        OWSFailDebug(@"database conversion failed: %@", error);
        *errorHandle = error;
        return NO;
    }

    OWSAssertDebug(backgroundTask);
    backgroundTask = nil;

    return YES;
}

+ (nullable NSError *)convertDatabaseIfNecessary
{
    OWSLogInfo(@"");

    NSString *databaseFilePath = [OWSPrimaryStorage legacyDatabaseFilePath];
    if (![[NSFileManager defaultManager] fileExistsAtPath:databaseFilePath]) {
        OWSLogVerbose(@"no legacy database file found");
        return nil;
    }

    NSError *_Nullable error;
    NSData *_Nullable databasePassword = [OWSStorage tryToLoadDatabaseLegacyPassphrase:&error];
    if (!databasePassword || error) {
        return (error
                ?: OWSErrorWithCodeDescription(
                       OWSErrorCodeDatabaseConversionFatalError, @"Failed to load database password"));
    }

    YapRecordDatabaseSaltBlock recordSaltBlock = ^(NSData *saltData) {
        OWSLogVerbose(@"saltData: %@", saltData.hexadecimalString);

        // Derive and store the raw cipher key spec, to avoid the ongoing tax of future KDF
        NSData *_Nullable keySpecData =
            [YapDatabaseCryptoUtils deriveDatabaseKeySpecForPassword:databasePassword saltData:saltData];

        if (!keySpecData) {
            OWSLogError(@"Failed to derive key spec.");
            return NO;
        }

        [OWSStorage storeDatabaseCipherKeySpec:keySpecData];

        return YES;
    };

    YapDatabaseOptions *dbOptions = [OWSStorage defaultDatabaseOptions];
    error = [YapDatabaseCryptoUtils convertDatabaseIfNecessary:databaseFilePath
                                              databasePassword:databasePassword
                                                       options:dbOptions
                                               recordSaltBlock:recordSaltBlock];
    if (!error) {
        [OWSStorage removeLegacyPassphrase];
    }

    return error;
}

@end

NS_ASSUME_NONNULL_END
