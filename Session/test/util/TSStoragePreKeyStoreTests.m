//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSPrimaryStorage+PreKeyStore.h"
#import "SSKBaseTest.h"

@interface TSStoragePreKeyStoreTests : SSKBaseTest

@end

@implementation TSStoragePreKeyStoreTests

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

- (void)testGeneratingAndStoringPreKeys
{
    NSArray *generatedKeys = [[OWSPrimaryStorage sharedManager] generatePreKeyRecords];


    XCTAssert([generatedKeys count] == 100, @"Not hundred keys generated");

    [[OWSPrimaryStorage sharedManager] storePreKeyRecords:generatedKeys];

    PreKeyRecord *lastPreKeyRecord = [generatedKeys lastObject];
    PreKeyRecord *firstPreKeyRecord = [generatedKeys firstObject];

    XCTAssert([[[OWSPrimaryStorage sharedManager] loadPreKey:lastPreKeyRecord.Id].keyPair.publicKey
        isEqualToData:lastPreKeyRecord.keyPair.publicKey]);

    XCTAssert([[[OWSPrimaryStorage sharedManager] loadPreKey:firstPreKeyRecord.Id].keyPair.publicKey
        isEqualToData:firstPreKeyRecord.keyPair.publicKey]);
}


- (void)testRemovingPreKeys
{
    NSArray *generatedKeys = [[OWSPrimaryStorage sharedManager] generatePreKeyRecords];

    XCTAssert([generatedKeys count] == 100, @"Not hundred keys generated");

    [[OWSPrimaryStorage sharedManager] storePreKeyRecords:generatedKeys];

    PreKeyRecord *lastPreKeyRecord = [generatedKeys lastObject];
    PreKeyRecord *firstPreKeyRecord = [generatedKeys firstObject];

    [[OWSPrimaryStorage sharedManager] removePreKey:lastPreKeyRecord.Id];

    XCTAssertThrows([[OWSPrimaryStorage sharedManager] loadPreKey:lastPreKeyRecord.Id]);
    XCTAssertNoThrow([[OWSPrimaryStorage sharedManager] loadPreKey:firstPreKeyRecord.Id]);
}

@end
