#import <Foundation/Foundation.h>
#import "DiscardingLog.h"
#import "Release.h"


NSObject* churnLock(void);
bool _testChurnHelper(int (^condition)(), NSTimeInterval delay);

#define testPhoneNumber1 [PhoneNumber phoneNumberFromE164:@"+19027777777"]
#define testPhoneNumber2 [PhoneNumber phoneNumberFromE164:@"+19028888888"]

#define test(expressionExpectedToBeTrue) XCTAssert(expressionExpectedToBeTrue, @"")
#define testThrows(expressionExpectedToThrow) XCTAssertThrows(expressionExpectedToThrow, @"")
#define testDoesNotThrow(expressionExpectedToNotThrow) expressionExpectedToNotThrow
#define testEnv [Release unitTestEnvironment:@[]]
#define testEnvWith(options) [Release unitTestEnvironment:(@[options])]
#define testChurnUntil(condition, timeout) test(_testChurnHelper(^int{ return condition; }, timeout))
#define testChurnAndConditionMustStayTrue(condition, timeout) test(!_testChurnHelper(^int{ return !(condition); }, timeout))

NSData* increasingData(NSUInteger n);
NSData* increasingDataFrom(NSUInteger offset, NSUInteger n);
NSData* sineWave(double frequency, double sampleRate, NSUInteger sampleCount);
NSData* generatePseudoRandomData(NSUInteger length);
