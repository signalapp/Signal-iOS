import SessionUtilitiesKit

@objc(SNJobQueue)
public final class JobQueue : NSObject, JobDelegate {

    @objc public static let shared = JobQueue()

    @objc public func add(_ job: Job, using transaction: Any) {
        let transaction = transaction as! YapDatabaseReadWriteTransaction
        addWithoutExecuting(job, using: transaction)
        transaction.addCompletionQueue(Threading.jobQueue) {
            job.execute()
        }
    }

    @objc public func addWithoutExecuting(_ job: Job, using transaction: Any) {
        job.id = String(NSDate.millisecondTimestamp())
        SNMessagingKitConfiguration.shared.storage.persist(job, using: transaction)
        job.delegate = self
    }

    @objc public func resumePendingJobs() {
        let allJobTypes: [Job.Type] = [ AttachmentDownloadJob.self, AttachmentUploadJob.self, MessageReceiveJob.self, MessageSendJob.self, NotifyPNServerJob.self ]
        allJobTypes.forEach { type in
            let allPendingJobs = SNMessagingKitConfiguration.shared.storage.getAllPendingJobs(of: type)
            allPendingJobs.sorted(by: { $0.id! < $1.id! }).forEach { job in // Retry the oldest jobs first
                SNLog("Resuming pending job of type: \(type).")
                job.delegate = self
                job.execute()
            }
        }
    }

    public func handleJobSucceeded(_ job: Job) {
        SNMessagingKitConfiguration.shared.storage.write(with: { transaction in
            SNMessagingKitConfiguration.shared.storage.markJobAsSucceeded(job, using: transaction)
        }, completion: {
            // Do nothing
        })
    }

    public func handleJobFailed(_ job: Job, with error: Error) {
        job.failureCount += 1
        let storage = SNMessagingKitConfiguration.shared.storage
        guard !storage.isJobCanceled(job) else { return SNLog("\(type(of: job)) canceled.") }
        storage.write(with: { transaction in
            storage.persist(job, using: transaction)
        }, completion: { // Intentionally capture self
            if job.failureCount == type(of: job).maxFailureCount {
                storage.write(with: { transaction in
                    storage.markJobAsFailed(job, using: transaction)
                }, completion: {
                    // Do nothing
                })
            } else {
                let retryInterval = self.getRetryInterval(for: job)
                SNLog("\(type(of: job)) failed; scheduling retry (failure count is \(job.failureCount)).")
                Timer.scheduledTimer(timeInterval: retryInterval, target: self, selector: #selector(self.retry(_:)), userInfo: job, repeats: false)
            }
        })
    }

    public func handleJobFailedPermanently(_ job: Job, with error: Error) {
        job.failureCount += 1
        let storage = SNMessagingKitConfiguration.shared.storage
        storage.write(with: { transaction in
            storage.persist(job, using: transaction)
        }, completion: { // Intentionally capture self
            storage.write(with: { transaction in
                storage.markJobAsFailed(job, using: transaction)
            }, completion: {
                // Do nothing
            })
        })
    }

    private func getRetryInterval(for job: Job) -> TimeInterval {
        // Arbitrary backoff factor...
        // try  1 delay: 0.5s
        // try  2 delay: 1s
        // ...
        // try  5 delay: 16s
        // ...
        // try 11 delay: 512s
        let maxBackoff: Double = 10 * 60 // 10 minutes
        return 0.25 * min(maxBackoff, pow(2, Double(job.failureCount)))
    }

    @objc private func retry(_ timer: Timer) {
        guard let job = timer.userInfo as? Job else { return }
        SNLog("Retrying \(type(of: job)).")
        job.delegate = self
        job.execute()
    }
}
