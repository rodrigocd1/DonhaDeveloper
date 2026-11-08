/**
 * @description Isolated sharing DML for CommunicatorGroup__c.
 *              Runs without sharing to avoid user-level record visibility
 *              blocking share maintenance flows.
 */
public without sharing class CommunicatorGroupSharingService {

    public static void ensureManualReadShares(Id groupId, Set<Id> userIds) {
        if (groupId == null || userIds == null || userIds.isEmpty()) return;

        // Sharing for the running user is unnecessary (owner/implicit access)
        // and can fail in some org setups, so we skip it defensively.
        Set<Id> targetUserIds = new Set<Id>(userIds);
        targetUserIds.remove(UserInfo.getUserId());
        if (targetUserIds.isEmpty()) return;

        Set<Id> existingShares = new Set<Id>();
        for (CommunicatorGroup__Share sh : [
            SELECT UserOrGroupId
            FROM   CommunicatorGroup__Share
            WHERE  ParentId = :groupId
            AND    UserOrGroupId IN :targetUserIds
            AND    RowCause = 'Manual'
        ]) {
            existingShares.add(sh.UserOrGroupId);
        }

        List<CommunicatorGroup__Share> toInsert = new List<CommunicatorGroup__Share>();
        for (Id userId : targetUserIds) {
            if (existingShares.contains(userId)) continue;
            CommunicatorGroup__Share sh = new CommunicatorGroup__Share();
            sh.ParentId      = groupId;
            sh.UserOrGroupId = userId;
            sh.AccessLevel   = 'Read';
            sh.RowCause      = Schema.CommunicatorGroup__Share.RowCause.Manual;
            toInsert.add(sh);
        }
        if (!toInsert.isEmpty()) {
            insert toInsert;
        }
    }

    public static void removeManualReadShares(Id groupId, Set<Id> userIds) {
        if (groupId == null || userIds == null || userIds.isEmpty()) return;

        List<CommunicatorGroup__Share> toDelete = [
            SELECT Id
            FROM   CommunicatorGroup__Share
            WHERE  ParentId = :groupId
            AND    UserOrGroupId IN :userIds
            AND    RowCause = 'Manual'
        ];
        if (!toDelete.isEmpty()) {
            delete toDelete;
        }
    }
}