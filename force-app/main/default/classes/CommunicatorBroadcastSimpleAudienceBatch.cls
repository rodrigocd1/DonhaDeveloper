public without sharing class CommunicatorBroadcastSimpleAudienceBatch
implements Database.Batchable<SObject>, Database.Stateful {

    private static final String AUDIENCE_TYPE_DIRECT_USER = 'DirectUser';
    private static final String AUDIENCE_TYPE_ROLE = 'Role';
    private static final String AUDIENCE_TYPE_SALES_COMPANY = 'SalesCompany';
    private static final String AUDIENCE_TYPE_JOB_TITLE = 'JobTitle';
    private static final String INVALID_SCOPE_ERROR =
        'O scope atual do executor simples e incompativel com o criterio do snapshot.';

    private final Id messageId;
    private final Id threadId;
    private final Id senderId;
    private final Integer criterionIndex;
    private final String audienceType;
    private final String targetId;

    private Boolean staleJob = false;
    private Boolean criticalFailure = false;
    private String criticalErrorMessage;

    @TestVisible private static Integer lastJobTitleScopeQueryCountForTest;

    public CommunicatorBroadcastSimpleAudienceBatch(
        Id messageId,
        Id threadId,
        Id senderId,
        Integer criterionIndex,
        String audienceType,
        String targetId
    ) {
        this.messageId = messageId;
        this.threadId = threadId;
        this.senderId = senderId;
        this.criterionIndex = criterionIndex == null ? 0 : criterionIndex;
        this.audienceType = audienceType;
        this.targetId = targetId;
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

        if (audienceType == AUDIENCE_TYPE_DIRECT_USER) {
            Id userId = tryParseId(targetId, User.SObjectType);
            return userId == null
                ? emptyUserQueryLocator()
                : Database.getQueryLocator([
                    SELECT Id
                    FROM User
                    WHERE Id = :userId
                ]);
        }
        if (audienceType == AUDIENCE_TYPE_ROLE) {
            Id roleId = tryParseId(targetId, UserRole.SObjectType);
            return roleId == null
                ? emptyUserQueryLocator()
                : Database.getQueryLocator([
                    SELECT Id
                    FROM User
                    WHERE IsActive = true
                    AND UserRoleId = :roleId
                ]);
        }
        if (audienceType == AUDIENCE_TYPE_SALES_COMPANY) {
            return Database.getQueryLocator([
                SELECT Id
                FROM User
                WHERE IsActive = true
                AND EmpresaVendas__c = :targetId
            ]);
        }
        if (audienceType == AUDIENCE_TYPE_JOB_TITLE) {
            Id jobTitleId = tryParseId(targetId, CargosDepartamentos__c.SObjectType);
            return jobTitleId == null
                ? emptyContactQueryLocator()
                : Database.getQueryLocator([
                    SELECT Id, Usuario__c
                    FROM Contact
                    WHERE Cargo__c = :jobTitleId
                    AND Usuario__c != null
                ]);
        }
        criticalFailure = true;
        criticalErrorMessage = 'O criterio atual do snapshot do comunicado esta invalido para a distribuicao.';
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
            Set<Id> scopedRecipientIds = audienceType == AUDIENCE_TYPE_JOB_TITLE
                ? resolveScopedJobTitleRecipientIds(scope)
                : resolveScopedUserRecipientIds(scope);
            if (scopedRecipientIds.isEmpty()) return;

            Savepoint savepoint = Database.setSavepoint();
            try {
                CommunicatorNotificationRecordService.createBroadcastNotificationsIfMissing(
                    messageId,
                    threadId,
                    scopedRecipientIds
                );
            } catch (Exception ex) {
                Database.rollback(savepoint);
                throw ex;
            }
        } catch (Exception ex) {
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

    private Set<Id> resolveScopedUserRecipientIds(List<SObject> scope) {
        assertScopeRecordType(scope, User.SObjectType);
        Set<Id> scopedUserIds = new Set<Id>();
        for (SObject recordItem : scope) {
            Id userId = (Id) recordItem.get('Id');
            if (userId != null && userId != senderId) {
                scopedUserIds.add(userId);
            }
        }
        if (scopedUserIds.isEmpty()) return new Set<Id>();

        Map<Id, CommunicatorBroadcastAudienceService.UserAudienceCategory> categories =
            CommunicatorBroadcastAudienceService.classifyUsers(scopedUserIds);
        Set<Id> eligibleRecipients = new Set<Id>();
        for (Id userId : scopedUserIds) {
            if (isSupportedCategory(categories.get(userId))) {
                eligibleRecipients.add(userId);
            }
        }
        return eligibleRecipients;
    }

    private Set<Id> resolveScopedJobTitleRecipientIds(List<SObject> scope) {
        assertScopeRecordType(scope, Contact.SObjectType);
        Set<Id> scopedUserIds = new Set<Id>();
        for (SObject recordItem : scope) {
            Id userId = (Id) recordItem.get('Usuario__c');
            if (userId != null && userId != senderId) {
                scopedUserIds.add(userId);
            }
        }
        if (Test.isRunningTest()) {
            lastJobTitleScopeQueryCountForTest = scopedUserIds.isEmpty() ? 0 : 1;
        }
        if (scopedUserIds.isEmpty()) return new Set<Id>();

        Map<Id, CommunicatorBroadcastAudienceService.UserAudienceCategory> categories =
            CommunicatorBroadcastAudienceService.classifyUsers(scopedUserIds);
        Set<Id> eligibleRecipients = new Set<Id>();
        for (Id userId : scopedUserIds) {
            if (isSupportedCategory(categories.get(userId))) {
                eligibleRecipients.add(userId);
            }
        }
        return eligibleRecipients;
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

    private static Boolean isSupportedCategory(
        CommunicatorBroadcastAudienceService.UserAudienceCategory category
    ) {
        return category == CommunicatorBroadcastAudienceService.UserAudienceCategory.CORE_SALESFORCE ||
            category == CommunicatorBroadcastAudienceService.UserAudienceCategory.CORE_PLATFORM ||
            category == CommunicatorBroadcastAudienceService.UserAudienceCategory.COMMUNITY_PARTNER;
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