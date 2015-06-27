#import <XCTest/XCTest.h>

#import "YapDatabaseQuery.h"

@interface TestYapDatabaseQuery : XCTestCase
@end

@implementation TestYapDatabaseQuery

- (void)test1
{
	YapDatabaseQuery *query = [YapDatabaseQuery queryWithFormat:@"WHERE col > 5"];
	XCTAssertTrue([query.queryString isEqualToString:@"WHERE col > 5"], @"Incorrect queryString");
	
	query = [YapDatabaseQuery queryWithFormat:@"WHERE col > ?", @(5)];
	NSArray *expectedArguments = @[@(5)];
	XCTAssertTrue([query.queryString isEqualToString:@"WHERE col > ?"], @"Incorrect queryString");
	XCTAssertTrue([query.queryParameters isEqualToArray:@[@(5)]], @"Incorrect queryParameters");
	
	query = [YapDatabaseQuery queryWithFormat:@"WHERE col > ? AND col < ?", @(1), @(5)];
	expectedArguments = @[@(1), @(5)];
	XCTAssertTrue([query.queryString isEqualToString:@"WHERE col > ? AND col < ?"], @"Incorrect queryString");
	XCTAssertTrue([query.queryParameters isEqualToArray:expectedArguments], @"Incorrect queryParameters");
	
	query = [YapDatabaseQuery queryWithFormat:@"WHERE col > ? AND col < ?", @(1), @(5)];
	expectedArguments = @[@(1), @(5)];
	XCTAssertTrue([query.queryString isEqualToString:@"WHERE col > ? AND col < ?"], @"Incorrect queryString");
	XCTAssertTrue([query.queryParameters isEqualToArray:expectedArguments], @"Incorrect queryParameters");
	
	query = [YapDatabaseQuery queryWithFormat:@"WHERE col IN (?)", @[@(1), @(5)]];
	expectedArguments = @[@(1), @(5)];
	XCTAssertTrue([query.queryString isEqualToString:@"WHERE col IN (?,?)"], @"Incorrect queryString");
	XCTAssertTrue([query.queryParameters isEqualToArray:expectedArguments], @"Incorrect queryParameters");
	
	query = [YapDatabaseQuery queryWithFormat:@"WHERE col IN (?) AND col2 <> ?", @[@(1), @(5)], @"test"];
	expectedArguments = @[@(1), @(5), @"test"];
	XCTAssertTrue([query.queryString isEqualToString:@"WHERE col IN (?,?) AND col2 <> ?"], @"Incorrect queryString");
	XCTAssertTrue([query.queryParameters isEqualToArray:expectedArguments], @"Incorrect queryParameters");
	
	query = [YapDatabaseQuery queryWithFormat:@"WHERE col2 <> ? AND col IN (?)", @"test", @[@(1), @(5)]];
	expectedArguments = @[@"test", @(1), @(5)];
	XCTAssertTrue([query.queryString isEqualToString:@"WHERE col2 <> ? AND col IN (?,?)"], @"Incorrect queryString");
	XCTAssertTrue([query.queryParameters isEqualToArray:expectedArguments], @"Incorrect queryParameters");
	
	query = [YapDatabaseQuery queryWithFormat:@"WHERE col1 IN (?) AND col2 IN (?)", @[@(1), @(2)], @[@(3), @(4)]];
	expectedArguments = @[@(1), @(2), @(3), @(4)];
	XCTAssertTrue([query.queryString isEqualToString:@"WHERE col1 IN (?,?) AND col2 IN (?,?)"], @"Incorrect queryString: %@", query.queryString);
	XCTAssertTrue([query.queryParameters isEqualToArray:expectedArguments], @"Incorrect queryParameters");
	
	query = [YapDatabaseQuery queryWithFormat:@"WHERE col1 IN (?)", @[]];
	expectedArguments = @[ [NSNull null] ];
	XCTAssertTrue([query.queryString isEqualToString:@"WHERE col1 IN (?)"], @"Incorrect queryString: %@", query.queryString);
	XCTAssertTrue([query.queryParameters isEqualToArray:expectedArguments], @"Incorrect queryParameters");
}

@end