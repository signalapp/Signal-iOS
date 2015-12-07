//
//  TSStoragePreKeyStoreTests.m
//  TextSecureKit
//
//  Created by Frederic Jacobs on 07/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "TSStorageManager+PreKeyStore.h"
#import <XCTest/XCTest.h>

@interface TSStoragePreKeyStoreTests : XCTestCase

@end

@implementation TSStoragePreKeyStoreTests

- (void)setUp {
    [super setUp];
    // Put setup code here. This method is called before the invocation of each test method in the class.
}

- (void)tearDown {
    // Put teardown code here. This method is called after the invocation of each test method in the class.
    [super tearDown];
}

- (void)testGeneratingAndStoringPreKeys {
    NSArray *generatedKeys = [[TSStorageManager sharedManager] generatePreKeyRecords];
    
    
    XCTAssert([generatedKeys count] == 100, @"Not hundred keys generated");
    
    [[TSStorageManager sharedManager] storePreKeyRecords:generatedKeys];
    
    PreKeyRecord *lastPreKeyRecord  = [generatedKeys lastObject];
    PreKeyRecord *firstPreKeyRecord = [generatedKeys firstObject];
    
    XCTAssert([[[TSStorageManager sharedManager] loadPreKey:lastPreKeyRecord.Id].keyPair.publicKey isEqualToData:lastPreKeyRecord.keyPair.publicKey]);
    
    XCTAssert([[[TSStorageManager sharedManager] loadPreKey:firstPreKeyRecord.Id].keyPair.publicKey isEqualToData:firstPreKeyRecord.keyPair.publicKey]);
    
}


- (void)testRemovingPreKeys {
    NSArray *generatedKeys = [[TSStorageManager sharedManager] generatePreKeyRecords];
    
    XCTAssert([generatedKeys count] == 100, @"Not hundred keys generated");
    
    [[TSStorageManager sharedManager] storePreKeyRecords:generatedKeys];
    
    PreKeyRecord *lastPreKeyRecord  = [generatedKeys lastObject];
    PreKeyRecord *firstPreKeyRecord = [generatedKeys firstObject];
    
    [[TSStorageManager sharedManager] removePreKey:lastPreKeyRecord.Id];
    
    XCTAssertThrows([[TSStorageManager sharedManager] loadPreKey:lastPreKeyRecord.Id]);
    XCTAssertNoThrow([[TSStorageManager sharedManager] loadPreKey:firstPreKeyRecord.Id]);
    
}

@end
