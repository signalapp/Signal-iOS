//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Testing

@testable import SignalUI

struct OWSByteCountFormatStyleTest {
    @Test(arguments: [
        (0, 0),
        (1024, 1000), // 1 KiB
        (1_048_576, 1_000_000), // 1 MiB
        (1_048_577, nil), // 1 MiB + 1 B
        (1_073_741_824, 1_000_000_000), // 1 GiB
        (1_074_790_400, nil), // 1 GiB + 2 MiB
        (39_728_447_488, 37_000_000_000), // 37 GiB
        (107_374_182_400, 100_000_000_000), // 100 GiB
        (1_099_511_627_776, 1_000_000_000_000), // 1 TiB
        (1_125_899_906_842_624, 1_000_000_000_000_000), // 1 PiB
    ])
    func fudgingBase2ToBase10ByteCount(byteCount: UInt64, expected: UInt64?) {
        #expect(
            expected == OWSBase2ByteCountFudger.fudgeBase2ToBase10(byteCount),
        )
    }
}
