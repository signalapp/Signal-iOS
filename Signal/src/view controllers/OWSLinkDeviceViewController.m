//  Copyright © 2016 Open Whisper Systems. All rights reserved.

#import "OWSLinkDeviceViewController.h"
#import "OWSDeviceProvisioningURLParser.h"
#import <SignalServiceKit/ECKeyPair+OWSPrivateKey.h>
#import <SignalServiceKit/OWSDeviceProvisioner.h>
#import <SignalServiceKit/TSStorageManager+IdentityKeyStore.h>
#import <SignalServiceKit/TSStorageManager+keyingMaterial.h>

NS_ASSUME_NONNULL_BEGIN

@implementation OWSLinkDeviceViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
}

- (void)didDetectQRCodeWithString:(NSString *)string
{
    OWSDeviceProvisioningURLParser *parser = [[OWSDeviceProvisioningURLParser alloc] initWithProvisioningURL:string];

    if (!parser.isValid) {
        DDLogError(@"Unable to parse provisioning params from QRCode: %@", string);
        return;
    }

    NSData *myPublicKey = [[TSStorageManager sharedManager] identityKeyPair].publicKey;
    NSData *myPrivateKey = [[TSStorageManager sharedManager] identityKeyPair].ows_privateKey;
    NSString *accountIdentifier = [TSStorageManager localNumber];

    OWSDeviceProvisioner *provisioner = [[OWSDeviceProvisioner alloc] initWithMyPublicKey:myPublicKey
                                                                             myPrivateKey:myPrivateKey
                                                                           theirPublicKey:parser.publicKey
                                                                   theirEphemeralDeviceId:parser.ephemeralDeviceId
                                                                        accountIdentifier:accountIdentifier];

    [provisioner provisionWithSuccess:^{
        DDLogInfo(@"Successfully provisioned device.");
    }
        failure:^(NSError *error) {
            DDLogError(@"Failed to provision device with error: %@", error);
        }];

    // TODO show progress. Maybe even incremental with progress callback in provisioner.
}

@end

NS_ASSUME_NONNULL_END
