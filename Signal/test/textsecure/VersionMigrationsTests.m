//
//  VersionMigrationsTests.m
//  TextSecureKit
//
//  Created by Frederic Jacobs on 06/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import <XCTest/XCTest.h>
#import "VersionMigrations.h"

#import "CategorizingLogger.h"
#import "Cryptography.h"
#import "Environment.h"
#import "TSStorageManager.h"
#import "TSStorageManager+IdentityKeyStore.h"
#import "RecentCall.h"
#import "RecentCallManager.h"
#import "Release.h"
#import "SecurityUtils.h"
#import "TestUtil.h"
#import "TSCall.h"
#import "TSContactThread.h"
#import "TSDatabaseView.h"
#import "SignalKeyingStorage.h"
#import "UICKeyChainStore.h"
#import "YapDatabaseConnection.h"


@interface VersionMigrations(Testing)
+(void) migrateRecentCallsToVersion2Dot0;
+(void) migrateKeyingStorageToVersion2Dot0;
@end


@interface SignalKeyingStorage(Testing)
+(void)storeData:(NSData*)data forKey:(NSString*)key;
+(NSData*)dataForKey:(NSString*)key;
+(void)storeString:(NSString*)string forKey:(NSString*)key;
+(NSString*)stringForKey:(NSString*)key;
@end

@interface TSDatabaseView(Testing)
+ (BOOL)threadShouldBeInInbox:(TSThread*)thread;
@end


@interface VersionMigrationsTests : XCTestCase
@property (nonatomic,strong) NSString* localNumber;
@property (nonatomic,strong) NSString* passwordCounter;
@property (nonatomic,strong) NSString* savedPassword;

@property (nonatomic,strong) NSData* signalingMacKey;
@property (nonatomic,strong) NSData* signalingCipherKey;
@property (nonatomic,strong) NSData* zidKey;
@property (nonatomic,strong) NSData* signalingExtraKey;
@property (nonatomic,strong) NSMutableArray* recentCalls;
@end

@implementation VersionMigrationsTests

- (void)setUp {
    [super setUp];
    [Environment setCurrent:[Release unitTestEnvironment:@[]]];


    _localNumber = @"+123456789";
    _passwordCounter = @"20";
    _savedPassword = @"muchlettersverysecure";
    _signalingMacKey = [Cryptography generateRandomBytes:8];
    _signalingCipherKey = [Cryptography generateRandomBytes:8];
    _zidKey = [Cryptography generateRandomBytes:8];
    _signalingExtraKey = [Cryptography generateRandomBytes:8];

    // setup the keys
    [UICKeyChainStore setString:_localNumber forKey:LOCAL_NUMBER_KEY];
    [UICKeyChainStore setString:_passwordCounter forKey:PASSWORD_COUNTER_KEY];
    [UICKeyChainStore setString:_savedPassword forKey:SAVED_PASSWORD_KEY];
    [UICKeyChainStore setData:_signalingMacKey forKey:SIGNALING_MAC_KEY];
    [UICKeyChainStore setData:_signalingCipherKey forKey:SIGNALING_CIPHER_KEY];
    [UICKeyChainStore setData:_zidKey forKey:ZID_KEY];
    [UICKeyChainStore setData:_signalingExtraKey forKey:SIGNALING_EXTRA_KEY];

    // setup the recent calls
    RecentCall* r1 = [RecentCall recentCallWithContactID:123
                                              andNumber:testPhoneNumber1
                                            andCallType:RPRecentCallTypeIncoming];
    RecentCall* r2 = [RecentCall recentCallWithContactID:456
                                              andNumber:testPhoneNumber2
                                            andCallType:RPRecentCallTypeMissed];
    
    r2.isArchived = YES;
    
    _recentCalls = [[NSMutableArray alloc] initWithObjects:r1,r2,nil];

    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    NSData *saveData = [NSKeyedArchiver archivedDataWithRootObject:_recentCalls.copy];
    [defaults setObject:saveData forKey:RECENT_CALLS_DEFAULT_KEY];
    [defaults synchronize];

}

- (void)tearDown {
    // Put teardown code here. This method is called after the invocation of each test method in the class.
    [super tearDown];
}

- (void)testMigrateKeyingStorageToVersion2Dot0 {
    // migrate keying storage
    [VersionMigrations migrateKeyingStorageToVersion2Dot0];
    
    // checking that everything is migrated correctly
    XCTAssert([[SignalKeyingStorage stringForKey:LOCAL_NUMBER_KEY] isEqualToString:_localNumber]);
    XCTAssert([[SignalKeyingStorage stringForKey:PASSWORD_COUNTER_KEY] isEqualToString:_passwordCounter]);
    XCTAssert([[SignalKeyingStorage stringForKey:SAVED_PASSWORD_KEY] isEqualToString:_savedPassword]);

    XCTAssert([[SignalKeyingStorage dataForKey:SIGNALING_MAC_KEY] isEqualToData:_signalingMacKey]);
    XCTAssert([[SignalKeyingStorage dataForKey:SIGNALING_CIPHER_KEY] isEqualToData:_signalingCipherKey]);
    XCTAssert([[SignalKeyingStorage dataForKey:ZID_KEY] isEqualToData:_zidKey]);
    XCTAssert([[SignalKeyingStorage dataForKey:SIGNALING_EXTRA_KEY] isEqualToData:_signalingExtraKey]);

    // checking that the old storage is empty
    XCTAssert([UICKeyChainStore stringForKey:LOCAL_NUMBER_KEY] == nil);
    XCTAssert([UICKeyChainStore stringForKey:PASSWORD_COUNTER_KEY] == nil);
    XCTAssert([UICKeyChainStore stringForKey:SAVED_PASSWORD_KEY] == nil);
    
    XCTAssert([UICKeyChainStore dataForKey:SIGNALING_MAC_KEY] == nil);
    XCTAssert([UICKeyChainStore dataForKey:SIGNALING_CIPHER_KEY] == nil);
    XCTAssert([UICKeyChainStore dataForKey:ZID_KEY] == nil);
    XCTAssert([UICKeyChainStore dataForKey:SIGNALING_EXTRA_KEY] == nil);

}

@end
