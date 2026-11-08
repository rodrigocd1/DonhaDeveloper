public without sharing class CommunicatorBroadcastNotifBatch
implements Database.Batchable<SObject> {

    private final Id messageId;
    private final Id senderId;
    private final String senderName;
    private final String subject;

    public CommunicatorBroadcastNotifBatch(
        Id messageId,
        Id senderId,
        String senderName,
        String subject
    ) {
        this.messageId = messageId;
        this.senderId = senderId;
        this.senderName = senderName;
        this.subject = subject;
    }

    public Database.QueryLocator start(Database.BatchableContext context) {
        List<CommunicatorMessage__c> messages = [
            SELECT Id, Status__c
            FROM CommunicatorMessage__c
            WHERE Id = :messageId
            LIMIT 1
        ];
        if (messages.isEmpty() || messages[0].Status__c != CommunicatorBroadcastDistributionService.STATUS_SENT) {
            return Database.getQueryLocator([
                SELECT Id
                FROM User
                WHERE Id = null
            ]);
        }
        return Database.getQueryLocator([
            SELECT Id
            FROM User
            WHERE IsActive = true
            AND Id != :senderId
            AND Id IN (
                SELECT Recipient__c
                FROM CommunicatorNotification__c
                WHERE Message__c = :messageId
                AND Type__c = 'Broadcast'
            )
        ]);
    }

    public void execute(Database.BatchableContext context, List<SObject> scope) {
        if (scope == null || scope.isEmpty()) return;

        Set<Id> scopedUserIds = new Set<Id>();
        for (SObject recordItem : scope) {
            Id userId = (Id) recordItem.get('Id');
            if (userId != null && userId != senderId) {
                scopedUserIds.add(userId);
            }
        }
        if (scopedUserIds.isEmpty()) return;

        Map<Id, CommunicatorBroadcastAudienceService.UserAudienceCategory> categories =
            CommunicatorBroadcastAudienceService.classifyUsers(scopedUserIds);
        Set<Id> eligibleRecipients = new Set<Id>();
        for (Id userId : scopedUserIds) {
            CommunicatorBroadcastAudienceService.UserAudienceCategory category = categories.get(userId);
            if (category == CommunicatorBroadcastAudienceService.UserAudienceCategory.CORE_SALESFORCE ||
                category == CommunicatorBroadcastAudienceService.UserAudienceCategory.CORE_PLATFORM ||
                category == CommunicatorBroadcastAudienceService.UserAudienceCategory.COMMUNITY_PARTNER) {
                eligibleRecipients.add(userId);
            }
        }
        if (eligibleRecipients.isEmpty()) return;

        CommunicatorBroadcastService.sendBroadcastCustomNotificationFromSnapshot(
            eligibleRecipients,
            senderName,
            subject
        );
    }

    public void finish(Database.BatchableContext context) {
    }
}