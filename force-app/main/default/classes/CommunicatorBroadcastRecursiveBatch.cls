public without sharing class CommunicatorBroadcastRecursiveBatch
implements Database.Batchable<SObject>, Database.Stateful {

    private static final String AUDIENCE_TYPE_ROLE_INTERNAL = 'RoleAndSubordinatesInternal';
    private static final String AUDIENCE_TYPE_ROLE_PORTAL = 'RoleAndSubordinatesPortal';
    private static final String AUDIENCE_TYPE_ROLE_INTERNAL_PORTAL =
        'RoleAndSubordinatesInternalAndPortal';
    private static final String AUDIENCE_TYPE_PUBLIC_GROUP = 'PublicGroup';
    private static final String AUDIENCE_TYPE_JOB_TITLE_AND_SUBORDINATES =
        'JobTitleAndSubordinates';
    private static final String MODE_ALL = 'ALL';
    private static final String MODE_INTERNAL = 'INTERNAL';
    private static final String MODE_PORTAL = 'PORTAL';
    private static final String MODE_EXACT = 'EXACT';
    private static final Integer DEFAULT_ROLE_HIERARCHY_ROLE_CHUNK_SIZE = 200;
    private static final Integer DEFAULT_PUBLIC_GROUP_FRONTIER_CHUNK_SIZE = 200;
    private static final Integer DEFAULT_JOB_TITLE_FRONTIER_CHUNK_SIZE = 200;
    private static final String INVALID_SCOPE_ERROR =
        'O scope atual do executor recursivo e incompativel com o criterio do snapshot.';
    private static final String INVALID_CRITERION_ERROR =
        'O criterio atual do snapshot do comunicado esta invalido para a distribuicao.';
    private static final String PUBLIC_GROUP_INVALID_MESSAGE =
        'O grupo publico selecionado nao e valido.';
    private static final String PUBLIC_GROUP_UNSUPPORTED_MEMBER_MESSAGE_PREFIX =
        'O grupo publico selecionado contem um tipo de membro nao suportado: ';
    private static final String PUBLIC_GROUP_UNSUPPORTED_MEMBER_MESSAGE_SUFFIX =
        '. Revise a composicao do grupo antes de publicar.';
    private static final String PUBLIC_GROUP_INVALID_ROLE_MEMBER_MESSAGE =
        'O grupo publico selecionado contem uma regra de papel invalida. Revise a composicao do grupo antes de publicar.';
    private static final String INVALID_CONTINUATION_STATE_ERROR =
        'Nao foi possivel continuar a distribuicao porque o estado recursivo nao apresentou progresso.';
    private static final String HANDOFF_OWNERSHIP_LOST_ERROR =
        'Nao foi possivel continuar a distribuicao porque o JobId ativo mudou durante o handoff recursivo.';
    @TestVisible
    private static Integer roleHierarchyRoleChunkSizeOverride;
    @TestVisible
    private static Integer publicGroupFrontierChunkSizeOverride;
    @TestVisible
    private static Integer jobTitleFrontierChunkSizeOverride;

    private final Id messageId;
    private final Id threadId;
    private final Id senderId;
    private final Integer criterionIndex;
    private final String audienceType;
    private final String targetId;
    private Integer traversalDepth;
    private Set<Id> frontierIds;
    private Set<Id> visitedIds;
    private Set<Id> deferredNextFrontierIds;
    private Set<Id> activeFrontierIds = new Set<Id>();
    private Integer publicGroupProcessedMemberCount;

    private Boolean staleJob = false;
    private Boolean criticalFailure = false;
    private String criticalErrorMessage;

    private Set<Id> nextFrontierIds = new Set<Id>();

    private class RoleAudienceRequest {
        Id rootRoleId;
        String mode;
        Boolean exact;

        RoleAudienceRequest(Id rootRoleId, String mode, Boolean exact) {
            this.rootRoleId = rootRoleId;
            this.mode = mode;
            this.exact = exact;
        }
    }

    public class ContinuationStateSnapshot {
        public Boolean shouldContinue = false;
        public Boolean terminalSuccess = false;
        public Integer nextTraversalDepth;
        public Set<Id> nextFrontierIds = new Set<Id>();
        public Set<Id> nextVisitedIds = new Set<Id>();
        public Set<Id> nextDeferredNextFrontierIds = new Set<Id>();
        public Integer nextPublicGroupProcessedMemberCount = 0;
    }

    public CommunicatorBroadcastRecursiveBatch(
        Id messageId,
        Id threadId,
        Id senderId,
        Integer criterionIndex,
        String audienceType,
        String targetId
    ) {
        this(messageId, threadId, senderId, criterionIndex, audienceType, targetId, 0, null, null, null, 0);
    }

    public CommunicatorBroadcastRecursiveBatch(
        Id messageId,
        Id threadId,
        Id senderId,
        Integer criterionIndex,
        String audienceType,
        String targetId,
        Integer traversalDepth,
        Set<Id> frontierIds,
        Set<Id> visitedIds,
        Set<Id> deferredNextFrontierIds,
        Integer publicGroupProcessedMemberCount
    ) {
        this.messageId = messageId;
        this.threadId = threadId;
        this.senderId = senderId;
        this.criterionIndex = criterionIndex == null ? 0 : criterionIndex;
        this.audienceType = audienceType;
        this.targetId = targetId;
        this.traversalDepth = traversalDepth == null || traversalDepth < 0 ? 0 : traversalDepth;
        this.frontierIds = cloneIds(frontierIds);
        this.visitedIds = cloneIds(visitedIds);
        this.deferredNextFrontierIds = cloneIds(deferredNextFrontierIds);
        this.publicGroupProcessedMemberCount = publicGroupProcessedMemberCount == null ||
            publicGroupProcessedMemberCount < 0
            ? 0
            : publicGroupProcessedMemberCount;
    }

    public Database.QueryLocator start(Database.BatchableContext context) {
        CommunicatorBroadcastDistributionService.PhaseOneExecutionState state =
            CommunicatorBroadcastDistributionService.validatePhaseOneExecution(
                messageId,
                threadId,
                senderId,
                context == null ? null : context.getJobId(),
                criterionIndex,
                audienceType,
                targetId
            );
        staleJob = state.staleJob == true;
        criticalFailure = state.ready != true && state.staleJob != true;
        criticalErrorMessage = state.safeErrorMessage;
        if (staleJob || criticalFailure) {
            return emptyUserQueryLocator();
        }

        try {
            if (audienceType == AUDIENCE_TYPE_ROLE_INTERNAL ||
                audienceType == AUDIENCE_TYPE_ROLE_PORTAL ||
                audienceType == AUDIENCE_TYPE_ROLE_INTERNAL_PORTAL) {
                return startRoleHierarchyScope();
            }
            if (audienceType == AUDIENCE_TYPE_PUBLIC_GROUP) {
                return startPublicGroupScope();
            }
            if (audienceType == AUDIENCE_TYPE_JOB_TITLE_AND_SUBORDINATES) {
                return startJobTitleHierarchyScope();
            }
            criticalFailure = true;
            criticalErrorMessage = INVALID_CRITERION_ERROR;
        } catch (Exception ex) {
            criticalFailure = true;
            criticalErrorMessage =
                CommunicatorBroadcastDistributionService.normalizeSafeErrorMessage(ex);
        }
        return emptyUserQueryLocator();
    }

    public void execute(Database.BatchableContext context, List<SObject> scope) {
        if (staleJob || criticalFailure || scope == null || scope.isEmpty()) return;

        CommunicatorBroadcastDistributionService.PhaseOneExecutionState state =
            CommunicatorBroadcastDistributionService.validatePhaseOneExecution(
                messageId,
                threadId,
                senderId,
                context == null ? null : context.getJobId(),
                criterionIndex,
                audienceType,
                targetId
            );
        if (state.staleJob == true) {
            staleJob = true;
            return;
        }
        if (state.ready != true) {
            criticalFailure = true;
            criticalErrorMessage = state.safeErrorMessage;
            return;
        }

        try {
            if (audienceType == AUDIENCE_TYPE_PUBLIC_GROUP) {
                executePublicGroupScope(scope);
            } else if (audienceType == AUDIENCE_TYPE_JOB_TITLE_AND_SUBORDINATES) {
                executeJobTitleHierarchyScope(scope);
            } else {
                executeRoleHierarchyScope(scope);
            }
        } catch (Exception ex) {
            criticalFailure = true;
            criticalErrorMessage =
                CommunicatorBroadcastDistributionService.normalizeSafeErrorMessage(ex);
        }
    }

    public void finish(Database.BatchableContext context) {
        if (staleJob) return;
        if (criticalFailure) {
            CommunicatorBroadcastDistributionService.finalizePhaseOneFailure(
                messageId,
                criterionIndex,
                context == null ? null : context.getJobId(),
                criticalErrorMessage,
                audienceType,
                targetId
            );
            return;
        }

        try {
            ContinuationStateSnapshot continuationState = buildContinuationState(
                audienceType,
                traversalDepth,
                frontierIds,
                activeFrontierIds,
                visitedIds,
                deferredNextFrontierIds,
                nextFrontierIds,
                publicGroupProcessedMemberCount
            );
            if (continuationState.shouldContinue == true) {
                handOffToNextRecursiveBatch(
                    context,
                    continuationState.nextTraversalDepth,
                    continuationState.nextFrontierIds,
                    continuationState.nextVisitedIds,
                    continuationState.nextDeferredNextFrontierIds,
                    continuationState.nextPublicGroupProcessedMemberCount
                );
                return;
            }
            if (continuationState.terminalSuccess == true) {
                CommunicatorBroadcastDistributionService.finalizePhaseOneSuccess(
                    messageId,
                    criterionIndex,
                    context == null ? null : context.getJobId(),
                    audienceType,
                    targetId
                );
                return;
            }
        } catch (Exception ex) {
            CommunicatorBroadcastDistributionService.finalizePhaseOneFailure(
                messageId,
                criterionIndex,
                context == null ? null : context.getJobId(),
                CommunicatorBroadcastDistributionService.normalizeSafeErrorMessage(ex),
                audienceType,
                targetId
            );
            return;
        }

        CommunicatorBroadcastDistributionService.finalizePhaseOneSuccess(
            messageId,
            criterionIndex,
            context == null ? null : context.getJobId(),
            audienceType,
            targetId
        );
    }

    private Database.QueryLocator startRoleHierarchyScope() {
        Id rootRoleId = tryParseId(targetId, UserRole.SObjectType);
        if (rootRoleId == null) {
            criticalFailure = true;
            criticalErrorMessage = INVALID_CRITERION_ERROR;
            return emptyUserQueryLocator();
        }

        if (frontierIds == null || frontierIds.isEmpty()) {
            Map<Id, Set<Id>> hierarchyByRoot =
                CommunicatorBroadcastAudienceService.getAsyncRoleAndDescendantIdsByRoot(
                    new Set<Id>{ rootRoleId }
                );
            Set<Id> resolvedRoleIds = hierarchyByRoot.get(rootRoleId);
            if (resolvedRoleIds == null || resolvedRoleIds.isEmpty()) {
                criticalFailure = true;
                criticalErrorMessage = INVALID_CRITERION_ERROR;
                return emptyUserQueryLocator();
            }
            frontierIds = cloneIds(resolvedRoleIds);
        }

        activeFrontierIds = takeNextIds(frontierIds, roleHierarchyRoleChunkSize());
        if (activeFrontierIds.isEmpty()) return emptyUserQueryLocator();
        return Database.getQueryLocator([
            SELECT Id
            FROM User
            WHERE IsActive = true
            AND UserRoleId IN :activeFrontierIds
        ]);
    }

    private Database.QueryLocator startPublicGroupScope() {
        if (frontierIds == null || frontierIds.isEmpty()) {
            Id rootGroupId = tryParseId(targetId, Group.SObjectType);
            if (rootGroupId == null) {
                criticalFailure = true;
                criticalErrorMessage = PUBLIC_GROUP_INVALID_MESSAGE;
                return emptyUserQueryLocator();
            }
            frontierIds = new Set<Id>{ rootGroupId };
        }

        activeFrontierIds = takeNextIds(frontierIds, publicGroupFrontierChunkSize());
        if (activeFrontierIds.isEmpty()) return emptyUserQueryLocator();

        Map<Id, CommunicatorBroadcastAudienceService.AudienceGroupRecord> groupsById =
            loadGroupsById(activeFrontierIds);
        for (Id groupId : activeFrontierIds) {
            CommunicatorBroadcastAudienceService.AudienceGroupRecord groupRecord = groupsById.get(groupId);
            if (groupRecord == null) {
                criticalFailure = true;
                criticalErrorMessage = PUBLIC_GROUP_INVALID_MESSAGE;
                return emptyUserQueryLocator();
            }
            if (traversalDepth == 0 && groupRecord.groupType != 'Regular') {
                criticalFailure = true;
                criticalErrorMessage = PUBLIC_GROUP_INVALID_MESSAGE;
                return emptyUserQueryLocator();
            }
            if (traversalDepth > 0 &&
                groupRecord.groupType != 'Regular' &&
                groupRecord.groupType != 'Queue') {
                criticalFailure = true;
                criticalErrorMessage = PUBLIC_GROUP_INVALID_MESSAGE;
                return emptyUserQueryLocator();
            }
        }

        visitedIds.addAll(activeFrontierIds);
        return Database.getQueryLocator([
            SELECT GroupId, UserOrGroupId
            FROM GroupMember
            WHERE GroupId IN :activeFrontierIds
        ]);
    }

    private Database.QueryLocator startJobTitleHierarchyScope() {
        if (frontierIds == null || frontierIds.isEmpty()) {
            Id rootJobTitleId = tryParseId(targetId, CargosDepartamentos__c.SObjectType);
            if (rootJobTitleId == null) {
                criticalFailure = true;
                criticalErrorMessage = INVALID_CRITERION_ERROR;
                return emptyContactQueryLocator();
            }
            return Database.getQueryLocator([
                SELECT Id
                FROM Contact
                WHERE Cargo__c = :rootJobTitleId
            ]);
        }

        activeFrontierIds = takeNextIds(frontierIds, jobTitleFrontierChunkSize());
        if (activeFrontierIds.isEmpty()) return emptyContactQueryLocator();
        return Database.getQueryLocator([
            SELECT Id
            FROM Contact
            WHERE ReportsToId IN :activeFrontierIds
        ]);
    }

    private void executeRoleHierarchyScope(List<SObject> scope) {
        assertScopeRecordType(scope, User.SObjectType);
        Set<Id> scopeUserIds = new Set<Id>();
        for (SObject recordItem : scope) {
            Id userId = (Id) recordItem.get('Id');
            if (userId != null && userId != senderId) {
                scopeUserIds.add(userId);
            }
        }
        if (scopeUserIds.isEmpty()) return;

        Map<Id, CommunicatorBroadcastAudienceService.UserAudienceCategory> categories =
            CommunicatorBroadcastAudienceService.classifyUsers(scopeUserIds);
        Set<Id> recipients = new Set<Id>();
        String roleMode = resolveRecursiveAudienceMode(audienceType);
        for (Id userId : scopeUserIds) {
            if (acceptsRoleMode(roleMode, categories.get(userId))) {
                recipients.add(userId);
            }
        }
        createBroadcastNotifications(recipients);
    }

    @TestVisible
    private void executeRoleHierarchyScopeForTest(List<User> scope) {
        List<SObject> records = new List<SObject>();
        if (scope != null) records.addAll(scope);
        executeRoleHierarchyScope(records);
    }

    private void executePublicGroupScope(List<SObject> scope) {
        assertScopeRecordType(scope, GroupMember.SObjectType);
        publicGroupProcessedMemberCount += scope.size();

        Set<Id> directUserIds = new Set<Id>();
        Set<Id> memberGroupIds = new Set<Id>();
        for (SObject recordItem : scope) {
            Id memberId = (Id) recordItem.get('UserOrGroupId');
            if (memberId == null) continue;
            if (memberId.getSObjectType() == User.SObjectType) {
                if (memberId != senderId) {
                    directUserIds.add(memberId);
                }
                continue;
            }
            if (memberId.getSObjectType() != Group.SObjectType) {
                throw unsupportedPublicGroupMemberException('Id');
            }
            memberGroupIds.add(memberId);
        }

        createNotificationsForDirectUsers(directUserIds);

        Map<Id, CommunicatorBroadcastAudienceService.AudienceGroupRecord> memberGroupsById =
            loadGroupsById(memberGroupIds);
        List<RoleAudienceRequest> roleRequests = new List<RoleAudienceRequest>();
        for (Id memberGroupId : memberGroupIds) {
            CommunicatorBroadcastAudienceService.AudienceGroupRecord memberGroup =
                memberGroupsById.get(memberGroupId);
            if (memberGroup == null) {
                throw unsupportedPublicGroupMemberException('desconhecido');
            }
            if (memberGroup.groupType == 'Regular' || memberGroup.groupType == 'Queue') {
                if (!visitedIds.contains(memberGroup.groupId) &&
                    !frontierIds.contains(memberGroup.groupId) &&
                    !deferredNextFrontierIds.contains(memberGroup.groupId)) {
                    nextFrontierIds.add(memberGroup.groupId);
                }
                continue;
            }

            if (memberGroup.groupType == 'Role') {
                assertValidPublicGroupRoleMember(memberGroup);
                roleRequests.add(new RoleAudienceRequest(memberGroup.relatedId, MODE_EXACT, true));
                continue;
            }
            if (memberGroup.groupType == 'RoleAndSubordinates') {
                assertValidPublicGroupRoleMember(memberGroup);
                roleRequests.add(new RoleAudienceRequest(memberGroup.relatedId, MODE_ALL, false));
                continue;
            }
            if (memberGroup.groupType == 'RoleAndSubordinatesInternal') {
                assertValidPublicGroupRoleMember(memberGroup);
                roleRequests.add(new RoleAudienceRequest(memberGroup.relatedId, MODE_INTERNAL, false));
                continue;
            }
            if (memberGroup.groupType == 'RoleAndSubordinatesPortal') {
                assertValidPublicGroupRoleMember(memberGroup);
                roleRequests.add(new RoleAudienceRequest(memberGroup.relatedId, MODE_PORTAL, false));
                continue;
            }
            if (memberGroup.groupType == 'RoleAndSubordinatesInternalAndPortal') {
                assertValidPublicGroupRoleMember(memberGroup);
                roleRequests.add(new RoleAudienceRequest(memberGroup.relatedId, MODE_ALL, false));
                continue;
            }
            throw unsupportedPublicGroupMemberException(memberGroup.groupType);
        }

        createNotificationsForRoleRequests(roleRequests);
    }

    @TestVisible
    private void executePublicGroupScopeForTest(List<GroupMember> scope) {
        List<SObject> records = new List<SObject>();
        if (scope != null) records.addAll(scope);
        executePublicGroupScope(records);
    }

    private void executeJobTitleHierarchyScope(List<SObject> scope) {
        assertScopeRecordType(scope, Contact.SObjectType);
        Set<Id> currentLevelContactIds = new Set<Id>();
        for (SObject recordItem : scope) {
            Id contactId = (Id) recordItem.get('Id');
            if (contactId == null || visitedIds.contains(contactId)) continue;
            currentLevelContactIds.add(contactId);
            visitedIds.add(contactId);
            nextFrontierIds.add(contactId);
        }
        if (currentLevelContactIds.isEmpty()) return;

        List<CommunicatorBroadcastAudienceService.AudienceContactRecord> activeUserContacts =
            CommunicatorBroadcastAudienceService.getAsyncActiveUserContactsByIds(
                currentLevelContactIds,
                currentLevelContactIds.size()
            );
        Set<Id> recipients = new Set<Id>();
        for (CommunicatorBroadcastAudienceService.AudienceContactRecord contactRecord : activeUserContacts) {
            if (contactRecord == null || contactRecord.usuarioId == null || contactRecord.usuarioId == senderId) {
                continue;
            }
            if (!currentLevelContactIds.contains(contactRecord.contactId)) continue;
            if (isSupportedCategory(classifyContactUser(contactRecord))) {
                recipients.add(contactRecord.usuarioId);
            }
        }
        createBroadcastNotifications(recipients);
    }

    @TestVisible
    private void executeJobTitleHierarchyScopeForTest(List<Contact> scope) {
        List<SObject> records = new List<SObject>();
        if (scope != null) records.addAll(scope);
        executeJobTitleHierarchyScope(records);
    }

    private void handOffToNextRecursiveBatch(
        Database.BatchableContext context,
        Integer nextTraversalDepth,
        Set<Id> nextFrontierIds,
        Set<Id> nextVisitedIds,
        Set<Id> nextDeferredNextFrontierIds,
        Integer nextPublicGroupProcessedMemberCount
    ) {
        Id nextJobId = Database.executeBatch(
            new CommunicatorBroadcastRecursiveBatch(
                messageId,
                threadId,
                senderId,
                criterionIndex,
                audienceType,
                targetId,
                nextTraversalDepth,
                nextFrontierIds,
                nextVisitedIds,
                nextDeferredNextFrontierIds,
                nextPublicGroupProcessedMemberCount
            ),
            100
        );
        Boolean ownershipTransferred = CommunicatorBroadcastDistributionService.replaceActivePhaseOneJob(
            messageId,
            criterionIndex,
            context == null ? null : context.getJobId(),
            nextJobId,
            audienceType,
            targetId
        );
        if (ownershipTransferred != true) {
            throw new CommunicatorException(HANDOFF_OWNERSHIP_LOST_ERROR);
        }
    }

    @TestVisible
    private void handOffToNextRecursiveBatchForTest(
        Id currentJobId,
        Id nextJobId,
        Integer nextTraversalDepth,
        Set<Id> nextFrontierIds,
        Set<Id> nextVisitedIds,
        Set<Id> nextDeferredNextFrontierIds,
        Integer nextPublicGroupProcessedMemberCount
    ) {
        Boolean ownershipTransferred = CommunicatorBroadcastDistributionService.replaceActivePhaseOneJob(
            messageId,
            criterionIndex,
            currentJobId,
            nextJobId,
            audienceType,
            targetId
        );
        if (ownershipTransferred != true) {
            throw new CommunicatorException(HANDOFF_OWNERSHIP_LOST_ERROR);
        }
    }

    private void createNotificationsForDirectUsers(Set<Id> directUserIds) {
        if (directUserIds == null || directUserIds.isEmpty()) return;
        Map<Id, CommunicatorBroadcastAudienceService.UserAudienceCategory> categories =
            CommunicatorBroadcastAudienceService.classifyUsers(directUserIds);
        Set<Id> recipients = new Set<Id>();
        for (Id userId : directUserIds) {
            if (isSupportedCategory(categories.get(userId))) {
                recipients.add(userId);
            }
        }
        createBroadcastNotifications(recipients);
    }

    private void createNotificationsForRoleRequests(List<RoleAudienceRequest> roleRequests) {
        if (roleRequests == null || roleRequests.isEmpty()) return;
        Set<Id> rootRoleIds = new Set<Id>();
        for (RoleAudienceRequest request : roleRequests) {
            if (request != null && request.rootRoleId != null) {
                rootRoleIds.add(request.rootRoleId);
            }
        }
        if (rootRoleIds.isEmpty()) return;

        Map<Id, Set<Id>> hierarchyByRoot =
            CommunicatorBroadcastAudienceService.getAsyncRoleAndDescendantIdsByRoot(rootRoleIds);
        Map<Id, Set<Id>> roleIdsByRequestRoot = new Map<Id, Set<Id>>();
        Set<Id> queriedRoleIds = new Set<Id>();
        for (RoleAudienceRequest request : roleRequests) {
            if (request == null || request.rootRoleId == null) continue;
            if (request.exact == true) {
                roleIdsByRequestRoot.put(request.rootRoleId, new Set<Id>{ request.rootRoleId });
                queriedRoleIds.add(request.rootRoleId);
                continue;
            }
            Set<Id> resolvedRoleIds = hierarchyByRoot.get(request.rootRoleId);
            if (resolvedRoleIds == null || resolvedRoleIds.isEmpty()) {
                throw new CommunicatorException(PUBLIC_GROUP_INVALID_ROLE_MEMBER_MESSAGE);
            }
            Set<Id> copiedRoleIds = new Set<Id>();
            copiedRoleIds.addAll(resolvedRoleIds);
            roleIdsByRequestRoot.put(request.rootRoleId, copiedRoleIds);
            queriedRoleIds.addAll(resolvedRoleIds);
        }
        Map<Id, List<CommunicatorBroadcastAudienceService.AudienceUserRecord>> usersByRoleId =
            new Map<Id, List<CommunicatorBroadcastAudienceService.AudienceUserRecord>>();
        Set<Id> candidateUserIds = new Set<Id>();
        List<Set<Id>> queriedRoleChunks = chunkIds(queriedRoleIds, roleHierarchyRoleChunkSize());
        for (Set<Id> queriedRoleChunk : queriedRoleChunks) {
            for (CommunicatorBroadcastAudienceService.AudienceUserRecord userRecord :
                CommunicatorBroadcastAudienceService.getAsyncActiveUsersByRoleIds(queriedRoleChunk)) {
                if (userRecord == null || userRecord.userId == null || userRecord.userRoleId == null) continue;
                candidateUserIds.add(userRecord.userId);
                if (!usersByRoleId.containsKey(userRecord.userRoleId)) {
                    usersByRoleId.put(userRecord.userRoleId, new List<CommunicatorBroadcastAudienceService.AudienceUserRecord>());
                }
                usersByRoleId.get(userRecord.userRoleId).add(userRecord);
            }
        }

        Map<Id, CommunicatorBroadcastAudienceService.UserAudienceCategory> categories =
            CommunicatorBroadcastAudienceService.classifyUsers(candidateUserIds);
        Set<Id> recipients = new Set<Id>();
        for (RoleAudienceRequest request : roleRequests) {
            if (request == null || request.rootRoleId == null) continue;
            Set<Id> resolvedRoleIds = roleIdsByRequestRoot.get(request.rootRoleId);
            if (resolvedRoleIds == null || resolvedRoleIds.isEmpty()) continue;
            for (Id roleId : resolvedRoleIds) {
                List<CommunicatorBroadcastAudienceService.AudienceUserRecord> roleUsers =
                    usersByRoleId.get(roleId);
                if (roleUsers == null) continue;
                for (CommunicatorBroadcastAudienceService.AudienceUserRecord userRecord : roleUsers) {
                    if (userRecord == null || userRecord.userId == null || userRecord.userId == senderId) continue;
                    if (acceptsRoleMode(request.mode, categories.get(userRecord.userId))) {
                        recipients.add(userRecord.userId);
                    }
                }
            }
        }
        createBroadcastNotifications(recipients);
    }

    private void createBroadcastNotifications(Set<Id> recipientIds) {
        if (recipientIds == null || recipientIds.isEmpty()) return;
        Savepoint savepoint = Database.setSavepoint();
        try {
            CommunicatorNotificationRecordService.createBroadcastNotificationsIfMissing(
                messageId,
                threadId,
                recipientIds
            );
        } catch (Exception ex) {
            Database.rollback(savepoint);
            throw ex;
        }
    }

    @TestVisible
    private static Map<Id, CommunicatorBroadcastAudienceService.AudienceGroupRecord> loadGroupsById(
        Set<Id> groupIds
    ) {
        Map<Id, CommunicatorBroadcastAudienceService.AudienceGroupRecord> result =
            new Map<Id, CommunicatorBroadcastAudienceService.AudienceGroupRecord>();
        for (CommunicatorBroadcastAudienceService.AudienceGroupRecord groupRecord :
            CommunicatorBroadcastAudienceService.getAsyncAudienceGroupsByIds(groupIds)) {
            if (groupRecord != null && groupRecord.groupId != null) {
                result.put(groupRecord.groupId, groupRecord);
            }
        }
        return result;
    }

    @TestVisible
    private static CommunicatorBroadcastAudienceService.UserAudienceCategory classifyContactUser(
        CommunicatorBroadcastAudienceService.AudienceContactRecord contactRecord
    ) {
        if (contactRecord == null ||
            contactRecord.usuarioId == null ||
            contactRecord.usuarioIsActive != true) {
            return CommunicatorBroadcastAudienceService.UserAudienceCategory.UNSUPPORTED;
        }
        if (contactRecord.usuarioType == 'Standard' &&
            contactRecord.usuarioLicenseName == 'Salesforce') {
            return CommunicatorBroadcastAudienceService.UserAudienceCategory.CORE_SALESFORCE;
        }
        if (contactRecord.usuarioType == 'Standard' &&
            contactRecord.usuarioLicenseName == 'Salesforce Platform') {
            return CommunicatorBroadcastAudienceService.UserAudienceCategory.CORE_PLATFORM;
        }
        if (contactRecord.usuarioType == 'PowerPartner' &&
            (contactRecord.usuarioLicenseName == 'Partner Community' ||
             contactRecord.usuarioLicenseName == 'Partner Community Login')) {
            return CommunicatorBroadcastAudienceService.UserAudienceCategory.COMMUNITY_PARTNER;
        }
        return CommunicatorBroadcastAudienceService.UserAudienceCategory.UNSUPPORTED;
    }

    @TestVisible
    private static Boolean acceptsRoleMode(
        String mode,
        CommunicatorBroadcastAudienceService.UserAudienceCategory category
    ) {
        if (!isSupportedCategory(category)) return false;
        if (mode == MODE_INTERNAL) {
            return category == CommunicatorBroadcastAudienceService.UserAudienceCategory.CORE_SALESFORCE ||
                category == CommunicatorBroadcastAudienceService.UserAudienceCategory.CORE_PLATFORM;
        }
        if (mode == MODE_PORTAL) {
            return category == CommunicatorBroadcastAudienceService.UserAudienceCategory.COMMUNITY_PARTNER;
        }
        return true;
    }

    private static Boolean isSupportedCategory(
        CommunicatorBroadcastAudienceService.UserAudienceCategory category
    ) {
        return category == CommunicatorBroadcastAudienceService.UserAudienceCategory.CORE_SALESFORCE ||
            category == CommunicatorBroadcastAudienceService.UserAudienceCategory.CORE_PLATFORM ||
            category == CommunicatorBroadcastAudienceService.UserAudienceCategory.COMMUNITY_PARTNER;
    }

    @TestVisible
    private static String resolveRecursiveAudienceMode(String audienceType) {
        if (audienceType == AUDIENCE_TYPE_ROLE_INTERNAL) return MODE_INTERNAL;
        if (audienceType == AUDIENCE_TYPE_ROLE_PORTAL) return MODE_PORTAL;
        return MODE_ALL;
    }

    @TestVisible
    private static void assertValidPublicGroupRoleMember(
        CommunicatorBroadcastAudienceService.AudienceGroupRecord groupRecord
    ) {
        if (groupRecord == null ||
            groupRecord.relatedId == null ||
            groupRecord.relatedId.getSObjectType() != UserRole.SObjectType) {
            throw new CommunicatorException(PUBLIC_GROUP_INVALID_ROLE_MEMBER_MESSAGE);
        }
    }

    @TestVisible
    private static CommunicatorException unsupportedPublicGroupMemberException(String groupType) {
        String safeType = String.isBlank(groupType) ? 'desconhecido' : groupType.trim();
        return new CommunicatorException(
            PUBLIC_GROUP_UNSUPPORTED_MEMBER_MESSAGE_PREFIX +
            safeType +
            PUBLIC_GROUP_UNSUPPORTED_MEMBER_MESSAGE_SUFFIX
        );
    }

    @TestVisible
    private static void assertScopeRecordType(List<SObject> scope, Schema.SObjectType expectedType) {
        if (scope == null || scope.isEmpty() || expectedType == null) return;
        for (SObject recordItem : scope) {
            if (recordItem == null || recordItem.getSObjectType() != expectedType) {
                throw new CommunicatorException(INVALID_SCOPE_ERROR);
            }
        }
    }

    private static Database.QueryLocator emptyUserQueryLocator() {
        return Database.getQueryLocator([
            SELECT Id
            FROM User
            WHERE Id = null
        ]);
    }

    private static Database.QueryLocator emptyContactQueryLocator() {
        return Database.getQueryLocator([
            SELECT Id
            FROM Contact
            WHERE Id = null
        ]);
    }

    private static Set<Id> cloneIds(Set<Id> sourceIds) {
        Set<Id> result = new Set<Id>();
        if (sourceIds != null) {
            result.addAll(sourceIds);
        }
        return result;
    }

    private static Set<Id> mergedIds(Set<Id> firstIds, Set<Id> secondIds) {
        Set<Id> result = cloneIds(firstIds);
        if (secondIds != null) {
            result.addAll(secondIds);
        }
        return result;
    }

    private static Set<Id> takeNextIds(Set<Id> sourceIds, Integer chunkSize) {
        Set<Id> result = new Set<Id>();
        if (sourceIds == null || sourceIds.isEmpty()) return result;
        Integer effectiveChunkSize = normalizeChunkSize(chunkSize, 1);
        List<Id> sourceList = sortIds(sourceIds);
        for (Id sourceId : sourceList) {
            if (result.size() >= effectiveChunkSize) break;
            result.add(sourceId);
        }
        sourceIds.removeAll(result);
        return result;
    }

    private static List<Set<Id>> chunkIds(Set<Id> sourceIds, Integer chunkSize) {
        List<Set<Id>> chunks = new List<Set<Id>>();
        if (sourceIds == null || sourceIds.isEmpty()) return chunks;
        Integer effectiveChunkSize = normalizeChunkSize(chunkSize, 1);
        Set<Id> currentChunk = new Set<Id>();
        for (Id sourceId : sortIds(sourceIds)) {
            currentChunk.add(sourceId);
            if (currentChunk.size() >= effectiveChunkSize) {
                chunks.add(currentChunk);
                currentChunk = new Set<Id>();
            }
        }
        if (!currentChunk.isEmpty()) {
            chunks.add(currentChunk);
        }
        return chunks;
    }

    private static Integer roleHierarchyRoleChunkSize() {
        return normalizeChunkSize(
            roleHierarchyRoleChunkSizeOverride,
            DEFAULT_ROLE_HIERARCHY_ROLE_CHUNK_SIZE
        );
    }

    private static Integer publicGroupFrontierChunkSize() {
        return normalizeChunkSize(
            publicGroupFrontierChunkSizeOverride,
            DEFAULT_PUBLIC_GROUP_FRONTIER_CHUNK_SIZE
        );
    }

    private static Integer jobTitleFrontierChunkSize() {
        return normalizeChunkSize(
            jobTitleFrontierChunkSizeOverride,
            DEFAULT_JOB_TITLE_FRONTIER_CHUNK_SIZE
        );
    }

    private static Integer normalizeChunkSize(Integer overrideValue, Integer defaultValue) {
        if (overrideValue != null && overrideValue > 0) return overrideValue;
        if (defaultValue != null && defaultValue > 0) return defaultValue;
        return 1;
    }

    @TestVisible
    private static ContinuationStateSnapshot buildContinuationStateForTest(
        String audienceType,
        Integer traversalDepth,
        Set<Id> frontierIds,
        Set<Id> activeFrontierIds,
        Set<Id> visitedIds,
        Set<Id> deferredNextFrontierIds,
        Set<Id> nextFrontierIds,
        Integer publicGroupProcessedMemberCount
    ) {
        return buildContinuationState(
            audienceType,
            traversalDepth,
            frontierIds,
            activeFrontierIds,
            visitedIds,
            deferredNextFrontierIds,
            nextFrontierIds,
            publicGroupProcessedMemberCount
        );
    }

    @TestVisible
    private static Set<Id> takeNextIdsForTest(Set<Id> sourceIds, Integer chunkSize) {
        return takeNextIds(sourceIds, chunkSize);
    }

    private static ContinuationStateSnapshot buildContinuationState(
        String audienceType,
        Integer traversalDepth,
        Set<Id> frontierIds,
        Set<Id> activeFrontierIds,
        Set<Id> visitedIds,
        Set<Id> deferredNextFrontierIds,
        Set<Id> nextFrontierIds,
        Integer publicGroupProcessedMemberCount
    ) {
        ContinuationStateSnapshot snapshot = new ContinuationStateSnapshot();
        snapshot.nextTraversalDepth = traversalDepth == null || traversalDepth < 0 ? 0 : traversalDepth;
        snapshot.nextVisitedIds = cloneIds(visitedIds);
        snapshot.nextPublicGroupProcessedMemberCount = safeInteger(publicGroupProcessedMemberCount);

        if (isRecursiveRoleAudience(audienceType)) {
            if (frontierIds == null || frontierIds.isEmpty()) {
                snapshot.terminalSuccess = true;
                return snapshot;
            }
            snapshot.shouldContinue = true;
            snapshot.nextFrontierIds = cloneIds(frontierIds);
            snapshot.nextDeferredNextFrontierIds = cloneIds(deferredNextFrontierIds);
            assertContinuationProgress(
                traversalDepth,
                frontierIds,
                activeFrontierIds,
                visitedIds,
                deferredNextFrontierIds,
                publicGroupProcessedMemberCount,
                snapshot
            );
            return snapshot;
        }

        Set<Id> carriedNextFrontierIds = mergedIds(deferredNextFrontierIds, nextFrontierIds);
        if (audienceType == AUDIENCE_TYPE_PUBLIC_GROUP ||
            audienceType == AUDIENCE_TYPE_JOB_TITLE_AND_SUBORDINATES) {
            if (frontierIds != null && !frontierIds.isEmpty()) {
                snapshot.shouldContinue = true;
                snapshot.nextFrontierIds = cloneIds(frontierIds);
                snapshot.nextDeferredNextFrontierIds = carriedNextFrontierIds;
                assertContinuationProgress(
                    traversalDepth,
                    frontierIds,
                    activeFrontierIds,
                    visitedIds,
                    deferredNextFrontierIds,
                    publicGroupProcessedMemberCount,
                    snapshot
                );
                return snapshot;
            }
            if (!carriedNextFrontierIds.isEmpty()) {
                snapshot.shouldContinue = true;
                snapshot.nextTraversalDepth++;
                snapshot.nextFrontierIds = carriedNextFrontierIds;
                snapshot.nextDeferredNextFrontierIds = new Set<Id>();
                assertContinuationProgress(
                    traversalDepth,
                    frontierIds,
                    activeFrontierIds,
                    visitedIds,
                    deferredNextFrontierIds,
                    publicGroupProcessedMemberCount,
                    snapshot
                );
                return snapshot;
            }
            snapshot.terminalSuccess = true;
            return snapshot;
        }

        snapshot.terminalSuccess = true;
        return snapshot;
    }

    private static void assertContinuationProgress(
        Integer currentTraversalDepth,
        Set<Id> currentFrontierIds,
        Set<Id> currentActiveFrontierIds,
        Set<Id> currentVisitedIds,
        Set<Id> currentDeferredNextFrontierIds,
        Integer currentPublicGroupProcessedMemberCount,
        ContinuationStateSnapshot nextState
    ) {
        if (nextState == null || nextState.shouldContinue != true) return;
        if ((currentActiveFrontierIds == null || currentActiveFrontierIds.isEmpty()) &&
            safeInteger(currentTraversalDepth) == safeInteger(nextState.nextTraversalDepth) &&
            cloneIds(currentFrontierIds) == cloneIds(nextState.nextFrontierIds) &&
            cloneIds(currentVisitedIds) == cloneIds(nextState.nextVisitedIds) &&
            cloneIds(currentDeferredNextFrontierIds) == cloneIds(nextState.nextDeferredNextFrontierIds) &&
            safeInteger(currentPublicGroupProcessedMemberCount) ==
                safeInteger(nextState.nextPublicGroupProcessedMemberCount)) {
            throw new CommunicatorException(INVALID_CONTINUATION_STATE_ERROR);
        }
    }

    private static List<Id> sortIds(Set<Id> sourceIds) {
        List<Id> sortedIds = new List<Id>();
        if (sourceIds != null) {
            sortedIds.addAll(sourceIds);
            sortedIds.sort();
        }
        return sortedIds;
    }

    private static Integer safeInteger(Integer value) {
        return value == null ? 0 : value;
    }

    private static Boolean isRecursiveRoleAudience(String audienceType) {
        return audienceType == AUDIENCE_TYPE_ROLE_INTERNAL ||
            audienceType == AUDIENCE_TYPE_ROLE_PORTAL ||
            audienceType == AUDIENCE_TYPE_ROLE_INTERNAL_PORTAL;
    }

    private static Id tryParseId(String rawId, Schema.SObjectType expectedType) {
        if (String.isBlank(rawId) || expectedType == null) return null;
        try {
            Id parsedId = (Id) rawId.trim();
            return parsedId.getSObjectType() == expectedType ? parsedId : null;
        } catch (Exception ex) {
            return null;
        }
    }
}