
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
            transaction.enumerateRows(inCollection: type.collection) { key, object, _, x in
                guard let job = object as? Job else { return }
                result.append(job)
            }
        }
        return result
    }

    public func cancelAllPendingJobs(of type: Job.Type, using transaction: YapDatabaseReadWriteTransaction) {
        transaction.removeAllObjects(inCollection: type.collection)
    }

    @objc(cancelPendingMessageSendJobIfNeededForMessage:using:)
    public func cancelPendingMessageSendJobIfNeeded(for tsMessageTimestamp: UInt64, using transaction: YapDatabaseReadWriteTransaction) {
        var attachmentUploadJobKeys: [String] = []
        transaction.enumerateRows(inCollection: AttachmentUploadJob.collection) { key, object, _, _ in
            guard let job = object as? AttachmentUploadJob, job.message.sentTimestamp == tsMessageTimestamp else { return }
            attachmentUploadJobKeys.append(key)
        }
        var messageSendJobKeys: [String] = []
        transaction.enumerateRows(inCollection: MessageSendJob.collection) { key, object, _, _ in
            guard let job = object as? MessageSendJob, job.message.sentTimestamp == tsMessageTimestamp else { return }
            messageSendJobKeys.append(key)
        }
        transaction.removeObjects(forKeys: attachmentUploadJobKeys, inCollection: AttachmentUploadJob.collection)
        transaction.removeObjects(forKeys: messageSendJobKeys, inCollection: MessageSendJob.collection)
    }

    @objc public func cancelPendingMessageSendJobs(for threadID: String, using transaction: YapDatabaseReadWriteTransaction) {
        var attachmentUploadJobKeys: [String] = []
        transaction.enumerateRows(inCollection: AttachmentUploadJob.collection) { key, object, _, _ in
            guard let job = object as? AttachmentUploadJob, job.threadID == threadID else { return }
            attachmentUploadJobKeys.append(key)
        }
        var messageSendJobKeys: [String] = []
        transaction.enumerateRows(inCollection: MessageSendJob.collection) { key, object, _, _ in
            guard let job = object as? MessageSendJob, job.message.threadID == threadID else { return }
            messageSendJobKeys.append(key)
        }
        transaction.removeObjects(forKeys: attachmentUploadJobKeys, inCollection: AttachmentUploadJob.collection)
        transaction.removeObjects(forKeys: messageSendJobKeys, inCollection: MessageSendJob.collection)
    }
    
    public func getAttachmentUploadJob(for attachmentID: String) -> AttachmentUploadJob? {
        var result: [AttachmentUploadJob] = []
        Storage.read { transaction in
            transaction.enumerateRows(inCollection: AttachmentUploadJob.collection) { _, object, _, _ in
                guard let job = object as? AttachmentUploadJob, job.attachmentID == attachmentID else { return }
                result.append(job)
            }
        }
        #if DEBUG
        assert(result.isEmpty || result.count == 1)
        #endif
        return result.first
    }
    
    public func getAttachmentDownloadJobs(for threadID: String) -> [AttachmentDownloadJob] {
        var result: [AttachmentDownloadJob] = []
        Storage.read { transaction in
            transaction.enumerateRows(inCollection: AttachmentDownloadJob.collection) { _, object, _, _ in
                guard let job = object as? AttachmentDownloadJob, job.threadID == threadID else { return }
                result.append(job)
            }
        }
        return result
    }
    
    public func resumeAttachmentDownloadJobsIfNeeded(for threadID: String) {
        let jobs = getAttachmentDownloadJobs(for: threadID)
        jobs.forEach { job in
            job.delegate = JobQueue.shared
            job.isDeferred = false
            job.execute()
        }
    }

    public func getMessageSendJob(for messageSendJobID: String) -> MessageSendJob? {
        var result: MessageSendJob?
        Storage.read { transaction in
            result = transaction.object(forKey: messageSendJobID, inCollection: MessageSendJob.collection) as? MessageSendJob
        }
        return result
    }

    public func resumeMessageSendJobIfNeeded(_ messageSendJobID: String) {
        guard let job = getMessageSendJob(for: messageSendJobID) else { return }
        job.delegate = JobQueue.shared
        job.execute()
    }

    public func isJobCanceled(_ job: Job) -> Bool {
        var result = true
        Storage.read { transaction in
            result = !transaction.hasObject(forKey: job.id!, inCollection: type(of: job).collection)
        }
        return result
    }
}
