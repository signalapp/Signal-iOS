//
//  TSStorageManager+keyingMaterial.h
//  TextSecureKit
//
//  Created by Frederic Jacobs on 06/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "TSStorageManager.h"

@interface TSStorageManager (keyingMaterial)

#pragma mark Server Credentials

/**
 *  The server signaling key that's used to encrypt push payloads
 *
 *  @return signaling key
 */

+ (NSString*)signalingKey;

/**
 *  The server auth token allows the TextSecure client to connect to the server
 *
 *  @return server authentication token
 */

+ (NSString*)serverAuthToken;

+ (void)storeServerToken:(NSString*)authToken signalingKey:(NSString*)signalingKey phoneNumber:(NSString*)phoneNumber;

@end
