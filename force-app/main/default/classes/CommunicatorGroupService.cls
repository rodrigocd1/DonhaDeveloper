/**
 * @description Service responsible for CommunicatorGroup__c and
 *              CommunicatorGroupMember__c business logic.
 *              Any user with the CommunicatorChat permission set can create
 *              and manage groups.
 */
public with sharing class CommunicatorGroupService {
    @TestVisible
    private static Set<Id> traditionalGroupAllowedUserIdsOverrideForTest;

    // ─────────────────────────────────────────
    // Queries
    // ─────────────────────────────────────────

    /**
     * @description Returns all active groups with member count.
     */
    public static List<CommunicatorGroup__c> getActiveGroups() {
        return [
            SELECT Id, Name, Description__c, IsActive__c, Type__c,
                   MemberCount__c, CreatedByUser__c, CreatedByUser__r.Name
            FROM   CommunicatorGroup__c
            WHERE  IsActive__c = true
            AND    (Type__c = null OR Type__c = 'Conventional')
            ORDER BY Name ASC
        ];
    }

    /**
     * @description Searches active groups by name keyword.
     */
    public static List<CommunicatorGroup__c> searchGroups(String keyword) {
        String pattern = '%' + keyword.trim().replace('%','\\%').replace('_','\\_') + '%';
        return [
            SELECT Id, Name, Description__c, MemberCount__c, Type__c
            FROM   CommunicatorGroup__c
            WHERE  IsActive__c = true
            AND    (Type__c = null OR Type__c = 'Conventional')
            AND    Name LIKE :pattern
            ORDER BY Name ASC
            LIMIT  20
        ];
    }

    /**
     * @description Returns all active members of a group with User details.
     */
    public static List<CommunicatorGroupMember__c> getGroupMembers(Id groupId) {
        assertConventionalGroup(groupId);
        return [
            SELECT Id, Group__c, User__c, User__r.Name, User__r.SmallPhotoUrl
            FROM   CommunicatorGroupMember__c
            WHERE  Group__c = :groupId
            ORDER BY User__r.Name ASC
        ];
    }

    /**
     * @description Returns User IDs of all members in a set of groups.
     *              Used to expand group mentions into individual user IDs.
     */
    public static Set<Id> getMemberUserIds(Set<Id> groupIds) {
        List<CommunicatorGroupMember__c> members = [
            SELECT User__c
            FROM   CommunicatorGroupMember__c
            WHERE  Group__c IN :groupIds
            AND    Group__r.IsActive__c = true
            AND    (Group__r.Type__c = null OR Group__r.Type__c = 'Conventional')
        ];
        Set<Id> userIds = new Set<Id>();
        for (CommunicatorGroupMember__c m : members) {
            if (m.User__c != null) userIds.add(m.User__c);
        }
        return userIds;
    }

    /**
     * @description Returns groups the current user belongs to, enriched with stats:
     *              unread mention count (per user) and distinct active opportunity count.
     */
    public static List<CommunicatorDTOs.GroupListItemDTO> getGroupsWithStatsForUser() {
        Id currentUserId = UserInfo.getUserId();

        // 1. Groups where current user is a member
        List<CommunicatorGroupMember__c> memberships = [
            SELECT Group__c, Group__r.Name, Group__r.CreatedByUser__c
            FROM   CommunicatorGroupMember__c
            WHERE  User__c = :currentUserId
            AND    Group__r.IsActive__c = true
            AND    (Group__r.Type__c = null OR Group__r.Type__c = 'Conventional')
            ORDER BY Group__r.Name ASC
        ];
        if (memberships.isEmpty()) return new List<CommunicatorDTOs.GroupListItemDTO>();

        Set<Id> groupIds = new Set<Id>();
        Map<Id, String> groupNames     = new Map<Id, String>();
        Map<Id, Id>     creatorByGroup = new Map<Id, Id>();
        for (CommunicatorGroupMember__c m : memberships) {
            groupIds.add(m.Group__c);
            groupNames.put(m.Group__c, m.Group__r.Name);
            creatorByGroup.put(m.Group__c, m.Group__r.CreatedByUser__c);
        }

        // 2. Messages that mention any of the user's groups
        List<CommunicatorMessage__c> mentionMsgs = [
            SELECT Id, MentionedGroupIds__c, Thread__r.RecordId__c, SentAt__c
            FROM   CommunicatorMessage__c
            WHERE  HasMention__c = true
            ORDER BY SentAt__c DESC
            LIMIT  2000
        ];

        Map<Id, Set<Id>>     msgIdsByGroup      = new Map<Id, Set<Id>>();
        Map<Id, Set<String>> recordsByGroup     = new Map<Id, Set<String>>();
        Map<Id, DateTime>    lastMentionByGroup = new Map<Id, DateTime>();
        for (Id gId : groupIds) {
            msgIdsByGroup.put(gId, new Set<Id>());
            recordsByGroup.put(gId, new Set<String>());
        }

        for (CommunicatorMessage__c msg : mentionMsgs) {
            Set<Id> mentionedGroups = CommunicatorMentionService.deserializeUserIds(msg.MentionedGroupIds__c);
            for (Id gId : mentionedGroups) {
                if (!groupIds.contains(gId)) continue;
                msgIdsByGroup.get(gId).add(msg.Id);
                String recId = msg.Thread__r != null ? msg.Thread__r.RecordId__c : null;
                if (String.isNotBlank(recId)) {
                    recordsByGroup.get(gId).add(recId);
                }
                if (msg.SentAt__c != null) {
                    DateTime ex = lastMentionByGroup.get(gId);
                    if (ex == null || msg.SentAt__c > ex) {
                        lastMentionByGroup.put(gId, msg.SentAt__c);
                    }
                }
            }
        }

        // 3. Unread notifications for current user scoped to those messages
        Set<Id> allMsgIds = new Set<Id>();
        for (Set<Id> ids : msgIdsByGroup.values()) allMsgIds.addAll(ids);

        Map<Id, Integer> unreadByGroup = new Map<Id, Integer>();
        for (Id gId : groupIds) unreadByGroup.put(gId, 0);

        if (!allMsgIds.isEmpty()) {
            List<CommunicatorNotification__c> unreadNotifs = [
                SELECT Message__c
                FROM   CommunicatorNotification__c
                WHERE  Message__c IN :allMsgIds
                AND    Recipient__c = :currentUserId
                AND    IsRead__c = false
            ];
            for (CommunicatorNotification__c n : unreadNotifs) {
                for (Id gId : groupIds) {
                    if (msgIdsByGroup.get(gId).contains(n.Message__c)) {
                        unreadByGroup.put(gId, unreadByGroup.get(gId) + 1);
                    }
                }
            }
        }

        // 4. Build DTOs
        List<CommunicatorDTOs.GroupListItemDTO> result = new List<CommunicatorDTOs.GroupListItemDTO>();
        for (CommunicatorGroupMember__c m : memberships) {
            Id gId = m.Group__c;
            CommunicatorDTOs.GroupListItemDTO dto = new CommunicatorDTOs.GroupListItemDTO();
            dto.groupId                = gId;
            dto.groupName              = groupNames.get(gId);
            Id creator                 = creatorByGroup.get(gId);
            dto.createdByUserId        = creator != null ? String.valueOf(creator) : null;
            dto.unreadMentionCount     = unreadByGroup.get(gId);
            dto.activeOpportunityCount = recordsByGroup.get(gId).size();
            DateTime lm = lastMentionByGroup.get(gId);
            dto.lastMentionAt = lm != null ? JSON.serialize(lm).replace('"', '') : null;
            result.add(dto);
        }
        return result;
    }

    /**
     * @description Returns members of a group as lightweight DTOs.
     */
    public static List<CommunicatorDTOs.GroupMemberDTO> getGroupMembersAsDTOs(Id groupId) {
        List<CommunicatorDTOs.GroupMemberDTO> result = new List<CommunicatorDTOs.GroupMemberDTO>();
        for (CommunicatorGroupMember__c m : getGroupMembers(groupId)) {
            CommunicatorDTOs.GroupMemberDTO dto = new CommunicatorDTOs.GroupMemberDTO();
            dto.memberId = String.valueOf(m.Id);
            dto.userId   = String.valueOf(m.User__c);
            dto.userName = m.User__r != null ? m.User__r.Name : '';
            result.add(dto);
        }
        return result;
    }

    /**
     * @description Persists group name changes and bulk-removes the given members.
     */
    public static void saveGroupDetails(
        Id groupId,
        String newName,
        List<Id> memberIdsToRemove,
        List<Id> userIdsToAdd
    ) {
        assertConventionalGroup(groupId);
        if (String.isNotBlank(newName)) {
            update new CommunicatorGroup__c(Id = groupId, Name = newName.trim());
        }
        if (memberIdsToRemove != null && !memberIdsToRemove.isEmpty()) {
            List<CommunicatorGroupMember__c> toDelete = [
                SELECT Id, User__c FROM CommunicatorGroupMember__c
                WHERE  Id IN :memberIdsToRemove
                AND    Group__c = :groupId
            ];
            if (!toDelete.isEmpty()) {
                Set<Id> removedUserIds = new Set<Id>();
                for (CommunicatorGroupMember__c m : toDelete) {
                    if (m.User__c != null) removedUserIds.add(m.User__c);
                }
                delete toDelete;
                CommunicatorGroupSharingService.removeManualReadShares(groupId, removedUserIds);
                updateMemberCount(groupId);
                deactivateParticipantsInGroupRelatedThreads(groupId, removedUserIds);
            }
        }
        if (userIdsToAdd != null && !userIdsToAdd.isEmpty()) {
            addMembers(groupId, new Set<Id>(userIdsToAdd));
        }
    }

    /**
     * @description Searches for active users eligible for traditional groups
     *              under the current role hierarchy rule. Returns an empty list
     *              if the current user has no role or if keyword is shorter than
     *              3 characters.
     */
    public static List<CommunicatorDTOs.UserResultDTO> searchSubordinateUsers(String keyword) {
        if (String.isBlank(keyword) || keyword.trim().length() < 3) {
            return new List<CommunicatorDTOs.UserResultDTO>();
        }

        Set<Id> eligibleRoleIds = getTraditionalGroupEligibleRoleIdsForCurrentUser();
        if (eligibleRoleIds.isEmpty()) return new List<CommunicatorDTOs.UserResultDTO>();

        String likeTerm = '%' + keyword.trim().replaceAll('\\s+', '%') + '%';

        List<CommunicatorDTOs.UserResultDTO> result = new List<CommunicatorDTOs.UserResultDTO>();
        for (User u : [
            SELECT Id, Name
            FROM   User
            WHERE  IsActive = true
            AND    UserRoleId IN :eligibleRoleIds
            AND    Name LIKE :likeTerm
            AND    Id != :UserInfo.getUserId()
            ORDER BY Name
            LIMIT 20
        ]) {
            CommunicatorDTOs.UserResultDTO dto = new CommunicatorDTOs.UserResultDTO();
            dto.id   = u.Id;
            dto.name = u.Name;
            result.add(dto);
        }
        return result;
    }

    public static void assertTraditionalGroupUsersCanBeAdded(Set<Id> userIds) {
        if (userIds == null || userIds.isEmpty()) {
            return;
        }

        Set<Id> requestedUserIds = new Set<Id>(userIds);
        requestedUserIds.remove(null);
        if (requestedUserIds.isEmpty()) {
            return;
        }

        Set<Id> eligibleUserIds = getTraditionalGroupEligibleUserIds(requestedUserIds);
        if (eligibleUserIds.size() != requestedUserIds.size()) {
            throw new CommunicatorException('One or more selected users cannot be added to this group.');
        }
    }

    // ─────────────────────────────────────────
    // Write operations
    // ─────────────────────────────────────────

    /**
     * @description Creates a new group and optionally adds the creator as first member.
     */
    public static CommunicatorGroup__c createGroup(String name, String description) {
        if (String.isBlank(name)) {
            throw new CommunicatorException('Group name cannot be blank.');
        }
        CommunicatorGroup__c grp = new CommunicatorGroup__c(
            Name            = name.trim(),
            Description__c  = description,
            IsActive__c     = true,
            Type__c         = 'Conventional',
            CreatedByUser__c = UserInfo.getUserId(),
            MemberCount__c  = 0
        );
        insert grp;
        // Add creator as first member.
        // Do not create explicit share for the creator here, because owner access is implicit
        // and sharing to self may fail in some org security configurations.
        insert new CommunicatorGroupMember__c(
            Group__c = grp.Id,
            User__c  = UserInfo.getUserId()
        );
        updateMemberCount(grp.Id);
        return grp;
    }

    /**
     * @description Adds a user to a group. Silently skips if already a member.
     */
    public static void addMember(Id groupId, Id userId) {
        assertConventionalGroup(groupId);
        Integer existing = [
            SELECT COUNT() FROM CommunicatorGroupMember__c
            WHERE Group__c = :groupId AND User__c = :userId
        ];
        if (existing > 0) return;

        insert new CommunicatorGroupMember__c(
            Group__c = groupId,
            User__c  = userId
        );
        CommunicatorGroupSharingService.ensureManualReadShares(groupId, new Set<Id>{ userId });
        updateMemberCount(groupId);
    }

    /**
     * @description Bulk-adds a set of users to a group, skipping any that are
     *              already members. Updates MemberCount__c once after the insert.
     */
    public static void addMembers(Id groupId, Set<Id> userIds) {
        if (userIds == null || userIds.isEmpty()) return;
        assertConventionalGroup(groupId);

        List<CommunicatorGroupMember__c> existing = [
            SELECT User__c
            FROM   CommunicatorGroupMember__c
            WHERE  Group__c = :groupId
            AND    User__c IN :userIds
        ];
        Set<Id> alreadyIn = new Set<Id>();
        for (CommunicatorGroupMember__c m : existing) alreadyIn.add(m.User__c);

        List<CommunicatorGroupMember__c> toInsert = new List<CommunicatorGroupMember__c>();
        Set<Id> insertedUserIds = new Set<Id>();
        for (Id uid : userIds) {
            if (!alreadyIn.contains(uid)) {
                toInsert.add(new CommunicatorGroupMember__c(Group__c = groupId, User__c = uid));
                insertedUserIds.add(uid);
            }
        }
        if (!toInsert.isEmpty()) {
            insert toInsert;
            CommunicatorGroupSharingService.ensureManualReadShares(groupId, insertedUserIds);
            updateMemberCount(groupId);
        }
    }

    /**
     * @description Removes a user from a group.
     */
    public static void removeMember(Id groupId, Id userId) {
        assertConventionalGroup(groupId);
        List<CommunicatorGroupMember__c> members = [
            SELECT Id FROM CommunicatorGroupMember__c
            WHERE Group__c = :groupId AND User__c = :userId
        ];
        if (!members.isEmpty()) {
            delete members;
            CommunicatorGroupSharingService.removeManualReadShares(groupId, new Set<Id>{ userId });
            updateMemberCount(groupId);
            deactivateParticipantsInGroupRelatedThreads(groupId, new Set<Id>{ userId });
        }
    }

    /**
     * @description Deactivates a group (soft delete).
     */
    public static void deactivateGroup(Id groupId) {
        assertConventionalGroup(groupId);
        update new CommunicatorGroup__c(Id = groupId, IsActive__c = false);
    }

    /**
     * @description Permanently deletes the group and all member rows.
     *              Only the group admin (CreatedByUser__c) can execute this action.
     */
    public static void deleteGroupAndMembers(Id groupId) {
        if (groupId == null) {
            throw new CommunicatorException('Group Id is required.');
        }
        assertConventionalGroup(groupId);

        CommunicatorGroup__c grp = [
            SELECT Id, CreatedByUser__c
            FROM   CommunicatorGroup__c
            WHERE  Id = :groupId
            LIMIT  1
        ];

        if (grp.CreatedByUser__c != UserInfo.getUserId()) {
            throw new CommunicatorException('Only the group admin can delete this group.');
        }

        List<CommunicatorGroupMember__c> members = [
            SELECT Id
            FROM   CommunicatorGroupMember__c
            WHERE  Group__c = :groupId
        ];
        if (!members.isEmpty()) {
            delete members;
        }

        delete grp;
    }

    // ─────────────────────────────────────────
    // Private helpers
    // ─────────────────────────────────────────

    /**
     * @description Returns all role IDs that are descendants of rootRoleId in the
     *              role hierarchy, using a single SOQL query + in-memory BFS.
     */
    private static Set<Id> getSubordinateRoleIds(Id rootRoleId) {
        Map<Id, Set<Id>> rolesByRoot =
            CommunicatorRoleHierarchyService.getRoleAndDescendantIdsByRoot(new Set<Id>{ rootRoleId });
        Set<Id> result = new Set<Id>();
        if (rolesByRoot.containsKey(rootRoleId)) result.addAll(rolesByRoot.get(rootRoleId));
        return excludeRootRole(rootRoleId, result);
    }

    private static Set<Id> getTraditionalGroupEligibleRoleIdsForCurrentUser() {
        User me = [SELECT UserRoleId FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
        if (me.UserRoleId == null) {
            return new Set<Id>();
        }
        return CommunicatorRoleHierarchyService.getTraditionalGroupEligibleRoleIds(me.UserRoleId);
    }

    private static Set<Id> getTraditionalGroupEligibleUserIds(Set<Id> requestedUserIds) {
        Set<Id> sanitizedRequestedUserIds = new Set<Id>();
        if (requestedUserIds != null) {
            sanitizedRequestedUserIds.addAll(requestedUserIds);
        }
        sanitizedRequestedUserIds.remove(null);
        if (sanitizedRequestedUserIds.isEmpty()) {
            return new Set<Id>();
        }

        Id currentUserId = UserInfo.getUserId();
        if (Test.isRunningTest() && traditionalGroupAllowedUserIdsOverrideForTest != null) {
            Set<Id> overriddenResult = new Set<Id>(sanitizedRequestedUserIds);
            overriddenResult.remove(currentUserId);
            overriddenResult.retainAll(traditionalGroupAllowedUserIdsOverrideForTest);
            return overriddenResult;
        }

        Set<Id> eligibleRoleIds = getTraditionalGroupEligibleRoleIdsForCurrentUser();
        if (eligibleRoleIds.isEmpty()) {
            return new Set<Id>();
        }

        List<User> candidateUsers = [
            SELECT Id, IsActive, UserRoleId
            FROM User
            WHERE Id IN :sanitizedRequestedUserIds
        ];
        return resolveTraditionalGroupEligibleUserIds(
            sanitizedRequestedUserIds,
            currentUserId,
            eligibleRoleIds,
            candidateUsers
        );
    }

    @TestVisible
    private static Set<Id> resolveTraditionalGroupEligibleUserIds(
        Set<Id> requestedUserIds,
        Id currentUserId,
        Set<Id> eligibleRoleIds,
        List<User> candidateUsers
    ) {
        Set<Id> sanitizedRequestedUserIds = new Set<Id>();
        if (requestedUserIds != null) {
            sanitizedRequestedUserIds.addAll(requestedUserIds);
        }
        sanitizedRequestedUserIds.remove(null);
        if (sanitizedRequestedUserIds.isEmpty() || eligibleRoleIds == null || eligibleRoleIds.isEmpty()) {
            return new Set<Id>();
        }

        Set<Id> result = new Set<Id>();
        for (User candidateUser : candidateUsers) {
            if (candidateUser == null || candidateUser.Id == null) {
                continue;
            }
            if (!sanitizedRequestedUserIds.contains(candidateUser.Id)) {
                continue;
            }
            if (candidateUser.Id == currentUserId) {
                continue;
            }
            if (candidateUser.IsActive != true) {
                continue;
            }
            if (candidateUser.UserRoleId == null || !eligibleRoleIds.contains(candidateUser.UserRoleId)) {
                continue;
            }
            result.add(candidateUser.Id);
        }
        return result;
    }

    @TestVisible
    private static Set<Id> excludeRootRole(Id rootRoleId, Set<Id> resolvedRoleIds) {
        Set<Id> result = new Set<Id>();
        if (resolvedRoleIds != null) result.addAll(resolvedRoleIds);
        result.remove(rootRoleId);
        return result;
    }

    private static void assertConventionalGroup(Id groupId) {
        if (groupId == null) throw new CommunicatorException('Group Id is required.');
        List<CommunicatorGroup__c> groups = [
            SELECT Id, Type__c
            FROM CommunicatorGroup__c
            WHERE Id = :groupId
            LIMIT 1
        ];
        if (groups.isEmpty() || groups[0].Type__c == 'Broadcast') {
            throw new CommunicatorException('Broadcast groups are not supported by conventional group operations.');
        }
    }

    private static void updateMemberCount(Id groupId) {
        Integer count = [
            SELECT COUNT() FROM CommunicatorGroupMember__c
            WHERE Group__c = :groupId
        ];
        update new CommunicatorGroup__c(Id = groupId, MemberCount__c = count);
    }

    /**
     * @description Deactivates CommunicatorParticipant__c records for the given users
     *              in all threads related to the group (group thread + opp threads where
     *              the group was mentioned). Called when members are removed from the group
     *              so they stop receiving notifications for those conversations.
     */
    private static void deactivateParticipantsInGroupRelatedThreads(Id groupId, Set<Id> removedUserIds) {
        if (removedUserIds == null || removedUserIds.isEmpty()) return;

        Set<Id> relatedThreadIds = new Set<Id>();

        // Group thread
        for (CommunicatorThread__c t : [
            SELECT Id FROM CommunicatorThread__c
            WHERE RecordId__c = :String.valueOf(groupId)
            AND   RecordType__c = 'CommunicatorGroup__c'
            LIMIT 1
        ]) {
            relatedThreadIds.add(t.Id);
        }

        // Opportunity threads where this group was mentioned
        for (CommunicatorMessage__c msg : [
            SELECT Thread__c, MentionedGroupIds__c
            FROM   CommunicatorMessage__c
            WHERE  HasMention__c = true
            LIMIT  2000
        ]) {
            if (String.isBlank(msg.MentionedGroupIds__c) || msg.Thread__c == null) continue;
            Set<Id> mentionedGroups = CommunicatorMentionService.deserializeUserIds(msg.MentionedGroupIds__c);
            if (mentionedGroups.contains(groupId)) {
                relatedThreadIds.add(msg.Thread__c);
            }
        }

        if (relatedThreadIds.isEmpty()) return;

        List<CommunicatorParticipant__c> toDeactivate = [
            SELECT Id FROM CommunicatorParticipant__c
            WHERE  Thread__c IN :relatedThreadIds
            AND    User__c   IN :removedUserIds
            AND    IsActive__c = true
        ];
        if (toDeactivate.isEmpty()) return;

        for (CommunicatorParticipant__c p : toDeactivate) {
            p.IsActive__c = false;
        }
        update toDeactivate;
    }

}