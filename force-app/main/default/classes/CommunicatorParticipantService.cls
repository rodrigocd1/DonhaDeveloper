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
        List<CommunicatorParticipant__c> existingParticipants = [
            SELECT Id, IsActive__c, Role__c
            FROM CommunicatorParticipant__c
            WHERE Thread__c = :threadId
            AND User__c = :userId
            LIMIT 1
        ];

        if (!existingParticipants.isEmpty()) {
            CommunicatorParticipant__c existingParticipant = existingParticipants[0];
            if (existingParticipant.IsActive__c == true) return;

            existingParticipant.IsActive__c = true;
            if (String.isBlank(existingParticipant.Role__c) && String.isNotBlank(role)) {
                existingParticipant.Role__c = role;
            }
            update existingParticipant;
            return;
        }

        insert new CommunicatorParticipant__c(
            Thread__c   = threadId,
            User__c     = userId,
            Role__c     = role,
            IsActive__c = true
        );
    }

    /**
     * @description Ensures all given users are participants in the thread.
     *              Inserts only those not already present (active or inactive).
     * @param threadId Thread record Id.
     * @param userIds  Set of User Ids to ensure.
     * @param role     Role to assign to newly added participants.
     */
    public static void ensureParticipants(Id threadId, Set<Id> userIds, String role) {
        if (userIds == null || userIds.isEmpty()) return;

        Map<Id, CommunicatorParticipant__c> participantByUserId = new Map<Id, CommunicatorParticipant__c>();
        for (CommunicatorParticipant__c p : [
            SELECT Id, User__c, IsActive__c, Role__c
            FROM CommunicatorParticipant__c
            WHERE Thread__c = :threadId
            AND User__c IN :userIds
        ]) {
            participantByUserId.put(p.User__c, p);
        }

        List<CommunicatorParticipant__c> toInsert = new List<CommunicatorParticipant__c>();
        List<CommunicatorParticipant__c> toUpdate = new List<CommunicatorParticipant__c>();
        for (Id uid : userIds) {
            CommunicatorParticipant__c existingParticipant = participantByUserId.get(uid);
            if (existingParticipant == null) {
                toInsert.add(new CommunicatorParticipant__c(
                    Thread__c   = threadId,
                    User__c     = uid,
                    Role__c     = role,
                    IsActive__c = true
                ));
                continue;
            }

            if (existingParticipant.IsActive__c != true) {
                existingParticipant.IsActive__c = true;
                if (String.isBlank(existingParticipant.Role__c) && String.isNotBlank(role)) {
                    existingParticipant.Role__c = role;
                }
                toUpdate.add(existingParticipant);
            }
        }

        if (!toUpdate.isEmpty()) update toUpdate;
        if (!toInsert.isEmpty()) insert toInsert;
    }
}