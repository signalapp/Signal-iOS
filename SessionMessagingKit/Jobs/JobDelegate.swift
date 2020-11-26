
@objc(SNJobDelegate)
public protocol JobDelegate {

    func handleJobSucceeded(_ job: Job)
    func handleJobFailed(_ job: Job, with error: Error)
    func handleJobFailedPermanently(_ job: Job, with error: Error)
}
