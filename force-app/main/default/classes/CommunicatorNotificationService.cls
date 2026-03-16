/**
 * @description Service responsible for sending notifications and managing unread counts.
 */
public with sharing class CommunicatorNotificationService {

    private static final String NOTIFICATION_TYPE_NAME = 'CommunicatorNewMessage';

    // ─────────────────────────────────────────
    // Notifications
    // ─────────────────────────────────────────

    /**
     * @description Sends a Salesforce bell notification to all thread participants
     *              except the current sender.
     */
    public static void notifyParticipants(Id threadId, Id messageId) {
        List<CommunicatorParticipant__c> participants = [
            SELECT Id, User__c
            FROM CommunicatorParticipant__c
            WHERE Thread__c = :threadId
            AND IsActive__c = true
            AND User__c != :UserInfo.getUserId()
        ];

        if (participants.isEmpty()) return;

        Set<String> recipientIds = new Set<String>();
        for (CommunicatorParticipant__c p : participants) {
            recipientIds.add(p.User__c);
        }

        List<CommunicatorThread__c> threads = [
            SELECT Id, RecordId__c, RecordType__c
            FROM CommunicatorThread__c
            WHERE Id = :threadId
            LIMIT 1
        ];

        String targetPageRef = buildTargetPageRef(threads.isEmpty() ? null : threads[0]);

        sendCustomNotification(recipientIds, targetPageRef, threadId);
    }

    // ─────────────────────────────────────────
    // Unread count
    // ─────────────────────────────────────────

    /**
     * @description Returns the number of messages created after the current user's last read time.
     */
    public static Integer getUnreadCount(Id threadId) {
        Id currentUserId = UserInfo.getUserId();

        List<CommunicatorParticipant__c> participants = [
            SELECT LastReadAt__c
            FROM CommunicatorParticipant__c
            WHERE Thread__c = :threadId
            AND User__c = :currentUserId
            LIMIT 1
        ];

        if (participants.isEmpty()) return 0;

        DateTime lastRead = participants[0].LastReadAt__c;
        if (lastRead == null) {
            return [
                SELECT COUNT()
                FROM CommunicatorMessage__c
                WHERE Thread__c = :threadId
                AND Sender__c != :currentUserId
            ];
        }

        return [
            SELECT COUNT()
            FROM CommunicatorMessage__c
            WHERE Thread__c = :threadId
            AND SentAt__c > :lastRead
            AND Sender__c != :currentUserId
        ];
    }

    /**
     * @description Updates the current user's LastReadAt timestamp to mark messages as read.
     */
    public static void markThreadAsRead(Id threadId) {
        Id currentUserId = UserInfo.getUserId();

        List<CommunicatorParticipant__c> participants = [
            SELECT Id
            FROM CommunicatorParticipant__c
            WHERE Thread__c = :threadId
            AND User__c = :currentUserId
            LIMIT 1
        ];

        if (participants.isEmpty()) {
            insert new CommunicatorParticipant__c(
                Thread__c    = threadId,
                User__c      = currentUserId,
                IsActive__c  = true,
                LastReadAt__c = System.now()
            );
        } else {
            update new CommunicatorParticipant__c(
                Id           = participants[0].Id,
                LastReadAt__c = System.now()
            );
        }
    }

    // ─────────────────────────────────────────
    // Private helpers
    // ─────────────────────────────────────────

    private static void sendCustomNotification(Set<String> recipientIds, String targetPageRef, Id threadId) {
        try {
            CustomNotificationType notificationType = [
                SELECT Id
                FROM CustomNotificationType
                WHERE DeveloperName = :NOTIFICATION_TYPE_NAME
                LIMIT 1
            ];

            Messaging.CustomNotification notification = new Messaging.CustomNotification();
            notification.setTitle('New message in Chat');
            notification.setBody('You have a new message. Click to view.');
            notification.setNotificationTypeId(notificationType.Id);
            notification.setTargetPageRef(targetPageRef);
            notification.send(recipientIds);
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, 'CommunicatorNotificationService.sendCustomNotification error: ' + ex.getMessage());
        }
    }

    private static String buildTargetPageRef(CommunicatorThread__c thread) {
        if (thread == null || String.isBlank(thread.RecordId__c)) return '{}';
        // Navigate to the linked record (generic — works for any SObject)
        return '{"type":"standard__recordPage","attributes":{"recordId":"' + thread.RecordId__c + '","actionName":"view"}}';
    }
}
