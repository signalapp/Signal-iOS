// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation

public enum JobRunnerError: Error {
    case generic
    
    case executorMissing
    case jobIdMissing
    case requiredThreadIdMissing
    case requiredInteractionIdMissing
    
    case missingRequiredDetails
    case missingDependencies
    
    case possibleDeferralLoop
}
