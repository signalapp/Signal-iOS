//
//  iOSVersions.h
//  Signal
//
//  Created by Frederic Jacobs on 03/08/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import <Foundation/Foundation.h>
#include <Availability.h>

// Source: https://github.com/carlj/CJAMacros/blob/master/CJAMacros/CJAMacros.h

/**
 Runtime check for the current version Nummer.
 checks ( CURRENT_VERSION_NUMBR == GIVEN_VERSION_NUMBER)
 @_gVersion - the given Version Number. aka (_iOS_7_0 or NSFoundationVersionNumber_iOS_7_0 and so on)
 */
#define SYSTEM_VERSION_EQUAL_TO(_gVersion)                  ( floor(NSFoundationVersionNumber) == _gVersion )

/**
 Runtime check for the current version Nummer.
 checks CURRENT_VERSION_NUMBER > GIVEN_VERSION_NUMBER
 @_gVersion - the given Version Number. aka (_iOS_7_0 or NSFoundationVersionNumber_iOS_7_0 and so on)
 */
#define SYSTEM_VERSION_GREATER_THAN(_gVersion)              ( floor(NSFoundationVersionNumber) >  _gVersion )

/**
 Runtime check for the current version Nummer.
 checks CURRENT_VERSION_NUMBER >= GIVEN_VERSION_NUMBER
 @_gVersion - the given Version Number. aka (_iOS_7_0 or NSFoundationVersionNumber_iOS_7_0 and so on)
 */
#define SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(_gVersion)  ( floor(NSFoundationVersionNumber) >= _gVersion )


/**
 Runtime check for the current version Nummer.
 checks CURRENT_VERSION_NUMBER < GIVEN_VERSION_NUMBER
 @_gVersion - the given Version Number. aka (_iOS_7_0 or NSFoundationVersionNumber_iOS_7_0 and so on)
 */
#define SYSTEM_VERSION_LESS_THAN(_gVersion)                 ( floor(NSFoundationVersionNumber) <  _gVersion )


/**
 Runtime check for the current version Nummer.
 checks CURRENT_VERSION_NUMBER <= GIVEN_VERSION_NUMBER
 @_gVersion - the given Version Number. aka (_iOS_7_0 or NSFoundationVersionNumber_iOS_7_0 and so on)
 */
#define SYSTEM_VERSION_LESS_THAN_OR_EQUAL_TO(_gVersion)     ( floor(NSFoundationVersionNumber) <= _gVersion )


//If the symbol for iOS 7 isnt defined, define it.
#ifndef NSFoundationVersionNumber_iOS_7_0
#define NSFoundationVersionNumber_iOS_7_0 1047.00 //extracted from iOS 7 Header
#endif

#ifdef NSFoundationVersionNumber_iOS_7_0
#define _iOS_7_0 NSFoundationVersionNumber_iOS_7_0
#endif

//If the symbol for iOS 7.1 isnt defined, define it.
#ifndef NSFoundationVersionNumber_iOS_7_1
#define NSFoundationVersionNumber_iOS_7_1 1047.25 //extracted from iOS 8 Header
#endif

#ifdef NSFoundationVersionNumber_iOS_7_1
#define _iOS_7_1 NSFoundationVersionNumber_iOS_7_1
#endif

//If the symbol for iOS 8 isnt defined, define it.
#ifndef NSFoundationVersionNumber_iOS_8_0
#define NSFoundationVersionNumber_iOS_8_0 1134.10 //extracted with NSLog(@"%f", NSFoundationVersionNumber)
#endif

#ifdef NSFoundationVersionNumber_iOS_8_0
#define _iOS_8_0 NSFoundationVersionNumber_iOS_8_0
#endif

#ifndef NSFoundationVersionNumber_iOS_8_0_2
#define NSFoundationVersionNumber_iOS_8_0_2 1140.110000 //extracted with NSLog(@"%f", NSFoundationVersionNumber)
#endif

#ifdef NSFoundationVersionNumber_iOS_8_0_2
#define _iOS_8_0_2 NSFoundationVersionNumber_iOS_8_0_2
#endif


#ifndef NSFoundationVersionNumber_iOS_8_2_0
#define NSFoundationVersionNumber_iOS_8_2_0 1142 //extracted with NSLog(@"%f", NSFoundationVersionNumber)
#endif

#ifdef NSFoundationVersionNumber_iOS_8_2_0
#define _iOS_8_2_0 NSFoundationVersionNumber_iOS_8_2_0
#endif

#ifndef NSFoundationVersionNumber_iOS_9
#define NSFoundationVersionNumber_iOS_9 1231 //extracted with NSLog(@"%f", NSFoundationVersionNumber)
#endif

#ifdef NSFoundationVersionNumber_iOS_9
#define _iOS_9 NSFoundationVersionNumber_iOS_9
#endif
