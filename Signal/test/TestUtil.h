//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#define testPhoneNumber1 [PhoneNumber phoneNumberFromE164:@"+19027777777"]
#define testPhoneNumber2 [PhoneNumber phoneNumberFromE164:@"+19028888888"]

#define test(expressionExpectedToBeTrue) XCTAssert(expressionExpectedToBeTrue, @"")
#define testThrows(expressionExpectedToThrow) XCTAssertThrows(expressionExpectedToThrow, @"")
#define testDoesNotThrow(expressionExpectedToNotThrow) expressionExpectedToNotThrow
#define testChurnUntil(condition, timeout) test(_testChurnHelper(^int{ return condition; }, timeout))
#define testChurnAndConditionMustStayTrue(condition, timeout) test(!_testChurnHelper(^int{ return !(condition); }, timeout))
