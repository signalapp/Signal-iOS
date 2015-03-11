//
//  BloomFilterTests.m
//  Signal
//
//  Created by Frederic Jacobs on 11/03/15.
//  Copyright (c) 2015 Open Whisper Systems. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <XCTest/XCTest.h>
#import "Cryptography.h"
#import "Environment.h"
#import "PropertyListPreferences.h"

@interface PropertyListPreferences()
- (NSData*)tryRetreiveBloomFilter;
- (void)storeBloomfilter:(NSData*)bloomFilterData;
@end

@interface BloomFilterTests : XCTestCase

@end

@implementation BloomFilterTests

- (void)tearDown{
    PropertyListPreferences *prefs = [Environment preferences];
    [prefs storeBloomfilter:nil];
}

- (void)testCreationRetreivalDeletion{
    NSData *randomData  = [Cryptography generateRandomBytes:30];
    PropertyListPreferences *prefs = [Environment preferences];
    
    NSData *bloomFilter = [prefs tryRetreiveBloomFilter];
    
    XCTAssert(bloomFilter == nil);
    
    [prefs storeBloomfilter:randomData];
    bloomFilter = [prefs tryRetreiveBloomFilter];
    
    XCTAssert([bloomFilter isEqualToData:randomData]);
    
    [prefs storeBloomfilter:nil];
    bloomFilter = [prefs tryRetreiveBloomFilter];
    XCTAssert(bloomFilter == nil);
}

@end
