//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "SSKBaseTestObjC.h"
#import "SSKPreKeyStore.h"
#import <SignalServiceKit/SDSDatabaseStorage+Objc.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>

@interface SSKPreKeyStoreTests : SSKBaseTestObjC

@end

#pragma mark -

@interface SSKPreKeyStore (Tests)

@end

#pragma mark -

@implementation SSKPreKeyStore (Tests)

#pragma mark - Dependencies

- (SDSDatabaseStorage *)databaseStorage
{
    return SDSDatabaseStorage.shared;
}

#pragma mark -

- (nullable PreKeyRecord *)loadPreKey:(int)preKeyId
{
    __block PreKeyRecord *_Nullable result;
    [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
        result = [self loadPreKey:preKeyId protocolContext:transaction];
    }];
    return result;
}

@end

#pragma mark -

@implementation SSKPreKeyStoreTests

- (void)setUp
{
    [super setUp];
    // Put setup code here. This method is called before the invocation of each test method in the class.
}

- (void)tearDown
{
    // Put teardown code here. This method is called after the invocation of each test method in the class.
    [super tearDown];
}

- (SSKPreKeyStore *)preKeyStore
{
    return SSKEnvironment.shared.preKeyStore;
}

- (void)testGeneratingAndStoringPreKeys
{
    NSArray *generatedKeys = [self.preKeyStore generatePreKeyRecords];

    XCTAssert([generatedKeys count] == 100, @"Not hundred keys generated");

    [self.preKeyStore storePreKeyRecords:generatedKeys];

    PreKeyRecord *lastPreKeyRecord = [generatedKeys lastObject];
    PreKeyRecord *firstPreKeyRecord = [generatedKeys firstObject];

    XCTAssert([[self.preKeyStore loadPreKey:lastPreKeyRecord.Id].keyPair.publicKey
        isEqualToData:lastPreKeyRecord.keyPair.publicKey]);

    XCTAssert([[self.preKeyStore loadPreKey:firstPreKeyRecord.Id].keyPair.publicKey
        isEqualToData:firstPreKeyRecord.keyPair.publicKey]);
}

- (void)testRemovingPreKeys
{
    NSArray *generatedKeys = [self.preKeyStore generatePreKeyRecords];

    XCTAssert([generatedKeys count] == 100, @"Not hundred keys generated");

    [self.preKeyStore storePreKeyRecords:generatedKeys];

    PreKeyRecord *lastPreKeyRecord = [generatedKeys lastObject];
    PreKeyRecord *firstPreKeyRecord = [generatedKeys firstObject];

    [self writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
        [self.preKeyStore removePreKey:lastPreKeyRecord.Id protocolContext:transaction];
    }];

    XCTAssertNil([self.preKeyStore loadPreKey:lastPreKeyRecord.Id]);
    XCTAssertNotNil([self.preKeyStore loadPreKey:firstPreKeyRecord.Id]);
}

@end
