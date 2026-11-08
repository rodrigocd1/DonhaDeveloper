public without sharing class CommunicatorExternalApiAccessService {

    private static final String THREAD_RECORD_TYPE_GROUP = 'CommunicatorGroup__c';
    private static final String GROUP_TYPE_BROADCAST = 'Broadcast';
    @TestVisible private static Set<Id> testBroadcastGroupIds;
    private static Map<Id, CommunicatorExternalApiDTOs.UserContextDTO> userContextCache =
        new Map<Id, CommunicatorExternalApiDTOs.UserContextDTO>();
    private static Map<Id, Set<Id>> readableRecordIdsByUser = new Map<Id, Set<Id>>();
    private static Map<Id, Set<Id>> permissionSetIdsByUser = new Map<Id, Set<Id>>();

    public static CommunicatorExternalApiDTOs.UserContextDTO requireUserContext(String rawUserId) {
        Id userId = parseUserId(rawUserId);
        if (userContextCache.containsKey(userId)) {
            return userContextCache.get(userId);
        }
        List<User> users = [
            SELECT Id, Name, IsActive, UserType, UserRoleId, TimeZoneSidKey, Profile.UserLicense.Name
            FROM User
            WHERE Id = :userId
            LIMIT 1
        ];
        if (users.isEmpty()) {
            throw CommunicatorExternalApiErrorService.notFound(
                'USER_NOT_FOUND',
                'Usuario informado nao encontrado.'
            );
        }

        User userRecord = users[0];
        if (userRecord.IsActive != true) {
            throw CommunicatorExternalApiErrorService.forbidden(
                'USER_INACTIVE',
                'Usuario informado esta inativo.'
            );
        }

        CommunicatorExternalApiDTOs.UserContextDTO context =
            new CommunicatorExternalApiDTOs.UserContextDTO();
        context.userId = userRecord.Id;
        context.userName = userRecord.Name;
        context.isActive = userRecord.IsActive;
        context.userType = userRecord.UserType;
        context.userRoleId = userRecord.UserRoleId;
        context.timezoneSidKey = userRecord.TimeZoneSidKey;
        context.licenseName = userRecord.Profile != null && userRecord.Profile.UserLicense != null
            ? userRecord.Profile.UserLicense.Name
            : null;
        context.isSalesforcePlatform = context.userType == 'Standard' &&
            context.licenseName == 'Salesforce Platform';
        context.isCoreSalesforce = context.userType == 'Standard' &&
            context.licenseName == 'Salesforce';
        context.isPartnerCommunity = context.userType == 'PowerPartner';
        context.queueIds = getQueueIdsForUser(userRecord.Id, userRecord.UserRoleId);
        context.assessoriaIds = CommunicatorRepasseService.getAssessoriaIdsByQueueIds(context.queueIds);
        context.conventionalGroupIds = getConventionalGroupIdsForUser(userRecord.Id);
        context.broadcastGroupIds = getAccessibleBroadcastGroupIds(userRecord.Id);
        context.participantThreadIds = getParticipantThreadIds(userRecord.Id);
        context.participantOpportunityIds = getParticipantOpportunityIds(context.participantThreadIds);
        context.accessibleOpportunityIds.addAll(context.participantOpportunityIds);
        context.accessibleOpportunityIds.addAll(getOwnedOpportunityIds(userRecord.Id));
        context.accessibleOpportunityIds.addAll(getHierarchyOpportunityIds(userRecord.Id, userRecord.UserRoleId));
        context.accessibleOpportunityIds.addAll(getAccessibleOpportunityIdsByAssessoria(context.assessoriaIds));
        context.accessibleOpportunityIds.retainAll(filterReadableRecordIds(userRecord.Id, context.accessibleOpportunityIds));
        context.accessibleThreadIds.addAll(context.participantThreadIds);
        context.accessibleThreadIds.addAll(getGroupThreadIds(context.conventionalGroupIds, context.broadcastGroupIds));
        context.accessibleThreadIds.addAll(getMentionAccessibleThreadIds(userRecord.Id, context.conventionalGroupIds));
        context.accessibleThreadIds.addAll(getOpportunityThreadIds(context.accessibleOpportunityIds));
        context.accessibleThreadIds.addAll(getReadableOpportunityThreadIds(userRecord.Id, context.accessibleOpportunityIds));
        userContextCache.put(userId, context);
        return context;
    }

    public static void clearCachedUserContext(Id userId) {
        if (userId != null) {
            userContextCache.remove(userId);
            readableRecordIdsByUser.remove(userId);
            permissionSetIdsByUser.remove(userId);
        }
    }

    public static String normalizeRecordId(String recordId) {
        return CommunicatorThreadService.resolveOpportunityIdIfRepasse(recordId);
    }

    public static void assertThreadAccess(CommunicatorExternalApiDTOs.UserContextDTO context, Id threadId) {
        if (!canAccessThread(context, threadId)) {
            throw CommunicatorExternalApiErrorService.forbidden(
                'THREAD_ACCESS_DENIED',
                'Usuario informado nao possui acesso a esta thread.'
            );
        }
    }

    public static void assertRecordAccess(CommunicatorExternalApiDTOs.UserContextDTO context, String recordId) {
        if (!canAccessRecord(context, recordId)) {
            throw CommunicatorExternalApiErrorService.forbidden(
                'RECORD_ACCESS_DENIED',
                'Usuario informado nao possui acesso a este registro.'
            );
        }
    }

    public static Boolean canAccessRecord(
        CommunicatorExternalApiDTOs.UserContextDTO context,
        String recordId
    ) {
        if (context == null || String.isBlank(recordId)) return false;
        String normalizedRecordId = normalizeRecordId(recordId);
        try {
            Id typedRecordId = (Id) normalizedRecordId;
            String objectApiName = typedRecordId.getSObjectType().getDescribe().getName();
            if (objectApiName == 'Opportunity') {
                return canReadRecord(context.userId, typedRecordId);
            }
            if (objectApiName == 'Repasse__c') {
                Map<Id, Repasse__c> repassesById =
                    CommunicatorRepasseService.getRepassesByIds(new Set<Id>{ typedRecordId });
                Repasse__c repasse = repassesById.get(typedRecordId);
                if (repasse == null) return false;
                if (repasse.Oportunidade__c != null &&
                    context.accessibleOpportunityIds.contains(repasse.Oportunidade__c)) return true;
                return repasse.ContaAssessoria__c != null &&
                    context.assessoriaIds.contains(repasse.ContaAssessoria__c);
            }
            return false;
        } catch (Exception ex) {
            return false;
        }
    }

    public static Boolean canAccessThread(
        CommunicatorExternalApiDTOs.UserContextDTO context,
        Id threadId
    ) {
        if (context == null || threadId == null) return false;
        if (context.accessibleThreadIds.contains(threadId)) return true;

        List<CommunicatorThread__c> threads = [
            SELECT Id, RecordId__c, RecordType__c
            FROM CommunicatorThread__c
            WHERE Id = :threadId
            LIMIT 1
        ];
        if (threads.isEmpty()) return false;

        CommunicatorThread__c threadRecord = threads[0];
        if (threadRecord.RecordType__c == THREAD_RECORD_TYPE_GROUP) {
            Id groupId = tryParseId(threadRecord.RecordId__c);
            if (groupId == null) return false;
            if (context.conventionalGroupIds.contains(groupId)) return true;
            if (context.broadcastGroupIds.contains(groupId)) return true;
            return false;
        }

        return canAccessRecord(context, threadRecord.RecordId__c);
    }

    public static void assertObjectRead(CommunicatorExternalApiDTOs.UserContextDTO context, String objectApiName) {
        if (!canReadObject(context, objectApiName)) {
            throw CommunicatorExternalApiErrorService.forbidden(
                'OBJECT_ACCESS_DENIED',
                'Usuario informado nao possui permissao de leitura para ' + objectApiName + '.'
            );
        }
    }

    public static Boolean canReadObject(
        CommunicatorExternalApiDTOs.UserContextDTO context,
        String objectApiName
    ) {
        if (context == null || String.isBlank(objectApiName)) return false;
        if (Test.isRunningTest() && context.userId == UserInfo.getUserId()) {
            Schema.SObjectType objectType = Schema.getGlobalDescribe().get(objectApiName);
            return objectType != null && objectType.getDescribe().isAccessible();
        }
        Set<Id> parentIds = getPermissionSetIds(context.userId);
        if (parentIds.isEmpty()) return false;
        return [
            SELECT COUNT()
            FROM ObjectPermissions
            WHERE ParentId IN :parentIds
            AND SObjectType = :objectApiName
            AND PermissionsRead = true
        ] > 0;
    }

    public static Boolean canReadField(
        CommunicatorExternalApiDTOs.UserContextDTO context,
        String objectApiName,
        String fieldApiName
    ) {
        if (context == null || String.isBlank(objectApiName) || String.isBlank(fieldApiName)) return false;
        if (Test.isRunningTest() && context.userId == UserInfo.getUserId()) {
            Schema.SObjectType objectType = Schema.getGlobalDescribe().get(objectApiName);
            if (objectType == null) return false;
            Schema.SObjectField fieldToken = objectType.getDescribe().fields.getMap().get(fieldApiName);
            return fieldToken != null && fieldToken.getDescribe().isAccessible();
        }
        Set<Id> parentIds = getPermissionSetIds(context.userId);
        if (parentIds.isEmpty()) return false;
        String qualifiedField = objectApiName + '.' + fieldApiName;
        return [
            SELECT COUNT()
            FROM FieldPermissions
            WHERE ParentId IN :parentIds
            AND SObjectType = :objectApiName
            AND Field = :qualifiedField
            AND PermissionsRead = true
        ] > 0;
    }

    public static Set<Id> filterThreadIds(
        CommunicatorExternalApiDTOs.UserContextDTO context,
        Set<Id> threadIds
    ) {
        Set<Id> result = new Set<Id>();
        if (context == null || threadIds == null || threadIds.isEmpty()) return result;
        for (Id threadId : threadIds) {
            if (canAccessThread(context, threadId)) {
                result.add(threadId);
            }
        }
        return result;
    }

    private static Id parseUserId(String rawUserId) {
        if (String.isBlank(rawUserId)) {
            throw CommunicatorExternalApiErrorService.badRequest(
                'USER_ID_REQUIRED',
                'userId e obrigatorio.'
            );
        }
        try {
            Id userId = (Id) rawUserId;
            if (userId.getSObjectType() != User.SObjectType) {
                throw new IllegalArgumentException();
            }
            return userId;
        } catch (Exception ex) {
            throw CommunicatorExternalApiErrorService.badRequest(
                'INVALID_USER_ID',
                'userId invalido.'
            );
        }
    }

    private static Set<Id> getParticipantThreadIds(Id userId) {
        Set<Id> threadIds = new Set<Id>();
        for (CommunicatorParticipant__c participant : [
            SELECT Thread__c
            FROM CommunicatorParticipant__c
            WHERE User__c = :userId
            AND IsActive__c = true
        ]) {
            if (participant.Thread__c != null) {
                threadIds.add(participant.Thread__c);
            }
        }
        return threadIds;
    }

    private static Set<Id> getParticipantOpportunityIds(Set<Id> threadIds) {
        Set<Id> opportunityIds = new Set<Id>();
        if (threadIds == null || threadIds.isEmpty()) return opportunityIds;
        for (CommunicatorThread__c threadRecord : [
            SELECT RecordId__c, RecordType__c
            FROM CommunicatorThread__c
            WHERE Id IN :threadIds
            AND Status__c != 'Archived'
        ]) {
            if (threadRecord.RecordType__c == 'Opportunity') {
                Id opportunityId = tryParseId(threadRecord.RecordId__c);
                if (opportunityId != null) {
                    opportunityIds.add(opportunityId);
                }
            }
            if (threadRecord.RecordType__c == 'Repasse__c') {
                String resolvedOpportunityId =
                    CommunicatorThreadService.resolveOpportunityIdIfRepasse(threadRecord.RecordId__c);
                Id opportunityId = tryParseId(resolvedOpportunityId);
                if (opportunityId != null) {
                    opportunityIds.add(opportunityId);
                }
            }
        }
        return opportunityIds;
    }

    private static Set<Id> getConventionalGroupIdsForUser(Id userId) {
        Set<Id> groupIds = new Set<Id>();
        for (CommunicatorGroupMember__c memberRecord : [
            SELECT Group__c
            FROM CommunicatorGroupMember__c
            WHERE User__c = :userId
            AND Group__r.IsActive__c = true
            AND (Group__r.Type__c = null OR Group__r.Type__c = 'Conventional')
        ]) {
            if (memberRecord.Group__c != null) {
                groupIds.add(memberRecord.Group__c);
            }
        }
        return groupIds;
    }

    private static Set<Id> getAccessibleBroadcastGroupIds(Id userId) {
        Set<Id> broadcastGroupIds = new Set<Id>();
        if (Test.isRunningTest() && testBroadcastGroupIds != null) {
            broadcastGroupIds.addAll(testBroadcastGroupIds);
        }

        for (CommunicatorGroup__c groupRecord : [
            SELECT Id
            FROM CommunicatorGroup__c
            WHERE Type__c = :GROUP_TYPE_BROADCAST
            AND IsActive__c = true
            AND CreatedByUser__c = :userId
        ]) {
            broadcastGroupIds.add(groupRecord.Id);
        }

        Set<Id> candidateGroupIds = new Set<Id>();
        for (CommunicatorBroadcastAudience__c audience : [
            SELECT CommunicatorGroup__c
            FROM CommunicatorBroadcastAudience__c
            WHERE IsActive__c = true
        ]) {
            if (audience.CommunicatorGroup__c != null) {
                candidateGroupIds.add(audience.CommunicatorGroup__c);
            }
        }
        if (candidateGroupIds.isEmpty()) return broadcastGroupIds;

        Map<Id, Set<Id>> recipientsByGroup =
            CommunicatorBroadcastAudienceService.resolveRecipientUserIdsByGroup(candidateGroupIds);
        for (Id groupId : recipientsByGroup.keySet()) {
            if (recipientsByGroup.get(groupId).contains(userId)) {
                broadcastGroupIds.add(groupId);
            }
        }
        return broadcastGroupIds;
    }

    private static Set<Id> getGroupThreadIds(Set<Id> conventionalGroupIds, Set<Id> broadcastGroupIds) {
        Set<Id> groupIds = new Set<Id>();
        if (conventionalGroupIds != null) groupIds.addAll(conventionalGroupIds);
        if (broadcastGroupIds != null) groupIds.addAll(broadcastGroupIds);
        Set<Id> threadIds = new Set<Id>();
        if (groupIds.isEmpty()) return threadIds;
        for (CommunicatorThread__c threadRecord : [
            SELECT Id
            FROM CommunicatorThread__c
            WHERE RecordId__c IN :groupIds
            AND RecordType__c = :THREAD_RECORD_TYPE_GROUP
            AND Status__c = 'Active'
        ]) {
            threadIds.add(threadRecord.Id);
        }
        return threadIds;
    }

    private static Set<Id> getMentionAccessibleThreadIds(Id userId, Set<Id> conventionalGroupIds) {
        Set<Id> accessibleThreadIds = new Set<Id>();
        if (userId == null) return accessibleThreadIds;
        Set<Id> groupIds = conventionalGroupIds == null ? new Set<Id>() : new Set<Id>(conventionalGroupIds);
        if (groupIds.isEmpty()) return accessibleThreadIds;

        for (CommunicatorMessage__c messageRecord : [
            SELECT Thread__c, MentionedGroupIds__c
            FROM CommunicatorMessage__c
            WHERE HasMention__c = true
            AND Thread__c != null
            LIMIT 5000
        ]) {
            Set<Id> mentionedGroups = CommunicatorMentionService.deserializeUserIds(
                messageRecord.MentionedGroupIds__c
            );
            mentionedGroups.retainAll(groupIds);
            if (!mentionedGroups.isEmpty()) {
                accessibleThreadIds.add(messageRecord.Thread__c);
            }
        }
        return accessibleThreadIds;
    }

    private static Set<Id> getAccessibleOpportunityIdsByAssessoria(Set<Id> assessoriaIds) {
        Set<Id> opportunityIds = new Set<Id>();
        if (assessoriaIds == null || assessoriaIds.isEmpty()) return opportunityIds;
        for (Repasse__c repasse : [
            SELECT Oportunidade__c
            FROM Repasse__c
            WHERE Oportunidade__c != null
            AND ContaAssessoria__c IN :assessoriaIds
        ]) {
            opportunityIds.add(repasse.Oportunidade__c);
        }
        return opportunityIds;
    }

    private static Set<Id> getOwnedOpportunityIds(Id userId) {
        Set<Id> opportunityIds = new Set<Id>();
        if (userId == null) return opportunityIds;
        for (Opportunity opportunityRecord : [
            SELECT Id
            FROM Opportunity
            WHERE OwnerId = :userId
            LIMIT 5000
        ]) {
            opportunityIds.add(opportunityRecord.Id);
        }
        return opportunityIds;
    }

    private static Set<Id> getOwnedOpportunityIds(Set<Id> userIds) {
        Set<Id> opportunityIds = new Set<Id>();
        if (userIds == null || userIds.isEmpty()) return opportunityIds;
        for (Opportunity opportunityRecord : [
            SELECT Id
            FROM Opportunity
            WHERE OwnerId IN :userIds
            LIMIT 5000
        ]) {
            opportunityIds.add(opportunityRecord.Id);
        }
        return opportunityIds;
    }

    private static Set<Id> getHierarchyOpportunityIds(Id userId, Id userRoleId) {
        if (userId == null || userRoleId == null) return new Set<Id>();
        Set<Id> roleIds = getDescendantRoleIds(userRoleId);
        if (roleIds.isEmpty()) return new Set<Id>();
        Set<Id> userIds = new Set<Id>{ userId };
        for (User userRecord : [
            SELECT Id
            FROM User
            WHERE IsActive = true
            AND UserRoleId IN :roleIds
            LIMIT 5000
        ]) {
            userIds.add(userRecord.Id);
        }
        return getOwnedOpportunityIds(userIds);
    }

    private static Set<Id> getDescendantRoleIds(Id userRoleId) {
        Set<Id> roleIds = new Set<Id>{ userRoleId };
        Map<Id, List<Id>> childRoleIdsByParent = new Map<Id, List<Id>>();
        for (UserRole roleRecord : [
            SELECT Id, ParentRoleId
            FROM UserRole
        ]) {
            if (roleRecord.ParentRoleId == null) continue;
            if (!childRoleIdsByParent.containsKey(roleRecord.ParentRoleId)) {
                childRoleIdsByParent.put(roleRecord.ParentRoleId, new List<Id>());
            }
            childRoleIdsByParent.get(roleRecord.ParentRoleId).add(roleRecord.Id);
        }

        Set<Id> frontierIds = new Set<Id>{ userRoleId };
        while (!frontierIds.isEmpty()) {
            Set<Id> nextFrontierIds = new Set<Id>();
            for (Id roleId : frontierIds) {
                if (!childRoleIdsByParent.containsKey(roleId)) continue;
                for (Id childRoleId : childRoleIdsByParent.get(roleId)) {
                    if (roleIds.add(childRoleId)) {
                        nextFrontierIds.add(childRoleId);
                    }
                }
            }
            frontierIds = nextFrontierIds;
        }
        return roleIds;
    }

    private static Set<Id> getReadableOpportunityThreadIds(Id userId, Set<Id> readableOpportunityIds) {
        Set<Id> threadIds = new Set<Id>();
        Map<Id, Id> opportunityIdByThreadId = new Map<Id, Id>();
        for (CommunicatorThread__c threadRecord : [
            SELECT Id, RecordId__c
            FROM CommunicatorThread__c
            WHERE RecordType__c = 'Opportunity'
            AND Status__c != 'Archived'
            LIMIT 5000
        ]) {
            Id opportunityId = tryParseId(threadRecord.RecordId__c);
            if (opportunityId != null) {
                opportunityIdByThreadId.put(threadRecord.Id, opportunityId);
            }
        }
        Set<Id> allowedOpportunityIds = filterReadableRecordIds(
            userId,
            new Set<Id>(opportunityIdByThreadId.values())
        );
        readableOpportunityIds.addAll(allowedOpportunityIds);
        for (Id threadId : opportunityIdByThreadId.keySet()) {
            if (allowedOpportunityIds.contains(opportunityIdByThreadId.get(threadId))) {
                threadIds.add(threadId);
            }
        }
        return threadIds;
    }

    private static Boolean canReadRecord(Id userId, Id recordId) {
        return filterReadableRecordIds(userId, new Set<Id>{ recordId }).contains(recordId);
    }

    private static Set<Id> filterReadableRecordIds(Id userId, Set<Id> recordIds) {
        Set<Id> result = new Set<Id>();
        if (userId == null || recordIds == null || recordIds.isEmpty()) return result;
        if (!readableRecordIdsByUser.containsKey(userId)) {
            readableRecordIdsByUser.put(userId, new Set<Id>());
        }
        Set<Id> cachedIds = readableRecordIdsByUser.get(userId);
        Set<Id> idsToCheck = new Set<Id>(recordIds);
        idsToCheck.removeAll(cachedIds);
        for (Set<Id> idChunk : chunkIds(idsToCheck, 200)) {
            for (UserRecordAccess accessRecord : [
                SELECT RecordId, HasReadAccess
                FROM UserRecordAccess
                WHERE UserId = :userId
                AND RecordId IN :idChunk
            ]) {
                if (accessRecord.HasReadAccess == true) {
                    cachedIds.add(accessRecord.RecordId);
                }
            }
        }
        result.addAll(recordIds);
        result.retainAll(cachedIds);
        return result;
    }

    private static List<Set<Id>> chunkIds(Set<Id> ids, Integer chunkSize) {
        List<Set<Id>> chunks = new List<Set<Id>>();
        if (ids == null || ids.isEmpty()) return chunks;
        Set<Id> currentChunk = new Set<Id>();
        for (Id recordId : ids) {
            currentChunk.add(recordId);
            if (currentChunk.size() == chunkSize) {
                chunks.add(currentChunk);
                currentChunk = new Set<Id>();
            }
        }
        if (!currentChunk.isEmpty()) chunks.add(currentChunk);
        return chunks;
    }

    private static Set<Id> getPermissionSetIds(Id userId) {
        if (userId == null) return new Set<Id>();
        if (permissionSetIdsByUser.containsKey(userId)) {
            return permissionSetIdsByUser.get(userId);
        }
        Set<Id> permissionSetIds = new Set<Id>();
        for (PermissionSetAssignment assignment : [
            SELECT PermissionSetId
            FROM PermissionSetAssignment
            WHERE AssigneeId = :userId
        ]) {
            permissionSetIds.add(assignment.PermissionSetId);
        }
        permissionSetIdsByUser.put(userId, permissionSetIds);
        return permissionSetIds;
    }

    private static Set<Id> getOpportunityThreadIds(Set<Id> opportunityIds) {
        Set<Id> threadIds = new Set<Id>();
        if (opportunityIds == null || opportunityIds.isEmpty()) return threadIds;
        for (CommunicatorThread__c threadRecord : [
            SELECT Id
            FROM CommunicatorThread__c
            WHERE RecordId__c IN :opportunityIds
            AND Status__c != 'Archived'
        ]) {
            threadIds.add(threadRecord.Id);
        }
        return threadIds;
    }

    private static Set<Id> getQueueIdsForUser(Id userId, Id userRoleId) {
        Set<Id> queueIds = new Set<Id>();
        Set<Id> visitedGroupIds = new Set<Id>();
        Set<Id> frontierIds = new Set<Id>{ userId };
        if (userRoleId != null) {
            frontierIds.addAll(getRoleGroupIdsForRole(userRoleId));
        }

        Integer depth = 0;
        while (!frontierIds.isEmpty() && depth < 10) {
            depth++;
            Set<Id> nextFrontier = new Set<Id>();
            for (GroupMember membership : [
                SELECT GroupId, UserOrGroupId, Group.Type
                FROM GroupMember
                WHERE UserOrGroupId IN :frontierIds
            ]) {
                if (membership.GroupId == null || visitedGroupIds.contains(membership.GroupId)) continue;
                visitedGroupIds.add(membership.GroupId);
                if (membership.Group != null && membership.Group.Type == 'Queue') {
                    queueIds.add(membership.GroupId);
                } else {
                    nextFrontier.add(membership.GroupId);
                }
            }
            frontierIds = nextFrontier;
        }
        return queueIds;
    }

    private static Set<Id> getRoleGroupIdsForRole(Id userRoleId) {
        Set<Id> groupIds = new Set<Id>();
        if (userRoleId == null) return groupIds;
        for (Group roleGroup : [
            SELECT Id
            FROM Group
            WHERE Type = 'Role'
            AND RelatedId = :userRoleId
        ]) {
            groupIds.add(roleGroup.Id);
        }
        return groupIds;
    }

    private static Id tryParseId(String rawId) {
        if (String.isBlank(rawId)) return null;
        try {
            return (Id) rawId;
        } catch (Exception ex) {
            return null;
        }
    }
}