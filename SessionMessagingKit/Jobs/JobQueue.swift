
public final class JobQueue : JobDelegate {

    public static let shared = JobQueue()

    public func add(_ job: Job, using transaction: Any) {
        Configuration.shared.storage.persist(job, using: transaction)
        job.delegate = self
        job.execute()
    }

    public func handleJobSucceeded(_ job: Job) {
        // Mark the job as succeeded
    }

    public func handleJobFailed(_ job: Job, with error: Error) {
        // Persist the job
        // Retry it if the max failure count hasn't been reached
        // Propagate the error otherwise
    }
}
