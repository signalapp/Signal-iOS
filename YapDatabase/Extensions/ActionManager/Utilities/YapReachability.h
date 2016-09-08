/**
 * This file is copied from a separate project:
 * https://github.com/tonymillion/Reachability
 * 
 * Unfortunately, the Podspec for this project hasn't been updated for tvOS & watchOS.
 * However, the source code itself works just fine.
 * So we're simply including the code directly for now.
 *
 * We may revert to the official project if its Podspec is updated.
 * Or switch to another if a suitable alternative open-source project is found.
**/

#import <Availability.h>
#import <TargetConditionals.h>

#if !TARGET_OS_WATCH

/*
 Copyright (c) 2011, Tony Million.
 All rights reserved.
 
 Redistribution and use in source and binary forms, with or without
 modification, are permitted provided that the following conditions are met:
 
 1. Redistributions of source code must retain the above copyright notice, this
 list of conditions and the following disclaimer.
 
 2. Redistributions in binary form must reproduce the above copyright notice,
 this list of conditions and the following disclaimer in the documentation
 and/or other materials provided with the distribution.
 
 THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
 AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
 LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
 CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
 POSSIBILITY OF SUCH DAMAGE. 
 */

#import <Foundation/Foundation.h>
#import <SystemConfiguration/SystemConfiguration.h>


/** 
 * Create NS_ENUM macro if it does not exist on the targeted version of iOS or OS X.
 *
 * @see http://nshipster.com/ns_enum-ns_options/
 **/
#ifndef NS_ENUM
#define NS_ENUM(_type, _name) enum _name : _type _name; enum _name : _type
#endif

extern NSString *const kYapReachabilityChangedNotification;

typedef NS_ENUM(NSInteger, YapReachabilityStatus) {
    // Apple NetworkStatus Compatible Names.
    YapReachabilityStatus_NotReachable = 0,
    YapReachabilityStatus_ReachableViaWiFi = 2,
    YapReachabilityStatus_ReachableViaWWAN = 1
};

@class YapReachability;

typedef void (^NetworkReachableBlock)(YapReachability * reachability);
typedef void (^NetworkUnreachableBlock)(YapReachability * reachability);


@interface YapReachability : NSObject

@property (nonatomic, copy) NetworkReachableBlock    reachableBlock;
@property (nonatomic, copy) NetworkUnreachableBlock  unreachableBlock;

@property (nonatomic, assign) BOOL reachableOnWWAN;


+(YapReachability*)reachabilityWithHostname:(NSString*)hostname;
// This is identical to the function above, but is here to maintain
//compatibility with Apples original code. (see .m)
+(YapReachability*)reachabilityWithHostName:(NSString*)hostname;
+(YapReachability*)reachabilityForInternetConnection;
+(YapReachability*)reachabilityWithAddress:(void *)hostAddress;
+(YapReachability*)reachabilityForLocalWiFi;

-(YapReachability *)initWithReachabilityRef:(SCNetworkReachabilityRef)ref;

-(BOOL)startNotifier;
-(void)stopNotifier;

-(BOOL)isReachable;
-(BOOL)isReachableViaWWAN;
-(BOOL)isReachableViaWiFi;

// WWAN may be available, but not active until a connection has been established.
// WiFi may require a connection for VPN on Demand.
-(BOOL)isConnectionRequired; // Identical DDG variant.
-(BOOL)connectionRequired; // Apple's routine.
// Dynamic, on demand connection?
-(BOOL)isConnectionOnDemand;
// Is user intervention required?
-(BOOL)isInterventionRequired;

-(YapReachabilityStatus)currentReachabilityStatus;
-(SCNetworkReachabilityFlags)reachabilityFlags;
-(NSString*)currentReachabilityString;
-(NSString*)currentReachabilityFlags;

@end

#endif
