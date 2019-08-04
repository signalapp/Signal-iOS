//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "SSKBaseTestObjC.h"
#import "SSKPreKeyStore.h"

@interface SSKPreKeyStoreTests : SSKBaseTestObjC

@end

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

    [self.preKeyStore removePreKey:lastPreKeyRecord.Id];

    XCTAssertNil([self.preKeyStore loadPreKey:lastPreKeyRecord.Id]);
    XCTAssertNotNil([self.preKeyStore loadPreKey:firstPreKeyRecord.Id]);
}

@end
