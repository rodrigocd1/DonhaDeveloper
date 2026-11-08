public without sharing class CommunicatorBroadcastDistributionService {

    public static final String STATUS_QUEUED = 'Queued';
    public static final String STATUS_PROCESSING = 'Processing';
    public static final String STATUS_SENT = 'Sent';
    public static final String STATUS_FAILED = 'Failed';

    private static final String THREAD_RECORD_TYPE = 'CommunicatorGroup__c';
    private static final String AUDIENCE_TYPE_ALL_SUPPORTED_USERS = 'AllSupportedUsers';
    private static final String AUDIENCE_TYPE_DIRECT_USER = 'DirectUser';
    private static final String AUDIENCE_TYPE_ROLE = 'Role';
    private static final String AUDIENCE_TYPE_ROLE_INTERNAL = 'RoleAndSubordinatesInternal';
    private static final String AUDIENCE_TYPE_ROLE_PORTAL = 'RoleAndSubordinatesPortal';
    private static final String AUDIENCE_TYPE_ROLE_INTERNAL_PORTAL =
        'RoleAndSubordinatesInternalAndPortal';
    private static final String AUDIENCE_TYPE_PUBLIC_GROUP = 'PublicGroup';
    private static final String AUDIENCE_TYPE_SALES_COMPANY = 'SalesCompany';
    private static final String AUDIENCE_TYPE_JOB_TITLE = 'JobTitle';
    private static final String AUDIENCE_TYPE_JOB_TITLE_AND_SUBORDINATES =
        'JobTitleAndSubordinates';
    private static final Integer PHASE_ONE_BATCH_SCOPE = 100;
    private static final Integer PHASE_TWO_BATCH_SCOPE = 100;
    private static final String DISTRIBUTION_ERROR_FALLBACK =
        'Nao foi possivel concluir a distribuicao do comunicado.';
    private static final String DISTRIBUTION_DISABLED_ERROR =
        'O criterio Todos os usuarios nao esta mais ativo para este comunicado.';
    private static final String DISTRIBUTION_SNAPSHOT_INVALID_ERROR =
        'O snapshot de criterios do comunicado esta invalido para a distribuicao.';
    private static final String DISTRIBUTION_SNAPSHOT_UNSUPPORTED_VERSION_ERROR =
        'A versao do snapshot de criterios do comunicado nao e suportada.';
    private static final String DISTRIBUTION_UNSUPPORTED_COORDINATOR_ERROR =
        'O snapshot de criterios do comunicado contem audiencias que ainda nao sao suportadas por este pipeline assincrono.';
    private static final String DISTRIBUTION_INVALID_CRITERION_ERROR =
        'O criterio atual do snapshot do comunicado esta invalido para a distribuicao.';
    private static final String DISTRIBUTION_NO_RECIPIENTS_ERROR =
        'Nao foi possivel concluir a distribuicao do comunicado porque nao existem destinatarios validos no snapshot.';
    private static final String DISTRIBUTION_BATCH_ERROR =
        'Nao foi possivel concluir a distribuicao do comunicado porque o batch ativo terminou com erro.';
    private static final String DISTRIBUTION_RECONCILIATION_ERROR =
        'A distribuicao anterior foi encerrada sem atualizacao final. Reenfileire o comunicado.';
    // Protects the handoff between recursive batches. AsyncApexJob.Completed can be
    // visible before the next executor owns the message; this is only a stale
    // reconciliation grace period for a recently completed JobId, not a maximum
    // distribution timeout.
    private static final Integer COMPLETED_JOB_STABILIZATION_SECONDS = 120;
    private static final Set<String> ACTIVE_PHASE_ONE_STATUSES =
        new Set<String>{ STATUS_QUEUED, STATUS_PROCESSING };
    private static final Set<String> TERMINAL_ASYNC_JOB_STATUSES =
        new Set<String>{ 'Completed', 'Failed', 'Aborted' };

    @TestVisible private static Boolean failCoordinatorEnqueueForTest = false;
    @TestVisible private static Boolean failPhaseOneEnqueueForTest = false;
    @TestVisible private static Boolean failPhaseTwoEnqueueForTest = false;
    @TestVisible private static Id coordinatorJobIdOverrideForTest;
    @TestVisible private static Id phaseOneBatchJobIdOverrideForTest;
    @TestVisible private static Map<Id, String> asyncJobStatusOverridesForTest = new Map<Id, String>();
    @TestVisible private static Map<Id, Integer> asyncJobErrorCountOverridesForTest = new Map<Id, Integer>();
    @TestVisible private static Map<Id, Datetime> asyncJobCompletedDateOverridesForTest = new Map<Id, Datetime>();
    @TestVisible private static Datetime currentDatetimeOverrideForTest;
    @TestVisible private static Set<Id> phaseOneRecipientIdsForTest = new Set<Id>();
    @TestVisible private static Id lastCoordinatorJobIdForTest;
    @TestVisible private static Id lastPhaseOneBatchJobIdForTest;
    @TestVisible private static String lastEnqueuedCriterionAudienceTypeForTest;
    @TestVisible private static String lastEnqueuedCriterionTargetIdForTest;

    private class DistributionMessageContext {
        CommunicatorMessage__c message;
        Id groupId;
    }

    public class PhaseOneExecutionState {
        public Boolean ready = false;
        public Boolean staleJob = false;
        public String safeErrorMessage = DISTRIBUTION_ERROR_FALLBACK;
        public Id groupId;
        public Integer criterionIndex;
        public String criterionAudienceType;
        public String criterionTargetId;
    }

    private class SnapshotCriterion {
        Integer index;
        String audienceKey;
        String audienceType;
        String targetId;

        Boolean isSupportedByCurrentCoordinator() {
            return audienceType == AUDIENCE_TYPE_ALL_SUPPORTED_USERS ||
                audienceType == AUDIENCE_TYPE_DIRECT_USER ||
                audienceType == AUDIENCE_TYPE_ROLE ||
                audienceType == AUDIENCE_TYPE_ROLE_INTERNAL ||
                audienceType == AUDIENCE_TYPE_ROLE_PORTAL ||
                audienceType == AUDIENCE_TYPE_ROLE_INTERNAL_PORTAL ||
                audienceType == AUDIENCE_TYPE_PUBLIC_GROUP ||
                audienceType == AUDIENCE_TYPE_SALES_COMPANY ||
                audienceType == AUDIENCE_TYPE_JOB_TITLE ||
                audienceType == AUDIENCE_TYPE_JOB_TITLE_AND_SUBORDINATES;
        }

        Boolean requiresAllSupportedUsersBatch() {
            return audienceType == AUDIENCE_TYPE_ALL_SUPPORTED_USERS;
        }

        Boolean requiresSimpleAudienceBatch() {
            return audienceType == AUDIENCE_TYPE_DIRECT_USER ||
                audienceType == AUDIENCE_TYPE_ROLE ||
                audienceType == AUDIENCE_TYPE_SALES_COMPANY ||
                audienceType == AUDIENCE_TYPE_JOB_TITLE;
        }

        Boolean requiresRecursiveAudienceBatch() {
            return audienceType == AUDIENCE_TYPE_ROLE_INTERNAL ||
                audienceType == AUDIENCE_TYPE_ROLE_PORTAL ||
                audienceType == AUDIENCE_TYPE_ROLE_INTERNAL_PORTAL ||
                audienceType == AUDIENCE_TYPE_PUBLIC_GROUP ||
                audienceType == AUDIENCE_TYPE_JOB_TITLE_AND_SUBORDINATES;
        }
    }

    private class AsyncJobExecutionDetails {
        Boolean found = false;
        String status;
        Integer numberOfErrors = 0;
        Datetime completedDate;
    }

    private class DistributionExecutionPlan {
        AllSupportedUsersSnapshotResult snapshotResult;
        List<SnapshotCriterion> criteria = new List<SnapshotCriterion>();

        Boolean isEligibleForCurrentCoordinator() {
            if (snapshotResult == null || criteria == null) {
                return false;
            }
            if (snapshotResult.status == AllSupportedUsersSnapshotStatus.SNAPSHOT_INVALID ||
                snapshotResult.status == AllSupportedUsersSnapshotStatus.SNAPSHOT_UNSUPPORTED_VERSION) {
                return false;
            }
            if (snapshotResult.status == AllSupportedUsersSnapshotStatus.LEGACY_SNAPSHOT_ABSENT) {
                return snapshotResult.legacyGroupContainsAllSupportedUsers == true;
            }
            for (SnapshotCriterion criterion : criteria) {
                if (criterion == null || criterion.isSupportedByCurrentCoordinator() != true) {
                    return false;
                }
            }
            return true;
        }
    }

    public enum AllSupportedUsersSnapshotStatus {
        LEGACY_SNAPSHOT_ABSENT,
        SNAPSHOT_V1_WITH_ALL_SUPPORTED_USERS,
        SNAPSHOT_V1_WITHOUT_ALL_SUPPORTED_USERS,
        SNAPSHOT_INVALID,
        SNAPSHOT_UNSUPPORTED_VERSION
    }

    public class AllSupportedUsersSnapshotResult {
        public AllSupportedUsersSnapshotStatus status;
        public Boolean legacyGroupContainsAllSupportedUsers = false;
        public String safeErrorMessage;

        public Boolean allowsAsyncAllSupportedUsers() {
            return status == AllSupportedUsersSnapshotStatus.SNAPSHOT_V1_WITH_ALL_SUPPORTED_USERS ||
                (status == AllSupportedUsersSnapshotStatus.LEGACY_SNAPSHOT_ABSENT &&
                 legacyGroupContainsAllSupportedUsers == true);
        }
    }

    public static Id enqueuePhaseOneDistribution(
        Id messageId,
        Id threadId,
        Id senderId
    ) {
        if (messageId == null || threadId == null || senderId == null) {
            throw new CommunicatorException('Nao foi possivel iniciar a distribuicao do comunicado.');
        }
        DistributionMessageContext context = lockMessageContext(messageId, true);
        validateLaunchContext(context, threadId, senderId);
        Id jobId;
        if (Test.isRunningTest() && coordinatorJobIdOverrideForTest != null) {
            jobId = coordinatorJobIdOverrideForTest;
        } else {
            if (Test.isRunningTest() && failCoordinatorEnqueueForTest) {
                throw new CommunicatorException('Falha simulada ao enfileirar o coordenador do Broadcast.');
            }
            jobId = System.enqueueJob(
                new CommunicatorBroadcastDistCoordinator(messageId, 0)
            );
        }
        if (Test.isRunningTest()) {
            lastCoordinatorJobIdForTest = jobId;
        }
        context.message.BroadcastDistributionJobId__c = String.valueOf(jobId);
        context.message.BroadcastDistributionError__c = null;
        context.message.BroadcastDistributionCompletedAt__c = null;
        authorizeMessageUpdate(new List<CommunicatorMessage__c>{ context.message });
        try {
            update context.message;
        } finally {
            CommunicatorBroadcastDmlGuardHandler.clearOfficialAuthorization();
        }
        return jobId;
    }

    public static void executeDistributionCoordinator(
        Id messageId,
        Integer criterionIndex,
        Id jobId
    ) {
        DistributionMessageContext context = lockMessageContext(messageId, true);
        PhaseOneExecutionState state = beginCoordinatorExecution(context, jobId);
        if (state.staleJob == true) return;
        if (state.ready != true) {
            markFailureForCurrentJob(
                context,
                jobId,
                state.safeErrorMessage
            );
            return;
        }

        DistributionExecutionPlan plan = buildDistributionExecutionPlan(
            context.message.BroadcastAudienceCriteriaSnapshot__c,
            context.groupId
        );
        Integer normalizedCriterionIndex = criterionIndex == null || criterionIndex < 0
            ? 0
            : criterionIndex;
        if (normalizedCriterionIndex >= plan.criteria.size()) {
            finalizeDistributionAfterCriterion(context, jobId);
            return;
        }

        SnapshotCriterion criterion = plan.criteria[normalizedCriterionIndex];
        if (criterion == null || criterion.isSupportedByCurrentCoordinator() != true) {
            markFailureForCurrentJob(
                context,
                jobId,
                DISTRIBUTION_UNSUPPORTED_COORDINATOR_ERROR
            );
            return;
        }

        Savepoint savepoint = Database.setSavepoint();
        try {
            if (Test.isRunningTest() && failPhaseOneEnqueueForTest) {
                throw new CommunicatorException('Falha simulada ao enfileirar a fase 1 do Broadcast.');
            }
            Id nextJobId = enqueueCriterionExecutor(
                context,
                criterion,
                normalizedCriterionIndex
            );
            if (Test.isRunningTest()) {
                lastPhaseOneBatchJobIdForTest = nextJobId;
            }
            context.message.BroadcastDistributionJobId__c = String.valueOf(nextJobId);
            context.message.BroadcastDistributionError__c = null;
            context.message.BroadcastDistributionCompletedAt__c = null;
            authorizeMessageUpdate(new List<CommunicatorMessage__c>{ context.message });
            try {
                update context.message;
            } finally {
                CommunicatorBroadcastDmlGuardHandler.clearOfficialAuthorization();
            }
        } catch (Exception ex) {
            Database.rollback(savepoint);
            context = lockMessageContext(messageId, true);
            markFailureForCurrentJob(context, jobId, normalizeSafeErrorMessage(ex));
        }
    }

    public static PhaseOneExecutionState beginPhaseOneExecution(
        Id messageId,
        Id threadId,
        Id senderId,
        Id jobId
    ) {
        DistributionMessageContext context = lockMessageContext(messageId, true);
        return validatePhaseOneExecution(context, threadId, senderId, jobId, true, null, null, null);
    }

    public static PhaseOneExecutionState validatePhaseOneExecution(
        Id messageId,
        Id threadId,
        Id senderId,
        Id jobId
    ) {
        DistributionMessageContext context = lockMessageContext(messageId, true);
        return validatePhaseOneExecution(context, threadId, senderId, jobId, false, null, null, null);
    }

    public static PhaseOneExecutionState validatePhaseOneExecution(
        Id messageId,
        Id threadId,
        Id senderId,
        Id jobId,
        Integer criterionIndex,
        String expectedAudienceType,
        String expectedTargetId
    ) {
        DistributionMessageContext context = lockMessageContext(messageId, true);
        return validatePhaseOneExecution(
            context,
            threadId,
            senderId,
            jobId,
            false,
            criterionIndex,
            expectedAudienceType,
            expectedTargetId
        );
    }

    public static void finalizePhaseOneFailure(
        Id messageId,
        Integer criterionIndex,
        Id jobId,
        String safeErrorMessage
    ) {
        completeCriterionExecution(messageId, criterionIndex, jobId, safeErrorMessage, true, null, null);
    }

    public static void finalizePhaseOneFailure(
        Id messageId,
        Integer criterionIndex,
        Id jobId,
        String safeErrorMessage,
        String expectedAudienceType,
        String expectedTargetId
    ) {
        completeCriterionExecution(
            messageId,
            criterionIndex,
            jobId,
            safeErrorMessage,
            true,
            expectedAudienceType,
            expectedTargetId
        );
    }

    public static void finalizePhaseOneSuccess(Id messageId, Integer criterionIndex, Id jobId) {
        completeCriterionExecution(messageId, criterionIndex, jobId, null, false, null, null);
    }

    public static void finalizePhaseOneSuccess(
        Id messageId,
        Integer criterionIndex,
        Id jobId,
        String expectedAudienceType,
        String expectedTargetId
    ) {
        completeCriterionExecution(
            messageId,
            criterionIndex,
            jobId,
            null,
            false,
            expectedAudienceType,
            expectedTargetId
        );
    }

    public static void finalizePhaseOneFailure(Id messageId, Id jobId, String safeErrorMessage) {
        finalizePhaseOneFailure(messageId, 0, jobId, safeErrorMessage);
    }

    public static void finalizePhaseOneSuccess(Id messageId, Id jobId) {
        finalizePhaseOneSuccess(messageId, 0, jobId);
    }

    public static Boolean replaceActivePhaseOneJob(
        Id messageId,
        Integer criterionIndex,
        Id currentJobId,
        Id nextJobId,
        String expectedAudienceType,
        String expectedTargetId
    ) {
        if (messageId == null || currentJobId == null || nextJobId == null) return false;
        DistributionMessageContext context = lockMessageContext(messageId, true);
        if (context.message == null ||
            !jobsMatch(context.message.BroadcastDistributionJobId__c, currentJobId) ||
            !ACTIVE_PHASE_ONE_STATUSES.contains(context.message.Status__c)) {
            return false;
        }

        DistributionExecutionPlan plan = buildDistributionExecutionPlan(
            context.message.BroadcastAudienceCriteriaSnapshot__c,
            context.groupId
        );
        String planEligibilityError = resolvePlanEligibilityError(plan);
        if (String.isNotBlank(planEligibilityError)) {
            throw new CommunicatorException(planEligibilityError);
        }
        if (getValidatedCriterionForExecution(
            plan,
            criterionIndex,
            expectedAudienceType,
            expectedTargetId
        ) == null) {
            throw new CommunicatorException(DISTRIBUTION_INVALID_CRITERION_ERROR);
        }

        context.message.BroadcastDistributionJobId__c = String.valueOf(nextJobId);
        context.message.BroadcastDistributionError__c = null;
        context.message.BroadcastDistributionCompletedAt__c = null;
        authorizeMessageUpdate(new List<CommunicatorMessage__c>{ context.message });
        try {
            update context.message;
        } finally {
            CommunicatorBroadcastDmlGuardHandler.clearOfficialAuthorization();
        }
        return true;
    }

    public static void reconcileTerminalMessageStates(Set<Id> messageIds) {
        if (messageIds == null || messageIds.isEmpty()) return;

        Map<Id, DistributionMessageContext> contextsByMessageId = new Map<Id, DistributionMessageContext>();
        Set<Id> jobIds = new Set<Id>();
        for (CommunicatorMessage__c message : [
            SELECT Id, Thread__c, Sender__c, Sender__r.Name, Subject__c, SentAt__c, Status__c,
                   BroadcastDistributionJobId__c, BroadcastDistributionError__c,
                   BroadcastDistributionCompletedAt__c, Thread__r.RecordId__c,
                   Thread__r.RecordType__c, Thread__r.LastMessageAt__c
            FROM CommunicatorMessage__c
            WHERE Id IN :messageIds
            AND Status__c IN :ACTIVE_PHASE_ONE_STATUSES
        ]) {
            if (String.isBlank(message.BroadcastDistributionJobId__c)) continue;
            DistributionMessageContext context = new DistributionMessageContext();
            context.message = message;
            context.groupId = tryParseGroupId(message.Thread__r == null ? null : message.Thread__r.RecordId__c);
            contextsByMessageId.put(message.Id, context);
            Id parsedJobId = tryParseJobId(message.BroadcastDistributionJobId__c);
            if (parsedJobId != null) jobIds.add(parsedJobId);
        }
        if (contextsByMessageId.isEmpty()) return;

        Map<Id, AsyncJobExecutionDetails> jobDetailsById = jobIds.isEmpty()
            ? new Map<Id, AsyncJobExecutionDetails>()
            : loadAsyncJobExecutionDetails(jobIds);
        for (DistributionMessageContext context : contextsByMessageId.values()) {
            String persistedJobId = context.message.BroadcastDistributionJobId__c;
            Id parsedJobId = tryParseJobId(context.message.BroadcastDistributionJobId__c);
            AsyncJobExecutionDetails jobDetails = parsedJobId == null
                ? null
                : jobDetailsById.get(parsedJobId);
            if (!shouldReconcileTerminalAsyncJob(jobDetails, getCurrentDatetime())) {
                continue;
            }

            DistributionMessageContext lockedContext = lockMessageContext(context.message.Id, true);
            if (lockedContext.message == null ||
                !persistedJobIdsMatch(
                    lockedContext.message.BroadcastDistributionJobId__c,
                    persistedJobId
                ) ||
                !ACTIVE_PHASE_ONE_STATUSES.contains(lockedContext.message.Status__c)) {
                continue;
            }
            Id lockedJobId = tryParseJobId(lockedContext.message.BroadcastDistributionJobId__c);
            AsyncJobExecutionDetails lockedJobDetails = lockedJobId == null
                ? null
                : loadAsyncJobExecutionDetails(lockedJobId);
            if (!shouldReconcileTerminalAsyncJob(lockedJobDetails, getCurrentDatetime())) {
                continue;
            }

            markFailureForCurrentJob(
                lockedContext,
                parsedJobId,
                resolveReconciliationFailureMessage(lockedContext)
            );
        }
    }

    public static String normalizeSafeErrorMessage(Exception ex) {
        return normalizeSafeErrorMessage(ex == null ? null : ex.getMessage());
    }

    public static String normalizeSafeErrorMessage(String safeErrorMessage) {
        String message = String.isBlank(safeErrorMessage)
            ? DISTRIBUTION_ERROR_FALLBACK
            : safeErrorMessage.trim();
        return message.length() > 255 ? message.substring(0, 255) : message;
    }

    public static Set<Id> getPhaseOneRecipientIdsForExecution(Id senderId) {
        if (!Test.isRunningTest() ||
            phaseOneRecipientIdsForTest == null ||
            phaseOneRecipientIdsForTest.isEmpty()) {
            return null;
        }
        Set<Id> scopedRecipientIds = new Set<Id>();
        for (Id recipientId : phaseOneRecipientIdsForTest) {
            if (recipientId != null && recipientId != senderId) {
                scopedRecipientIds.add(recipientId);
            }
        }
        return scopedRecipientIds;
    }

    public static AllSupportedUsersSnapshotResult evaluateAllSupportedUsersSnapshot(
        String criteriaSnapshot,
        Id fallbackGroupId
    ) {
        AllSupportedUsersSnapshotResult result = new AllSupportedUsersSnapshotResult();
        if (String.isBlank(criteriaSnapshot)) {
            result.status = AllSupportedUsersSnapshotStatus.LEGACY_SNAPSHOT_ABSENT;
            result.legacyGroupContainsAllSupportedUsers =
                fallbackGroupId != null &&
                CommunicatorBroadcastAudienceService.hasActiveAudienceType(
                    fallbackGroupId,
                    AUDIENCE_TYPE_ALL_SUPPORTED_USERS
                );
            result.safeErrorMessage = result.legacyGroupContainsAllSupportedUsers
                ? null
                : DISTRIBUTION_DISABLED_ERROR;
            return result;
        }

        return evaluateSnapshotPayload(criteriaSnapshot);
    }

    public static Boolean canCurrentCoordinatorProcessSnapshot(
        String criteriaSnapshot,
        Id fallbackGroupId
    ) {
        return String.isBlank(getCoordinatorEligibilityError(criteriaSnapshot, fallbackGroupId));
    }

    public static Boolean canCurrentProductivePublishUseQueuedPath(
        String criteriaSnapshot,
        Id fallbackGroupId
    ) {
        return String.isBlank(getCoordinatorEligibilityError(criteriaSnapshot, fallbackGroupId));
    }

    public static String getCoordinatorEligibilityError(
        String criteriaSnapshot,
        Id fallbackGroupId
    ) {
        return resolvePlanEligibilityError(
            buildDistributionExecutionPlan(criteriaSnapshot, fallbackGroupId)
        );
    }

    private static void authorizeMessageUpdate(List<CommunicatorMessage__c> messages) {
        CommunicatorBroadcastDmlGuardHandler.authorizeMessageDml('UPDATE', messages);
    }

    private static DistributionMessageContext lockMessageContext(Id messageId, Boolean forUpdate) {
        DistributionMessageContext context = new DistributionMessageContext();
        if (messageId == null) return context;

        List<CommunicatorMessage__c> messages = forUpdate
            ? [
                SELECT Id, Thread__c, Subject__c, Body__c, Sender__c, Sender__r.Name, SentAt__c,
                       Status__c, HasAttachment__c, ContentDocumentId__c, HasMention__c,
                       IsSystemMessage__c, EditedAt__c, BroadcastDistributionJobId__c,
                       BroadcastDistributionError__c, BroadcastDistributionCompletedAt__c,
                       BroadcastAudienceCriteriaSnapshot__c,
                       Thread__r.RecordId__c, Thread__r.RecordType__c, Thread__r.LastMessageAt__c
                FROM CommunicatorMessage__c
                WHERE Id = :messageId
                LIMIT 1
                FOR UPDATE
            ]
            : [
                SELECT Id, Thread__c, Subject__c, Body__c, Sender__c, Sender__r.Name, SentAt__c,
                       Status__c, HasAttachment__c, ContentDocumentId__c, HasMention__c,
                       IsSystemMessage__c, EditedAt__c, BroadcastDistributionJobId__c,
                       BroadcastDistributionError__c, BroadcastDistributionCompletedAt__c,
                       BroadcastAudienceCriteriaSnapshot__c,
                       Thread__r.RecordId__c, Thread__r.RecordType__c, Thread__r.LastMessageAt__c
                FROM CommunicatorMessage__c
                WHERE Id = :messageId
                LIMIT 1
            ];
        if (messages.isEmpty()) return context;

        context.message = messages[0];
        context.groupId = tryParseGroupId(
            context.message.Thread__r == null ? null : context.message.Thread__r.RecordId__c
        );
        return context;
    }

    private static void validateLaunchContext(
        DistributionMessageContext context,
        Id threadId,
        Id senderId
    ) {
        if (context.message == null ||
            context.message.Thread__c != threadId ||
            context.message.Sender__c != senderId ||
            senderId != UserInfo.getUserId()) {
            throw new CommunicatorException('Nao foi possivel iniciar a distribuicao do comunicado.');
        }
        if (context.groupId == null ||
            context.message.Thread__r == null ||
            context.message.Thread__r.RecordType__c != THREAD_RECORD_TYPE) {
            throw new CommunicatorException('Nao foi possivel iniciar a distribuicao do comunicado.');
        }
        if (!CommunicatorBroadcastAudienceService.canCurrentUserPublishToBroadcast(context.groupId)) {
            throw new CommunicatorException('Somente o remetente autorizado pode iniciar esta distribuicao.');
        }
        DistributionExecutionPlan plan = buildDistributionExecutionPlan(
            context.message.BroadcastAudienceCriteriaSnapshot__c,
            context.groupId
        );
        String planEligibilityError = resolvePlanEligibilityError(plan);
        if (String.isNotBlank(planEligibilityError)) {
            throw new CommunicatorException(planEligibilityError);
        }
        if (context.message.Status__c != STATUS_QUEUED) {
            throw new CommunicatorException('Somente comunicados enfileirados podem iniciar a distribuicao.');
        }
        if (String.isNotBlank(context.message.BroadcastDistributionJobId__c)) {
            throw new CommunicatorException('Ja existe um job de distribuicao em andamento para este comunicado.');
        }
    }

    private static PhaseOneExecutionState validatePhaseOneExecution(
        DistributionMessageContext context,
        Id threadId,
        Id senderId,
        Id jobId,
        Boolean markProcessing,
        Integer criterionIndex,
        String expectedAudienceType,
        String expectedTargetId
    ) {
        PhaseOneExecutionState state = new PhaseOneExecutionState();
        if (context.message == null) {
            state.staleJob = true;
            return state;
        }
        if (jobId == null) {
            state.safeErrorMessage = DISTRIBUTION_ERROR_FALLBACK;
            return state;
        }
        if (context.message.Thread__c != threadId ||
            context.message.Sender__c != senderId ||
            context.groupId == null ||
            context.message.Thread__r == null ||
            context.message.Thread__r.RecordType__c != THREAD_RECORD_TYPE) {
            state.safeErrorMessage = DISTRIBUTION_ERROR_FALLBACK;
            return state;
        }
        if (!jobsMatch(context.message.BroadcastDistributionJobId__c, jobId)) {
            state.staleJob = true;
            return state;
        }
        if (!ACTIVE_PHASE_ONE_STATUSES.contains(context.message.Status__c)) {
            state.staleJob = true;
            return state;
        }
        DistributionExecutionPlan plan = buildDistributionExecutionPlan(
            context.message.BroadcastAudienceCriteriaSnapshot__c,
            context.groupId
        );
        String planEligibilityError = resolvePlanEligibilityError(plan);
        if (String.isNotBlank(planEligibilityError)) {
            state.safeErrorMessage = planEligibilityError;
            return state;
        }

        if (criterionIndex != null) {
            SnapshotCriterion criterion = getValidatedCriterionForExecution(
                plan,
                criterionIndex,
                expectedAudienceType,
                expectedTargetId
            );
            if (criterion == null) {
                state.safeErrorMessage = DISTRIBUTION_INVALID_CRITERION_ERROR;
                return state;
            }
            state.criterionIndex = criterion.index;
            state.criterionAudienceType = criterion.audienceType;
            state.criterionTargetId = criterion.targetId;
        }

        if (markProcessing && context.message.Status__c == STATUS_QUEUED) {
            context.message.Status__c = STATUS_PROCESSING;
            context.message.BroadcastDistributionError__c = null;
            context.message.BroadcastDistributionCompletedAt__c = null;
            authorizeMessageUpdate(new List<CommunicatorMessage__c>{ context.message });
            try {
                update context.message;
            } finally {
                CommunicatorBroadcastDmlGuardHandler.clearOfficialAuthorization();
            }
        } else if (markProcessing != true && context.message.Status__c != STATUS_PROCESSING) {
            state.staleJob = true;
            return state;
        }

        state.ready = true;
        state.groupId = context.groupId;
        return state;
    }

    private static PhaseOneExecutionState beginCoordinatorExecution(
        DistributionMessageContext context,
        Id jobId
    ) {
        PhaseOneExecutionState state = new PhaseOneExecutionState();
        if (context.message == null) {
            state.staleJob = true;
            return state;
        }
        if (jobId == null) {
            state.safeErrorMessage = DISTRIBUTION_ERROR_FALLBACK;
            return state;
        }
        if (context.groupId == null ||
            context.message.Thread__r == null ||
            context.message.Thread__r.RecordType__c != THREAD_RECORD_TYPE) {
            state.safeErrorMessage = DISTRIBUTION_ERROR_FALLBACK;
            return state;
        }
        if (!jobsMatch(context.message.BroadcastDistributionJobId__c, jobId)) {
            state.staleJob = true;
            return state;
        }
        if (context.message.Status__c == STATUS_SENT || context.message.Status__c == STATUS_FAILED) {
            state.staleJob = true;
            return state;
        }

        DistributionExecutionPlan plan = buildDistributionExecutionPlan(
            context.message.BroadcastAudienceCriteriaSnapshot__c,
            context.groupId
        );
        String planEligibilityError = resolvePlanEligibilityError(plan);
        if (String.isNotBlank(planEligibilityError)) {
            state.safeErrorMessage = planEligibilityError;
            return state;
        }

        if (context.message.Status__c == STATUS_QUEUED) {
            context.message.Status__c = STATUS_PROCESSING;
            context.message.BroadcastDistributionError__c = null;
            context.message.BroadcastDistributionCompletedAt__c = null;
            authorizeMessageUpdate(new List<CommunicatorMessage__c>{ context.message });
            try {
                update context.message;
            } finally {
                CommunicatorBroadcastDmlGuardHandler.clearOfficialAuthorization();
            }
        } else if (context.message.Status__c != STATUS_PROCESSING) {
            state.staleJob = true;
            return state;
        }

        state.ready = true;
        state.groupId = context.groupId;
        return state;
    }

    private static void completeCriterionExecution(
        Id messageId,
        Integer criterionIndex,
        Id jobId,
        String safeErrorMessage,
        Boolean criticalFailure,
        String expectedAudienceType,
        String expectedTargetId
    ) {
        if (messageId == null || jobId == null) return;
        DistributionMessageContext context = lockMessageContext(messageId, true);
        if (context.message == null || !jobsMatch(context.message.BroadcastDistributionJobId__c, jobId)) {
            return;
        }
        if (!ACTIVE_PHASE_ONE_STATUSES.contains(context.message.Status__c)) {
            return;
        }

        DistributionExecutionPlan plan = buildDistributionExecutionPlan(
            context.message.BroadcastAudienceCriteriaSnapshot__c,
            context.groupId
        );
        String planEligibilityError = resolvePlanEligibilityError(plan);
        if (String.isNotBlank(planEligibilityError)) {
            markFailureForCurrentJob(
                context,
                jobId,
                planEligibilityError
            );
            return;
        }
        if (criterionIndex != null &&
            getValidatedCriterionForExecution(
                plan,
                criterionIndex,
                expectedAudienceType,
                expectedTargetId
            ) == null) {
            markFailureForCurrentJob(
                context,
                jobId,
                DISTRIBUTION_INVALID_CRITERION_ERROR
            );
            return;
        }
        if (criticalFailure == true) {
            markFailureForCurrentJob(context, jobId, safeErrorMessage);
            return;
        }
        String batchExecutionError = evaluateCurrentBatchExecution(jobId);
        if (String.isNotBlank(batchExecutionError)) {
            markFailureForCurrentJob(context, jobId, batchExecutionError);
            return;
        }

        Integer nextCriterionIndex = (criterionIndex == null ? 0 : criterionIndex) + 1;
        if (nextCriterionIndex < plan.criteria.size()) {
            enqueueNextCoordinatorOrFail(context, jobId, nextCriterionIndex);
            return;
        }

        finalizeDistributionAfterCriterion(context, jobId);
    }

    private static void enqueueNextCoordinatorOrFail(
        DistributionMessageContext context,
        Id currentJobId,
        Integer nextCriterionIndex
    ) {
        Savepoint savepoint = Database.setSavepoint();
        try {
            if (Test.isRunningTest() && failCoordinatorEnqueueForTest) {
                throw new CommunicatorException('Falha simulada ao enfileirar o coordenador do Broadcast.');
            }
            Id nextJobId = System.enqueueJob(
                new CommunicatorBroadcastDistCoordinator(
                    context.message.Id,
                    nextCriterionIndex
                )
            );
            if (Test.isRunningTest()) {
                lastCoordinatorJobIdForTest = nextJobId;
            }
            context.message.BroadcastDistributionJobId__c = String.valueOf(nextJobId);
            context.message.BroadcastDistributionError__c = null;
            context.message.BroadcastDistributionCompletedAt__c = null;
            authorizeMessageUpdate(new List<CommunicatorMessage__c>{ context.message });
            try {
                update context.message;
            } finally {
                CommunicatorBroadcastDmlGuardHandler.clearOfficialAuthorization();
            }
        } catch (Exception ex) {
            Database.rollback(savepoint);
            DistributionMessageContext lockedContext = lockMessageContext(context.message.Id, true);
            markFailureForCurrentJob(lockedContext, currentJobId, normalizeSafeErrorMessage(ex));
        }
    }

    private static String evaluateCurrentBatchExecution(Id jobId) {
        AsyncJobExecutionDetails details = loadAsyncJobExecutionDetails(jobId);
        if (details.found != true) {
            return DISTRIBUTION_RECONCILIATION_ERROR;
        }
        if (safeInteger(details.numberOfErrors) > 0) {
            return DISTRIBUTION_BATCH_ERROR;
        }
        if (details.status == 'Failed' || details.status == 'Aborted') {
            return DISTRIBUTION_BATCH_ERROR;
        }
        return null;
    }

    private static Id enqueueCriterionExecutor(
        DistributionMessageContext context,
        SnapshotCriterion criterion,
        Integer criterionIndex
    ) {
        if (Test.isRunningTest()) {
            lastEnqueuedCriterionAudienceTypeForTest = criterion == null ? null : criterion.audienceType;
            lastEnqueuedCriterionTargetIdForTest = criterion == null ? null : criterion.targetId;
        }
        if (Test.isRunningTest() && phaseOneBatchJobIdOverrideForTest != null) {
            return phaseOneBatchJobIdOverrideForTest;
        }
        if (criterion == null || criterion.isSupportedByCurrentCoordinator() != true) {
            throw new CommunicatorException(DISTRIBUTION_UNSUPPORTED_COORDINATOR_ERROR);
        }
        if (criterion.requiresAllSupportedUsersBatch()) {
            return Database.executeBatch(
                new CommunicatorBroadcastAllUsersBatch(
                    context.message.Id,
                    context.message.Thread__c,
                    context.message.Sender__c,
                    criterionIndex
                ),
                PHASE_ONE_BATCH_SCOPE
            );
        }
        if (criterion.requiresSimpleAudienceBatch()) {
            return Database.executeBatch(
                new CommunicatorBroadcastSimpleAudienceBatch(
                    context.message.Id,
                    context.message.Thread__c,
                    context.message.Sender__c,
                    criterionIndex,
                    criterion.audienceType,
                    criterion.targetId
                ),
                PHASE_ONE_BATCH_SCOPE
            );
        }
        if (criterion.requiresRecursiveAudienceBatch()) {
            return Database.executeBatch(
                new CommunicatorBroadcastRecursiveBatch(
                    context.message.Id,
                    context.message.Thread__c,
                    context.message.Sender__c,
                    criterionIndex,
                    criterion.audienceType,
                    criterion.targetId
                ),
                PHASE_ONE_BATCH_SCOPE
            );
        }
        throw new CommunicatorException(DISTRIBUTION_UNSUPPORTED_COORDINATOR_ERROR);
    }

    private static void finalizeDistributionAfterCriterion(
        DistributionMessageContext context,
        Id jobId
    ) {
        if (context == null || context.message == null) return;
        if (!jobsMatch(context.message.BroadcastDistributionJobId__c, jobId)) return;

        Integer broadcastNotificationCount = [
            SELECT COUNT()
            FROM CommunicatorNotification__c
            WHERE Message__c = :context.message.Id
            AND Type__c = 'Broadcast'
        ];
        if (broadcastNotificationCount == 0) {
            markFailureForCurrentJob(context, jobId, DISTRIBUTION_NO_RECIPIENTS_ERROR);
            return;
        }

        Datetime activityAt = context.message.SentAt__c == null ? System.now() : context.message.SentAt__c;
        Datetime completedAt = System.now();

        context.message.Status__c = STATUS_SENT;
        context.message.BroadcastDistributionJobId__c = null;
        context.message.BroadcastDistributionError__c = null;
        context.message.BroadcastDistributionCompletedAt__c = completedAt;
        authorizeMessageUpdate(new List<CommunicatorMessage__c>{ context.message });
        try {
            update context.message;
        } finally {
            CommunicatorBroadcastDmlGuardHandler.clearOfficialAuthorization();
        }

        if (context.message.Thread__c != null &&
            (context.message.Thread__r == null || context.message.Thread__r.LastMessageAt__c == null ||
             context.message.Thread__r.LastMessageAt__c < activityAt)) {
            CommunicatorThread__c threadToUpdate = new CommunicatorThread__c(
                Id = context.message.Thread__c,
                LastMessageAt__c = activityAt
            );
            CommunicatorBroadcastDmlGuardHandler.authorizeThreadDml(
                'UPDATE',
                new List<CommunicatorThread__c>{ threadToUpdate }
            );
            try {
                update threadToUpdate;
            } finally {
                CommunicatorBroadcastDmlGuardHandler.clearOfficialAuthorization();
            }
        }

        if (context.message.Thread__c != null) {
            CommunicatorBroadcastAudienceService.updateBroadcastActivityFromDistribution(
                context.message.Id,
                activityAt
            );
        }

        try {
            if (Test.isRunningTest() && failPhaseTwoEnqueueForTest) {
                throw new CommunicatorException('Falha simulada ao enfileirar a fase 2 do Broadcast.');
            }
            Database.executeBatch(
                new CommunicatorBroadcastNotifBatch(
                    context.message.Id,
                    context.message.Sender__c,
                    context.message.Sender__r == null ? null : context.message.Sender__r.Name,
                    context.message.Subject__c
                ),
                PHASE_TWO_BATCH_SCOPE
            );
        } catch (Exception ex) {
            System.debug(
                LoggingLevel.ERROR,
                'CommunicatorBroadcastDistributionService.finalizeDistributionAfterCriterion phase2 enqueue error: ' +
                ex.getMessage()
            );
        }
    }

    private static void markFailureForCurrentJob(
        DistributionMessageContext context,
        Id currentJobId,
        String safeErrorMessage
    ) {
        if (context == null || context.message == null) return;
        if (currentJobId != null && !jobsMatch(context.message.BroadcastDistributionJobId__c, currentJobId)) {
            return;
        }
        context.message.Status__c = STATUS_FAILED;
        context.message.BroadcastDistributionJobId__c = null;
        context.message.BroadcastDistributionError__c = normalizeSafeErrorMessage(safeErrorMessage);
        context.message.BroadcastDistributionCompletedAt__c = System.now();
        authorizeMessageUpdate(new List<CommunicatorMessage__c>{ context.message });
        try {
            update context.message;
        } finally {
            CommunicatorBroadcastDmlGuardHandler.clearOfficialAuthorization();
        }
    }

    private static DistributionExecutionPlan buildDistributionExecutionPlan(
        String criteriaSnapshot,
        Id fallbackGroupId
    ) {
        DistributionExecutionPlan plan = new DistributionExecutionPlan();
        plan.snapshotResult = evaluateAllSupportedUsersSnapshot(criteriaSnapshot, fallbackGroupId);
        if (plan.snapshotResult == null) {
            plan.snapshotResult = new AllSupportedUsersSnapshotResult();
            plan.snapshotResult.safeErrorMessage = DISTRIBUTION_ERROR_FALLBACK;
            return plan;
        }

        if (String.isBlank(criteriaSnapshot)) {
            if (plan.snapshotResult.legacyGroupContainsAllSupportedUsers == true) {
                SnapshotCriterion criterion = new SnapshotCriterion();
                criterion.index = 0;
                criterion.audienceKey = 'legacy|AllSupportedUsers';
                criterion.audienceType = AUDIENCE_TYPE_ALL_SUPPORTED_USERS;
                criterion.targetId = fallbackGroupId == null ? null : String.valueOf(fallbackGroupId);
                plan.criteria.add(criterion);
            }
            return plan;
        }

        if (plan.snapshotResult.status != AllSupportedUsersSnapshotStatus.SNAPSHOT_V1_WITH_ALL_SUPPORTED_USERS &&
            plan.snapshotResult.status != AllSupportedUsersSnapshotStatus.SNAPSHOT_V1_WITHOUT_ALL_SUPPORTED_USERS) {
            return plan;
        }

        try {
            Map<String, Object> payload =
                (Map<String, Object>) JSON.deserializeUntyped(criteriaSnapshot);
            List<Object> rawCriteria = (List<Object>) payload.get('c');
            if (rawCriteria == null) return plan;
            Set<String> seenSignatures = new Set<String>();
            Integer index = 0;
            for (Object rawCriterion : rawCriteria) {
                Map<String, Object> criterionPayload = (Map<String, Object>) rawCriterion;
                String audienceKey = extractSnapshotText(criterionPayload.get('k'));
                String audienceType = extractSnapshotText(criterionPayload.get('t'));
                String targetId = extractSnapshotText(criterionPayload.get('i'));
                String signature = audienceKey + '|' + audienceType + '|' + targetId;
                if (seenSignatures.contains(signature)) {
                    continue;
                }
                seenSignatures.add(signature);
                SnapshotCriterion criterion = new SnapshotCriterion();
                criterion.index = index;
                criterion.audienceKey = audienceKey;
                criterion.audienceType = audienceType;
                criterion.targetId = targetId;
                plan.criteria.add(criterion);
                index++;
            }
        } catch (Exception ex) {
            plan.criteria.clear();
            if (plan.snapshotResult != null) {
                plan.snapshotResult.status = AllSupportedUsersSnapshotStatus.SNAPSHOT_INVALID;
                plan.snapshotResult.safeErrorMessage = DISTRIBUTION_SNAPSHOT_INVALID_ERROR;
            }
        }
        return plan;
    }

    private static String resolvePlanEligibilityError(DistributionExecutionPlan plan) {
        if (plan == null || plan.snapshotResult == null) {
            return DISTRIBUTION_ERROR_FALLBACK;
        }
        if (plan.isEligibleForCurrentCoordinator()) {
            return null;
        }
        if (plan.snapshotResult.status == AllSupportedUsersSnapshotStatus.SNAPSHOT_INVALID ||
            plan.snapshotResult.status == AllSupportedUsersSnapshotStatus.SNAPSHOT_UNSUPPORTED_VERSION) {
            return String.isBlank(plan.snapshotResult.safeErrorMessage)
                ? DISTRIBUTION_ERROR_FALLBACK
                : plan.snapshotResult.safeErrorMessage;
        }
        if (plan.snapshotResult.status == AllSupportedUsersSnapshotStatus.LEGACY_SNAPSHOT_ABSENT &&
            plan.snapshotResult.legacyGroupContainsAllSupportedUsers != true) {
            return String.isBlank(plan.snapshotResult.safeErrorMessage)
                ? DISTRIBUTION_DISABLED_ERROR
                : plan.snapshotResult.safeErrorMessage;
        }
        if (plan.criteria == null) {
            return DISTRIBUTION_ERROR_FALLBACK;
        }
        for (SnapshotCriterion criterion : plan.criteria) {
            if (criterion == null) {
                return DISTRIBUTION_INVALID_CRITERION_ERROR;
            }
            if (criterion.isSupportedByCurrentCoordinator() != true) {
                return DISTRIBUTION_UNSUPPORTED_COORDINATOR_ERROR;
            }
        }
        return DISTRIBUTION_ERROR_FALLBACK;
    }

    private static SnapshotCriterion getValidatedCriterionForExecution(
        DistributionExecutionPlan plan,
        Integer criterionIndex,
        String expectedAudienceType,
        String expectedTargetId
    ) {
        if (plan == null || plan.criteria == null) return null;
        Integer normalizedCriterionIndex = criterionIndex == null || criterionIndex < 0
            ? 0
            : criterionIndex;
        if (normalizedCriterionIndex >= plan.criteria.size()) return null;
        SnapshotCriterion criterion = plan.criteria[normalizedCriterionIndex];
        if (criterion == null || criterion.isSupportedByCurrentCoordinator() != true) {
            return null;
        }
        if (String.isNotBlank(expectedAudienceType) && criterion.audienceType != expectedAudienceType) {
            return null;
        }
        String normalizedExpectedTargetId = normalizeSnapshotText(expectedTargetId);
        if (normalizedExpectedTargetId != null && criterion.targetId != normalizedExpectedTargetId) {
            return null;
        }
        return criterion;
    }

    private static Map<Id, AsyncJobExecutionDetails> loadAsyncJobExecutionDetails(Set<Id> jobIds) {
        Map<Id, AsyncJobExecutionDetails> result = new Map<Id, AsyncJobExecutionDetails>();
        if (jobIds == null || jobIds.isEmpty()) return result;

        if (Test.isRunningTest()) {
            for (Id jobId : jobIds) {
                AsyncJobExecutionDetails details = buildAsyncJobExecutionDetailsFromOverrides(jobId);
                if (details.found == true) {
                    result.put(jobId, details);
                }
            }
            if (!result.isEmpty()) return result;
        }

        for (AsyncApexJob jobRecord : [
            SELECT Id, Status, NumberOfErrors, CompletedDate
            FROM AsyncApexJob
            WHERE Id IN :jobIds
        ]) {
            AsyncJobExecutionDetails details = new AsyncJobExecutionDetails();
            details.found = true;
            details.status = jobRecord.Status;
            details.numberOfErrors = jobRecord.NumberOfErrors;
            details.completedDate = jobRecord.CompletedDate;
            result.put(jobRecord.Id, details);
        }
        return result;
    }

    private static AsyncJobExecutionDetails loadAsyncJobExecutionDetails(Id jobId) {
        AsyncJobExecutionDetails result = new AsyncJobExecutionDetails();
        if (jobId == null) return result;

        if (Test.isRunningTest()) {
            result = buildAsyncJobExecutionDetailsFromOverrides(jobId);
            if (result.found == true) return result;
        }

        for (AsyncApexJob jobRecord : [
            SELECT Id, Status, NumberOfErrors, CompletedDate
            FROM AsyncApexJob
            WHERE Id = :jobId
            LIMIT 1
        ]) {
            result.found = true;
            result.status = jobRecord.Status;
            result.numberOfErrors = jobRecord.NumberOfErrors;
            result.completedDate = jobRecord.CompletedDate;
        }
        return result;
    }

    private static AsyncJobExecutionDetails buildAsyncJobExecutionDetailsFromOverrides(Id jobId) {
        AsyncJobExecutionDetails result = new AsyncJobExecutionDetails();
        if (jobId == null) return result;
        Boolean hasStatus = asyncJobStatusOverridesForTest != null &&
            asyncJobStatusOverridesForTest.containsKey(jobId);
        Boolean hasErrorCount = asyncJobErrorCountOverridesForTest != null &&
            asyncJobErrorCountOverridesForTest.containsKey(jobId);
        Boolean hasCompletedDate = asyncJobCompletedDateOverridesForTest != null &&
            asyncJobCompletedDateOverridesForTest.containsKey(jobId);
        if (!hasStatus && !hasErrorCount && !hasCompletedDate) return result;
        result.found = true;
        result.status = hasStatus ? asyncJobStatusOverridesForTest.get(jobId) : null;
        result.numberOfErrors = hasErrorCount ? asyncJobErrorCountOverridesForTest.get(jobId) : 0;
        result.completedDate = hasCompletedDate ? asyncJobCompletedDateOverridesForTest.get(jobId) : null;
        return result;
    }

    @TestVisible
    private static Boolean shouldReconcileTerminalAsyncJob(
        AsyncJobExecutionDetails details,
        Datetime nowValue
    ) {
        if (details == null || details.found != true || String.isBlank(details.status)) {
            return true;
        }
        if (!TERMINAL_ASYNC_JOB_STATUSES.contains(details.status)) {
            return false;
        }
        if (details.status == 'Completed') {
            return isCompletedJobOutsideStabilizationWindow(details.completedDate, nowValue);
        }
        return true;
    }

    @TestVisible
    private static Boolean isCompletedJobOutsideStabilizationWindow(
        Datetime completedDate,
        Datetime nowValue
    ) {
        if (completedDate == null) return true;
        Datetime effectiveNow = nowValue == null ? getCurrentDatetime() : nowValue;
        return completedDate.addSeconds(COMPLETED_JOB_STABILIZATION_SECONDS) <= effectiveNow;
    }

    private static Datetime getCurrentDatetime() {
        return currentDatetimeOverrideForTest == null
            ? System.now()
            : currentDatetimeOverrideForTest;
    }

    private static Boolean jobsMatch(String persistedJobId, Id currentJobId) {
        Id persistedId = tryParseJobId(persistedJobId);
        return persistedId != null &&
            currentJobId != null &&
            persistedId == currentJobId;
    }

    private static Boolean persistedJobIdsMatch(String leftJobId, String rightJobId) {
        Id leftId = tryParseJobId(leftJobId);
        Id rightId = tryParseJobId(rightJobId);
        if (leftId == null || rightId == null) {
            return !String.isBlank(leftJobId) &&
                !String.isBlank(rightJobId) &&
                leftJobId.trim() == rightJobId.trim();
        }
        return leftId != null &&
            rightId != null &&
            leftId == rightId;
    }

    private static Id tryParseGroupId(String rawGroupId) {
        if (String.isBlank(rawGroupId)) return null;
        try {
            return (Id) rawGroupId.trim();
        } catch (Exception ex) {
            return null;
        }
    }

    private static Id tryParseJobId(String rawJobId) {
        if (String.isBlank(rawJobId)) return null;
        try {
            return (Id) rawJobId.trim();
        } catch (Exception ex) {
            return null;
        }
    }

    private static AllSupportedUsersSnapshotResult evaluateSnapshotPayload(String criteriaSnapshot) {
        AllSupportedUsersSnapshotResult result = new AllSupportedUsersSnapshotResult();
        result.status = AllSupportedUsersSnapshotStatus.SNAPSHOT_INVALID;
        result.safeErrorMessage = DISTRIBUTION_SNAPSHOT_INVALID_ERROR;

        try {
            Map<String, Object> payload =
                (Map<String, Object>) JSON.deserializeUntyped(criteriaSnapshot);
            if (payload == null || !payload.containsKey('v')) {
                return result;
            }

            Integer version = extractSnapshotVersion(payload.get('v'));
            if (version == null) {
                return result;
            }
            if (version != 1) {
                result.status = AllSupportedUsersSnapshotStatus.SNAPSHOT_UNSUPPORTED_VERSION;
                result.safeErrorMessage = DISTRIBUTION_SNAPSHOT_UNSUPPORTED_VERSION_ERROR;
                return result;
            }

            if (!payload.containsKey('c')) {
                return result;
            }
            List<Object> criteria = (List<Object>) payload.get('c');
            if (criteria == null) return result;
            Set<String> audienceTypes = new Set<String>();
            for (Object rawCriterion : criteria) {
                Map<String, Object> criterion = (Map<String, Object>) rawCriterion;
                if (criterion == null ||
                    !criterion.containsKey('k') ||
                    !criterion.containsKey('t') ||
                    !criterion.containsKey('i')) {
                    return result;
                }
                String key = extractSnapshotText(criterion.get('k'));
                String type = extractSnapshotText(criterion.get('t'));
                String target = extractSnapshotText(criterion.get('i'));
                if (String.isBlank(key) || String.isBlank(type) || String.isBlank(target)) {
                    return result;
                }
                audienceTypes.add(type);
            }

            result.status = audienceTypes.contains(AUDIENCE_TYPE_ALL_SUPPORTED_USERS)
                ? AllSupportedUsersSnapshotStatus.SNAPSHOT_V1_WITH_ALL_SUPPORTED_USERS
                : AllSupportedUsersSnapshotStatus.SNAPSHOT_V1_WITHOUT_ALL_SUPPORTED_USERS;
            result.safeErrorMessage = audienceTypes.contains(AUDIENCE_TYPE_ALL_SUPPORTED_USERS)
                ? null
                : DISTRIBUTION_DISABLED_ERROR;
        } catch (Exception ex) {
            return result;
        }
        return result;
    }

    private static Integer extractSnapshotVersion(Object rawValue) {
        if (rawValue == null) return null;
        if (rawValue instanceof Integer) {
            return (Integer) rawValue;
        }
        if (rawValue instanceof Long) {
            return Integer.valueOf(String.valueOf(rawValue));
        }
        if (rawValue instanceof Decimal) {
            Decimal decimalValue = (Decimal) rawValue;
            if (decimalValue.scale() != 0) return null;
            return Integer.valueOf(String.valueOf(decimalValue.intValue()));
        }
        return null;
    }

    private static String resolveReconciliationFailureMessage(DistributionMessageContext context) {
        String planEligibilityError = getCoordinatorEligibilityError(
            context == null || context.message == null
                ? null
                : context.message.BroadcastAudienceCriteriaSnapshot__c,
            context == null ? null : context.groupId
        );
        if (String.isNotBlank(planEligibilityError)) {
            return planEligibilityError;
        }
        return DISTRIBUTION_RECONCILIATION_ERROR;
    }

    private static Integer safeInteger(Integer value) {
        return value == null ? 0 : value;
    }

    private static String extractSnapshotText(Object rawValue) {
        if (!(rawValue instanceof String)) return null;
        return normalizeSnapshotText((String) rawValue);
    }

    private static String normalizeSnapshotText(String rawValue) {
        if (String.isBlank(rawValue)) return null;
        String value = rawValue.trim();
        return String.isBlank(value) ? null : value;
    }
}