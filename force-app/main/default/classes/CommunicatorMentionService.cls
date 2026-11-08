/**
 * @description Service responsible for resolving @mentions in messages.
 *              Expands group mentions into individual user IDs and returns
 *              the full set of users to be notified.
 */
public with sharing class CommunicatorMentionService {

    /**
     * @description Resolves a list of mention IDs (User IDs and/or Group IDs)
     *              into a flat set of User IDs to notify.
     *
     * @param mentionIds  Set of Ids — can be a mix of User and Group IDs.
     * @return            Set of User IDs with duplicates removed.
     */
    public static Set<Id> resolveUserIds(Set<Id> mentionIds) {
        if (mentionIds == null || mentionIds.isEmpty()) return new Set<Id>();

        Set<Id> userIds  = new Set<Id>();
        Set<Id> groupIds = extractGroupIds(mentionIds);

        for (Id mid : mentionIds) {
            Schema.SObjectType sType = mid.getSObjectType();
            String objName = sType.getDescribe().getName();
            if (objName == 'User') {
                userIds.add(mid);
            }
        }

        // Expand groups into member user IDs
        if (!groupIds.isEmpty()) {
            userIds.addAll(CommunicatorGroupService.getMemberUserIds(groupIds));
        }

        // Remove sender from mentions
        userIds.remove(UserInfo.getUserId());

        return userIds;
    }

    /**
     * @description Extracts only CommunicatorGroup__c IDs from a mixed set of mention IDs.
     *              Used by CommunicatorMessageService to store original group IDs on the message.
     */
    public static Set<Id> extractGroupIds(Set<Id> mentionIds) {
        Set<Id> candidateGroupIds = new Set<Id>();
        if (mentionIds == null || mentionIds.isEmpty()) return candidateGroupIds;
        for (Id mid : mentionIds) {
            if (mid.getSObjectType().getDescribe().getName() == 'CommunicatorGroup__c') {
                candidateGroupIds.add(mid);
            }
        }
        if (candidateGroupIds.isEmpty()) return candidateGroupIds;

        Set<Id> conventionalGroupIds = new Set<Id>();
        for (CommunicatorGroup__c groupRecord : [
            SELECT Id
            FROM CommunicatorGroup__c
            WHERE Id IN :candidateGroupIds
            AND IsActive__c = true
            AND (Type__c = null OR Type__c = 'Conventional')
        ]) {
            conventionalGroupIds.add(groupRecord.Id);
        }
        return conventionalGroupIds;
    }

    /**
     * @description Serializes a set of user IDs as semicolon-separated string
     *              for storage in MentionedUserIds__c.
     */
    public static String serializeUserIds(Set<Id> userIds) {
        if (userIds == null || userIds.isEmpty()) return null;
        List<String> parts = new List<String>();
        for (Id uid : userIds) parts.add(String.valueOf(uid));
        return String.join(parts, ';');
    }

    /**
     * @description Deserializes MentionedUserIds__c back into a Set<Id>.
     */
    public static Set<Id> deserializeUserIds(String serialized) {
        Set<Id> result = new Set<Id>();
        if (String.isBlank(serialized)) return result;
        for (String part : serialized.split(';')) {
            String trimmed = part.trim();
            if (String.isNotBlank(trimmed)) {
                try { result.add((Id) trimmed); } catch (Exception e) { /* skip invalid */ }
            }
        }
        return result;
    }

    /**
     * @description Returns mention candidates for the picker:
     *              all active users + all active groups.
     *              Filters by keyword if provided.
     */
    public static List<CommunicatorDTOs.MentionCandidateDTO> getMentionCandidates(
        Id threadId, String keyword
    ) {
        List<CommunicatorDTOs.MentionCandidateDTO> results = new List<CommunicatorDTOs.MentionCandidateDTO>();
        String kw = String.isBlank(keyword) ? '' : keyword.trim().toLowerCase();

        // All active users (excluding current user)
        List<User> users = String.isBlank(kw)
            ? [SELECT Id, Name, SmallPhotoUrl FROM User WHERE IsActive = true AND Id != :UserInfo.getUserId() ORDER BY Name ASC LIMIT 50]
            : [SELECT Id, Name, SmallPhotoUrl FROM User WHERE IsActive = true AND Id != :UserInfo.getUserId() AND Name LIKE :('%' + kw + '%') ORDER BY Name ASC LIMIT 20];

        for (User u : users) {
            CommunicatorDTOs.MentionCandidateDTO dto = new CommunicatorDTOs.MentionCandidateDTO();
            dto.id            = u.Id;
            dto.name          = u.Name;
            dto.photoUrl      = u.SmallPhotoUrl;
            dto.candidateType = 'User';
            dto.memberCount   = null;
            results.add(dto);
        }

        // Active groups
        List<CommunicatorGroup__c> groups = String.isBlank(kw)
            ? CommunicatorGroupMentionQueryService.getActiveGroupsForMention()
            : CommunicatorGroupMentionQueryService.searchGroupsForMention(kw);

        for (CommunicatorGroup__c g : groups) {
            CommunicatorDTOs.MentionCandidateDTO dto = new CommunicatorDTOs.MentionCandidateDTO();
            dto.id            = g.Id;
            dto.name          = g.Name;
            dto.photoUrl      = null;
            dto.candidateType = 'Group';
            dto.memberCount   = (Integer) g.MemberCount__c;
            results.add(dto);
        }

        return results;
    }

    /**
     * @description Resolves a map of User Id to User Name for mention rendering in chat history.
     */
    public static Map<String, String> getUserNamesByIds(List<Id> userIds) {
        Map<String, String> result = new Map<String, String>();
        if (userIds == null || userIds.isEmpty()) return result;

        Set<Id> uniqueIds = new Set<Id>();
        for (Id userId : userIds) {
            if (userId != null) uniqueIds.add(userId);
        }
        if (uniqueIds.isEmpty()) return result;

        for (User u : [
            SELECT Id, Name
            FROM User
            WHERE Id IN :uniqueIds
        ]) {
            result.put(String.valueOf(u.Id), u.Name);
        }
        return result;
    }
}