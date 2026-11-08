public without sharing class CommunicatorBroadcastAllUsersBatch
implements Database.Batchable<SObject>, Database.Stateful {

    private static final String AUDIENCE_TYPE_ALL_SUPPORTED_USERS = 'AllSupportedUsers';

    private final Id messageId;
    private final Id threadId;
    private final Id senderId;
    private final Integer criterionIndex;

    private Boolean staleJob = false;
    private Boolean criticalFailure = false;
    private String criticalErrorMessage;

    public CommunicatorBroadcastAllUsersBatch(
        Id messageId,
        Id threadId,
        Id senderId,
        Integer criterionIndex
    ) {
        this.messageId = messageId;
        this.threadId = threadId;
        this.senderId = senderId;
        this.criterionIndex = criterionIndex == null ? 0 : criterionIndex;
    }

    public Database.QueryLocator start(Database.BatchableContext context) {
        CommunicatorBroadcastDistributionService.PhaseOneExecutionState state =
            CommunicatorBroadcastDistributionService.validatePhaseOneExecution(
                messageId,
                threadId,
                senderId,
                context == null ? null : context.getJobId(),
                criterionIndex,
                AUDIENCE_TYPE_ALL_SUPPORTED_USERS,
                null
            );
        staleJob = state.staleJob == true;
        criticalFailure = state.ready != true && state.staleJob != true;
        criticalErrorMessage = state.safeErrorMessage;
        if (staleJob || criticalFailure) {
            return Database.getQueryLocator([
                SELECT Id
                FROM User
                WHERE Id = null
            ]);
        }
        Set<Id> scopedRecipientIds =
            CommunicatorBroadcastDistributionService.getPhaseOneRecipientIdsForExecution(senderId);
        if (scopedRecipientIds != null) {
            if (scopedRecipientIds.isEmpty()) {
                return Database.getQueryLocator([
                    SELECT Id
                    FROM User
                    WHERE Id = null
                ]);
            }
            return Database.getQueryLocator([
                SELECT Id
                FROM User
                WHERE IsActive = true
                AND Id IN :scopedRecipientIds
            ]);
        }
        return Database.getQueryLocator([
            SELECT Id
            FROM User
            WHERE IsActive = true
            AND Id != :senderId
        ]);
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
                AUDIENCE_TYPE_ALL_SUPPORTED_USERS,
                null
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

        Set<Id> scopedUserIds = new Set<Id>();
        for (SObject recordItem : scope) {
            Id userId = (Id) recordItem.get('Id');
            if (userId != null && userId != senderId) {
                scopedUserIds.add(userId);
            }
        }
        if (scopedUserIds.isEmpty()) return;

        Map<Id, CommunicatorBroadcastAudienceService.UserAudienceCategory> categories =
            CommunicatorBroadcastAudienceService.classifyUsers(scopedUserIds);
        Set<Id> eligibleRecipients = new Set<Id>();
        for (Id userId : scopedUserIds) {
            CommunicatorBroadcastAudienceService.UserAudienceCategory category = categories.get(userId);
            if (category == CommunicatorBroadcastAudienceService.UserAudienceCategory.CORE_SALESFORCE ||
                category == CommunicatorBroadcastAudienceService.UserAudienceCategory.CORE_PLATFORM ||
                category == CommunicatorBroadcastAudienceService.UserAudienceCategory.COMMUNITY_PARTNER) {
                eligibleRecipients.add(userId);
            }
        }
        if (eligibleRecipients.isEmpty()) return;

        Savepoint savepoint = Database.setSavepoint();
        try {
            CommunicatorNotificationRecordService.createBroadcastNotificationsIfMissing(
                messageId,
                threadId,
                eligibleRecipients
            );
        } catch (Exception ex) {
            Database.rollback(savepoint);
            criticalFailure = true;
            criticalErrorMessage = CommunicatorBroadcastDistributionService.normalizeSafeErrorMessage(ex);
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
                AUDIENCE_TYPE_ALL_SUPPORTED_USERS,
                null
            );
            return;
        }
        CommunicatorBroadcastDistributionService.finalizePhaseOneSuccess(
            messageId,
            criterionIndex,
            context == null ? null : context.getJobId(),
            AUDIENCE_TYPE_ALL_SUPPORTED_USERS,
            null
        );
    }
}