public without sharing class CommunicatorBroadcastLwcAccessService {

    private static final String GROUP_TYPE_BROADCAST = 'Broadcast';
    private static final String THREAD_RECORD_TYPE_GROUP = 'CommunicatorGroup__c';
    private static final String TYPE_ROLE = 'Role';
    private static final String TYPE_ROLE_INTERNAL = 'RoleAndSubordinatesInternal';
    private static final String TYPE_ROLE_PORTAL = 'RoleAndSubordinatesPortal';
    private static final String TYPE_ROLE_INTERNAL_PORTAL = 'RoleAndSubordinatesInternalAndPortal';
    private static final String TYPE_PUBLIC_GROUP = 'PublicGroup';
    private static final String TYPE_DIRECT_USER = 'DirectUser';
    private static final String TYPE_SALES_COMPANY = 'SalesCompany';
    private static final String TYPE_JOB_TITLE = 'JobTitle';
    private static final String TYPE_JOB_TITLE_AND_SUBORDINATES = 'JobTitleAndSubordinates';
    private static final String TYPE_ALL_SUPPORTED_USERS = 'AllSupportedUsers';
    private static final Integer MAX_PUBLIC_GROUP_DEPTH = 20;
    private static final Integer CONTACT_QUERY_LIMIT = 51;
    private static final String ACCESS_REASON_CREATOR = 'CREATOR';
    private static final String ACCESS_REASON_CURRENT_AUDIENCE = 'CURRENT_AUDIENCE';
    private static final String ACCESS_REASON_NOT_BROADCAST_GROUP = 'NOT_BROADCAST_GROUP';
    private static final String ACCESS_REASON_GROUP_INACTIVE = 'GROUP_INACTIVE';
    private static final String ACCESS_REASON_GROUP_NOT_FOUND = 'GROUP_NOT_FOUND';
    private static final String ACCESS_REASON_OUTSIDE_CURRENT_AUDIENCE = 'OUTSIDE_CURRENT_AUDIENCE';
    private static final String ACCESS_REASON_UNSUPPORTED_USER = 'UNSUPPORTED_USER';
    private static final String ACCESS_REASON_MESSAGE_NOT_FOUND = 'MESSAGE_NOT_FOUND';
    private static final String PUBLIC_GROUP_TYPE_REGULAR = 'Regular';
    private static final String PUBLIC_GROUP_TYPE_QUEUE = 'Queue';
    private static final String PUBLIC_GROUP_TYPE_ROLE = 'Role';
    private static final String PUBLIC_GROUP_TYPE_ROLE_AND_SUBORDINATES = 'RoleAndSubordinates';
    private static final String PUBLIC_GROUP_TYPE_ROLE_AND_SUBORDINATES_INTERNAL =
        'RoleAndSubordinatesInternal';
    private static final String PUBLIC_GROUP_TYPE_ROLE_AND_SUBORDINATES_PORTAL =
        'RoleAndSubordinatesPortal';
    private static final String PUBLIC_GROUP_TYPE_ROLE_AND_SUBORDINATES_INTERNAL_AND_PORTAL =
        'RoleAndSubordinatesInternalAndPortal';

    @TestVisible private static AccessDataProvider dataProvider = new SoqlAccessDataProvider();
    @TestVisible private static Map<Id, CurrentUserContext> currentUserContextCacheByUserId =
        new Map<Id, CurrentUserContext>();
    @TestVisible private static Integer currentUserContextBuildCount = 0;
    @TestVisible private static Integer groupEvaluationInvocationCount = 0;
    @TestVisible private static Integer messageEvaluationInvocationCount = 0;
    @TestVisible private static Integer activeCriteriaQueryCount = 0;

    public class GroupAccessDecision {
        public Id groupId;
        public Boolean isBroadcastGroup = false;
        public Boolean isGroupActive = false;
        public Boolean isCreator = false;
        public Boolean hasCurrentAudienceAccess = false;
        public Boolean canAccessGroup = false;
        public Boolean canAccessMessage = false;
        public Boolean canPublish = false;
        public String accessReason = ACCESS_REASON_GROUP_NOT_FOUND;
    }

    public class MessageAccessDecision {
        public Id messageId;
        public Id threadId;
        public Id groupId;
        public Boolean isBroadcastGroup = false;
        public Boolean isGroupActive = false;
        public Boolean isCreator = false;
        public Boolean hasCurrentAudienceAccess = false;
        public Boolean canAccessGroup = false;
        public Boolean canAccessMessage = false;
        public Boolean canPublish = false;
        public String accessReason = ACCESS_REASON_MESSAGE_NOT_FOUND;
    }

    public class CurrentUserContext {
        public Id currentUserId;
        public Boolean isActive = false;
        public String userType;
        public String licenseName;
        public Id userRoleId;
        public String salesCompany;
        public CommunicatorBroadcastAudienceService.UserAudienceCategory category =
            CommunicatorBroadcastAudienceService.UserAudienceCategory.UNSUPPORTED;
        public Set<Id> currentUserContactIds = new Set<Id>();
        public Set<Id> currentUserContactJobTitleIds = new Set<Id>();
        public Set<Id> currentUserContactChainJobTitleIds = new Set<Id>();
        public Set<Id> matchedPublicRootGroupIds = new Set<Id>();
        public Set<Id> evaluatedPublicRootGroupIds = new Set<Id>();
        public Map<Id, Set<Id>> roleHierarchyByRoot = new Map<Id, Set<Id>>();
        public Boolean contactsLoaded = false;
        public Boolean contactChainLoaded = false;
    }

    public class AccessGroupRecord {
        public Id groupId;
        public String groupType;
        public Boolean isActive;
        public Id createdByUserId;

        public AccessGroupRecord(Id groupId, String groupType, Boolean isActive, Id createdByUserId) {
            this.groupId = groupId;
            this.groupType = groupType;
            this.isActive = isActive;
            this.createdByUserId = createdByUserId;
        }
    }

    public class AccessMessageRecord {
        public Id messageId;
        public Id threadId;
        public Id groupId;

        public AccessMessageRecord(Id messageId, Id threadId, Id groupId) {
            this.messageId = messageId;
            this.threadId = threadId;
            this.groupId = groupId;
        }
    }

    private class PublicGroupGraph {
        private Map<Id, CommunicatorBroadcastAudienceService.AudienceGroupRecord> groupsById =
            new Map<Id, CommunicatorBroadcastAudienceService.AudienceGroupRecord>();
        private Map<Id, List<Id>> memberIdsByGroup = new Map<Id, List<Id>>();
    }

    public interface AccessDataProvider {
        List<CommunicatorBroadcastAudienceService.AudienceUserRecord> getUsersByIds(Set<Id> userIds);
        List<CommunicatorBroadcastAudienceService.AudienceContactRecord> getContactsByUserId(
            Id userId,
            Integer limitSize
        );
        List<CommunicatorBroadcastAudienceService.AudienceContactRecord> getContactsByIds(Set<Id> contactIds);
        List<CommunicatorBroadcastAudienceService.AudienceGroupRecord> getGroupsByIds(Set<Id> groupIds);
        List<CommunicatorBroadcastAudienceService.AudienceGroupMemberRecord> getGroupMembersByGroupIds(
            Set<Id> groupIds,
            Integer limitSize
        );
        Map<Id, Set<Id>> getRoleAndDescendantIdsByRoot(Set<Id> rootRoleIds);
        List<CommunicatorBroadcastAudience__c> getActiveCriteria(Set<Id> groupIds);
        List<AccessGroupRecord> getBroadcastGroupsByIds(Set<Id> groupIds);
        List<AccessMessageRecord> getMessagesByIds(Set<Id> messageIds);
    }

    private class SoqlAccessDataProvider implements AccessDataProvider {
        public List<CommunicatorBroadcastAudienceService.AudienceUserRecord> getUsersByIds(Set<Id> userIds) {
            List<CommunicatorBroadcastAudienceService.AudienceUserRecord> result =
                new List<CommunicatorBroadcastAudienceService.AudienceUserRecord>();
            if (userIds == null || userIds.isEmpty()) return result;
            for (User userRecord : [
                SELECT Id, IsActive, UserType, UserRoleId, EmpresaVendas__c,
                       ContactId, Contact.Cargo__c, Profile.UserLicense.Name
                FROM User
                WHERE Id IN :userIds
            ]) {
                result.add(new CommunicatorBroadcastAudienceService.AudienceUserRecord(
                    userRecord.Id,
                    userRecord.IsActive,
                    userRecord.UserType,
                    userRecord.Profile != null && userRecord.Profile.UserLicense != null
                        ? userRecord.Profile.UserLicense.Name
                        : null,
                    userRecord.UserRoleId,
                    userRecord.EmpresaVendas__c,
                    userRecord.ContactId,
                    userRecord.Contact != null ? userRecord.Contact.Cargo__c : null
                ));
            }
            return result;
        }

        public List<CommunicatorBroadcastAudienceService.AudienceContactRecord> getContactsByUserId(
            Id userId,
            Integer limitSize
        ) {
            List<CommunicatorBroadcastAudienceService.AudienceContactRecord> result =
                new List<CommunicatorBroadcastAudienceService.AudienceContactRecord>();
            if (userId == null) return result;
            Integer effectiveLimit = normalizeLimit(limitSize);
            for (Contact contactRecord : [
                SELECT Id, ReportsToId, Cargo__c
                FROM Contact
                WHERE Usuario__c = :userId
                LIMIT :effectiveLimit
            ]) {
                result.add(new CommunicatorBroadcastAudienceService.AudienceContactRecord(
                    contactRecord.Id,
                    contactRecord.ReportsToId,
                    contactRecord.Cargo__c,
                    null,
                    null,
                    null,
                    null,
                    null,
                    null
                ));
            }
            return result;
        }

        public List<CommunicatorBroadcastAudienceService.AudienceContactRecord> getContactsByIds(
            Set<Id> contactIds
        ) {
            List<CommunicatorBroadcastAudienceService.AudienceContactRecord> result =
                new List<CommunicatorBroadcastAudienceService.AudienceContactRecord>();
            if (contactIds == null || contactIds.isEmpty()) return result;
            for (Contact contactRecord : [
                SELECT Id, ReportsToId, Cargo__c
                FROM Contact
                WHERE Id IN :contactIds
            ]) {
                result.add(new CommunicatorBroadcastAudienceService.AudienceContactRecord(
                    contactRecord.Id,
                    contactRecord.ReportsToId,
                    contactRecord.Cargo__c,
                    null,
                    null,
                    null,
                    null,
                    null,
                    null
                ));
            }
            return result;
        }

        public List<CommunicatorBroadcastAudienceService.AudienceGroupRecord> getGroupsByIds(
            Set<Id> groupIds
        ) {
            List<CommunicatorBroadcastAudienceService.AudienceGroupRecord> result =
                new List<CommunicatorBroadcastAudienceService.AudienceGroupRecord>();
            if (groupIds == null || groupIds.isEmpty()) return result;
            for (Group groupRecord : [
                SELECT Id, Type, RelatedId
                FROM Group
                WHERE Id IN :groupIds
            ]) {
                result.add(
                    new CommunicatorBroadcastAudienceService.AudienceGroupRecord(
                        groupRecord.Id,
                        groupRecord.Type,
                        groupRecord.RelatedId
                    )
                );
            }
            return result;
        }

        public List<CommunicatorBroadcastAudienceService.AudienceGroupMemberRecord> getGroupMembersByGroupIds(
            Set<Id> groupIds,
            Integer limitSize
        ) {
            List<CommunicatorBroadcastAudienceService.AudienceGroupMemberRecord> result =
                new List<CommunicatorBroadcastAudienceService.AudienceGroupMemberRecord>();
            if (groupIds == null || groupIds.isEmpty()) return result;
            Integer effectiveLimit = normalizeLimit(limitSize);
            for (GroupMember memberRecord : [
                SELECT GroupId, UserOrGroupId
                FROM GroupMember
                WHERE GroupId IN :groupIds
                LIMIT :effectiveLimit
            ]) {
                result.add(
                    new CommunicatorBroadcastAudienceService.AudienceGroupMemberRecord(
                        memberRecord.GroupId,
                        memberRecord.UserOrGroupId
                    )
                );
            }
            return result;
        }

        public Map<Id, Set<Id>> getRoleAndDescendantIdsByRoot(Set<Id> rootRoleIds) {
            return CommunicatorRoleHierarchyService.getRoleAndDescendantIdsByRoot(rootRoleIds);
        }

        public List<CommunicatorBroadcastAudience__c> getActiveCriteria(Set<Id> groupIds) {
            if (groupIds == null || groupIds.isEmpty()) {
                return new List<CommunicatorBroadcastAudience__c>();
            }
            activeCriteriaQueryCount++;
            return [
                SELECT Id, CommunicatorGroup__c, AudienceType__c, TargetId__c,
                       TargetName__c, SortOrder__c, IsActive__c, AudienceKey__c
                FROM CommunicatorBroadcastAudience__c
                WHERE CommunicatorGroup__c IN :groupIds
                AND IsActive__c = true
                ORDER BY SortOrder__c ASC NULLS LAST, CreatedDate ASC
            ];
        }

        public List<AccessGroupRecord> getBroadcastGroupsByIds(Set<Id> groupIds) {
            List<AccessGroupRecord> result = new List<AccessGroupRecord>();
            if (groupIds == null || groupIds.isEmpty()) return result;
            for (CommunicatorGroup__c groupRecord : [
                SELECT Id, Type__c, IsActive__c, CreatedByUser__c
                FROM CommunicatorGroup__c
                WHERE Id IN :groupIds
            ]) {
                result.add(new AccessGroupRecord(
                    groupRecord.Id,
                    groupRecord.Type__c,
                    groupRecord.IsActive__c,
                    groupRecord.CreatedByUser__c
                ));
            }
            return result;
        }

        public List<AccessMessageRecord> getMessagesByIds(Set<Id> messageIds) {
            List<AccessMessageRecord> result = new List<AccessMessageRecord>();
            if (messageIds == null || messageIds.isEmpty()) return result;
            for (CommunicatorMessage__c messageRecord : [
                SELECT Id, Thread__c, Thread__r.RecordId__c, Thread__r.RecordType__c
                FROM CommunicatorMessage__c
                WHERE Id IN :messageIds
            ]) {
                Id groupId =
                    messageRecord.Thread__r != null &&
                    messageRecord.Thread__r.RecordType__c == THREAD_RECORD_TYPE_GROUP
                        ? tryParseId(messageRecord.Thread__r.RecordId__c)
                        : null;
                result.add(new AccessMessageRecord(messageRecord.Id, messageRecord.Thread__c, groupId));
            }
            return result;
        }

        private Integer normalizeLimit(Integer limitSize) {
            return limitSize == null || limitSize <= 0 ? 50000 : limitSize;
        }
    }

    public static Map<Id, GroupAccessDecision> evaluateGroupAccess(Set<Id> groupIds) {
        groupEvaluationInvocationCount++;
        Map<Id, GroupAccessDecision> result = initializeGroupDecisions(groupIds);
        if (result.isEmpty()) return result;

        CurrentUserContext context = getCurrentUserContext();
        Map<Id, AccessGroupRecord> groupsById = loadGroups(groupIds);
        Set<Id> activeBroadcastGroupIds = new Set<Id>();
        for (Id groupId : result.keySet()) {
            applyGroupMetadata(result.get(groupId), groupsById.get(groupId), context);
            if (result.get(groupId).isBroadcastGroup == true &&
                result.get(groupId).isGroupActive == true) {
                activeBroadcastGroupIds.add(groupId);
            }
        }
        if (activeBroadcastGroupIds.isEmpty()) return result;

        Map<Id, Boolean> audienceAccessByGroup = evaluateCurrentAudienceAccess(context, activeBroadcastGroupIds);
        for (Id groupId : activeBroadcastGroupIds) {
            GroupAccessDecision decision = result.get(groupId);
            decision.hasCurrentAudienceAccess = audienceAccessByGroup.get(groupId) == true;
            finalizeDecision(decision);
        }
        return result;
    }

    public static Map<Id, MessageAccessDecision> evaluateMessageAccess(Set<Id> messageIds) {
        messageEvaluationInvocationCount++;
        Map<Id, MessageAccessDecision> result = initializeMessageDecisions(messageIds);
        if (result.isEmpty()) return result;

        Map<Id, AccessMessageRecord> messagesById = loadMessages(messageIds);
        Set<Id> groupIds = new Set<Id>();
        for (AccessMessageRecord messageRecord : messagesById.values()) {
            if (messageRecord.groupId != null) groupIds.add(messageRecord.groupId);
        }

        Map<Id, GroupAccessDecision> groupAccessById = evaluateGroupAccess(groupIds);
        for (Id messageId : result.keySet()) {
            MessageAccessDecision decision = result.get(messageId);
            AccessMessageRecord messageRecord = messagesById.get(messageId);
            if (messageRecord == null) {
                decision.accessReason = ACCESS_REASON_MESSAGE_NOT_FOUND;
                continue;
            }

            decision.threadId = messageRecord.threadId;
            decision.groupId = messageRecord.groupId;

            GroupAccessDecision groupDecision = groupAccessById.get(messageRecord.groupId);
            if (groupDecision == null) {
                decision.accessReason = ACCESS_REASON_NOT_BROADCAST_GROUP;
                continue;
            }

            decision.isBroadcastGroup = groupDecision.isBroadcastGroup;
            decision.isGroupActive = groupDecision.isGroupActive;
            decision.isCreator = groupDecision.isCreator;
            decision.hasCurrentAudienceAccess = groupDecision.hasCurrentAudienceAccess;
            decision.canAccessGroup = groupDecision.canAccessGroup;
            decision.canAccessMessage = groupDecision.canAccessMessage;
            decision.canPublish = groupDecision.canPublish;
            decision.accessReason = groupDecision.accessReason;
        }
        return result;
    }

    @TestVisible
    private static void resetForTest() {
        dataProvider = new SoqlAccessDataProvider();
        currentUserContextCacheByUserId.clear();
        currentUserContextBuildCount = 0;
        groupEvaluationInvocationCount = 0;
        messageEvaluationInvocationCount = 0;
        activeCriteriaQueryCount = 0;
    }

    private static Map<Id, Boolean> evaluateCurrentAudienceAccess(
        CurrentUserContext context,
        Set<Id> groupIds
    ) {
        Map<Id, Boolean> result = new Map<Id, Boolean>();
        for (Id groupId : groupIds) result.put(groupId, false);
        if (groupIds == null || groupIds.isEmpty() || !isSupportedActiveUser(context)) return result;

        List<CommunicatorBroadcastAudience__c> criteria = dataProvider.getActiveCriteria(groupIds);
        Set<Id> publicRootIds = new Set<Id>();
        Set<Id> hierarchyRootIds = new Set<Id>();
        Boolean hasJobTitleCriterion = false;
        Boolean hasJobTitleAndSubordinatesCriterion = false;

        for (CommunicatorBroadcastAudience__c criterion : criteria) {
            Id targetId = tryParseId(criterion.TargetId__c);
            String audienceType = normalizeAudienceType(criterion.AudienceType__c);
            if (audienceType == TYPE_PUBLIC_GROUP && targetId != null) {
                publicRootIds.add(targetId);
            } else if (
                (audienceType == TYPE_ROLE_INTERNAL ||
                 audienceType == TYPE_ROLE_PORTAL ||
                 audienceType == TYPE_ROLE_INTERNAL_PORTAL) &&
                targetId != null
            ) {
                hierarchyRootIds.add(targetId);
            } else if (audienceType == TYPE_JOB_TITLE) {
                hasJobTitleCriterion = true;
            } else if (audienceType == TYPE_JOB_TITLE_AND_SUBORDINATES) {
                hasJobTitleAndSubordinatesCriterion = true;
            }
        }

        if (!hierarchyRootIds.isEmpty()) {
            ensureRoleHierarchyLoaded(context, hierarchyRootIds);
        }
        if (hasJobTitleCriterion || hasJobTitleAndSubordinatesCriterion) {
            ensureCurrentUserContactsLoaded(context);
        }
        if (hasJobTitleAndSubordinatesCriterion) {
            ensureCurrentUserContactChainLoaded(context);
        }
        if (!publicRootIds.isEmpty()) {
            ensurePublicGroupMembershipLoaded(context, publicRootIds);
        }

        for (CommunicatorBroadcastAudience__c criterion : criteria) {
            if (result.get(criterion.CommunicatorGroup__c) == true) continue;

            String audienceType = normalizeAudienceType(criterion.AudienceType__c);
            Id targetId = tryParseId(criterion.TargetId__c);
            Boolean hasAccess = false;
            if (audienceType == TYPE_DIRECT_USER) {
                hasAccess = targetId == context.currentUserId;
            } else if (audienceType == TYPE_ROLE) {
                hasAccess = targetId != null && targetId == context.userRoleId;
            } else if (audienceType == TYPE_ROLE_INTERNAL) {
                hasAccess = isCore(context) && roleContainsCurrentUser(targetId, context);
            } else if (audienceType == TYPE_ROLE_PORTAL) {
                hasAccess = isCommunityPartner(context) && roleContainsCurrentUser(targetId, context);
            } else if (audienceType == TYPE_ROLE_INTERNAL_PORTAL) {
                hasAccess = roleContainsCurrentUser(targetId, context);
            } else if (audienceType == TYPE_PUBLIC_GROUP) {
                hasAccess = targetId != null && context.matchedPublicRootGroupIds.contains(targetId);
            } else if (audienceType == TYPE_SALES_COMPANY) {
                hasAccess = String.isNotBlank(context.salesCompany) &&
                    context.salesCompany == criterion.TargetId__c;
            } else if (audienceType == TYPE_JOB_TITLE) {
                hasAccess = targetId != null && context.currentUserContactJobTitleIds.contains(targetId);
            } else if (audienceType == TYPE_JOB_TITLE_AND_SUBORDINATES) {
                hasAccess = targetId != null &&
                    context.currentUserContactChainJobTitleIds.contains(targetId);
            } else if (audienceType == TYPE_ALL_SUPPORTED_USERS) {
                hasAccess = true;
            }
            if (hasAccess) result.put(criterion.CommunicatorGroup__c, true);
        }
        return result;
    }

    private static void applyGroupMetadata(
        GroupAccessDecision decision,
        AccessGroupRecord groupRecord,
        CurrentUserContext context
    ) {
        if (decision == null) return;
        if (groupRecord == null) {
            decision.accessReason = ACCESS_REASON_GROUP_NOT_FOUND;
            return;
        }

        decision.isBroadcastGroup = groupRecord.groupType == GROUP_TYPE_BROADCAST;
        if (!decision.isBroadcastGroup) {
            decision.accessReason = ACCESS_REASON_NOT_BROADCAST_GROUP;
            return;
        }

        decision.isGroupActive = groupRecord.isActive == true;
        decision.isCreator = groupRecord.createdByUserId == context.currentUserId;
        if (!decision.isGroupActive) {
            decision.canPublish = false;
            decision.accessReason = ACCESS_REASON_GROUP_INACTIVE;
        }
    }

    private static void finalizeDecision(GroupAccessDecision decision) {
        if (decision == null || decision.isBroadcastGroup != true) return;
        if (decision.isGroupActive != true) {
            decision.canAccessGroup = false;
            decision.canAccessMessage = false;
            return;
        }

        decision.canPublish = decision.isCreator &&
            CommunicatorBroadcastAudienceService.currentUserHasCreatorPermission();
        if (decision.isCreator) {
            decision.canAccessGroup = true;
            decision.canAccessMessage = true;
            decision.accessReason = ACCESS_REASON_CREATOR;
            return;
        }
        if (decision.hasCurrentAudienceAccess == true) {
            decision.canAccessGroup = true;
            decision.canAccessMessage = true;
            decision.accessReason = ACCESS_REASON_CURRENT_AUDIENCE;
            return;
        }

        decision.canAccessGroup = false;
        decision.canAccessMessage = false;
        decision.accessReason =
            isSupportedActiveUser(getCurrentUserContext())
                ? ACCESS_REASON_OUTSIDE_CURRENT_AUDIENCE
                : ACCESS_REASON_UNSUPPORTED_USER;
    }

    private static CurrentUserContext getCurrentUserContext() {
        Id currentUserId = UserInfo.getUserId();
        if (currentUserContextCacheByUserId.containsKey(currentUserId)) {
            return currentUserContextCacheByUserId.get(currentUserId);
        }

        currentUserContextBuildCount++;
        CurrentUserContext context = new CurrentUserContext();
        context.currentUserId = currentUserId;

        List<CommunicatorBroadcastAudienceService.AudienceUserRecord> users =
            dataProvider.getUsersByIds(new Set<Id>{ context.currentUserId });
        if (!users.isEmpty()) {
            CommunicatorBroadcastAudienceService.AudienceUserRecord currentUser = users[0];
            context.isActive = currentUser.isActive == true;
            context.userType = currentUser.userType;
            context.licenseName = currentUser.licenseName;
            context.userRoleId = currentUser.userRoleId;
            context.salesCompany = currentUser.salesCompany;
            context.category = classifyUser(currentUser);
            if (currentUser.contactId != null) context.currentUserContactIds.add(currentUser.contactId);
            if (currentUser.contactJobTitleId != null) {
                context.currentUserContactJobTitleIds.add(currentUser.contactJobTitleId);
            }
        }

        currentUserContextCacheByUserId.put(currentUserId, context);
        return context;
    }

    private static void ensureCurrentUserContactsLoaded(CurrentUserContext context) {
        if (context == null || context.contactsLoaded) return;
        List<CommunicatorBroadcastAudienceService.AudienceContactRecord> contacts =
            dataProvider.getContactsByUserId(context.currentUserId, CONTACT_QUERY_LIMIT);
        for (CommunicatorBroadcastAudienceService.AudienceContactRecord contactRecord : contacts) {
            if (contactRecord == null || contactRecord.contactId == null) continue;
            context.currentUserContactIds.add(contactRecord.contactId);
            if (contactRecord.cargoId != null) {
                context.currentUserContactJobTitleIds.add(contactRecord.cargoId);
            }
        }
        context.contactsLoaded = true;
    }

    private static void ensureCurrentUserContactChainLoaded(CurrentUserContext context) {
        if (context == null || context.contactChainLoaded) return;
        ensureCurrentUserContactsLoaded(context);
        context.currentUserContactChainJobTitleIds.addAll(context.currentUserContactJobTitleIds);

        Set<Id> visitedContactIds = new Set<Id>();
        Set<Id> frontierContactIds = new Set<Id>();
        frontierContactIds.addAll(context.currentUserContactIds);

        while (!frontierContactIds.isEmpty()) {
            List<CommunicatorBroadcastAudienceService.AudienceContactRecord> contactLevel =
                dataProvider.getContactsByIds(frontierContactIds);
            Set<Id> nextFrontierContactIds = new Set<Id>();
            for (CommunicatorBroadcastAudienceService.AudienceContactRecord contactRecord : contactLevel) {
                if (contactRecord == null || contactRecord.contactId == null) continue;
                if (!visitedContactIds.add(contactRecord.contactId)) continue;
                if (contactRecord.cargoId != null) {
                    context.currentUserContactChainJobTitleIds.add(contactRecord.cargoId);
                }
                if (contactRecord.reportsToId != null &&
                    !visitedContactIds.contains(contactRecord.reportsToId)) {
                    nextFrontierContactIds.add(contactRecord.reportsToId);
                }
            }
            frontierContactIds = nextFrontierContactIds;
        }
        context.contactChainLoaded = true;
    }

    private static void ensureRoleHierarchyLoaded(CurrentUserContext context, Set<Id> rootRoleIds) {
        if (context == null || rootRoleIds == null || rootRoleIds.isEmpty()) return;
        Set<Id> missingRoleIds = new Set<Id>();
        for (Id roleId : rootRoleIds) {
            if (roleId != null && !context.roleHierarchyByRoot.containsKey(roleId)) {
                missingRoleIds.add(roleId);
            }
        }
        if (missingRoleIds.isEmpty()) return;
        Map<Id, Set<Id>> loadedHierarchy = dataProvider.getRoleAndDescendantIdsByRoot(missingRoleIds);
        for (Id roleId : missingRoleIds) {
            context.roleHierarchyByRoot.put(
                roleId,
                loadedHierarchy.containsKey(roleId) ? loadedHierarchy.get(roleId) : new Set<Id>()
            );
        }
    }

    private static void ensurePublicGroupMembershipLoaded(
        CurrentUserContext context,
        Set<Id> publicRootIds
    ) {
        if (context == null || publicRootIds == null || publicRootIds.isEmpty()) return;

        Set<Id> missingRootIds = new Set<Id>();
        for (Id groupId : publicRootIds) {
            if (groupId != null && !context.evaluatedPublicRootGroupIds.contains(groupId)) {
                missingRootIds.add(groupId);
            }
        }
        if (missingRootIds.isEmpty()) return;

        PublicGroupGraph graph = loadPublicGroupGraph(missingRootIds);
        Set<Id> hierarchyRootIds = new Set<Id>();
        for (CommunicatorBroadcastAudienceService.AudienceGroupRecord groupRecord : graph.groupsById.values()) {
            if (isRolePublicGroupMember(groupRecord) && groupRecord.relatedId != null) {
                hierarchyRootIds.add(groupRecord.relatedId);
            }
        }
        ensureRoleHierarchyLoaded(context, hierarchyRootIds);

        for (Id rootGroupId : missingRootIds) {
            if (currentUserBelongsToPublicRoot(rootGroupId, graph, context)) {
                context.matchedPublicRootGroupIds.add(rootGroupId);
            }
            context.evaluatedPublicRootGroupIds.add(rootGroupId);
        }
    }

    private static PublicGroupGraph loadPublicGroupGraph(Set<Id> rootGroupIds) {
        PublicGroupGraph graph = new PublicGroupGraph();
        loadMissingPublicGroups(graph, rootGroupIds);

        Set<Id> frontierGroupIds = new Set<Id>();
        frontierGroupIds.addAll(rootGroupIds);
        Integer depth = 0;
        while (!frontierGroupIds.isEmpty() && depth < MAX_PUBLIC_GROUP_DEPTH) {
            depth++;
            List<CommunicatorBroadcastAudienceService.AudienceGroupMemberRecord> members =
                dataProvider.getGroupMembersByGroupIds(frontierGroupIds, 50000);
            Set<Id> memberGroupIds = new Set<Id>();
            for (CommunicatorBroadcastAudienceService.AudienceGroupMemberRecord memberRecord : members) {
                if (memberRecord == null || memberRecord.groupId == null || memberRecord.memberId == null) continue;
                ensureMemberBucket(graph, memberRecord.groupId).add(memberRecord.memberId);
                if (memberRecord.memberId.getSObjectType() == Group.SObjectType &&
                    !graph.groupsById.containsKey(memberRecord.memberId)) {
                    memberGroupIds.add(memberRecord.memberId);
                }
            }
            if (memberGroupIds.isEmpty()) break;
            loadMissingPublicGroups(graph, memberGroupIds);
            frontierGroupIds = memberGroupIds;
        }
        return graph;
    }

    private static void loadMissingPublicGroups(PublicGroupGraph graph, Set<Id> groupIds) {
        if (graph == null || groupIds == null || groupIds.isEmpty()) return;
        Set<Id> missingGroupIds = new Set<Id>();
        for (Id groupId : groupIds) {
            if (groupId != null && !graph.groupsById.containsKey(groupId)) {
                missingGroupIds.add(groupId);
            }
        }
        if (missingGroupIds.isEmpty()) return;

        for (CommunicatorBroadcastAudienceService.AudienceGroupRecord groupRecord :
            dataProvider.getGroupsByIds(missingGroupIds)) {
            if (groupRecord != null && groupRecord.groupId != null) {
                graph.groupsById.put(groupRecord.groupId, groupRecord);
            }
        }
    }

    private static Boolean currentUserBelongsToPublicRoot(
        Id rootGroupId,
        PublicGroupGraph graph,
        CurrentUserContext context
    ) {
        if (rootGroupId == null || graph == null || context == null) return false;
        CommunicatorBroadcastAudienceService.AudienceGroupRecord rootGroup = graph.groupsById.get(rootGroupId);
        if (rootGroup == null || rootGroup.groupType != PUBLIC_GROUP_TYPE_REGULAR) return false;

        Set<Id> visitedGroupIds = new Set<Id>();
        Set<Id> frontierGroupIds = new Set<Id>{ rootGroupId };
        Integer depth = 0;
        while (!frontierGroupIds.isEmpty() && depth < MAX_PUBLIC_GROUP_DEPTH) {
            depth++;
            Set<Id> nextFrontierGroupIds = new Set<Id>();
            for (Id currentGroupId : frontierGroupIds) {
                if (!visitedGroupIds.add(currentGroupId)) continue;
                List<Id> memberIds = graph.memberIdsByGroup.get(currentGroupId);
                if (memberIds == null) continue;
                for (Id memberId : memberIds) {
                    if (memberId == context.currentUserId) return true;
                    if (memberId == null || memberId.getSObjectType() != Group.SObjectType) continue;
                    CommunicatorBroadcastAudienceService.AudienceGroupRecord memberGroup =
                        graph.groupsById.get(memberId);
                    if (memberGroup == null) continue;
                    if (isExpandablePublicGroupMember(memberGroup)) {
                        if (!visitedGroupIds.contains(memberGroup.groupId)) {
                            nextFrontierGroupIds.add(memberGroup.groupId);
                        }
                    } else if (currentUserMatchesSystemGroup(context, memberGroup)) {
                        return true;
                    }
                }
            }
            frontierGroupIds = nextFrontierGroupIds;
        }
        return false;
    }

    private static List<Id> ensureMemberBucket(PublicGroupGraph graph, Id groupId) {
        if (!graph.memberIdsByGroup.containsKey(groupId)) {
            graph.memberIdsByGroup.put(groupId, new List<Id>());
        }
        return graph.memberIdsByGroup.get(groupId);
    }

    private static Map<Id, AccessGroupRecord> loadGroups(Set<Id> groupIds) {
        Map<Id, AccessGroupRecord> result = new Map<Id, AccessGroupRecord>();
        if (groupIds == null || groupIds.isEmpty()) return result;
        for (AccessGroupRecord groupRecord : dataProvider.getBroadcastGroupsByIds(groupIds)) {
            if (groupRecord != null && groupRecord.groupId != null) {
                result.put(groupRecord.groupId, groupRecord);
            }
        }
        return result;
    }

    private static Map<Id, AccessMessageRecord> loadMessages(Set<Id> messageIds) {
        Map<Id, AccessMessageRecord> result = new Map<Id, AccessMessageRecord>();
        if (messageIds == null || messageIds.isEmpty()) return result;
        for (AccessMessageRecord messageRecord : dataProvider.getMessagesByIds(messageIds)) {
            if (messageRecord != null && messageRecord.messageId != null) {
                result.put(messageRecord.messageId, messageRecord);
            }
        }
        return result;
    }

    private static Map<Id, GroupAccessDecision> initializeGroupDecisions(Set<Id> groupIds) {
        Map<Id, GroupAccessDecision> result = new Map<Id, GroupAccessDecision>();
        if (groupIds == null || groupIds.isEmpty()) return result;
        for (Id groupId : groupIds) {
            GroupAccessDecision decision = new GroupAccessDecision();
            decision.groupId = groupId;
            result.put(groupId, decision);
        }
        return result;
    }

    private static Map<Id, MessageAccessDecision> initializeMessageDecisions(Set<Id> messageIds) {
        Map<Id, MessageAccessDecision> result = new Map<Id, MessageAccessDecision>();
        if (messageIds == null || messageIds.isEmpty()) return result;
        for (Id messageId : messageIds) {
            MessageAccessDecision decision = new MessageAccessDecision();
            decision.messageId = messageId;
            result.put(messageId, decision);
        }
        return result;
    }

    private static String normalizeAudienceType(String audienceType) {
        return String.isBlank(audienceType) ? null : audienceType.trim();
    }

    private static Id tryParseId(String rawId) {
        if (String.isBlank(rawId)) return null;
        try {
            return (Id) rawId.trim();
        } catch (Exception ex) {
            return null;
        }
    }

    private static CommunicatorBroadcastAudienceService.UserAudienceCategory classifyUser(
        CommunicatorBroadcastAudienceService.AudienceUserRecord userRecord
    ) {
        if (userRecord == null || userRecord.isActive != true) {
            return CommunicatorBroadcastAudienceService.UserAudienceCategory.UNSUPPORTED;
        }
        if (userRecord.userType == 'Standard' && userRecord.licenseName == 'Salesforce') {
            return CommunicatorBroadcastAudienceService.UserAudienceCategory.CORE_SALESFORCE;
        }
        if (userRecord.userType == 'Standard' && userRecord.licenseName == 'Salesforce Platform') {
            return CommunicatorBroadcastAudienceService.UserAudienceCategory.CORE_PLATFORM;
        }
        if (userRecord.userType == 'PowerPartner' &&
            (userRecord.licenseName == 'Partner Community' ||
             userRecord.licenseName == 'Partner Community Login')) {
            return CommunicatorBroadcastAudienceService.UserAudienceCategory.COMMUNITY_PARTNER;
        }
        return CommunicatorBroadcastAudienceService.UserAudienceCategory.UNSUPPORTED;
    }

    private static Boolean isSupportedActiveUser(CurrentUserContext context) {
        return context != null &&
            context.isActive == true &&
            context.category != CommunicatorBroadcastAudienceService.UserAudienceCategory.UNSUPPORTED;
    }

    private static Boolean isCore(CurrentUserContext context) {
        return context != null &&
            (context.category == CommunicatorBroadcastAudienceService.UserAudienceCategory.CORE_SALESFORCE ||
             context.category == CommunicatorBroadcastAudienceService.UserAudienceCategory.CORE_PLATFORM);
    }

    private static Boolean isCommunityPartner(CurrentUserContext context) {
        return context != null &&
            context.category == CommunicatorBroadcastAudienceService.UserAudienceCategory.COMMUNITY_PARTNER;
    }

    private static Boolean roleContainsCurrentUser(Id rootRoleId, CurrentUserContext context) {
        if (rootRoleId == null || context == null || context.userRoleId == null) return false;
        Set<Id> roleIds = context.roleHierarchyByRoot.get(rootRoleId);
        return roleIds != null && roleIds.contains(context.userRoleId);
    }

    private static Boolean isExpandablePublicGroupMember(
        CommunicatorBroadcastAudienceService.AudienceGroupRecord groupRecord
    ) {
        return groupRecord != null &&
            (groupRecord.groupType == PUBLIC_GROUP_TYPE_REGULAR ||
             groupRecord.groupType == PUBLIC_GROUP_TYPE_QUEUE);
    }

    private static Boolean isRolePublicGroupMember(
        CommunicatorBroadcastAudienceService.AudienceGroupRecord groupRecord
    ) {
        return groupRecord != null &&
            (groupRecord.groupType == PUBLIC_GROUP_TYPE_ROLE ||
             groupRecord.groupType == PUBLIC_GROUP_TYPE_ROLE_AND_SUBORDINATES ||
             groupRecord.groupType == PUBLIC_GROUP_TYPE_ROLE_AND_SUBORDINATES_INTERNAL ||
             groupRecord.groupType == PUBLIC_GROUP_TYPE_ROLE_AND_SUBORDINATES_PORTAL ||
             groupRecord.groupType == PUBLIC_GROUP_TYPE_ROLE_AND_SUBORDINATES_INTERNAL_AND_PORTAL);
    }

    private static Boolean currentUserMatchesSystemGroup(
        CurrentUserContext context,
        CommunicatorBroadcastAudienceService.AudienceGroupRecord groupRecord
    ) {
        if (context == null || context.userRoleId == null || groupRecord == null || groupRecord.relatedId == null) {
            return false;
        }
        if (groupRecord.groupType == PUBLIC_GROUP_TYPE_ROLE) {
            return context.userRoleId == groupRecord.relatedId;
        }
        if (groupRecord.groupType == PUBLIC_GROUP_TYPE_ROLE_AND_SUBORDINATES) {
            return roleContainsCurrentUser(groupRecord.relatedId, context);
        }
        if (groupRecord.groupType == PUBLIC_GROUP_TYPE_ROLE_AND_SUBORDINATES_INTERNAL) {
            return isCore(context) && roleContainsCurrentUser(groupRecord.relatedId, context);
        }
        if (groupRecord.groupType == PUBLIC_GROUP_TYPE_ROLE_AND_SUBORDINATES_PORTAL) {
            return isCommunityPartner(context) && roleContainsCurrentUser(groupRecord.relatedId, context);
        }
        if (groupRecord.groupType == PUBLIC_GROUP_TYPE_ROLE_AND_SUBORDINATES_INTERNAL_AND_PORTAL) {
            return roleContainsCurrentUser(groupRecord.relatedId, context);
        }
        return false;
    }
}