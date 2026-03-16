/**
 * @description Service responsible for CommunicatorThread__c business logic.
 *              Thread is generic — it can be linked to any SObject via RecordId__c.
 */
public with sharing class CommunicatorThreadService {

    /**
     * @description Returns the existing active thread for a given record Id,
     *              or creates a new one if none exists.
     * @param recordId   Id of any SObject record (Opportunity, Account, Case, etc.)
     * @param objectType API name of the SObject (e.g. 'Opportunity'). Used for reference only.
     * @return CommunicatorThread__c record.
     */
    public static CommunicatorThread__c getOrCreateThread(String recordId, String objectType) {
        validateRecordAccess(recordId);

        List<CommunicatorThread__c> threads = [
            SELECT Id, Name, RecordId__c, RecordType__c, Status__c, Stage__c,
                   SubStatus__c, Reason__c, ExternalId__c,
                   LastMessageAt__c, UnreadCount__c
            FROM CommunicatorThread__c
            WHERE RecordId__c = :recordId
            AND   Status__c  != 'Archived'
            LIMIT 1
        ];

        if (!threads.isEmpty()) {
            return threads[0];
        }

        return createThread(recordId, objectType);
    }

    // ─────────────────────────────────────────
    // Private helpers
    // ─────────────────────────────────────────

    private static CommunicatorThread__c createThread(String recordId, String objectType) {
        CommunicatorThread__c thread = new CommunicatorThread__c(
            RecordId__c   = recordId,
            RecordType__c = objectType,
            Status__c     = 'Active'
        );
        insert thread;

        ensureCurrentUserIsParticipant(thread.Id);
        return thread;
    }

    private static void ensureCurrentUserIsParticipant(Id threadId) {
        Id currentUserId = UserInfo.getUserId();

        Integer existing = [
            SELECT COUNT()
            FROM CommunicatorParticipant__c
            WHERE Thread__c = :threadId
            AND   User__c   = :currentUserId
        ];

        if (existing == 0) {
            insert new CommunicatorParticipant__c(
                Thread__c   = threadId,
                User__c     = currentUserId,
                IsActive__c = true
            );
        }
    }

    /**
     * @description Validates that the given record Id is accessible to the current user.
     *              Uses a generic SOQL approach via Schema to avoid hardcoding object types.
     */
    private static void validateRecordAccess(String recordId) {
        if (String.isBlank(recordId)) {
            throw new CommunicatorException('Record ID cannot be blank.');
        }

        // Extract SObject type from the Id prefix
        try {
            Id sfId = (Id) recordId;
            Schema.SObjectType sObjectType = sfId.getSObjectType();
            String objectName = sObjectType.getDescribe().getName();

            // Dynamic SOQL to check read access without hardcoding the object
            Integer count = Database.countQuery(
                'SELECT COUNT() FROM ' + objectName + ' WHERE Id = :sfId'
            );
            if (count == 0) {
                throw new CommunicatorException('Record not found or not accessible.');
            }
        } catch (CommunicatorException ce) {
            throw ce;
        } catch (Exception ex) {
            throw new CommunicatorException('Invalid Record ID: ' + ex.getMessage());
        }
    }
}
