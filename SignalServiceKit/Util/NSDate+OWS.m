//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "NSDate+OWS.h"

NS_ASSUME_NONNULL_BEGIN

const NSTimeInterval kSecondInterval = 1;
const NSTimeInterval kMinuteInterval = 60;
const NSTimeInterval kHourInterval = 60 * kMinuteInterval;
const NSTimeInterval kDayInterval = 24 * kHourInterval;
const NSTimeInterval kWeekInterval = 7 * kDayInterval;
const NSTimeInterval kMonthInterval = 30 * kDayInterval;
const NSTimeInterval kYearInterval = 365 * kDayInterval;

NS_ASSUME_NONNULL_END
