/**
 * @description Service responsible for CommunicatorMessage__c business logic.
 */
public with sharing class CommunicatorMessageService {

    private static final Integer DEFAULT_PAGE_SIZE = 20;

    // ─────────────────────────────────────────
    // Queries
    // ─────────────────────────────────────────

    /**
     * @description Returns a paginated list of messages for a thread, ordered oldest-first.
     */
    public static List<CommunicatorMessage__c> getMessages(Id threadId, Integer pageSize, Integer offsetVal) {
        Integer size   = (pageSize  != null && pageSize  > 0) ? pageSize  : DEFAULT_PAGE_SIZE;
        Integer offset = (offsetVal != null && offsetVal > 0) ? offsetVal : 0;

        return [
            SELECT Id, Name, Body__c, Status__c, HasAttachment__c, ContentDocumentId__c,
                   SentAt__c, ExternalId__c,
                   Sender__c, Sender__r.Name, Sender__r.SmallPhotoUrl,
                   Thread__c
            FROM CommunicatorMessage__c
            WHERE Thread__c = :threadId
            ORDER BY SentAt__c ASC
            LIMIT :size
            OFFSET :offset
        ];
    }

    /**
     * @description Returns messages created after a specific timestamp (for polling).
     */
    public static List<CommunicatorMessage__c> getMessagesSince(Id threadId, DateTime sinceDateTime) {
        return [
            SELECT Id, Name, Body__c, Status__c, HasAttachment__c, ContentDocumentId__c,
                   SentAt__c, ExternalId__c,
                   Sender__c, Sender__r.Name, Sender__r.SmallPhotoUrl,
                   Thread__c
            FROM CommunicatorMessage__c
            WHERE Thread__c = :threadId
            AND SentAt__c > :sinceDateTime
            ORDER BY SentAt__c ASC
            LIMIT 50
        ];
    }

    /**
     * @description Returns the total count of messages in a thread.
     */
    public static Integer getMessageCount(Id threadId) {
        return [
            SELECT COUNT()
            FROM CommunicatorMessage__c
            WHERE Thread__c = :threadId
        ];
    }

    // ─────────────────────────────────────────
    // Write operations
    // ─────────────────────────────────────────

    /**
     * @description Creates and persists a new text message.
     */
    public static CommunicatorMessage__c sendMessage(Id threadId, String messageBody) {
        validateThreadAccess(threadId);

        if (String.isBlank(messageBody)) {
            throw new CommunicatorException('Message body cannot be empty.');
        }

        CommunicatorMessage__c msg = buildMessage(threadId, messageBody, false, null);
        insert msg;

        updateThreadLastMessage(threadId);

        CommunicatorNotificationService.notifyParticipants(threadId, msg.Id);

        return queryById(msg.Id);
    }

    /**
     * @description Creates and persists a message with a file attachment.
     */
    public static CommunicatorMessage__c sendMessageWithAttachment(Id threadId, String messageBody, Id contentDocumentId) {
        validateThreadAccess(threadId);

        if (contentDocumentId == null) {
            throw new CommunicatorException('ContentDocument Id is required for attachment messages.');
        }

        CommunicatorMessage__c msg = buildMessage(threadId, messageBody, true, String.valueOf(contentDocumentId));
        insert msg;

        // Note: ContentDocumentLink is already created by lightning-file-upload
        // (record-id prop points to threadId). No need to create it again.
        updateThreadLastMessage(threadId);

        CommunicatorNotificationService.notifyParticipants(threadId, msg.Id);

        return queryById(msg.Id);
    }

    // ─────────────────────────────────────────
    // Private helpers
    // ─────────────────────────────────────────

    private static CommunicatorMessage__c buildMessage(Id threadId, String body, Boolean hasAttachment, String contentDocumentId) {
        return new CommunicatorMessage__c(
            Thread__c           = threadId,
            Body__c             = body,
            Sender__c           = UserInfo.getUserId(),
            SentAt__c           = System.now(),
            Status__c           = 'Sent',
            HasAttachment__c    = hasAttachment,
            ContentDocumentId__c = contentDocumentId
        );
    }

    private static void linkContentDocument(Id contentDocumentId, Id threadId) {
        List<CommunicatorThread__c> threads = [
            SELECT Id, Opportunity__c FROM CommunicatorThread__c WHERE Id = :threadId LIMIT 1
        ];
        if (threads.isEmpty()) return;

        ContentDocumentLink cdl = new ContentDocumentLink(
            ContentDocumentId = contentDocumentId,
            LinkedEntityId    = threadId,
            ShareType         = 'V',
            Visibility        = 'AllUsers'
        );
        insert cdl;
    }

    private static void updateThreadLastMessage(Id threadId) {
        update new CommunicatorThread__c(
            Id              = threadId,
            LastMessageAt__c = System.now()
        );
    }

    private static CommunicatorMessage__c queryById(Id msgId) {
        return [
            SELECT Id, Name, Body__c, Status__c, HasAttachment__c, ContentDocumentId__c,
                   SentAt__c, ExternalId__c,
                   Sender__c, Sender__r.Name, Sender__r.SmallPhotoUrl,
                   Thread__c
            FROM CommunicatorMessage__c
            WHERE Id = :msgId
            LIMIT 1
        ];
    }

    private static void validateThreadAccess(Id threadId) {
        List<CommunicatorThread__c> threads = [
            SELECT Id FROM CommunicatorThread__c WHERE Id = :threadId LIMIT 1
        ];
        if (threads.isEmpty()) {
            throw new CommunicatorException('Thread not found or not accessible.');
        }
    }
}
