/**
 * @description Removes expired non-Broadcast notifications using the retention configured in CMDT.
 *              Messages and Chatter posts are never deleted by this batch.
 */
public without sharing class CommunicatorNotificationPurgeBatch
    implements Database.Batchable<SObject>, Database.Stateful, Schedulable {

    @TestVisible private Integer eligibleCount = 0;
    @TestVisible private Integer deletedCount = 0;
    @TestVisible private Integer failedRecordCount = 0;
    @TestVisible private Map<String, Integer> failureCountByStatusCode = new Map<String, Integer>();

    public Database.QueryLocator start(Database.BatchableContext bc) {
        Datetime readCutoff = System.now().addDays(-CommunicatorConfigService.getReadNotificationRetentionDays());
        Datetime unreadCutoff = System.now().addDays(-CommunicatorConfigService.getUnreadNotificationRetentionDays());
        return Database.getQueryLocator([
            SELECT Id
            FROM CommunicatorNotification__c
            WHERE Type__c != 'Broadcast'
            AND (
                (IsRead__c = true AND ReadAt__c != null AND ReadAt__c < :readCutoff)
                OR (IsRead__c = true AND ReadAt__c = null AND LastModifiedDate < :readCutoff)
                OR (IsRead__c = false AND CreatedDate < :unreadCutoff)
            )
        ]);
    }

    public void execute(
        Database.BatchableContext bc,
        List<SObject> scope
    ) {
        if (scope == null || scope.isEmpty()) return;
        Set<Id> scopeIds = new Set<Id>();
        for (SObject row : scope) {
            CommunicatorNotification__c notification = (CommunicatorNotification__c) row;
            if (notification.Id != null) scopeIds.add(notification.Id);
        }
        if (scopeIds.isEmpty()) return;

        Datetime readCutoff = System.now().addDays(-CommunicatorConfigService.getReadNotificationRetentionDays());
        Datetime unreadCutoff = System.now().addDays(-CommunicatorConfigService.getUnreadNotificationRetentionDays());
        List<CommunicatorNotification__c> eligible = [
            SELECT Id, Type__c, IsRead__c, ReadAt__c, CreatedDate, LastModifiedDate,
                   Thread__c, Message__c, Recipient__c, IsMention__c
            FROM CommunicatorNotification__c
            WHERE Id IN :scopeIds
            AND Type__c != 'Broadcast'
            AND (
                (IsRead__c = true AND ReadAt__c != null AND ReadAt__c < :readCutoff)
                OR (IsRead__c = true AND ReadAt__c = null AND LastModifiedDate < :readCutoff)
                OR (IsRead__c = false AND CreatedDate < :unreadCutoff)
            )
            FOR UPDATE
        ];
        eligibleCount += eligible.size();
        if (eligible.isEmpty()) return;

        recordDeleteResults(Database.delete(eligible, false));
    }

    @TestVisible
    private void recordDeleteResults(List<Database.DeleteResult> results) {
        if (results == null) return;
        for (Database.DeleteResult result : results) {
            if (result.isSuccess()) {
                deletedCount++;
                continue;
            }
            failedRecordCount++;
            for (Database.Error error : result.getErrors()) {
                String statusCode = String.valueOf(error.getStatusCode());
                Integer countForCode = failureCountByStatusCode.containsKey(statusCode)
                    ? failureCountByStatusCode.get(statusCode)
                    : 0;
                failureCountByStatusCode.put(statusCode, countForCode + 1);
            }
        }
    }

    public void finish(Database.BatchableContext bc) {
        Map<String, Object> summary = new Map<String, Object>{
            'eligible' => eligibleCount,
            'deleted' => deletedCount,
            'failedRecords' => failedRecordCount,
            'failureStatusCodes' => failureCountByStatusCode
        };
        System.debug(
            failedRecordCount > 0 ? LoggingLevel.WARN : LoggingLevel.INFO,
            'CommunicatorNotificationPurgeBatch summary=' + JSON.serialize(summary)
        );
    }

    public void execute(SchedulableContext sc) {
        Database.executeBatch(new CommunicatorNotificationPurgeBatch(), 2000);
    }
}