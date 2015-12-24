//
//  AppStoreRating.m
//  Signal
//
//  Created by Frederic Jacobs on 23/08/15.
//  Copyright (c) 2015 Open Whisper Systems. All rights reserved.
//

#import "AppStoreRating.h"
#import "iRate.h"

@implementation AppStoreRating

+ (void)setupRatingLibrary {
    iRate *rate                         = [iRate sharedInstance];
    rate.appStoreID                     = 874139669;
    rate.appStoreGenreID                = 6005;
    rate.daysUntilPrompt                = 15;
    rate.usesUntilPrompt                = 10;
    rate.remindPeriod                   = 20;
    rate.onlyPromptIfLatestVersion      = YES;
    rate.promptForNewVersionIfUserRated = NO;
    rate.messageTitle                   = NSLocalizedString(@"RATING_TITLE", nil);
    rate.message                        = NSLocalizedString(@"RATING_MSG", nil);
    rate.rateButtonLabel                = NSLocalizedString(@"RATING_RATE", nil);
}

@end
