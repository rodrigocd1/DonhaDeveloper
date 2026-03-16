/**
 * @description Service responsible for CommunicatorThread__c business logic.
 */
public with sharing class CommunicatorThreadService {

    /**
     * @description Returns the existing thread for an Opportunity, or creates one if none exists.
     * @param opportunityId The Opportunity record Id.
     * @return CommunicatorThread__c record.
     */
    public static CommunicatorThread__c getOrCreateThread(Id opportunityId) {
        validateOpportunityAccess(opportunityId);

        List<CommunicatorThread__c> threads = [
            SELECT Id, Name, Opportunity__c, Status__c, Stage__c, SubStatus__c,
                   Reason__c, ExternalId__c, LastMessageAt__c, UnreadCount__c
            FROM CommunicatorThread__c
            WHERE Opportunity__c = :opportunityId
            AND Status__c != 'Archived'
            LIMIT 1
        ];

        if (!threads.isEmpty()) {
            return threads[0];
        }

        return createThread(opportunityId);
    }

    // ─────────────────────────────────────────
    // Private helpers
    // ─────────────────────────────────────────

    private static CommunicatorThread__c createThread(Id opportunityId) {
        CommunicatorThread__c thread = new CommunicatorThread__c(
            Opportunity__c = opportunityId,
            Status__c = 'Active'
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
            AND User__c = :currentUserId
        ];

        if (existing == 0) {
            CommunicatorParticipant__c participant = new CommunicatorParticipant__c(
                Thread__c = threadId,
                User__c = currentUserId,
                IsActive__c = true
            );
            insert participant;
        }
    }

    private static void validateOpportunityAccess(Id opportunityId) {
        List<Opportunity> opps = [
            SELECT Id FROM Opportunity WHERE Id = :opportunityId LIMIT 1
        ];
        if (opps.isEmpty()) {
            throw new CommunicatorException('Opportunity not found or not accessible.');
        }
    }
}
