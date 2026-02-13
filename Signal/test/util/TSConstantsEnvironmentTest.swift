//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Testing

import SignalServiceKit

@Test
func testUseStagingEnvironmentVariableSelectsStaging() {
    #expect(TSConstants.isStagingEnvironmentForTests(processEnvironment: ["USE_STAGING": "1"]))
}

@Test
func testUseStagingEnvironmentVariableDefaultsToProduction() {
    #expect(!TSConstants.isStagingEnvironmentForTests(processEnvironment: [:]))
    #expect(!TSConstants.isStagingEnvironmentForTests(processEnvironment: ["USE_STAGING": "0"]))
}

@Test
func testProductionUpdates2URLUsesBeforeveCDN() {
    // Regression test: production updates2 base URL must not point at a non-resolving hostname,
    // otherwise RemoteMegaphoneFetcher fails with NSURLErrorDomain -1003.
    #expect(TSConstantsProduction().updates2URL == "https://cdn.beforeve.com")
}
