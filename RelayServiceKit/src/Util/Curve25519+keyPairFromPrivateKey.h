//
//  Curve25519+keyPairFromPrivateKey.h
//  Forsta
//
//  Created by Mark Descalzo on 5/10/18.
//  Copyright © 2018 Forsta. All rights reserved.
//

#import <Curve25519Kit/Curve25519.h>

@import Foundation;

@interface ECKeyPair (keyPairFromPrivateKey)

@end

@interface Curve25519 (keyPairFromPrivateKey)

/**
 *  Generate a curve25519 key pair from provided private key
 *
 * @return curve25519 key pair
 */
+ (ECKeyPair *)generateKeyPairWithPrivateKey:(NSData *)privKey;

@end
