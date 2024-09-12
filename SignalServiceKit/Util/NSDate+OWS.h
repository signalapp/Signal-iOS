//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

NS_ASSUME_NONNULL_BEGIN

// These NSTimeInterval constants provide simplified durations for readability.
//
// These approximations should never be used for strict date/time calcuations.
extern const NSTimeInterval kSecondInterval;
extern const NSTimeInterval kMinuteInterval;
extern const NSTimeInterval kHourInterval;
extern const NSTimeInterval kDayInterval;
extern const NSTimeInterval kWeekInterval;
extern const NSTimeInterval kMonthInterval;
extern const NSTimeInterval kYearInterval;

#define kSecondInMs ((uint64_t)1000)
#define kMinuteInMs (kSecondInMs * 60)
#define kHourInMs (kMinuteInMs * 60)
#define kDayInMs (kHourInMs * 24)
#define kWeekInMs (kDayInMs * 7)
#define kMonthInMs (kDayInMs * 30)

// kYearsInMs is a double to avoid overflow
#define kYearsInMs (kDayInMs * 365.0)

NS_ASSUME_NONNULL_END
