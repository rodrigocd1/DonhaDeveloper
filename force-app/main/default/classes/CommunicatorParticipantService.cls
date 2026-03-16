/**
 * @description Service responsible for CommunicatorParticipant__c logic.
 */
public with sharing class CommunicatorParticipantService {

    /**
     * @description Returns all active participants of a thread.
     * @param threadId Thread record Id.
     * @return List of CommunicatorParticipant__c records.
     */
    public static List<CommunicatorParticipant__c> getParticipants(Id threadId) {
        return [
            SELECT Id, Thread__c, User__c, User__r.Name, User__r.SmallPhotoUrl,
                   Role__c, LastReadAt__c, IsActive__c, ExternalId__c
            FROM CommunicatorParticipant__c
            WHERE Thread__c = :threadId
            AND IsActive__c = true
            ORDER BY User__r.Name ASC
        ];
    }

    /**
     * @description Adds a user as participant in a thread if not already present.
     * @param threadId Thread record Id.
     * @param userId   User record Id.
     * @param role     Participant role.
     */
    public static void addParticipant(Id threadId, Id userId, String role) {
        Integer existing = [
            SELECT COUNT()
            FROM CommunicatorParticipant__c
            WHERE Thread__c = :threadId
            AND User__c = :userId
        ];

        if (existing > 0) return;

        insert new CommunicatorParticipant__c(
            Thread__c   = threadId,
            User__c     = userId,
            Role__c     = role,
            IsActive__c = true
        );
    }
}
