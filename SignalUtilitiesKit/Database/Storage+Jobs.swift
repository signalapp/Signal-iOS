
extension Storage {
    
    public func persist(_ job: Job, using transaction: Any) {
        (transaction as! YapDatabaseReadWriteTransaction).setObject(job, forKey: job.id!, inCollection: type(of: job).collection)
    }

    public func markJobAsSucceeded(_ job: Job, using transaction: Any) {
        (transaction as! YapDatabaseReadWriteTransaction).removeObject(forKey: job.id!, inCollection: type(of: job).collection)
    }

    public func markJobAsFailed(_ job: Job, using transaction: Any) {
        (transaction as! YapDatabaseReadWriteTransaction).removeObject(forKey: job.id!, inCollection: type(of: job).collection)
    }

    public func getAllPendingJobs(of type: Job.Type) -> [Job] {
        var result: [Job] = []
        Storage.read { transaction in
            transaction.enumerateRows(inCollection: type.collection) { _, object, _, _ in
                guard let job = object as? Job else { return }
                result.append(job)
            }
        }
        return result
    }
}
