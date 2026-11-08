/**
 * @description Backend operations and endpoint authorization for Broadcast communication.
 */
public without sharing class CommunicatorBroadcastService {

    private static final String GROUP_TYPE = 'Broadcast';
    private static final String THREAD_RECORD_TYPE = 'CommunicatorGroup__c';
    private static final String NOTIFICATION_TYPE = 'Broadcast';
    private static final String CUSTOM_NOTIFICATION_TYPE_NAME = 'CommunicatorBroadcast';
    private static final String AUDIENCE_TYPE_ALL_SUPPORTED_USERS = 'AllSupportedUsers';
    private static final String CUSTOM_NOTIFICATION_TITLE = 'Novo comunicado';
    private static final String CUSTOM_NOTIFICATION_INTERNAL_TARGET_PAGE_REF =
        '{"type":"standard__namedPage","attributes":{"pageName":"home"}}';
    private static final String CUSTOM_NOTIFICATION_COMMUNITY_TARGET_PAGE_REF =
        '{"type":"comm__namedPage","attributes":{"name":"comunicatorHistory__c"}}';
    private static final Integer CUSTOM_NOTIFICATION_CHUNK_SIZE = 50;
    private static final String MESSAGE_STATUS_SENT = 'Sent';
    private static final String CAPACITY_ERROR =
        'Não é possível enviar o comunicado porque a quantidade de destinatários excede o limite suportado para um envio único.';
    private static final Integer DEFAULT_PAGE_SIZE = 20;
    private static final Integer MAX_PAGE_SIZE = 200;
    private static final Integer MAX_SCAN_SIZE = 2000;
    private static final Integer MAX_SEARCH_RESULTS = 50;
    private static final String SNAPSHOT_OVERSIZED_ERROR =
        'Nao foi possivel enviar o comunicado porque a configuracao do publico excede o limite suportado para publicacao.';
    private static final Integer BROADCAST_AUDIENCE_CRITERIA_SNAPSHOT_VERSION = 1;
    private static final Integer BROADCAST_AUDIENCE_CRITERIA_SNAPSHOT_MAX_LENGTH = 131072;
    private static final String SUBJECT_REQUIRED_ERROR = 'Informe o assunto do comunicado.';
    private static final String EDIT_CONFIG_INVALID_ERROR =
        'A configuração de prazo para edição de Comunicados é inválida.';
    private static final String EDIT_EXPIRED_ERROR =
        'O prazo para edição deste comunicado expirou.';
    private static final String EDIT_SENT_AT_INVALID_ERROR =
        'Não foi possível validar o prazo para edição deste comunicado.';
    private static final String EDIT_DISTRIBUTION_IN_PROGRESS_ERROR =
        'Aguarde a conclusao da distribuicao antes de editar este comunicado.';
    private static final Set<String> CLIPBOARD_IMAGE_EXTENSIONS = new Set<String>{ 'png', 'jpg', 'jpeg' };
    private static final Set<String> CLIPBOARD_IMAGE_CONTENT_TYPES =
        new Set<String>{ 'image/png', 'image/jpeg' };
    private static final Integer CUSTOM_NOTIFICATION_BODY_MAX_LENGTH = 255;
    @TestVisible private static Boolean failBroadcastCustomNotificationSendForTest = false;
    @TestVisible private static Boolean failClipboardUploadAfterContentVersionInsertForTest = false;
    @TestVisible private static Set<Integer> failBroadcastCustomNotificationChunkNumbersForTest =
        new Set<Integer>();
    @TestVisible private static Integer broadcastCustomNotificationSendAttempts = 0;
    @TestVisible private static Set<String> lastBroadcastCustomNotificationRecipients = new Set<String>();
    @TestVisible private static List<Set<String>> broadcastCustomNotificationRecipientChunks =
        new List<Set<String>>();
    @TestVisible private static Datetime currentDatetimeOverrideForTest;
    @TestVisible private static List<Integer> broadcastCustomNotificationChunkRecipientCounts =
        new List<Integer>();
    @TestVisible private static Integer lastBroadcastCustomNotificationOriginalRecipientCount = 0;
    @TestVisible private static Integer lastBroadcastCustomNotificationEligibleRecipientCount = 0;
    @TestVisible private static Integer lastBroadcastCustomNotificationDiscardedRecipientCount = 0;
    @TestVisible
    private static Map<Id, CommunicatorBroadcastAudienceService.UserAudienceCategory>
        broadcastCustomNotificationRecipientCategoriesForTest;
    @TestVisible private static String broadcastAudienceCriteriaSnapshotOverrideForTest;
    @TestVisible private static String lastBroadcastCustomNotificationTypeName;
    @TestVisible private static String lastBroadcastCustomNotificationTargetPageRef;
    @TestVisible private static String lastBroadcastCustomNotificationTitle;
    @TestVisible private static String lastBroadcastCustomNotificationBody;
    @TestVisible private static List<String> broadcastCustomNotificationTargetPageRefsBySendAttempt =
        new List<String>();
    @TestVisible
    private static Map<String, Set<String>> broadcastCustomNotificationRecipientsByTargetPageRef =
        new Map<String, Set<String>>();
    @TestVisible
    private static Map<String, String> broadcastCustomNotificationBodiesByTargetPageRef =
        new Map<String, String>();

    private class BroadcastCursor {
        Datetime timestampValue;
        Id recordId;
    }

    private class AttachmentDmlPlan {
        Integer messageLinkRows = 0;
        Integer missingThreadLinkRows = 0;
        Integer missingNetworkLinkRows = 0;
        Integer linkUpdateRows = 0;
        Integer fileShareStatements = 0;
    }

    private class AttachmentEditState {
        List<Id> originalAttachmentIds = new List<Id>();
        Set<Id> originalAttachmentIdSet = new Set<Id>();
        List<Id> newAttachmentIds = new List<Id>();
        Set<Id> removedAttachmentIds = new Set<Id>();
        List<Id> finalAttachmentIds = new List<Id>();
        Id finalPrimaryAttachmentId;
    }

    private class BroadcastEditAccessResult {
        Boolean showEditAction = false;
        Boolean canEdit = false;
        Datetime editDeadline;
        String blockedReason;
    }

    private class BroadcastCustomNotificationRecipientPartition {
        Set<String> internalRecipientIds = new Set<String>();
        Set<String> communityRecipientIds = new Set<String>();
        Set<String> eligibleRecipientIds = new Set<String>();
    }

    private class BroadcastEditLimitContext {
        Boolean loaded = false;
        Integer limitDays;
        String errorMessage;
    }

    private class BroadcastAudienceCriteriaSnapshotCriterion {
        String k;
        String t;
        String i;
    }

    private class BroadcastAudienceCriteriaSnapshotPayload {
        Integer v;
        List<BroadcastAudienceCriteriaSnapshotCriterion> c;
    }

    private class QueuedBroadcastPublicationContext {
        Id messageId;
        Id threadId;
        Id senderId;
    }

    private virtual class LwcBroadcastReadAccessContext {
        Id groupId;
        Boolean canPublish = false;
    }

    private virtual class LwcBroadcastThreadReadAccessContext extends LwcBroadcastReadAccessContext {
        Id threadId;
    }

    private class LwcBroadcastMessageReadAccessContext extends LwcBroadcastThreadReadAccessContext {
        Id messageId;
    }

    public static CommunicatorGroup__c createBroadcast(
        String name,
        String description,
        List<CommunicatorBroadcastAudience__c> criteria
    ) {
        Datetime nowValue = System.now();
        return CommunicatorBroadcastAudienceService.createBroadcastGroupForLwc(
            name,
            description,
            criteria,
            nowValue
        );
    }

    public static CommunicatorDTOs.BroadcastAuthoringContextDTO getBroadcastAuthoringContext() {
        CommunicatorDTOs.BroadcastAuthoringContextDTO response =
            new CommunicatorDTOs.BroadcastAuthoringContextDTO();
        response.canCreateBroadcast = CommunicatorBroadcastAudienceService.canCurrentUserCreateBroadcast();
        response.maxClipboardBroadcastImageSizeMB =
            CommunicatorConfigService.getMaxClipboardBroadcastImageSizeMB();
        try {
            response.maxUploadBroadcastFileSizeMB = CommunicatorConfigService.getMaxUploadBroadcastFileSizeMB();
            response.uploadConfigValid = true;
            response.uploadConfigErrorMessage = null;
        } catch (Exception ex) {
            response.maxUploadBroadcastFileSizeMB = null;
            response.uploadConfigValid = false;
            response.uploadConfigErrorMessage = ex == null ? null : ex.getMessage();
        }
        return response;
    }

    public static void replaceBroadcastAudience(
        Id broadcastGroupId,
        List<CommunicatorBroadcastAudience__c> criteria
    ) {
        lockBroadcastGroup(broadcastGroupId);
        CommunicatorBroadcastAudienceService.replaceAudienceCriteriaForLwc(broadcastGroupId, criteria);
    }

    public static CommunicatorDTOs.BroadcastDetailsDTO getBroadcastDetails(Id broadcastGroupId) {
        CommunicatorGroup__c groupRecord = loadBroadcastGroup(broadcastGroupId, true);
        LwcBroadcastReadAccessContext accessContext = requireReadableBroadcastGroupForLwc(groupRecord.Id);
        if (accessContext.canPublish != true) {
            throw new CommunicatorException('Somente o criador autorizado pode alterar este comunicado.');
        }

        CommunicatorThread__c threadRecord = findActiveBroadcastThread(groupRecord.Id, false);
        CommunicatorDTOs.BroadcastDetailsDTO response = new CommunicatorDTOs.BroadcastDetailsDTO();
        response.broadcast = buildListItem(
            groupRecord,
            threadRecord,
            threadRecord == null ? new Map<Id, Integer>() : getUnreadByThread(new Set<Id>{ threadRecord.Id }),
            true
        );
        response.audiences = [
            SELECT Id, CommunicatorGroup__c, AudienceKey__c, AudienceType__c, TargetId__c,
                   TargetName__c, SortOrder__c, IsActive__c
            FROM CommunicatorBroadcastAudience__c
            WHERE CommunicatorGroup__c = :groupRecord.Id
            AND IsActive__c = true
            ORDER BY SortOrder__c ASC, CreatedDate ASC, Id ASC
        ];
        return response;
    }

    public static CommunicatorDTOs.BroadcastListPageDTO getBroadcastList(
        Integer pageSize,
        String cursor
    ) {
        Integer size = normalizePageSize(pageSize);
        BroadcastCursor parsedCursor = parseCursor(cursor);
        Integer scanSize = Math.min(MAX_SCAN_SIZE, Math.max(size + 1, size * 5));
        BroadcastCursor scanCursor = parsedCursor;
        List<CommunicatorDTOs.BroadcastListItemDTO> items =
            new List<CommunicatorDTOs.BroadcastListItemDTO>();
        Boolean exhausted = false;
        String nextCursor = null;

        while (items.size() < size && !exhausted) {
            List<CommunicatorGroup__c> candidateGroups = queryBroadcastGroups(scanCursor, scanSize);
            if (candidateGroups.isEmpty()) {
                exhausted = true;
                break;
            }

            Set<Id> candidateGroupIds = new Set<Id>();
            for (CommunicatorGroup__c groupRecord : candidateGroups) {
                candidateGroupIds.add(groupRecord.Id);
            }
            Map<Id, CommunicatorBroadcastLwcAccessService.GroupAccessDecision> accessByGroup =
                CommunicatorBroadcastLwcAccessService.evaluateGroupAccess(candidateGroupIds);
            Map<Id, CommunicatorThread__c> threadByGroup = loadBestActiveBroadcastThreads(candidateGroupIds);
            Set<Id> threadIds = new Set<Id>();
            for (CommunicatorThread__c threadRecord : threadByGroup.values()) {
                threadIds.add(threadRecord.Id);
            }
            Map<Id, Integer> unreadByThread = getUnreadByThread(threadIds);

            BroadcastCursor lastProcessedCursor;
            BroadcastCursor lastEmittedCursor;
            for (CommunicatorGroup__c groupRecord : candidateGroups) {
                lastProcessedCursor = new BroadcastCursor();
                lastProcessedCursor.timestampValue = groupRecord.BroadcastLastActivityAt__c;
                lastProcessedCursor.recordId = groupRecord.Id;

                CommunicatorBroadcastLwcAccessService.GroupAccessDecision accessDecision =
                    accessByGroup.get(groupRecord.Id);
                if (accessDecision == null || accessDecision.canAccessGroup != true) continue;

                CommunicatorThread__c threadRecord = threadByGroup.get(groupRecord.Id);
                Boolean canManageGroup = accessDecision.canPublish == true;
                if (!canManageGroup && threadRecord != null && threadRecord.LastMessageAt__c == null) {
                    threadRecord = null;
                }
                items.add(buildListItem(groupRecord, threadRecord, unreadByThread, canManageGroup));
                lastEmittedCursor = lastProcessedCursor;
                if (items.size() >= size) break;
            }

            if (items.size() >= size) {
                nextCursor = serializeCursor(lastEmittedCursor.timestampValue, lastEmittedCursor.recordId);
                break;
            }

            if (candidateGroups.size() < scanSize) {
                exhausted = true;
                break;
            }

            scanCursor = lastProcessedCursor;
        }

        CommunicatorDTOs.BroadcastListPageDTO response = new CommunicatorDTOs.BroadcastListPageDTO();
        response.items = items;
        response.nextCursor = exhausted ? null : nextCursor;
        return response;
    }

    public static List<CommunicatorDTOs.BroadcastListItemDTO> getBroadcastDrafts() {
        return new List<CommunicatorDTOs.BroadcastListItemDTO>();
    }

    public static CommunicatorDTOs.BroadcastThreadDTO getBroadcastThread(Id broadcastGroupId) {
        LwcBroadcastReadAccessContext accessContext =
            requireReadableBroadcastGroupForLwc(broadcastGroupId);
        CommunicatorGroup__c groupRecord = loadBroadcastGroup(broadcastGroupId, true);
        Boolean canManageBroadcast = accessContext.canPublish == true;
        CommunicatorThread__c threadRecord = findActiveBroadcastThread(
            broadcastGroupId,
            !canManageBroadcast
        );

        CommunicatorDTOs.BroadcastThreadDTO response = new CommunicatorDTOs.BroadcastThreadDTO();
        response.broadcast = buildListItem(
            groupRecord,
            threadRecord,
            threadRecord == null ? new Map<Id, Integer>() : getUnreadByThread(new Set<Id>{ threadRecord.Id }),
            canManageBroadcast
        );
        response.thread = threadRecord;
        return response;
    }

    public static List<CommunicatorMessage__c> getBroadcastMessages(
        Id threadId,
        Integer pageSize,
        Integer offsetVal
    ) {
        LwcBroadcastThreadReadAccessContext accessContext =
            requireReadableBroadcastThreadForLwc(threadId);
        Boolean canManageBroadcast = accessContext.canPublish == true;
        reconcilePendingDistributionsForThread(threadId, canManageBroadcast);
        Integer size = normalizePageSize(pageSize);
        Integer offset = offsetVal != null && offsetVal > 0 ? offsetVal : 0;
        return queryVisibleBroadcastMessages(threadId, size, offset, canManageBroadcast);
    }

    public static List<CommunicatorDTOs.BroadcastMessageDTO> getBroadcastMessageViews(
        Id threadId,
        Integer pageSize,
        Integer offsetVal
    ) {
        LwcBroadcastThreadReadAccessContext accessContext =
            requireReadableBroadcastThreadForLwc(threadId);
        Boolean canManageBroadcast = accessContext.canPublish == true;
        reconcilePendingDistributionsForThread(threadId, canManageBroadcast);
        Integer size = normalizePageSize(pageSize);
        Integer offset = offsetVal != null && offsetVal > 0 ? offsetVal : 0;
        return buildBroadcastMessageViews(
            queryVisibleBroadcastMessages(threadId, size, offset, canManageBroadcast),
            canManageBroadcast
        );
    }

    public static Integer getBroadcastMessageCount(Id threadId) {
        LwcBroadcastThreadReadAccessContext accessContext =
            requireReadableBroadcastThreadForLwc(threadId);
        Boolean canManageBroadcast = accessContext.canPublish == true;
        return canManageBroadcast
            ? [
                SELECT COUNT()
                FROM CommunicatorMessage__c
                WHERE Thread__c = :threadId
            ]
            : [
                SELECT COUNT()
                FROM CommunicatorMessage__c
                WHERE Thread__c = :threadId
                AND Status__c = :MESSAGE_STATUS_SENT
            ];
    }

    public static Integer getBroadcastMessageOffset(Id threadId, Id messageId) {
        LwcBroadcastThreadReadAccessContext accessContext =
            requireReadableBroadcastThreadForLwc(threadId);
        Boolean canManageBroadcast = accessContext.canPublish == true;
        List<CommunicatorMessage__c> targetMessages = canManageBroadcast
            ? [
                SELECT SentAt__c
                FROM CommunicatorMessage__c
                WHERE Id = :messageId
                AND Thread__c = :threadId
                LIMIT 1
            ]
            : [
                SELECT SentAt__c
                FROM CommunicatorMessage__c
                WHERE Id = :messageId
                AND Thread__c = :threadId
                AND Status__c = :MESSAGE_STATUS_SENT
                LIMIT 1
            ];
        if (targetMessages.isEmpty()) {
            throw new CommunicatorException('Mensagem nao encontrada neste comunicado.');
        }
        Integer baseOffset = canManageBroadcast
            ? [
                SELECT COUNT()
                FROM CommunicatorMessage__c
                WHERE Thread__c = :threadId
                AND (
                    SentAt__c < :targetMessages[0].SentAt__c
                    OR (SentAt__c = :targetMessages[0].SentAt__c AND Id < :messageId)
                )
            ]
            : [
                SELECT COUNT()
                FROM CommunicatorMessage__c
                WHERE Thread__c = :threadId
                AND Status__c = :MESSAGE_STATUS_SENT
                AND (
                    SentAt__c < :targetMessages[0].SentAt__c
                    OR (SentAt__c = :targetMessages[0].SentAt__c AND Id < :messageId)
                )
            ];
        return baseOffset;
    }

    public static CommunicatorDTOs.BroadcastPollPageDTO pollBroadcastMessages(
        Id threadId,
        String cursor
    ) {
        LwcBroadcastThreadReadAccessContext accessContext =
            requireReadableBroadcastThreadForLwc(threadId);
        Boolean canManageBroadcast = accessContext.canPublish == true;
        reconcilePendingDistributionsForThread(threadId, canManageBroadcast);
        BroadcastCursor parsedCursor = parseCursor(cursor);
        List<CommunicatorMessage__c> messages =
            queryVisibleBroadcastMessagesForPoll(threadId, parsedCursor, canManageBroadcast);

        CommunicatorDTOs.BroadcastPollPageDTO response = new CommunicatorDTOs.BroadcastPollPageDTO();
        response.messages = buildBroadcastMessageViews(messages, canManageBroadcast);
        response.nextCursor = cursor;
        if (!messages.isEmpty()) {
            CommunicatorMessage__c lastMessage = messages[messages.size() - 1];
            response.nextCursor = serializeCursor(lastMessage.SystemModstamp, lastMessage.Id);
        }
        return response;
    }

    public static List<CommunicatorMessage__c> searchBroadcastMessages(Id threadId, String keyword) {
        LwcBroadcastThreadReadAccessContext accessContext =
            requireReadableBroadcastThreadForLwc(threadId);
        Boolean canManageBroadcast = accessContext.canPublish == true;
        reconcilePendingDistributionsForThread(threadId, canManageBroadcast);
        if (String.isBlank(keyword)) {
            throw new CommunicatorException('Search keyword cannot be empty.');
        }

        String likePattern = '%' + sanitizeSearchKeyword(keyword) + '%';
        return queryVisibleBroadcastMessagesByKeyword(threadId, likePattern, canManageBroadcast);
    }

    public static List<CommunicatorDTOs.BroadcastMessageDTO> searchBroadcastMessageViews(
        Id threadId,
        String keyword
    ) {
        LwcBroadcastThreadReadAccessContext accessContext =
            requireReadableBroadcastThreadForLwc(threadId);
        Boolean canManageBroadcast = accessContext.canPublish == true;
        reconcilePendingDistributionsForThread(threadId, canManageBroadcast);
        if (String.isBlank(keyword)) {
            throw new CommunicatorException('Search keyword cannot be empty.');
        }

        String likePattern = '%' + sanitizeSearchKeyword(keyword) + '%';
        return buildBroadcastMessageViews(
            queryVisibleBroadcastMessagesByKeyword(threadId, likePattern, canManageBroadcast),
            canManageBroadcast
        );
    }

    public static CommunicatorMessage__c publishBroadcastMessage(
        Id broadcastGroupId,
        String body,
        List<Id> contentDocumentIds
    ) {
        return publishBroadcastMessage(broadcastGroupId, body, body, contentDocumentIds);
    }

    public static CommunicatorMessage__c publishBroadcastMessage(
        Id broadcastGroupId,
        String subject,
        String body,
        List<Id> contentDocumentIds
    ) {
        CommunicatorGroup__c lockedGroup = lockBroadcastGroup(broadcastGroupId);
        if (!CommunicatorBroadcastAudienceService.canCurrentUserPublishToBroadcast(lockedGroup.Id)) {
            throw new CommunicatorException('Somente o criador autorizado pode publicar neste comunicado.');
        }
        if (String.isBlank(body) && (contentDocumentIds == null || contentDocumentIds.isEmpty())) {
            throw new CommunicatorException('Informe uma mensagem ou ao menos um anexo.');
        }
        String normalizedSubject = normalizeBroadcastSubject(subject);
        validateBroadcastSubject(normalizedSubject);

        String criteriaSnapshot = null;
        if (CommunicatorBroadcastAudienceService.hasActiveAudienceType(
            lockedGroup.Id,
            AUDIENCE_TYPE_ALL_SUPPORTED_USERS
        )) {
            criteriaSnapshot = buildBroadcastAudienceCriteriaSnapshot(lockedGroup.Id);
            validateBroadcastAudienceCriteriaSnapshotSize(criteriaSnapshot);
            if (canLegacyAllSupportedUsersOnlyPublishUseQueuedPath(criteriaSnapshot)) {
                return publishQueuedBroadcastMessageForLwc(
                    lockedGroup,
                    normalizedSubject,
                    body,
                    contentDocumentIds,
                    criteriaSnapshot
                );
            }
        }

        return publishSynchronousBroadcastMessage(
            lockedGroup,
            normalizedSubject,
            body,
            contentDocumentIds
        );
    }

    public static CommunicatorMessage__c publishBroadcastMessageForLwc(
        Id broadcastGroupId,
        String subject,
        String body,
        List<Id> contentDocumentIds
    ) {
        CommunicatorGroup__c lockedGroup = lockBroadcastGroup(broadcastGroupId);
        if (!CommunicatorBroadcastAudienceService.canCurrentUserPublishToBroadcast(lockedGroup.Id)) {
            throw new CommunicatorException('Somente o criador autorizado pode publicar neste comunicado.');
        }
        if (String.isBlank(body) && (contentDocumentIds == null || contentDocumentIds.isEmpty())) {
            throw new CommunicatorException('Informe uma mensagem ou ao menos um anexo.');
        }
        String normalizedSubject = normalizeBroadcastSubject(subject);
        validateBroadcastSubject(normalizedSubject);

        String criteriaSnapshot = buildBroadcastAudienceCriteriaSnapshot(lockedGroup.Id);
        validateBroadcastAudienceCriteriaSnapshotSize(criteriaSnapshot);
        String eligibilityError = CommunicatorBroadcastDistributionService.getCoordinatorEligibilityError(
            criteriaSnapshot,
            null
        );
        if (String.isNotBlank(eligibilityError)) {
            throw new CommunicatorException(eligibilityError);
        }

        return publishQueuedBroadcastMessageForLwc(
            lockedGroup,
            normalizedSubject,
            body,
            contentDocumentIds,
            criteriaSnapshot
        );
    }

    private static Boolean canLegacyAllSupportedUsersOnlyPublishUseQueuedPath(String criteriaSnapshot) {
        if (String.isBlank(criteriaSnapshot)) return false;
        try {
            Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(criteriaSnapshot);
            List<Object> rawCriteria = payload == null ? null : (List<Object>) payload.get('c');
            if (rawCriteria == null || rawCriteria.isEmpty()) return false;
            for (Object rawCriterion : rawCriteria) {
                Map<String, Object> criterion = (Map<String, Object>) rawCriterion;
                if (criterion == null ||
                    String.valueOf(criterion.get('t')) != AUDIENCE_TYPE_ALL_SUPPORTED_USERS) {
                    return false;
                }
            }
            return CommunicatorBroadcastDistributionService.canCurrentCoordinatorProcessSnapshot(
                criteriaSnapshot,
                null
            );
        } catch (Exception ex) {
            return false;
        }
    }

    private static CommunicatorMessage__c publishSynchronousBroadcastMessage(
        CommunicatorGroup__c lockedGroup,
        String normalizedSubject,
        String body,
        List<Id> contentDocumentIds
    ) {
        Set<Id> recipients =
            CommunicatorBroadcastAudienceService.validateCurrentAudienceForPublish(lockedGroup.Id);
        recipients.remove(UserInfo.getUserId());
        if (recipients.isEmpty()) {
            throw new CommunicatorException(
                'Não é possível enviar o comunicado porque não existem destinatários válidos no momento. Revise o público selecionado.'
            );
        }

        List<Id> attachmentIds = validateAttachmentsForPublish(lockedGroup.Id, contentDocumentIds);
        CommunicatorThread__c existingThread = findActiveBroadcastThread(lockedGroup.Id, false);
        Id networkId = Network.getNetworkId();
        AttachmentDmlPlan attachmentPlan = buildAttachmentDmlPlan(
            attachmentIds,
            existingThread == null ? null : existingThread.Id,
            networkId
        );

        Integer requiredRows = calculateRequiredDmlRows(
            existingThread == null,
            attachmentPlan.messageLinkRows,
            attachmentPlan.missingThreadLinkRows,
            attachmentPlan.missingNetworkLinkRows,
            attachmentPlan.linkUpdateRows,
            recipients.size()
        );
        Integer requiredStatements = calculateRequiredDmlStatements(
            existingThread == null,
            attachmentIds.isEmpty(),
            attachmentPlan.fileShareStatements,
            !recipients.isEmpty()
        );
        Integer availableRows = Limits.getLimitDmlRows() - Limits.getDmlRows();
        Integer availableStatements = Limits.getLimitDmlStatements() - Limits.getDmlStatements();
        if (requiredRows > availableRows || requiredStatements > availableStatements) {
            throw new CommunicatorException(CAPACITY_ERROR);
        }

        Savepoint savepoint = Database.setSavepoint();
        try {
            Datetime nowValue = System.now();
            CommunicatorThread__c threadRecord = getOrCreateBroadcastThread(lockedGroup.Id, existingThread);

            CommunicatorMessage__c message = new CommunicatorMessage__c(
                Thread__c = threadRecord.Id,
                Subject__c = normalizedSubject,
                Body__c = String.isBlank(body) ? null : body.trim(),
                Sender__c = UserInfo.getUserId(),
                SentAt__c = nowValue,
                Status__c = MESSAGE_STATUS_SENT,
                HasAttachment__c = !attachmentIds.isEmpty(),
                ContentDocumentId__c = attachmentIds.isEmpty()
                    ? null
                    : String.valueOf(attachmentIds[0]),
                HasMention__c = false,
                IsSystemMessage__c = false
            );
            CommunicatorBroadcastDmlGuardHandler.authorizeMessageDml(
                'INSERT', new List<CommunicatorMessage__c>{ message }
            );
            try {
                insert message;
            } finally {
                CommunicatorBroadcastDmlGuardHandler.clearOfficialAuthorization();
            }

            if (!attachmentIds.isEmpty()) {
                CommunicatorMessageService.linkAttachmentsForAuthorizedBroadcast(
                    message.Id, threadRecord.Id, attachmentIds
                );
            }

            threadRecord.LastMessageAt__c = nowValue;
            CommunicatorBroadcastDmlGuardHandler.authorizeThreadDml(
                'UPDATE', new List<CommunicatorThread__c>{ threadRecord }
            );
            try {
                update threadRecord;
            } finally {
                CommunicatorBroadcastDmlGuardHandler.clearOfficialAuthorization();
            }

            CommunicatorBroadcastAudienceService.updateBroadcastActivity(lockedGroup.Id, nowValue);

            CommunicatorNotificationRecordService.createBroadcastNotifications(
                message.Id, threadRecord.Id, recipients
            );
            sendBroadcastCustomNotification(recipients, message.Subject__c);
            return queryBroadcastMessage(message.Id);
        } catch (Exception ex) {
            Database.rollback(savepoint);
            CommunicatorBroadcastDmlGuardHandler.clearOfficialAuthorization();
            throw ex;
        }
    }

    private static CommunicatorMessage__c publishQueuedBroadcastMessageForLwc(
        CommunicatorGroup__c lockedGroup,
        String normalizedSubject,
        String body,
        List<Id> contentDocumentIds,
        String criteriaSnapshot
    ) {
        validateBroadcastAudienceCriteriaSnapshotSize(criteriaSnapshot);

        List<Id> attachmentIds = validateAttachmentsForPublish(lockedGroup.Id, contentDocumentIds);
        CommunicatorThread__c existingThread = findActiveBroadcastThread(lockedGroup.Id, false);
        Id networkId = Network.getNetworkId();
        AttachmentDmlPlan attachmentPlan = buildAttachmentDmlPlan(
            attachmentIds,
            existingThread == null ? null : existingThread.Id,
            networkId
        );

        Savepoint savepoint = Database.setSavepoint();
        try {
            QueuedBroadcastPublicationContext publicationContext =
                createQueuedBroadcastMessageForLwc(
                    lockedGroup,
                    normalizedSubject,
                    body,
                    criteriaSnapshot,
                    attachmentIds,
                    existingThread,
                    attachmentPlan
                );

            CommunicatorBroadcastDistributionService.enqueuePhaseOneDistribution(
                publicationContext.messageId,
                publicationContext.threadId,
                publicationContext.senderId
            );
            return queryBroadcastMessage(publicationContext.messageId);
        } catch (Exception ex) {
            Database.rollback(savepoint);
            CommunicatorBroadcastDmlGuardHandler.clearOfficialAuthorization();
            throw ex;
        }
    }

    private static QueuedBroadcastPublicationContext createQueuedBroadcastMessageForLwc(
        CommunicatorGroup__c lockedGroup,
        String normalizedSubject,
        String body,
        String criteriaSnapshot,
        List<Id> attachmentIds,
        CommunicatorThread__c existingThread,
        AttachmentDmlPlan attachmentPlan
    ) {
        Integer requiredRows = calculateRequiredDmlRows(
            existingThread == null,
            attachmentPlan == null ? 0 : attachmentPlan.messageLinkRows,
            attachmentPlan == null ? 0 : attachmentPlan.missingThreadLinkRows,
            attachmentPlan == null ? 0 : attachmentPlan.missingNetworkLinkRows,
            attachmentPlan == null ? 0 : attachmentPlan.linkUpdateRows,
            0
        );
        Integer requiredStatements = calculateRequiredDmlStatements(
            existingThread == null,
            attachmentIds == null || attachmentIds.isEmpty(),
            attachmentPlan == null ? 0 : attachmentPlan.fileShareStatements,
            false
        );
        Integer availableRows = Limits.getLimitDmlRows() - Limits.getDmlRows();
        Integer availableStatements = Limits.getLimitDmlStatements() - Limits.getDmlStatements();
        if (requiredRows > availableRows || requiredStatements > availableStatements) {
            throw new CommunicatorException(CAPACITY_ERROR);
        }

        Datetime nowValue = System.now();
        CommunicatorThread__c threadRecord = getOrCreateBroadcastThread(lockedGroup.Id, existingThread);
        CommunicatorMessage__c message = new CommunicatorMessage__c(
            Thread__c = threadRecord.Id,
            Subject__c = normalizedSubject,
            Body__c = String.isBlank(body) ? null : body.trim(),
            Sender__c = UserInfo.getUserId(),
            SentAt__c = nowValue,
            Status__c = CommunicatorBroadcastDistributionService.STATUS_QUEUED,
            HasAttachment__c = attachmentIds != null && !attachmentIds.isEmpty(),
            ContentDocumentId__c = attachmentIds == null || attachmentIds.isEmpty()
                ? null
                : String.valueOf(attachmentIds[0]),
            HasMention__c = false,
            IsSystemMessage__c = false,
            BroadcastAudienceCriteriaSnapshot__c = criteriaSnapshot,
            BroadcastDistributionJobId__c = null,
            BroadcastDistributionError__c = null,
            BroadcastDistributionCompletedAt__c = null
        );
        CommunicatorBroadcastDmlGuardHandler.authorizeMessageDml(
            'INSERT', new List<CommunicatorMessage__c>{ message }
        );
        try {
            insert message;
        } finally {
            CommunicatorBroadcastDmlGuardHandler.clearOfficialAuthorization();
        }

        if (attachmentIds != null && !attachmentIds.isEmpty()) {
            CommunicatorMessageService.linkAttachmentsForAuthorizedBroadcast(
                message.Id, threadRecord.Id, attachmentIds
            );
        }

        QueuedBroadcastPublicationContext publicationContext =
            new QueuedBroadcastPublicationContext();
        publicationContext.messageId = message.Id;
        publicationContext.threadId = threadRecord.Id;
        publicationContext.senderId = message.Sender__c;
        return publicationContext;
    }

    private static CommunicatorThread__c getOrCreateBroadcastThread(
        Id groupId,
        CommunicatorThread__c existingThread
    ) {
        CommunicatorThread__c threadRecord = existingThread;
        if (threadRecord != null) return threadRecord;

        threadRecord = new CommunicatorThread__c(
            RecordId__c = String.valueOf(groupId),
            RecordType__c = THREAD_RECORD_TYPE,
            Stage__c = 'group',
            Status__c = 'Active',
            UnreadCount__c = 0,
            IsBroadcast__c = true
        );
        CommunicatorBroadcastDmlGuardHandler.authorizeThreadDml(
            'INSERT',
            new List<CommunicatorThread__c>{ threadRecord }
        );
        try {
            insert threadRecord;
        } finally {
            CommunicatorBroadcastDmlGuardHandler.clearOfficialAuthorization();
        }
        return [
            SELECT Id, Name, RecordId__c, RecordType__c, Status__c, Stage__c,
                   LastMessageAt__c, UnreadCount__c, IsBroadcast__c
            FROM CommunicatorThread__c
            WHERE Id = :threadRecord.Id
            LIMIT 1
        ];
    }

    public static CommunicatorMessage__c editBroadcastMessage(Id messageId, String body) {
        return editBroadcastMessage(messageId, body, body);
    }

    public static CommunicatorMessage__c editBroadcastMessage(Id messageId, String subject, String body) {
        return editBroadcastMessage(messageId, subject, body, null, null);
    }

    public static CommunicatorMessage__c editBroadcastMessage(
        Id messageId,
        String subject,
        String body,
        List<Id> newContentDocumentIds,
        List<Id> removedContentDocumentIds
    ) {
        if (messageId == null || String.isBlank(body)) {
            throw new CommunicatorException('Informe a mensagem e o novo conteudo.');
        }
        String normalizedSubject = normalizeBroadcastSubject(subject);
        validateBroadcastSubject(normalizedSubject);
        List<CommunicatorMessage__c> messages = [
            SELECT Id, Thread__c, Subject__c, Body__c, Sender__c, SentAt__c, Status__c,
                   HasAttachment__c, ContentDocumentId__c, HasMention__c,
                   IsSystemMessage__c, EditedAt__c
            FROM CommunicatorMessage__c
            WHERE Id = :messageId
            LIMIT 1
        ];
        if (messages.isEmpty()) throw new CommunicatorException('Mensagem não encontrada.');
        CommunicatorMessage__c message = messages[0];
        LwcBroadcastMessageReadAccessContext accessContext =
            requireReadableBroadcastMessageForLwc(message.Id);
        if (message.Sender__c != UserInfo.getUserId() || accessContext.canPublish != true) {
            throw new CommunicatorException('Somente o remetente autorizado pode editar esta mensagem.');
        }
        assertBroadcastMessageEditable(message, accessContext.canPublish, getCurrentDatetime());

        AttachmentEditState attachmentState = buildAttachmentEditState(
            message,
            accessContext.groupId,
            newContentDocumentIds,
            removedContentDocumentIds
        );

        String originalSubject = message.Subject__c;
        String originalBody = message.Body__c;
        String finalBody = body.trim();
        Boolean contentChanged = originalSubject != normalizedSubject || originalBody != finalBody;

        Savepoint savepoint = Database.setSavepoint();
        message.Subject__c = normalizedSubject;
        message.Body__c = finalBody;
        message.EditedAt__c = System.now();
        try {
            message.HasAttachment__c = !attachmentState.finalAttachmentIds.isEmpty();
            message.ContentDocumentId__c = attachmentState.finalPrimaryAttachmentId == null
                ? null
                : String.valueOf(attachmentState.finalPrimaryAttachmentId);
            CommunicatorBroadcastDmlGuardHandler.authorizeMessageDml(
                'UPDATE', new List<CommunicatorMessage__c>{ message }
            );
            try {
                update message;
            } finally {
                CommunicatorBroadcastDmlGuardHandler.clearOfficialAuthorization();
            }

            if (!attachmentState.newAttachmentIds.isEmpty()) {
                CommunicatorMessageService.linkAttachmentsForAuthorizedBroadcast(
                    message.Id, message.Thread__c, attachmentState.newAttachmentIds
                );
            }
            if (!attachmentState.removedAttachmentIds.isEmpty()) {
                delete [
                    SELECT Id
                    FROM ContentDocument
                    WHERE Id IN :attachmentState.removedAttachmentIds
                ];
            }
            if (contentChanged) {
                CommunicatorNotificationRecordService.reopenReadBroadcastNotificationsForMessage(
                    message.Id,
                    message.Thread__c,
                    message.Sender__c
                );
            }
        } catch (Exception ex) {
            Database.rollback(savepoint);
            CommunicatorBroadcastDmlGuardHandler.clearOfficialAuthorization();
            throw ex;
        }
        return queryBroadcastMessage(message.Id);
    }

    public static Integer getBroadcastUnreadCount(Id threadId) {
        requireReadableBroadcastThreadForLwc(threadId);
        Map<Id, Integer> unreadByThread = getUnreadByThread(new Set<Id>{ threadId });
        return unreadByThread.containsKey(threadId) ? unreadByThread.get(threadId) : 0;
    }

    public static Integer getBroadcastUnreadTotal() {
        Integer total = 0;
        for (Integer countValue : getAccessibleUnreadByThreadForLwc(null).values()) {
            total += countValue;
        }
        return total;
    }

    public static Map<Id, Integer> getBroadcastUnreadCountsByThread(Set<Id> threadIds) {
        return getAccessibleUnreadByThreadForLwc(threadIds);
    }

    public static void markBroadcastAsRead(Id threadId) {
        requireReadableBroadcastThreadForLwc(threadId);
        CommunicatorNotificationRecordService.markBroadcastNotificationsAsRead(threadId);
    }

    public static CommunicatorMessage__c retryBroadcastDistribution(Id messageId) {
        if (messageId == null) {
            throw new CommunicatorException('Informe a mensagem do comunicado.');
        }
        CommunicatorMessage__c message = [
            SELECT Id, Thread__c, Body__c, Sender__c, SentAt__c, Status__c,
                   HasAttachment__c, ContentDocumentId__c, HasMention__c,
                   IsSystemMessage__c, EditedAt__c, BroadcastDistributionJobId__c,
                   BroadcastDistributionError__c, BroadcastDistributionCompletedAt__c,
                   BroadcastAudienceCriteriaSnapshot__c
            FROM CommunicatorMessage__c
            WHERE Id = :messageId
            LIMIT 1
            FOR UPDATE
        ];
        LwcBroadcastMessageReadAccessContext accessContext =
            requireReadableBroadcastMessageForLwc(message.Id);
        if (accessContext.canPublish != true || message.Sender__c != UserInfo.getUserId()) {
            throw new CommunicatorException('Somente o remetente autorizado pode reenfileirar este comunicado.');
        }
        if (message.Status__c != CommunicatorBroadcastDistributionService.STATUS_FAILED) {
            throw new CommunicatorException('Somente comunicados com falha podem ser reenfileirados.');
        }
        String coordinatorEligibilityError =
            CommunicatorBroadcastDistributionService.getCoordinatorEligibilityError(
                message.BroadcastAudienceCriteriaSnapshot__c,
                accessContext.groupId
            );
        if (String.isNotBlank(coordinatorEligibilityError)) {
            throw new CommunicatorException(coordinatorEligibilityError);
        }

        Savepoint savepoint = Database.setSavepoint();
        try {
            message.Status__c = CommunicatorBroadcastDistributionService.STATUS_QUEUED;
            message.BroadcastDistributionJobId__c = null;
            message.BroadcastDistributionError__c = null;
            message.BroadcastDistributionCompletedAt__c = null;
            CommunicatorBroadcastDmlGuardHandler.authorizeMessageDml(
                'UPDATE',
                new List<CommunicatorMessage__c>{ message }
            );
            try {
                update message;
            } finally {
                CommunicatorBroadcastDmlGuardHandler.clearOfficialAuthorization();
            }

            CommunicatorBroadcastDistributionService.enqueuePhaseOneDistribution(
                message.Id,
                message.Thread__c,
                message.Sender__c
            );
            return queryBroadcastMessage(message.Id);
        } catch (Exception ex) {
            Database.rollback(savepoint);
            CommunicatorBroadcastDmlGuardHandler.clearOfficialAuthorization();
            throw ex;
        }
    }

    public static CommunicatorDTOs.UploadValidationResultDTO validateBroadcastUploadedFiles(
        Id broadcastGroupId,
        List<String> contentDocumentIds
    ) {
        if (!CommunicatorBroadcastAudienceService.canCurrentUserPublishToBroadcast(broadcastGroupId)) {
            throw new CommunicatorException('Somente o criador autorizado pode anexar arquivos.');
        }
        Integer maxMB = CommunicatorConfigService.getMaxUploadBroadcastFileSizeMB();
        CommunicatorDTOs.UploadValidationResultDTO result = new CommunicatorDTOs.UploadValidationResultDTO();
        result.validContentDocumentIds = new List<String>();
        result.rejectedFileNames = new List<String>();
        result.errorMessage = CommunicatorConfigService.getMensagemErroArquivoGrande()
            + ' (Limite: ' + maxMB + ' MB)';
        Set<Id> documentIds = parseDocumentIds(contentDocumentIds);
        if (documentIds.isEmpty()) return result;

        Set<Id> linkedDocumentIds = new Set<Id>();
        for (ContentDocumentLink link : [
            SELECT ContentDocumentId
            FROM ContentDocumentLink
            WHERE ContentDocumentId IN :documentIds
            AND LinkedEntityId = :broadcastGroupId
        ]) {
            linkedDocumentIds.add(link.ContentDocumentId);
        }
        Long maxBytes = (Long) maxMB * 1024 * 1024;
        Set<Id> oversizedIds = new Set<Id>();
        for (ContentVersion version : [
            SELECT ContentDocumentId, ContentSize, Title
            FROM ContentVersion
            WHERE ContentDocumentId IN :linkedDocumentIds
            AND IsLatest = true
        ]) {
            if (version.ContentSize > maxBytes) {
                oversizedIds.add(version.ContentDocumentId);
                result.rejectedFileNames.add(version.Title);
            } else {
                result.validContentDocumentIds.add(String.valueOf(version.ContentDocumentId));
            }
        }
        if (!oversizedIds.isEmpty()) {
            delete [SELECT Id FROM ContentDocument WHERE Id IN :oversizedIds];
        }
        return result;
    }

    public static CommunicatorDTOs.MessageAttachmentDTO uploadBroadcastTemporaryAttachmentFromBase64(
        Id broadcastGroupId,
        String fileName,
        String base64Data,
        String contentType
    ) {
        if (UserInfo.getUserId() == null) {
            throw new CommunicatorException('Usuario atual nao identificado.');
        }

        CommunicatorGroup__c groupRecord = loadBroadcastGroup(broadcastGroupId, true);
        if (!CommunicatorBroadcastAudienceService.canCurrentUserPublishToBroadcast(groupRecord.Id)) {
            throw new CommunicatorException('Somente o criador autorizado pode anexar imagens.');
        }

        String normalizedFileName = normalizeClipboardImageFileName(fileName);
        String normalizedContentType = normalizeClipboardContentType(contentType);
        String extension = getClipboardImageExtension(normalizedFileName);
        validateClipboardImageType(extension, normalizedContentType);

        Decimal maxMB = CommunicatorConfigService.getMaxClipboardBroadcastImageSizeMB();
        String normalizedBase64 = normalizeClipboardBase64(base64Data, maxMB);

        Blob fileBody;
        try {
            fileBody = EncodingUtil.base64Decode(normalizedBase64);
        } catch (Exception ex) {
            throw new CommunicatorException('Conteudo base64 invalido.');
        }
        normalizedBase64 = null;
        validateClipboardImageBlob(fileBody, maxMB);
        validateClipboardImageSignature(fileBody, extension);

        Savepoint sp = Database.setSavepoint();
        try {
            ContentVersion version = new ContentVersion(
                Title = buildClipboardContentTitle(normalizedFileName),
                PathOnClient = normalizedFileName,
                VersionData = fileBody,
                FirstPublishLocationId = groupRecord.Id,
                IsMajorVersion = true
            );
            insert version;

            if (failClipboardUploadAfterContentVersionInsertForTest) {
                throw new CommunicatorException('Falha simulada ao concluir upload temporario.');
            }

            ContentVersion insertedVersion = [
                SELECT ContentDocumentId, FileExtension, PathOnClient, Title
                FROM ContentVersion
                WHERE Id = :version.Id
                LIMIT 1
            ];
            if (insertedVersion.ContentDocumentId == null) {
                throw new CommunicatorException('Nao foi possivel resolver o arquivo enviado.');
            }

            ensureTemporaryGroupLink(insertedVersion.ContentDocumentId, groupRecord.Id);

            CommunicatorDTOs.MessageAttachmentDTO dto = new CommunicatorDTOs.MessageAttachmentDTO();
            dto.contentDocumentId = String.valueOf(insertedVersion.ContentDocumentId);
            dto.fileName = String.isNotBlank(insertedVersion.PathOnClient)
                ? insertedVersion.PathOnClient
                : normalizedFileName;
            dto.fileExtension = String.isNotBlank(insertedVersion.FileExtension)
                ? insertedVersion.FileExtension
                : extension;
            return dto;
        } catch (CommunicatorException ex) {
            Database.rollback(sp);
            throw ex;
        } catch (Exception ex) {
            Database.rollback(sp);
            throw new CommunicatorException('Nao foi possivel anexar a imagem colada.');
        }
    }

    public static List<CommunicatorDTOs.MessageAttachmentDTO> getBroadcastMessageAttachments(
        Id threadId,
        List<Id> messageIds
    ) {
        LwcBroadcastThreadReadAccessContext accessContext =
            requireReadableBroadcastThreadForLwc(threadId);
        Boolean canManageBroadcast = accessContext.canPublish == true;
        Set<Id> requested = messageIds == null ? new Set<Id>() : new Set<Id>(messageIds);
        if (requested.isEmpty()) return new List<CommunicatorDTOs.MessageAttachmentDTO>();
        Set<Id> boundMessageIds = new Set<Id>();
        List<CommunicatorMessage__c> visibleMessages = canManageBroadcast
            ? [
                SELECT Id
                FROM CommunicatorMessage__c
                WHERE Id IN :requested
                AND Thread__c = :threadId
            ]
            : [
                SELECT Id
                FROM CommunicatorMessage__c
                WHERE Id IN :requested
                AND Thread__c = :threadId
                AND Status__c = :MESSAGE_STATUS_SENT
            ];
        for (CommunicatorMessage__c message : visibleMessages) {
            boundMessageIds.add(message.Id);
        }
        return CommunicatorMessageService.getMessageAttachments(new List<Id>(boundMessageIds));
    }

    public static CommunicatorDTOs.AttachmentFileDTO getBroadcastAttachmentFile(
        Id threadId,
        Id messageId,
        String contentDocumentId,
        String contentVersionId
    ) {
        LwcBroadcastThreadReadAccessContext accessContext;
        if (messageId == null) {
            accessContext = requireReadableBroadcastThreadForLwc(threadId);
        } else {
            accessContext = requireReadableBroadcastMessageForLwc(messageId);
        }
        Id effectiveThreadId = accessContext.threadId != null ? accessContext.threadId : threadId;
        assertCurrentUserCanAccessBroadcastAttachment(
            accessContext.groupId,
            effectiveThreadId,
            messageId,
            contentDocumentId,
            contentVersionId,
            accessContext.canPublish
        );
        return getBroadcastAttachmentFileForAuthorizedContext(
            contentDocumentId,
            contentVersionId,
            effectiveThreadId,
            messageId
        );
    }

    public static Id requireReadableBroadcastThread(Id threadId) {
        Id groupId = getBroadcastGroupIdForThread(threadId, true);
        assertCurrentUserCanAccessGroup(groupId);
        return groupId;
    }

    public static Boolean isBroadcastGroup(Id groupId) {
        return groupId != null && !loadBroadcastGroups(new Set<Id>{ groupId }, false).isEmpty();
    }

    public static Boolean isBroadcastRecordId(String recordId) {
        Id groupId = tryParseGroupId(recordId);
        return groupId != null && isBroadcastGroup(groupId);
    }

    public static Boolean isBroadcastThread(Id threadId) {
        return threadId != null && !getBroadcastThreadIds(new Set<Id>{ threadId }).isEmpty();
    }

    public static Set<Id> getBroadcastThreadIds(Set<Id> threadIds) {
        return getBroadcastGroupIdsByThreadIds(threadIds, false).keySet();
    }

    public static Set<Id> filterConventionalThreadIds(List<Id> threadIds) {
        Set<Id> result = threadIds == null ? new Set<Id>() : new Set<Id>(threadIds);
        result.removeAll(getBroadcastThreadIds(result));
        return result;
    }

    public static Set<Id> getBroadcastMessageIds(Set<Id> messageIds) {
        Set<Id> result = new Set<Id>();
        if (messageIds == null || messageIds.isEmpty()) return result;
        Map<Id, Id> threadIdByMessageId = new Map<Id, Id>();
        Set<Id> threadIds = new Set<Id>();
        for (CommunicatorMessage__c message : [
            SELECT Id, Thread__c FROM CommunicatorMessage__c WHERE Id IN :messageIds
        ]) {
            threadIdByMessageId.put(message.Id, message.Thread__c);
            threadIds.add(message.Thread__c);
        }
        Set<Id> broadcastThreadIds = getBroadcastThreadIds(threadIds);
        for (Id messageId : threadIdByMessageId.keySet()) {
            if (broadcastThreadIds.contains(threadIdByMessageId.get(messageId))) result.add(messageId);
        }
        return result;
    }

    public static Set<Id> getBroadcastDocumentIds(Set<Id> documentIds) {
        Set<Id> result = new Set<Id>();
        if (documentIds == null || documentIds.isEmpty()) return result;
        Set<String> documentIdStrings = new Set<String>();
        for (Id documentId : documentIds) documentIdStrings.add(String.valueOf(documentId));

        Set<Id> messageIds = new Set<Id>();
        Map<Id, Id> legacyDocumentIdByMessageId = new Map<Id, Id>();
        for (CommunicatorMessage__c message : [
            SELECT Id, ContentDocumentId__c
            FROM CommunicatorMessage__c
            WHERE ContentDocumentId__c IN :documentIdStrings
        ]) {
            messageIds.add(message.Id);
            try { legacyDocumentIdByMessageId.put(message.Id, (Id) message.ContentDocumentId__c); }
            catch (Exception ex) { }
        }
        for (ContentDocumentLink link : [
            SELECT ContentDocumentId, LinkedEntityId
            FROM ContentDocumentLink
            WHERE ContentDocumentId IN :documentIds
        ]) {
            if (link.LinkedEntityId != null &&
                link.LinkedEntityId.getSObjectType() == CommunicatorMessage__c.SObjectType) {
                messageIds.add(link.LinkedEntityId);
            }
        }
        Set<Id> broadcastMessageIds = getBroadcastMessageIds(messageIds);
        if (broadcastMessageIds.isEmpty()) return new Set<Id>();
        for (Id broadcastMessageId : broadcastMessageIds) {
            if (legacyDocumentIdByMessageId.containsKey(broadcastMessageId)) {
                result.add(legacyDocumentIdByMessageId.get(broadcastMessageId));
            }
        }
        for (ContentDocumentLink link : [
            SELECT ContentDocumentId
            FROM ContentDocumentLink
            WHERE ContentDocumentId IN :documentIds
            AND LinkedEntityId IN :broadcastMessageIds
        ]) {
            result.add(link.ContentDocumentId);
        }
        return result;
    }

    public static void assertConventionalDocuments(Set<Id> documentIds) {
        Set<Id> sanitizedDocumentIds = new Set<Id>();
        if (documentIds != null) {
            for (Id documentId : documentIds) if (documentId != null) sanitizedDocumentIds.add(documentId);
        }
        if (!getBroadcastDocumentIds(sanitizedDocumentIds).isEmpty()) {
            throw new CommunicatorException('Use a API específica de comunicado para estes anexos.');
        }
    }

    public static void assertConventionalAttachmentRequest(
        Id threadId,
        Id messageId,
        String contentDocumentId,
        String contentVersionId
    ) {
        assertConventionalThread(threadId);
        if (messageId != null && getBroadcastMessageIds(new Set<Id>{ messageId }).contains(messageId)) {
            throw new CommunicatorException('Use a API específica de comunicado para este anexo.');
        }
        Set<Id> documentIds = new Set<Id>();
        try {
            Id documentId = (Id) contentDocumentId;
            if (documentId.getSObjectType() == ContentDocument.SObjectType) documentIds.add(documentId);
        } catch (Exception ex) { }
        if (documentIds.isEmpty() && String.isNotBlank(contentVersionId)) {
            try {
                Id versionId = (Id) contentVersionId;
                if (versionId.getSObjectType() == ContentVersion.SObjectType) {
                    for (ContentVersion version : [
                        SELECT ContentDocumentId FROM ContentVersion WHERE Id = :versionId LIMIT 1
                    ]) {
                        documentIds.add(version.ContentDocumentId);
                    }
                }
            } catch (Exception ex) { }
        }
        assertConventionalDocuments(documentIds);
    }

    public static void assertConventionalThread(Id threadId) {
        if (isBroadcastThread(threadId)) {
            throw new CommunicatorException('Use a API específica de comunicado para este thread.');
        }
    }

    public static void assertConventionalGroup(Id groupId) {
        if (isBroadcastGroup(groupId)) {
            throw new CommunicatorException('Use a API específica de comunicado para este grupo.');
        }
    }

    @TestVisible
    private static void resetBroadcastCustomNotificationTestState() {
        failBroadcastCustomNotificationSendForTest = false;
        failClipboardUploadAfterContentVersionInsertForTest = false;
        failBroadcastCustomNotificationChunkNumbersForTest = new Set<Integer>();
        broadcastCustomNotificationSendAttempts = 0;
        lastBroadcastCustomNotificationRecipients = new Set<String>();
        broadcastCustomNotificationRecipientChunks = new List<Set<String>>();
        broadcastCustomNotificationChunkRecipientCounts = new List<Integer>();
        lastBroadcastCustomNotificationOriginalRecipientCount = 0;
        lastBroadcastCustomNotificationEligibleRecipientCount = 0;
        lastBroadcastCustomNotificationDiscardedRecipientCount = 0;
        broadcastCustomNotificationRecipientCategoriesForTest = null;
        broadcastAudienceCriteriaSnapshotOverrideForTest = null;
        lastBroadcastCustomNotificationTypeName = null;
        lastBroadcastCustomNotificationTargetPageRef = null;
        lastBroadcastCustomNotificationTitle = null;
        lastBroadcastCustomNotificationBody = null;
        broadcastCustomNotificationTargetPageRefsBySendAttempt = new List<String>();
        broadcastCustomNotificationRecipientsByTargetPageRef = new Map<String, Set<String>>();
        broadcastCustomNotificationBodiesByTargetPageRef = new Map<String, String>();
    }

    @TestVisible
    private static Integer calculateRequiredDmlRows(
        Boolean createThread,
        Integer messageLinkRows,
        Integer missingThreadLinkRows,
        Integer missingNetworkLinkRows,
        Integer linkUpdateRows,
        Integer recipientRows
    ) {
        return (createThread == true ? 1 : 0)
            + 1
            + 1
            + safeInteger(messageLinkRows)
            + safeInteger(missingThreadLinkRows)
            + safeInteger(missingNetworkLinkRows)
            + safeInteger(linkUpdateRows)
            + safeInteger(recipientRows);
    }

    @TestVisible
    private static Integer calculateRequiredDmlStatements(
        Boolean createThread,
        Boolean noAttachments,
        Integer fileShareStatements,
        Boolean createNotifications
    ) {
        return 1
            + (createThread == true ? 1 : 0)
            + 1
            + 1
            + (noAttachments == true ? 0 : safeInteger(fileShareStatements) + 1)
            + (createNotifications == true ? 1 : 0);
    }

    private static AttachmentDmlPlan buildAttachmentDmlPlan(
        List<Id> documentIds,
        Id threadId,
        Id networkId
    ) {
        AttachmentDmlPlan plan = new AttachmentDmlPlan();
        if (documentIds == null || documentIds.isEmpty()) return plan;
        plan.messageLinkRows = documentIds.size();

        Map<Id, List<ContentDocumentLink>> linksByDocumentId = new Map<Id, List<ContentDocumentLink>>();
        for (Id documentId : documentIds) linksByDocumentId.put(documentId, new List<ContentDocumentLink>());
        for (ContentDocumentLink link : [
            SELECT ContentDocumentId, LinkedEntityId, ShareType, Visibility
            FROM ContentDocumentLink
            WHERE ContentDocumentId IN :documentIds
        ]) {
            if (linksByDocumentId.containsKey(link.ContentDocumentId)) {
                linksByDocumentId.get(link.ContentDocumentId).add(link);
            }
        }

        for (Id documentId : documentIds) {
            Boolean hasThreadLink = false;
            Boolean hasNetworkLink = networkId == null;
            Integer updatesForDocument = 0;
            for (ContentDocumentLink link : linksByDocumentId.get(documentId)) {
                if (threadId != null && link.LinkedEntityId == threadId) hasThreadLink = true;
                if (networkId != null && link.LinkedEntityId == networkId) hasNetworkLink = true;
                if (link.LinkedEntityId != null &&
                    link.LinkedEntityId.getSObjectType() != User.SObjectType &&
                    link.Visibility != 'AllUsers') {
                    updatesForDocument++;
                }
            }
            if (threadId == null || !hasThreadLink) plan.missingThreadLinkRows++;
            if (!hasNetworkLink) plan.missingNetworkLinkRows++;
            plan.linkUpdateRows += updatesForDocument;
            if (updatesForDocument > 0) plan.fileShareStatements++;
            if ((threadId == null || !hasThreadLink) || !hasNetworkLink) plan.fileShareStatements++;
        }
        return plan;
    }

    private static List<Id> validateAttachmentsForPublish(Id groupId, List<Id> rawDocumentIds) {
        List<Id> documentIds = new List<Id>();
        Set<Id> uniqueIds = new Set<Id>();
        if (rawDocumentIds != null) {
            for (Id documentId : rawDocumentIds) {
                if (documentId == null || uniqueIds.contains(documentId) ||
                    documentId.getSObjectType() != ContentDocument.SObjectType) continue;
                uniqueIds.add(documentId);
                documentIds.add(documentId);
            }
        }
        if (documentIds.isEmpty()) return documentIds;

        Set<Id> linkedIds = new Set<Id>();
        for (ContentDocumentLink link : [
            SELECT ContentDocumentId
            FROM ContentDocumentLink
            WHERE ContentDocumentId IN :uniqueIds
            AND LinkedEntityId = :groupId
        ]) {
            linkedIds.add(link.ContentDocumentId);
        }
        if (linkedIds.size() != uniqueIds.size()) {
            throw new CommunicatorException('Todos os anexos devem pertencer ao comunicado informado.');
        }

        Integer maxMB = CommunicatorConfigService.getMaxUploadBroadcastFileSizeMB();
        Long maxBytes = (Long) maxMB * 1024 * 1024;
        Set<Id> validSizedIds = new Set<Id>();
        for (ContentVersion version : [
            SELECT ContentDocumentId, ContentSize
            FROM ContentVersion
            WHERE ContentDocumentId IN :uniqueIds
            AND IsLatest = true
        ]) {
            if (version.ContentSize > maxBytes) {
                throw new CommunicatorException(
                    CommunicatorConfigService.getMensagemErroArquivoGrande() + ' (Limite: ' + maxMB + ' MB)'
                );
            }
            validSizedIds.add(version.ContentDocumentId);
        }
        if (validSizedIds.size() != uniqueIds.size()) {
            throw new CommunicatorException('Não foi possível validar todos os anexos informados.');
        }
        return documentIds;
    }

    private static AttachmentEditState buildAttachmentEditState(
        CommunicatorMessage__c message,
        Id groupId,
        List<Id> rawNewDocumentIds,
        List<Id> rawRemovedDocumentIds
    ) {
        AttachmentEditState state = new AttachmentEditState();
        state.originalAttachmentIds = loadAttachmentDocumentIdsForMessage(
            message.Id,
            message.ContentDocumentId__c
        );
        state.originalAttachmentIdSet.addAll(state.originalAttachmentIds);
        state.removedAttachmentIds = sanitizeDocumentIdSet(rawRemovedDocumentIds);

        if (!state.originalAttachmentIdSet.containsAll(state.removedAttachmentIds)) {
            throw new CommunicatorException('Um ou mais anexos removidos nÃ£o pertencem Ã  mensagem informada.');
        }

        List<Id> candidateNewIds = validateAttachmentsForPublish(groupId, rawNewDocumentIds);
        Set<Id> newIdSet = new Set<Id>();
        for (Id documentId : candidateNewIds) {
            if (state.removedAttachmentIds.contains(documentId)) {
                throw new CommunicatorException('O mesmo anexo nÃ£o pode ser adicionado e removido na mesma ediÃ§Ã£o.');
            }
            if (state.originalAttachmentIdSet.contains(documentId) || newIdSet.contains(documentId)) continue;
            newIdSet.add(documentId);
            state.newAttachmentIds.add(documentId);
        }

        validateDocumentsNotLinkedToOtherMessages(
            state.newAttachmentIds,
            message.Id,
            'Um ou mais anexos novos jÃ¡ estÃ£o publicados em outra mensagem.'
        );
        validateDocumentsNotLinkedToOtherMessages(
            new List<Id>(state.removedAttachmentIds),
            message.Id,
            'NÃ£o Ã© possÃ­vel remover anexo compartilhado com outra mensagem.'
        );

        Set<Id> finalIds = new Set<Id>();
        for (Id originalId : state.originalAttachmentIds) {
            if (state.removedAttachmentIds.contains(originalId) || finalIds.contains(originalId)) continue;
            finalIds.add(originalId);
            state.finalAttachmentIds.add(originalId);
        }
        for (Id newId : state.newAttachmentIds) {
            if (finalIds.contains(newId)) continue;
            finalIds.add(newId);
            state.finalAttachmentIds.add(newId);
        }

        Id currentPrimaryId = tryParseContentDocumentId(message.ContentDocumentId__c);
        if (currentPrimaryId != null && finalIds.contains(currentPrimaryId)) {
            state.finalPrimaryAttachmentId = currentPrimaryId;
        } else if (!state.finalAttachmentIds.isEmpty()) {
            state.finalPrimaryAttachmentId = state.finalAttachmentIds[0];
        }
        return state;
    }

    private static List<Id> loadAttachmentDocumentIdsForMessage(Id messageId, String fallbackDocumentId) {
        List<Id> orderedIds = new List<Id>();
        Set<Id> seen = new Set<Id>();
        Id fallbackId = tryParseContentDocumentId(fallbackDocumentId);
        if (fallbackId != null) {
            orderedIds.add(fallbackId);
            seen.add(fallbackId);
        }
        if (messageId == null) return orderedIds;

        for (ContentDocumentLink link : [
            SELECT ContentDocumentId
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :messageId
            AND ContentDocumentId != null
            ORDER BY ContentDocumentId ASC
        ]) {
            if (seen.contains(link.ContentDocumentId)) continue;
            seen.add(link.ContentDocumentId);
            orderedIds.add(link.ContentDocumentId);
        }
        return orderedIds;
    }

    private static Set<Id> sanitizeDocumentIdSet(List<Id> rawDocumentIds) {
        Set<Id> result = new Set<Id>();
        if (rawDocumentIds == null) return result;
        for (Id documentId : rawDocumentIds) {
            if (documentId == null ||
                documentId.getSObjectType() != ContentDocument.SObjectType) continue;
            result.add(documentId);
        }
        return result;
    }

    private static Id tryParseContentDocumentId(String rawId) {
        if (String.isBlank(rawId)) return null;
        try {
            Id documentId = (Id) rawId;
            return documentId.getSObjectType() == ContentDocument.SObjectType ? documentId : null;
        } catch (Exception ex) {
            return null;
        }
    }

    private static void validateDocumentsNotLinkedToOtherMessages(
        List<Id> documentIds,
        Id currentMessageId,
        String errorMessage
    ) {
        Set<Id> uniqueIds = new Set<Id>();
        if (documentIds != null) {
            for (Id documentId : documentIds) if (documentId != null) uniqueIds.add(documentId);
        }
        if (uniqueIds.isEmpty()) return;

        Set<String> documentIdStrings = new Set<String>();
        for (Id documentId : uniqueIds) documentIdStrings.add(String.valueOf(documentId));

        for (CommunicatorMessage__c otherMessage : [
            SELECT Id
            FROM CommunicatorMessage__c
            WHERE Id != :currentMessageId
            AND ContentDocumentId__c IN :documentIdStrings
            LIMIT 1
        ]) {
            throw new CommunicatorException(errorMessage);
        }

        for (ContentDocumentLink link : [
            SELECT ContentDocumentId, LinkedEntityId
            FROM ContentDocumentLink
            WHERE ContentDocumentId IN :uniqueIds
        ]) {
            if (link.LinkedEntityId == null || link.LinkedEntityId == currentMessageId) continue;
            if (link.LinkedEntityId.getSObjectType() == CommunicatorMessage__c.SObjectType) {
                throw new CommunicatorException(errorMessage);
            }
        }
    }

    private static CommunicatorGroup__c lockBroadcastGroup(Id groupId) {
        if (groupId == null) throw new CommunicatorException('Informe o comunicado.');
        List<CommunicatorGroup__c> groups = [
            SELECT Id, Name, Description__c, CreatedByUser__c, CreatedByUser__r.Name,
                   CreatedByUser__r.SmallPhotoUrl,
                   IsActive__c, Type__c, BroadcastLastActivityAt__c
            FROM CommunicatorGroup__c
            WHERE Id = :groupId
            AND Type__c = :GROUP_TYPE
            AND IsActive__c = true
            LIMIT 1
            FOR UPDATE
        ];
        if (groups.isEmpty()) throw new CommunicatorException('Comunicado não encontrado ou inativo.');
        return groups[0];
    }

    private static CommunicatorGroup__c loadBroadcastGroup(Id groupId, Boolean requireActive) {
        Map<Id, CommunicatorGroup__c> groups = loadBroadcastGroups(new Set<Id>{ groupId }, requireActive);
        if (!groups.containsKey(groupId)) throw new CommunicatorException('Comunicado não encontrado ou inativo.');
        return groups.get(groupId);
    }

    private static Map<Id, CommunicatorGroup__c> loadBroadcastGroups(
        Set<Id> groupIds,
        Boolean requireActive
    ) {
        Map<Id, CommunicatorGroup__c> result = new Map<Id, CommunicatorGroup__c>();
        if (groupIds == null || groupIds.isEmpty()) return result;
        for (CommunicatorGroup__c groupRecord : [
            SELECT Id, Name, Description__c, CreatedByUser__c, CreatedByUser__r.Name,
                   CreatedByUser__r.SmallPhotoUrl,
                   IsActive__c, Type__c, CreatedDate, BroadcastLastActivityAt__c
            FROM CommunicatorGroup__c
            WHERE Id IN :groupIds
            AND Type__c = :GROUP_TYPE
        ]) {
            if (requireActive && groupRecord.IsActive__c != true) continue;
            result.put(groupRecord.Id, groupRecord);
        }
        return result;
    }

    private static List<CommunicatorGroup__c> queryBroadcastGroups(BroadcastCursor cursor, Integer limitSize) {
        if (cursor == null || cursor.timestampValue == null || cursor.recordId == null) {
            return [
                SELECT Id, Name, Description__c, CreatedByUser__c, CreatedByUser__r.Name,
                       CreatedByUser__r.SmallPhotoUrl,
                       IsActive__c, Type__c, BroadcastLastActivityAt__c
                FROM CommunicatorGroup__c
                WHERE Type__c = :GROUP_TYPE
                AND IsActive__c = true
                AND BroadcastLastActivityAt__c != null
                ORDER BY BroadcastLastActivityAt__c DESC, Id DESC
                LIMIT :limitSize
            ];
        }
        return [
            SELECT Id, Name, Description__c, CreatedByUser__c, CreatedByUser__r.Name,
                   CreatedByUser__r.SmallPhotoUrl,
                   IsActive__c, Type__c, BroadcastLastActivityAt__c
            FROM CommunicatorGroup__c
            WHERE Type__c = :GROUP_TYPE
            AND IsActive__c = true
            AND BroadcastLastActivityAt__c != null
            AND (
                BroadcastLastActivityAt__c < :cursor.timestampValue
                OR (BroadcastLastActivityAt__c = :cursor.timestampValue AND Id < :cursor.recordId)
            )
            ORDER BY BroadcastLastActivityAt__c DESC, Id DESC
            LIMIT :limitSize
        ];
    }

    private static void assertCurrentUserCanAccessGroup(Id groupId) {
        if (!CommunicatorBroadcastAudienceService.canCurrentUserAccessBroadcast(groupId)) {
            throw new CommunicatorException('Você não possui acesso a este comunicado.');
        }
    }

    private static void assertCurrentUserCanAccessBroadcastAttachment(
        Id groupId,
        Id threadId,
        Id messageId,
        String contentDocumentId,
        String contentVersionId,
        Boolean canManageBroadcast
    ) {
        if (canManageBroadcast == true) return;

        Id documentId = resolveBroadcastAttachmentDocumentId(contentDocumentId, contentVersionId);
        Integer visibleMessageCount = messageId == null
            ? 0
            : [
                SELECT COUNT()
                FROM CommunicatorMessage__c
                WHERE Id = :messageId
                AND Thread__c = :threadId
                AND Status__c = :MESSAGE_STATUS_SENT
            ];
        if (messageId != null && visibleMessageCount == 0) {
            throw new CommunicatorException('Voce nao possui acesso a este anexo.');
        }
        if (documentId == null) return;
        String documentIdValue = String.valueOf(documentId);
        Set<Id> linkedMessageIds = new Set<Id>();
        for (ContentDocumentLink link : [
            SELECT LinkedEntityId
            FROM ContentDocumentLink
            WHERE ContentDocumentId = :documentId
        ]) {
            if (link.LinkedEntityId != null &&
                link.LinkedEntityId.getSObjectType() == CommunicatorMessage__c.SObjectType) {
                linkedMessageIds.add(link.LinkedEntityId);
            }
        }

        Integer accessibleAttachmentCount = messageId == null
            ? [
                SELECT COUNT()
                FROM CommunicatorMessage__c
                WHERE Thread__c = :threadId
                AND Status__c = :MESSAGE_STATUS_SENT
                AND (
                    ContentDocumentId__c = :documentIdValue
                    OR Id IN :linkedMessageIds
                )
            ]
            : [
                SELECT COUNT()
                FROM CommunicatorMessage__c
                WHERE Id = :messageId
                AND Thread__c = :threadId
                AND Status__c = :MESSAGE_STATUS_SENT
                AND (
                    ContentDocumentId__c = :documentIdValue
                    OR Id IN :linkedMessageIds
                )
            ];
        if (accessibleAttachmentCount == 0) {
            throw new CommunicatorException('Voce nao possui acesso a este anexo.');
        }
    }

    private static Id resolveBroadcastAttachmentDocumentId(
        String contentDocumentId,
        String contentVersionId
    ) {
        try {
            Id parsedDocumentId = (Id) contentDocumentId;
            if (parsedDocumentId.getSObjectType() == ContentDocument.SObjectType) {
                return parsedDocumentId;
            }
        } catch (Exception ex) {
        }
        try {
            Id parsedVersionId = (Id) contentVersionId;
            if (parsedVersionId.getSObjectType() == ContentVersion.SObjectType) {
                for (ContentVersion version : [
                    SELECT ContentDocumentId
                    FROM ContentVersion
                    WHERE Id = :parsedVersionId
                    LIMIT 1
                ]) {
                    return version.ContentDocumentId;
                }
            }
        } catch (Exception ex) {
        }
        return null;
    }

    private static CommunicatorDTOs.AttachmentFileDTO getBroadcastAttachmentFileForAuthorizedContext(
        String contentDocumentId,
        String contentVersionId,
        Id threadId,
        Id messageId
    ) {
        if (threadId == null && messageId == null) {
            throw new CommunicatorException('Thread ou mensagem sao obrigatorios para baixar o anexo.');
        }

        Id documentId = resolveBroadcastAttachmentDocumentId(contentDocumentId, contentVersionId);
        if (documentId == null) {
            throw new CommunicatorException('Attachment id is required.');
        }

        if (messageId != null) {
            List<CommunicatorMessage__c> messages = [
                SELECT Id, Thread__c, ContentDocumentId__c
                FROM CommunicatorMessage__c
                WHERE Id = :messageId
                AND Thread__c = :threadId
                LIMIT 1
            ];
            if (messages.isEmpty()) {
                throw new CommunicatorException('O anexo nao pertence a mensagem informada.');
            }

            Boolean isLegacyAttachment = messages[0].ContentDocumentId__c == String.valueOf(documentId);
            if (!isLegacyAttachment && !isBroadcastAttachmentLinkedToEntity(documentId, messageId)) {
                throw new CommunicatorException('O anexo nao pertence a mensagem informada.');
            }
        } else if (!isBroadcastAttachmentLinkedToEntity(documentId, threadId)) {
            throw new CommunicatorException('O anexo nao pertence ao contexto informado.');
        }

        return buildBroadcastAttachmentFileDto(queryLatestBroadcastAttachmentVersion(documentId));
    }

    private static Boolean isBroadcastAttachmentLinkedToEntity(Id contentDocumentId, Id linkedEntityId) {
        if (contentDocumentId == null || linkedEntityId == null) return false;
        Integer linkCount = [
            SELECT COUNT()
            FROM ContentDocumentLink
            WHERE ContentDocumentId = :contentDocumentId
            AND LinkedEntityId = :linkedEntityId
        ];
        return linkCount > 0;
    }

    private static ContentVersion queryLatestBroadcastAttachmentVersion(Id contentDocumentId) {
        List<ContentVersion> rows = [
            SELECT Id, Title, FileType, FileExtension, PathOnClient, VersionData
            FROM ContentVersion
            WHERE ContentDocumentId = :contentDocumentId
            ORDER BY VersionNumber DESC
            LIMIT 1
        ];
        if (rows.isEmpty() || rows[0].VersionData == null) {
            throw new CommunicatorException('Attachment content not found.');
        }
        return rows[0];
    }

    private static CommunicatorDTOs.AttachmentFileDTO buildBroadcastAttachmentFileDto(
        ContentVersion version
    ) {
        CommunicatorDTOs.AttachmentFileDTO dto = new CommunicatorDTOs.AttachmentFileDTO();
        dto.fileName = String.isNotBlank(version.PathOnClient)
            ? version.PathOnClient.trim()
            : buildBroadcastAttachmentFileName(version.Title, version.FileExtension);
        dto.contentType = String.isNotBlank(version.FileType) ? version.FileType : 'UNKNOWN';
        dto.fileExtension = String.isNotBlank(version.FileExtension) ? version.FileExtension : '';
        dto.base64Data = EncodingUtil.base64Encode(version.VersionData);
        return dto;
    }

    private static String buildBroadcastAttachmentFileName(String title, String extension) {
        String safeTitle = String.isNotBlank(title) ? title.trim() : 'arquivo';
        String safeExtension = String.isNotBlank(extension) ? extension.trim() : '';
        if (String.isBlank(safeExtension)) return safeTitle;
        String lowerTitle = safeTitle.toLowerCase();
        String expectedSuffix = '.' + safeExtension.toLowerCase();
        if (lowerTitle.endsWith(expectedSuffix)) return safeTitle;
        return safeTitle + '.' + safeExtension;
    }

    private static CommunicatorThread__c findActiveBroadcastThread(Id groupId, Boolean requirePublished) {
        String groupIdValue = String.valueOf(groupId);
        List<CommunicatorThread__c> threads = [
            SELECT Id, Name, RecordId__c, RecordType__c, Status__c, Stage__c,
                   LastMessageAt__c, UnreadCount__c, IsBroadcast__c
            FROM CommunicatorThread__c
            WHERE RecordId__c = :groupIdValue
            AND RecordType__c = :THREAD_RECORD_TYPE
            AND Status__c = 'Active'
            ORDER BY LastMessageAt__c DESC NULLS LAST, Id DESC
            LIMIT 10
        ];
        if (threads.isEmpty()) return null;
        if (requirePublished && threads[0].LastMessageAt__c == null) return null;
        return threads[0];
    }

    private static Map<Id, CommunicatorThread__c> loadBestActiveBroadcastThreads(Set<Id> groupIds) {
        Map<Id, CommunicatorThread__c> result = new Map<Id, CommunicatorThread__c>();
        if (groupIds == null || groupIds.isEmpty()) return result;
        for (CommunicatorThread__c threadRecord : [
            SELECT Id, Name, RecordId__c, RecordType__c, Status__c, Stage__c,
                   LastMessageAt__c, UnreadCount__c, IsBroadcast__c
            FROM CommunicatorThread__c
            WHERE RecordId__c IN :groupIds
            AND RecordType__c = :THREAD_RECORD_TYPE
            AND Status__c = 'Active'
            ORDER BY RecordId__c, LastMessageAt__c DESC NULLS LAST, Id DESC
        ]) {
            Id groupId = tryParseGroupId(threadRecord.RecordId__c);
            if (groupId == null || result.containsKey(groupId)) continue;
            result.put(groupId, threadRecord);
        }
        return result;
    }

    private static Id getBroadcastGroupIdForThread(Id threadId, Boolean requireActiveGroup) {
        Map<Id, Id> groupByThread = getBroadcastGroupIdsByThreadIds(
            new Set<Id>{ threadId }, requireActiveGroup
        );
        Id groupId = groupByThread.get(threadId);
        if (groupId == null) throw new CommunicatorException('Thread de comunicado não encontrado.');
        return groupId;
    }

    private static Map<Id, Id> getBroadcastGroupIdsByThreadIds(
        Set<Id> threadIds,
        Boolean requireActiveGroup
    ) {
        Map<Id, Id> candidateGroupByThread = new Map<Id, Id>();
        Set<Id> groupIds = new Set<Id>();
        if (threadIds == null || threadIds.isEmpty()) return candidateGroupByThread;
        for (CommunicatorThread__c threadRecord : [
            SELECT Id, RecordId__c, RecordType__c
            FROM CommunicatorThread__c
            WHERE Id IN :threadIds
            AND RecordType__c = :THREAD_RECORD_TYPE
        ]) {
            Id groupId = tryParseGroupId(threadRecord.RecordId__c);
            if (groupId == null) continue;
            candidateGroupByThread.put(threadRecord.Id, groupId);
            groupIds.add(groupId);
        }
        Set<Id> validGroupIds = loadBroadcastGroups(groupIds, requireActiveGroup).keySet();
        Map<Id, Id> result = new Map<Id, Id>();
        for (Id threadId : candidateGroupByThread.keySet()) {
            Id groupId = candidateGroupByThread.get(threadId);
            if (validGroupIds.contains(groupId)) result.put(threadId, groupId);
        }
        return result;
    }

    private static LwcBroadcastReadAccessContext requireReadableBroadcastGroupForLwc(Id groupId) {
        Map<Id, CommunicatorBroadcastLwcAccessService.GroupAccessDecision> decisions =
            CommunicatorBroadcastLwcAccessService.evaluateGroupAccess(new Set<Id>{ groupId });
        CommunicatorBroadcastLwcAccessService.GroupAccessDecision decision = decisions.get(groupId);
        if (decision == null || decision.canAccessGroup != true) {
            throw new CommunicatorException('Você não possui acesso a este comunicado.');
        }

        LwcBroadcastReadAccessContext context = new LwcBroadcastReadAccessContext();
        context.groupId = groupId;
        context.canPublish = decision.canPublish == true;
        return context;
    }

    private static LwcBroadcastThreadReadAccessContext requireReadableBroadcastThreadForLwc(Id threadId) {
        Id groupId = getBroadcastGroupIdForThread(threadId, true);
        LwcBroadcastReadAccessContext groupAccess = requireReadableBroadcastGroupForLwc(groupId);

        LwcBroadcastThreadReadAccessContext context = new LwcBroadcastThreadReadAccessContext();
        context.threadId = threadId;
        context.groupId = groupAccess.groupId;
        context.canPublish = groupAccess.canPublish;
        return context;
    }

    private static LwcBroadcastMessageReadAccessContext requireReadableBroadcastMessageForLwc(Id messageId) {
        Map<Id, CommunicatorBroadcastLwcAccessService.MessageAccessDecision> decisions =
            CommunicatorBroadcastLwcAccessService.evaluateMessageAccess(new Set<Id>{ messageId });
        CommunicatorBroadcastLwcAccessService.MessageAccessDecision decision = decisions.get(messageId);
        if (decision == null || decision.canAccessMessage != true || decision.threadId == null) {
            throw new CommunicatorException('Você não possui acesso a este comunicado.');
        }

        LwcBroadcastMessageReadAccessContext context = new LwcBroadcastMessageReadAccessContext();
        context.messageId = messageId;
        context.threadId = decision.threadId;
        context.groupId = decision.groupId;
        context.canPublish = decision.canPublish == true;
        return context;
    }

    private static Map<Id, Integer> getUnreadByThread(Set<Id> threadIds) {
        Map<Id, Integer> result = new Map<Id, Integer>();
        if (threadIds != null && threadIds.isEmpty()) return result;
        List<AggregateResult> rows = threadIds == null
            ? [
                SELECT Thread__c threadId, COUNT(Id) countValue
                FROM CommunicatorNotification__c
                WHERE Recipient__c = :UserInfo.getUserId()
                AND Type__c = :NOTIFICATION_TYPE
                AND IsRead__c = false
                AND Message__r.Status__c = :MESSAGE_STATUS_SENT
                GROUP BY Thread__c
            ]
            : [
                SELECT Thread__c threadId, COUNT(Id) countValue
                FROM CommunicatorNotification__c
                WHERE Thread__c IN :threadIds
                AND Recipient__c = :UserInfo.getUserId()
                AND Type__c = :NOTIFICATION_TYPE
                AND IsRead__c = false
                AND Message__r.Status__c = :MESSAGE_STATUS_SENT
                GROUP BY Thread__c
            ];
        for (AggregateResult row : rows) {
            result.put((Id) row.get('threadId'), Integer.valueOf(row.get('countValue')));
        }
        return result;
    }

    private static void reconcilePendingDistributionsForThread(Id threadId, Boolean canManageBroadcast) {
        if (!canManageBroadcast || threadId == null) return;
        Set<Id> pendingMessageIds = new Set<Id>();
        Set<String> pendingStatuses = new Set<String>{
            CommunicatorBroadcastDistributionService.STATUS_QUEUED,
            CommunicatorBroadcastDistributionService.STATUS_PROCESSING
        };
        for (CommunicatorMessage__c message : [
            SELECT Id
            FROM CommunicatorMessage__c
            WHERE Thread__c = :threadId
            AND Status__c IN :pendingStatuses
            AND BroadcastDistributionJobId__c != null
            LIMIT 25
        ]) {
            pendingMessageIds.add(message.Id);
        }
        if (!pendingMessageIds.isEmpty()) {
            CommunicatorBroadcastDistributionService.reconcileTerminalMessageStates(
                pendingMessageIds
            );
        }
    }

    private static Map<Id, Integer> getAccessibleUnreadByThread(Set<Id> requestedThreadIds) {
        Map<Id, Integer> unreadByThread = getUnreadByThread(requestedThreadIds);
        Set<Id> candidateThreadIds = requestedThreadIds == null
            ? new Set<Id>(unreadByThread.keySet())
            : new Set<Id>(requestedThreadIds);
        Map<Id, Integer> result = new Map<Id, Integer>();
        if (candidateThreadIds.isEmpty()) return result;

        Map<Id, Id> groupIdByThreadId = getBroadcastGroupIdsByThreadIds(candidateThreadIds, true);
        if (groupIdByThreadId.isEmpty()) return result;

        Map<Id, Boolean> accessByGroup =
            CommunicatorBroadcastAudienceService.getCurrentUserAccessByBroadcastGroup(
                new Set<Id>(groupIdByThreadId.values())
            );
        for (Id threadId : candidateThreadIds) {
            Id groupId = groupIdByThreadId.get(threadId);
            if (groupId == null || accessByGroup.get(groupId) != true) continue;
            result.put(threadId, unreadByThread.containsKey(threadId) ? unreadByThread.get(threadId) : 0);
        }
        return result;
    }

    private static Map<Id, Integer> getAccessibleUnreadByThreadForLwc(Set<Id> requestedThreadIds) {
        Map<Id, Integer> unreadByThread = getUnreadByThread(requestedThreadIds);
        Set<Id> candidateThreadIds = requestedThreadIds == null
            ? new Set<Id>(unreadByThread.keySet())
            : new Set<Id>(requestedThreadIds);
        Map<Id, Integer> result = new Map<Id, Integer>();
        if (candidateThreadIds.isEmpty()) return result;

        Map<Id, Id> groupIdByThreadId = getBroadcastGroupIdsByThreadIds(candidateThreadIds, true);
        if (groupIdByThreadId.isEmpty()) return result;

        Map<Id, CommunicatorBroadcastLwcAccessService.GroupAccessDecision> accessByGroup =
            CommunicatorBroadcastLwcAccessService.evaluateGroupAccess(
                new Set<Id>(groupIdByThreadId.values())
            );
        for (Id threadId : candidateThreadIds) {
            Id groupId = groupIdByThreadId.get(threadId);
            CommunicatorBroadcastLwcAccessService.GroupAccessDecision accessDecision =
                groupId == null ? null : accessByGroup.get(groupId);
            if (accessDecision == null || accessDecision.canAccessGroup != true) continue;
            result.put(threadId, unreadByThread.containsKey(threadId) ? unreadByThread.get(threadId) : 0);
        }
        return result;
    }

    @TestVisible
    private static List<Set<String>> chunkBroadcastCustomNotificationRecipients(
        Set<String> recipients,
        Integer chunkSize
    ) {
        List<Set<String>> chunks = new List<Set<String>>();
        if (recipients == null || recipients.isEmpty()) return chunks;

        Integer effectiveChunkSize = chunkSize == null || chunkSize <= 0
            ? CUSTOM_NOTIFICATION_CHUNK_SIZE
            : chunkSize;
        List<String> orderedRecipients = new List<String>(recipients);
        orderedRecipients.sort();
        for (Integer startIndex = 0; startIndex < orderedRecipients.size(); startIndex += effectiveChunkSize) {
            Set<String> chunk = new Set<String>();
            Integer endIndex = Math.min(startIndex + effectiveChunkSize, orderedRecipients.size());
            for (Integer index = startIndex; index < endIndex; index++) {
                chunk.add(orderedRecipients[index]);
            }
            if (!chunk.isEmpty()) chunks.add(chunk);
        }
        return chunks;
    }

    public static void sendBroadcastCustomNotificationFromSnapshot(
        Set<Id> recipientIds,
        String senderName,
        String subject
    ) {
        sendBroadcastCustomNotification(recipientIds, senderName, subject);
    }

    private static void sendBroadcastCustomNotification(Set<Id> recipientIds, String subject) {
        sendBroadcastCustomNotification(recipientIds, UserInfo.getName(), subject);
    }

    private static void sendBroadcastCustomNotification(
        Set<Id> recipientIds,
        String senderName,
        String subject
    ) {
        if (recipientIds == null || recipientIds.isEmpty()) return;

        Integer originalRecipientCount = recipientIds.size();
        BroadcastCustomNotificationRecipientPartition recipientPartition =
            partitionBroadcastCustomNotificationRecipients(recipientIds);
        Integer eligibleRecipientCount = recipientPartition.eligibleRecipientIds.size();
        Integer discardedRecipientCount = Math.max(0, originalRecipientCount - eligibleRecipientCount);
        if (Test.isRunningTest()) {
            lastBroadcastCustomNotificationOriginalRecipientCount = originalRecipientCount;
            lastBroadcastCustomNotificationEligibleRecipientCount = eligibleRecipientCount;
            lastBroadcastCustomNotificationDiscardedRecipientCount = discardedRecipientCount;
            lastBroadcastCustomNotificationRecipients =
                new Set<String>(recipientPartition.eligibleRecipientIds);
        }
        if (recipientPartition.eligibleRecipientIds.isEmpty()) {
            System.debug(
                LoggingLevel.WARN,
                'CommunicatorBroadcastService.sendBroadcastCustomNotification skipped: originalRecipientCount=' +
                originalRecipientCount +
                ', eligibleRecipientCount=' + eligibleRecipientCount +
                ', discardedRecipientCount=' + discardedRecipientCount +
                ', chunkSize=' + CUSTOM_NOTIFICATION_CHUNK_SIZE +
                ', reason=no_eligible_core_recipients'
            );
            return;
        }

        CustomNotificationType notificationType;
        try {
            notificationType = [
                SELECT Id, DeveloperName
                FROM CustomNotificationType
                WHERE DeveloperName = :CUSTOM_NOTIFICATION_TYPE_NAME
                LIMIT 1
            ];
        } catch (Exception ex) {
            System.debug(
                LoggingLevel.ERROR,
                'CommunicatorBroadcastService.sendBroadcastCustomNotification setup error: ' +
                'originalRecipientCount=' + originalRecipientCount +
                ', eligibleRecipientCount=' + eligibleRecipientCount +
                ', discardedRecipientCount=' + discardedRecipientCount +
                ', chunkSize=' + CUSTOM_NOTIFICATION_CHUNK_SIZE +
                ', errorMessage=' + ex.getMessage() +
                ', stackTrace=' + getBroadcastCustomNotificationStackTraceExcerpt(ex)
            );
            return;
        }

        Integer chunkOffset = 0;
        String internalNotificationBody = recipientPartition.internalRecipientIds.isEmpty()
            ? null
            : buildBroadcastCustomNotificationBody(senderName, subject);
        String communityNotificationBody = recipientPartition.communityRecipientIds.isEmpty()
            ? null
            : buildBroadcastCustomNotificationBody(
                senderName,
                subject,
                CommunicatorConfigService.getBroadcastCommunityNotificationMessage()
            );
        chunkOffset = sendBroadcastCustomNotificationChunks(
            recipientPartition.internalRecipientIds,
            buildInternalBroadcastNotificationTargetPageRef(),
            notificationType,
            internalNotificationBody,
            originalRecipientCount,
            eligibleRecipientCount,
            discardedRecipientCount,
            chunkOffset
        );
        sendBroadcastCustomNotificationChunks(
            recipientPartition.communityRecipientIds,
            buildCommunityBroadcastNotificationTargetPageRef(),
            notificationType,
            communityNotificationBody,
            originalRecipientCount,
            eligibleRecipientCount,
            discardedRecipientCount,
            chunkOffset
        );
    }

    @TestVisible
    private static String buildBroadcastCustomNotificationBody(String senderName, String subject) {
        return buildBroadcastCustomNotificationBody(
            senderName,
            subject,
            CommunicatorConfigService.getBroadcastNotificationMessage()
        );
    }

    @TestVisible
    private static String buildBroadcastCustomNotificationBody(
        String senderName,
        String subject,
        String notificationMessage
    ) {
        String body = 'Novo Comunicado de ' + String.valueOf(senderName).trim() + '. Assunto: ' + String.valueOf(subject).trim()
            + '\n' + notificationMessage;
        return body.length() > CUSTOM_NOTIFICATION_BODY_MAX_LENGTH
            ? body.substring(0, CUSTOM_NOTIFICATION_BODY_MAX_LENGTH)
            : body;
    }

    private static Map<Id, CommunicatorBroadcastAudienceService.UserAudienceCategory>
    classifyBroadcastCustomNotificationRecipients(Set<Id> recipientIds) {
        Map<Id, CommunicatorBroadcastAudienceService.UserAudienceCategory> categories =
            CommunicatorBroadcastAudienceService.classifyUsers(recipientIds);
        if (Test.isRunningTest() && broadcastCustomNotificationRecipientCategoriesForTest != null) {
            for (Id recipientId : broadcastCustomNotificationRecipientCategoriesForTest.keySet()) {
                if (recipientIds.contains(recipientId)) {
                    categories.put(
                        recipientId,
                        broadcastCustomNotificationRecipientCategoriesForTest.get(recipientId)
                    );
                }
            }
        }
        return categories;
    }

    @TestVisible
    private static BroadcastCustomNotificationRecipientPartition partitionBroadcastCustomNotificationRecipients(
        Set<Id> recipientIds
    ) {
        BroadcastCustomNotificationRecipientPartition partition =
            new BroadcastCustomNotificationRecipientPartition();
        if (recipientIds == null || recipientIds.isEmpty()) return partition;

        Set<Id> candidateRecipientIds = new Set<Id>();
        for (Id recipientId : recipientIds) {
            if (recipientId == null || recipientId == UserInfo.getUserId()) continue;
            candidateRecipientIds.add(recipientId);
        }
        if (candidateRecipientIds.isEmpty()) return partition;

        Map<Id, CommunicatorBroadcastAudienceService.UserAudienceCategory> categories =
            classifyBroadcastCustomNotificationRecipients(candidateRecipientIds);
        for (Id recipientId : candidateRecipientIds) {
            String recipientKey = String.valueOf(recipientId);
            CommunicatorBroadcastAudienceService.UserAudienceCategory category = categories.get(recipientId);
            if (category == CommunicatorBroadcastAudienceService.UserAudienceCategory.CORE_SALESFORCE ||
                category == CommunicatorBroadcastAudienceService.UserAudienceCategory.CORE_PLATFORM) {
                partition.internalRecipientIds.add(recipientKey);
                partition.eligibleRecipientIds.add(recipientKey);
            } else if (category ==
                CommunicatorBroadcastAudienceService.UserAudienceCategory.COMMUNITY_PARTNER) {
                partition.communityRecipientIds.add(recipientKey);
                partition.eligibleRecipientIds.add(recipientKey);
            }
        }
        return partition;
    }

    private static Integer sendBroadcastCustomNotificationChunks(
        Set<String> recipientIds,
        String targetPageRef,
        CustomNotificationType notificationType,
        String notificationBody,
        Integer originalRecipientCount,
        Integer eligibleRecipientCount,
        Integer discardedRecipientCount,
        Integer chunkOffset
    ) {
        if (recipientIds == null || recipientIds.isEmpty()) return chunkOffset;

        List<Set<String>> recipientChunks = chunkBroadcastCustomNotificationRecipients(
            recipientIds,
            CUSTOM_NOTIFICATION_CHUNK_SIZE
        );
        Integer totalChunks = recipientChunks.size();
        Integer currentOffset = chunkOffset == null ? 0 : chunkOffset;
        for (Integer chunkIndex = 0; chunkIndex < totalChunks; chunkIndex++) {
            Set<String> recipientChunk = recipientChunks[chunkIndex];
            Integer absoluteChunkNumber = currentOffset + chunkIndex + 1;
            try {
                if (Test.isRunningTest()) {
                    rememberBroadcastCustomNotificationSendAttempt(
                        recipientChunk,
                        targetPageRef,
                        notificationType == null ? null : notificationType.DeveloperName,
                        notificationBody
                    );
                }

                Messaging.CustomNotification notification = new Messaging.CustomNotification();
                notification.setTitle(CUSTOM_NOTIFICATION_TITLE);
                notification.setBody(notificationBody);
                notification.setNotificationTypeId(notificationType.Id);
                notification.setTargetPageRef(targetPageRef);
                if (Test.isRunningTest() &&
                    (failBroadcastCustomNotificationSendForTest ||
                     failBroadcastCustomNotificationChunkNumbersForTest.contains(absoluteChunkNumber))) {
                    throw new CommunicatorException('Falha sintetica no envio do push Broadcast.');
                }
                notification.send(recipientChunk);
            } catch (Exception ex) {
                System.debug(
                    LoggingLevel.ERROR,
                    'CommunicatorBroadcastService.sendBroadcastCustomNotification chunk error: ' +
                    'originalRecipientCount=' + originalRecipientCount +
                    ', eligibleRecipientCount=' + eligibleRecipientCount +
                    ', discardedRecipientCount=' + discardedRecipientCount +
                    ', chunkSize=' + CUSTOM_NOTIFICATION_CHUNK_SIZE +
                    ', chunkIndex=' + absoluteChunkNumber +
                    ', totalChunks=' + (currentOffset + totalChunks) +
                    ', chunkRecipientCount=' + recipientChunk.size() +
                    ', targetPageRef=' + targetPageRef +
                    ', errorMessage=' + ex.getMessage() +
                    ', stackTrace=' + getBroadcastCustomNotificationStackTraceExcerpt(ex)
                );
            }
        }
        return currentOffset + totalChunks;
    }

    private static void rememberBroadcastCustomNotificationSendAttempt(
        Set<String> recipientChunk,
        String targetPageRef,
        String notificationTypeName,
        String notificationBody
    ) {
        broadcastCustomNotificationSendAttempts++;
        broadcastCustomNotificationRecipientChunks.add(new Set<String>(recipientChunk));
        broadcastCustomNotificationChunkRecipientCounts.add(recipientChunk.size());
        lastBroadcastCustomNotificationTypeName = notificationTypeName;
        lastBroadcastCustomNotificationTargetPageRef = targetPageRef;
        lastBroadcastCustomNotificationTitle = CUSTOM_NOTIFICATION_TITLE;
        lastBroadcastCustomNotificationBody = notificationBody;
        broadcastCustomNotificationTargetPageRefsBySendAttempt.add(targetPageRef);
        if (!broadcastCustomNotificationRecipientsByTargetPageRef.containsKey(targetPageRef)) {
            broadcastCustomNotificationRecipientsByTargetPageRef.put(targetPageRef, new Set<String>());
        }
        broadcastCustomNotificationRecipientsByTargetPageRef.get(targetPageRef)
            .addAll(recipientChunk);
        broadcastCustomNotificationBodiesByTargetPageRef.put(targetPageRef, notificationBody);
    }

    private static String getBroadcastCustomNotificationStackTraceExcerpt(Exception ex) {
        if (ex == null || String.isBlank(ex.getStackTraceString())) return null;
        String stackTrace = ex.getStackTraceString();
        return stackTrace.length() > 1000 ? stackTrace.substring(0, 1000) : stackTrace;
    }

    @TestVisible
    private static String buildInternalBroadcastNotificationTargetPageRef() {
        return CUSTOM_NOTIFICATION_INTERNAL_TARGET_PAGE_REF;
    }

    @TestVisible
    private static String buildCommunityBroadcastNotificationTargetPageRef() {
        return CUSTOM_NOTIFICATION_COMMUNITY_TARGET_PAGE_REF;
    }

    private static String buildBroadcastNotificationTargetPageRef() {
        return buildInternalBroadcastNotificationTargetPageRef();
    }

    private static CommunicatorDTOs.BroadcastListItemDTO buildListItem(
        CommunicatorGroup__c groupRecord,
        CommunicatorThread__c threadRecord,
        Map<Id, Integer> unreadByThread,
        Boolean hasCreatorPermission
    ) {
        CommunicatorDTOs.BroadcastListItemDTO dto = new CommunicatorDTOs.BroadcastListItemDTO();
        dto.groupId = String.valueOf(groupRecord.Id);
        dto.groupName = groupRecord.Name;
        dto.description = groupRecord.Description__c;
        dto.createdByUserId = String.valueOf(groupRecord.CreatedByUser__c);
        dto.createdByUserName = groupRecord.CreatedByUser__r == null
            ? null
            : groupRecord.CreatedByUser__r.Name;
        dto.createdByUserPhotoUrl = groupRecord.CreatedByUser__r == null
            ? null
            : groupRecord.CreatedByUser__r.SmallPhotoUrl;
        dto.threadId = threadRecord == null ? null : String.valueOf(threadRecord.Id);
        dto.broadcastLastActivityAt = groupRecord.BroadcastLastActivityAt__c;
        dto.lastMessageAt = groupRecord.BroadcastLastActivityAt__c;
        dto.unreadCount = threadRecord != null && unreadByThread.containsKey(threadRecord.Id)
            ? unreadByThread.get(threadRecord.Id)
            : 0;
        dto.canPublish = hasCreatorPermission == true &&
            groupRecord.CreatedByUser__c == UserInfo.getUserId();
        return dto;
    }

    private static CommunicatorMessage__c queryBroadcastMessage(Id messageId) {
        return [
            SELECT Id, Name, Subject__c, Body__c, SearchBody__c, Status__c, HasAttachment__c,
                   ContentDocumentId__c, SentAt__c, EditedAt__c, SystemModstamp,
                   IsSystemMessage__c, HasMention__c, Sender__c, Sender__r.Name,
                   BroadcastDistributionJobId__c, BroadcastDistributionError__c,
                   BroadcastDistributionCompletedAt__c, BroadcastAudienceCriteriaSnapshot__c,
                   Sender__r.SmallPhotoUrl, Thread__c
            FROM CommunicatorMessage__c
            WHERE Id = :messageId
            LIMIT 1
        ];
    }

    @TestVisible
    private static String buildBroadcastAudienceCriteriaSnapshot(Id broadcastGroupId) {
        if (Test.isRunningTest() && broadcastAudienceCriteriaSnapshotOverrideForTest != null) {
            return broadcastAudienceCriteriaSnapshotOverrideForTest;
        }

        BroadcastAudienceCriteriaSnapshotPayload payload =
            new BroadcastAudienceCriteriaSnapshotPayload();
        payload.v = BROADCAST_AUDIENCE_CRITERIA_SNAPSHOT_VERSION;
        payload.c = new List<BroadcastAudienceCriteriaSnapshotCriterion>();

        if (broadcastGroupId == null) {
            return JSON.serialize(payload);
        }

        for (CommunicatorBroadcastAudience__c criterion : [
            SELECT AudienceKey__c, AudienceType__c, TargetId__c
            FROM CommunicatorBroadcastAudience__c
            WHERE CommunicatorGroup__c = :broadcastGroupId
            AND IsActive__c = true
            ORDER BY AudienceKey__c ASC, AudienceType__c ASC, TargetId__c ASC, Id ASC
        ]) {
            if (String.isBlank(criterion.AudienceKey__c) ||
                String.isBlank(criterion.AudienceType__c) ||
                String.isBlank(criterion.TargetId__c)) {
                continue;
            }

            BroadcastAudienceCriteriaSnapshotCriterion item =
                new BroadcastAudienceCriteriaSnapshotCriterion();
            item.k = criterion.AudienceKey__c;
            item.t = criterion.AudienceType__c;
            item.i = criterion.TargetId__c;
            payload.c.add(item);
        }
        return JSON.serialize(payload);
    }

    private static void validateBroadcastAudienceCriteriaSnapshotSize(String criteriaSnapshot) {
        if (criteriaSnapshot != null &&
            criteriaSnapshot.length() > BROADCAST_AUDIENCE_CRITERIA_SNAPSHOT_MAX_LENGTH) {
            throw new CommunicatorException(SNAPSHOT_OVERSIZED_ERROR);
        }
    }

    public static CommunicatorDTOs.BroadcastMessageDTO getBroadcastMessageView(Id messageId) {
        CommunicatorMessage__c message = queryBroadcastMessage(messageId);
        LwcBroadcastMessageReadAccessContext accessContext =
            requireReadableBroadcastMessageForLwc(messageId);
        Boolean canManageBroadcast = accessContext.canPublish == true;
        return buildBroadcastMessageViews(
            new List<CommunicatorMessage__c>{ message },
            canManageBroadcast
        )[0];
    }

    private static List<CommunicatorDTOs.BroadcastMessageDTO> buildBroadcastMessageViews(
        List<CommunicatorMessage__c> messages,
        Boolean canManageBroadcast
    ) {
        List<CommunicatorDTOs.BroadcastMessageDTO> result =
            new List<CommunicatorDTOs.BroadcastMessageDTO>();
        if (messages == null || messages.isEmpty()) return result;

        Datetime nowValue = getCurrentDatetime();
        BroadcastEditLimitContext limitContext = new BroadcastEditLimitContext();
        for (CommunicatorMessage__c message : messages) {
            result.add(toBroadcastMessageDTO(message, canManageBroadcast, nowValue, limitContext));
        }
        return result;
    }

    private static CommunicatorDTOs.BroadcastMessageDTO toBroadcastMessageDTO(
        CommunicatorMessage__c message,
        Boolean canManageBroadcast,
        Datetime nowValue,
        BroadcastEditLimitContext limitContext
    ) {
        CommunicatorDTOs.BroadcastMessageDTO dto = new CommunicatorDTOs.BroadcastMessageDTO();
        dto.Id = String.valueOf(message.Id);
        dto.Name = message.Name;
        dto.subject = message.Subject__c;
        dto.body = message.Body__c;
        dto.searchBody = message.SearchBody__c;
        dto.status = message.Status__c;
        dto.hasAttachment = message.HasAttachment__c;
        dto.contentDocumentId = message.ContentDocumentId__c;
        dto.sentAt = message.SentAt__c;
        dto.editedAt = message.EditedAt__c;
        dto.SystemModstamp = message.SystemModstamp;
        dto.isSystemMessage = message.IsSystemMessage__c;
        dto.hasMention = message.HasMention__c;
        dto.senderId = message.Sender__c == null ? null : String.valueOf(message.Sender__c);
        dto.senderName = message.Sender__r == null ? null : message.Sender__r.Name;
        dto.senderPhotoUrl = message.Sender__r == null ? null : message.Sender__r.SmallPhotoUrl;
        dto.threadId = message.Thread__c == null ? null : String.valueOf(message.Thread__c);
        dto.broadcastDistributionJobId = message.BroadcastDistributionJobId__c;
        dto.broadcastDistributionError = message.BroadcastDistributionError__c;
        dto.broadcastDistributionCompletedAt = message.BroadcastDistributionCompletedAt__c;

        BroadcastEditAccessResult accessResult =
            evaluateBroadcastEditAccess(message, canManageBroadcast, nowValue, limitContext);
        dto.showEditAction = accessResult.showEditAction;
        dto.canEdit = accessResult.canEdit;
        dto.editDeadline = accessResult.editDeadline;
        dto.editBlockedReason = accessResult.blockedReason;
        dto.canRetry = canRetryBroadcastMessage(message, canManageBroadcast);
        return dto;
    }

    private static void assertBroadcastMessageEditable(
        CommunicatorMessage__c message,
        Boolean canManageBroadcast,
        Datetime nowValue
    ) {
        BroadcastEditAccessResult accessResult = evaluateBroadcastEditAccess(
            message,
            canManageBroadcast,
            nowValue,
            new BroadcastEditLimitContext()
        );
        if (accessResult.canEdit) return;
        if (String.isNotBlank(accessResult.blockedReason)) {
            throw new CommunicatorException(accessResult.blockedReason);
        }
        throw new CommunicatorException('Somente o remetente autorizado pode editar esta mensagem.');
    }

    private static BroadcastEditAccessResult evaluateBroadcastEditAccess(
        CommunicatorMessage__c message,
        Boolean canManageBroadcast,
        Datetime nowValue,
        BroadcastEditLimitContext limitContext
    ) {
        BroadcastEditAccessResult result = new BroadcastEditAccessResult();
        if (message == null || message.IsSystemMessage__c == true) return result;
        if (canManageBroadcast != true || message.Sender__c != UserInfo.getUserId()) return result;

        String statusValue = message.Status__c == null ? null : String.valueOf(message.Status__c).trim();
        result.showEditAction = true;
        if (statusValue == CommunicatorBroadcastDistributionService.STATUS_QUEUED ||
            statusValue == CommunicatorBroadcastDistributionService.STATUS_PROCESSING) {
            result.showEditAction = false;
            result.blockedReason = EDIT_DISTRIBUTION_IN_PROGRESS_ERROR;
            return result;
        }
        if (String.isBlank(statusValue) || statusValue != MESSAGE_STATUS_SENT) {
            result.canEdit = true;
            return result;
        }
        if (message.SentAt__c == null) {
            result.blockedReason = EDIT_SENT_AT_INVALID_ERROR;
            return result;
        }

        loadBroadcastEditLimitContext(limitContext);
        if (String.isNotBlank(limitContext.errorMessage)) {
            result.blockedReason = limitContext.errorMessage;
            return result;
        }

        result.editDeadline = message.SentAt__c.addDays(limitContext.limitDays);
        if (nowValue != null && nowValue.getTime() < result.editDeadline.getTime()) {
            result.canEdit = true;
            return result;
        }

        result.blockedReason = EDIT_EXPIRED_ERROR;
        return result;
    }

    private static void loadBroadcastEditLimitContext(BroadcastEditLimitContext limitContext) {
        if (limitContext == null || limitContext.loaded) return;
        limitContext.loaded = true;
        try {
            limitContext.limitDays = CommunicatorConfigService.getBroadcastEditLimitDays();
        } catch (CommunicatorException ex) {
            limitContext.errorMessage =
                ex != null && String.isNotBlank(ex.getMessage())
                    ? ex.getMessage()
                    : EDIT_CONFIG_INVALID_ERROR;
        }
    }

    private static Datetime getCurrentDatetime() {
        return currentDatetimeOverrideForTest == null
            ? System.now()
            : currentDatetimeOverrideForTest;
    }

    private static Boolean canRetryBroadcastMessage(
        CommunicatorMessage__c message,
        Boolean canManageBroadcast
    ) {
        return canManageBroadcast == true &&
            message != null &&
            message.Sender__c == UserInfo.getUserId() &&
            message.Status__c != null &&
            String.valueOf(message.Status__c).trim() == CommunicatorBroadcastDistributionService.STATUS_FAILED;
    }

    private static List<CommunicatorMessage__c> queryVisibleBroadcastMessages(
        Id threadId,
        Integer size,
        Integer offset,
        Boolean canManageBroadcast
    ) {
        return canManageBroadcast
            ? [
                SELECT Id, Name, Subject__c, Body__c, SearchBody__c, Status__c, HasAttachment__c,
                       ContentDocumentId__c, SentAt__c, EditedAt__c, SystemModstamp,
                       IsSystemMessage__c, HasMention__c, Sender__c, Sender__r.Name,
                       Sender__r.SmallPhotoUrl, Thread__c, BroadcastDistributionJobId__c,
                       BroadcastDistributionError__c, BroadcastDistributionCompletedAt__c
                FROM CommunicatorMessage__c
                WHERE Thread__c = :threadId
                ORDER BY SentAt__c ASC, Id ASC
                LIMIT :size
                OFFSET :offset
            ]
            : [
                SELECT Id, Name, Subject__c, Body__c, SearchBody__c, Status__c, HasAttachment__c,
                       ContentDocumentId__c, SentAt__c, EditedAt__c, SystemModstamp,
                       IsSystemMessage__c, HasMention__c, Sender__c, Sender__r.Name,
                       Sender__r.SmallPhotoUrl, Thread__c, BroadcastDistributionJobId__c,
                       BroadcastDistributionError__c, BroadcastDistributionCompletedAt__c
                FROM CommunicatorMessage__c
                WHERE Thread__c = :threadId
                AND Status__c = :MESSAGE_STATUS_SENT
                ORDER BY SentAt__c ASC, Id ASC
                LIMIT :size
                OFFSET :offset
            ];
    }

    private static List<CommunicatorMessage__c> queryVisibleBroadcastMessagesForPoll(
        Id threadId,
        BroadcastCursor parsedCursor,
        Boolean canManageBroadcast
    ) {
        if (parsedCursor == null || parsedCursor.timestampValue == null || parsedCursor.recordId == null) {
            return canManageBroadcast
                ? [
                    SELECT Id, Name, Subject__c, Body__c, SearchBody__c, Status__c, HasAttachment__c,
                           ContentDocumentId__c, SentAt__c, EditedAt__c, SystemModstamp,
                           IsSystemMessage__c, HasMention__c, Sender__c, Sender__r.Name,
                           Sender__r.SmallPhotoUrl, Thread__c, BroadcastDistributionJobId__c,
                           BroadcastDistributionError__c, BroadcastDistributionCompletedAt__c
                    FROM CommunicatorMessage__c
                    WHERE Thread__c = :threadId
                    ORDER BY SystemModstamp ASC, Id ASC
                    LIMIT 50
                ]
                : [
                    SELECT Id, Name, Subject__c, Body__c, SearchBody__c, Status__c, HasAttachment__c,
                           ContentDocumentId__c, SentAt__c, EditedAt__c, SystemModstamp,
                           IsSystemMessage__c, HasMention__c, Sender__c, Sender__r.Name,
                           Sender__r.SmallPhotoUrl, Thread__c, BroadcastDistributionJobId__c,
                           BroadcastDistributionError__c, BroadcastDistributionCompletedAt__c
                    FROM CommunicatorMessage__c
                    WHERE Thread__c = :threadId
                    AND Status__c = :MESSAGE_STATUS_SENT
                    ORDER BY SystemModstamp ASC, Id ASC
                    LIMIT 50
                ];
        }

        return canManageBroadcast
            ? [
                SELECT Id, Name, Subject__c, Body__c, SearchBody__c, Status__c, HasAttachment__c,
                       ContentDocumentId__c, SentAt__c, EditedAt__c, SystemModstamp,
                       IsSystemMessage__c, HasMention__c, Sender__c, Sender__r.Name,
                       Sender__r.SmallPhotoUrl, Thread__c, BroadcastDistributionJobId__c,
                       BroadcastDistributionError__c, BroadcastDistributionCompletedAt__c
                FROM CommunicatorMessage__c
                WHERE Thread__c = :threadId
                AND (
                    SystemModstamp > :parsedCursor.timestampValue
                    OR (SystemModstamp = :parsedCursor.timestampValue AND Id > :parsedCursor.recordId)
                )
                ORDER BY SystemModstamp ASC, Id ASC
                LIMIT 50
            ]
            : [
                SELECT Id, Name, Subject__c, Body__c, SearchBody__c, Status__c, HasAttachment__c,
                       ContentDocumentId__c, SentAt__c, EditedAt__c, SystemModstamp,
                       IsSystemMessage__c, HasMention__c, Sender__c, Sender__r.Name,
                       Sender__r.SmallPhotoUrl, Thread__c, BroadcastDistributionJobId__c,
                       BroadcastDistributionError__c, BroadcastDistributionCompletedAt__c
                FROM CommunicatorMessage__c
                WHERE Thread__c = :threadId
                AND Status__c = :MESSAGE_STATUS_SENT
                AND (
                    SystemModstamp > :parsedCursor.timestampValue
                    OR (SystemModstamp = :parsedCursor.timestampValue AND Id > :parsedCursor.recordId)
                )
                ORDER BY SystemModstamp ASC, Id ASC
                LIMIT 50
            ];
    }

    private static List<CommunicatorMessage__c> queryVisibleBroadcastMessagesByKeyword(
        Id threadId,
        String likePattern,
        Boolean canManageBroadcast
    ) {
        return canManageBroadcast
            ? [
                SELECT Id, Name, Subject__c, Body__c, SearchBody__c, Status__c, HasAttachment__c,
                       ContentDocumentId__c, SentAt__c, EditedAt__c, SystemModstamp,
                       IsSystemMessage__c, HasMention__c, Sender__c, Sender__r.Name,
                       Sender__r.SmallPhotoUrl, Thread__c, BroadcastDistributionJobId__c,
                       BroadcastDistributionError__c, BroadcastDistributionCompletedAt__c
                FROM CommunicatorMessage__c
                WHERE Thread__c = :threadId
                AND (
                    Subject__c LIKE :likePattern
                    OR SearchBody__c LIKE :likePattern
                )
                ORDER BY SentAt__c ASC
                LIMIT :MAX_SEARCH_RESULTS
            ]
            : [
                SELECT Id, Name, Subject__c, Body__c, SearchBody__c, Status__c, HasAttachment__c,
                       ContentDocumentId__c, SentAt__c, EditedAt__c, SystemModstamp,
                       IsSystemMessage__c, HasMention__c, Sender__c, Sender__r.Name,
                       Sender__r.SmallPhotoUrl, Thread__c, BroadcastDistributionJobId__c,
                       BroadcastDistributionError__c, BroadcastDistributionCompletedAt__c
                FROM CommunicatorMessage__c
                WHERE Thread__c = :threadId
                AND Status__c = :MESSAGE_STATUS_SENT
                AND (
                    Subject__c LIKE :likePattern
                    OR SearchBody__c LIKE :likePattern
                )
                ORDER BY SentAt__c ASC
                LIMIT :MAX_SEARCH_RESULTS
            ];
    }

    private static String normalizeClipboardImageFileName(String fileName) {
        String value = String.valueOf(fileName == null ? '' : fileName).trim();
        if (String.isBlank(value)) {
            throw new CommunicatorException('Informe o nome da imagem colada.');
        }
        value = value.replace('\\', '/');
        Integer slashIndex = value.lastIndexOf('/');
        if (slashIndex >= 0 && slashIndex + 1 < value.length()) {
            value = value.substring(slashIndex + 1);
        }
        value = value.replaceAll('[\\r\\n\\t]+', ' ');
        value = value.replaceAll('[<>:"/\\\\|?*]+', '_').trim();
        if (String.isBlank(value)) {
            throw new CommunicatorException('Informe o nome da imagem colada.');
        }
        if (value.length() > 255) {
            String extension = getClipboardImageExtension(value);
            Integer maxBaseLength = 254 - extension.length();
            if (maxBaseLength < 1) maxBaseLength = 1;
            value = value.substring(0, maxBaseLength) + '.' + extension;
        }
        return value;
    }

    private static String normalizeClipboardContentType(String contentType) {
        String value = String.valueOf(contentType == null ? '' : contentType).trim().toLowerCase();
        Integer semicolonIndex = value.indexOf(';');
        return semicolonIndex >= 0 ? value.substring(0, semicolonIndex).trim() : value;
    }

    private static String getClipboardImageExtension(String fileName) {
        Integer dotIndex = String.isBlank(fileName) ? -1 : fileName.lastIndexOf('.');
        if (dotIndex < 0 || dotIndex + 1 >= fileName.length()) {
            throw new CommunicatorException('A imagem colada deve possuir extensao PNG, JPG ou JPEG.');
        }
        return fileName.substring(dotIndex + 1).toLowerCase();
    }

    private static void validateClipboardImageType(String extension, String contentType) {
        if (!CLIPBOARD_IMAGE_EXTENSIONS.contains(extension)) {
            throw new CommunicatorException('Formato de imagem colada nao permitido. Use PNG, JPG ou JPEG.');
        }
        if (!CLIPBOARD_IMAGE_CONTENT_TYPES.contains(contentType)) {
            throw new CommunicatorException('Tipo de imagem colada nao permitido. Use PNG, JPG ou JPEG.');
        }
        if (extension == 'png' && contentType != 'image/png') {
            throw new CommunicatorException('Tipo da imagem colada incompatível com a extensao.');
        }
        if ((extension == 'jpg' || extension == 'jpeg') && contentType != 'image/jpeg') {
            throw new CommunicatorException('Tipo da imagem colada incompatível com a extensao.');
        }
    }

    private static String normalizeClipboardBase64(String base64Data, Decimal maxMB) {
        String value = String.valueOf(base64Data == null ? '' : base64Data).trim();
        if (String.isBlank(value)) {
            throw new CommunicatorException('Conteudo base64 invalido.');
        }
        if (value.toLowerCase().startsWith('data:')) {
            throw new CommunicatorException('Envie somente o conteudo base64 da imagem colada.');
        }
        Integer maxBase64Chars = calculateMaxBase64Characters(maxMB);
        if (value.length() > maxBase64Chars + 16) {
            throw new CommunicatorException(buildClipboardImageSizeErrorMessage());
        }
        if (value.length() > maxBase64Chars) {
            throw new CommunicatorException(buildClipboardImageSizeErrorMessage());
        }
        return value;
    }

    private static Integer calculateMaxBase64Characters(Decimal maxMB) {
        Integer maxBytes = calculateClipboardMaxBytes(maxMB);
        Integer groups = (maxBytes + 2) / 3;
        return groups * 4;
    }

    private static void validateClipboardImageSignature(Blob fileBody, String extension) {
        String hexPrefix = EncodingUtil.convertToHex(fileBody).toUpperCase();
        Boolean isPng = hexPrefix.startsWith('89504E470D0A1A0A');
        Boolean isJpeg = hexPrefix.startsWith('FFD8FF');
        if (extension == 'png' && !isPng) {
            throw new CommunicatorException('Conteudo da imagem colada incompativel com PNG.');
        }
        if ((extension == 'jpg' || extension == 'jpeg') && !isJpeg) {
            throw new CommunicatorException('Conteudo da imagem colada incompativel com JPEG.');
        }
    }

    private static void validateClipboardImageBlob(Blob fileBody, Decimal maxMB) {
        if (fileBody == null || fileBody.size() <= 0) {
            throw new CommunicatorException('A imagem colada esta vazia.');
        }
        if (fileBody.size() > calculateClipboardMaxBytes(maxMB)) {
            throw new CommunicatorException(buildClipboardImageSizeErrorMessage());
        }
    }

    private static Integer calculateClipboardMaxBytes(Decimal maxMB) {
        Decimal safeMaxMB = maxMB != null && maxMB > 0 ? maxMB : 1.5;
        return (safeMaxMB * 1024 * 1024).intValue();
    }

    private static String buildClipboardImageSizeErrorMessage() {
        String clipboardLimit = formatMegabytes(CommunicatorConfigService.getMaxClipboardBroadcastImageSizeMB());
        String uploadLimit = 'limite configurado';
        try {
            uploadLimit = formatMegabytes(
                Decimal.valueOf(CommunicatorConfigService.getMaxUploadBroadcastFileSizeMB())
            ) + ' MB';
        } catch (Exception ex) {
        }
        return 'Imagens coladas podem ter ate ' + clipboardLimit +
            ' MB. Para arquivos maiores, use Anexar arquivo, com limite de ' + uploadLimit + '.';
    }

    private static String formatMegabytes(Decimal value) {
        String result = String.valueOf(value);
        if (result.endsWith('.0')) result = result.substring(0, result.length() - 2);
        return result.replace('.', ',');
    }

    private static String buildClipboardContentTitle(String fileName) {
        Integer dotIndex = String.isBlank(fileName) ? -1 : fileName.lastIndexOf('.');
        return dotIndex > 0 ? fileName.substring(0, dotIndex) : fileName;
    }

    private static void ensureTemporaryGroupLink(Id contentDocumentId, Id groupId) {
        if (contentDocumentId == null || groupId == null) {
            throw new CommunicatorException('Nao foi possivel criar o vinculo temporario da imagem.');
        }
        List<ContentDocumentLink> existingLinks = [
            SELECT Id
            FROM ContentDocumentLink
            WHERE ContentDocumentId = :contentDocumentId
            AND LinkedEntityId = :groupId
            LIMIT 1
        ];
        if (!existingLinks.isEmpty()) return;

        insert new ContentDocumentLink(
            ContentDocumentId = contentDocumentId,
            LinkedEntityId = groupId,
            ShareType = 'V',
            Visibility = 'AllUsers'
        );
    }

    private static Set<Id> parseDocumentIds(List<String> rawIds) {
        Set<Id> result = new Set<Id>();
        if (rawIds == null) return result;
        for (String rawId : rawIds) {
            try {
                Id documentId = (Id) rawId;
                if (documentId.getSObjectType() == ContentDocument.SObjectType) result.add(documentId);
            } catch (Exception ex) { }
        }
        return result;
    }

    private static Id tryParseGroupId(String rawId) {
        if (String.isBlank(rawId)) return null;
        try {
            Id groupId = (Id) rawId;
            return groupId.getSObjectType() == CommunicatorGroup__c.SObjectType ? groupId : null;
        } catch (Exception ex) {
            return null;
        }
    }

    private static Integer normalizePageSize(Integer pageSize) {
        Integer result = pageSize != null && pageSize > 0 ? pageSize : DEFAULT_PAGE_SIZE;
        return Math.min(result, MAX_PAGE_SIZE);
    }

    private static String normalizeBroadcastSubject(String subject) {
        return String.isBlank(subject) ? null : subject.trim();
    }

    private static void validateBroadcastSubject(String subject) {
        if (String.isBlank(subject)) {
            throw new CommunicatorException(SUBJECT_REQUIRED_ERROR);
        }
        Integer maxLength = CommunicatorMessage__c.Subject__c.getDescribe().getLength();
        if (subject.length() > maxLength) {
            throw new CommunicatorException(
                'O assunto do comunicado excede o limite permitido de ' + maxLength + ' caracteres.'
            );
        }
    }

    private static String sanitizeSearchKeyword(String keyword) {
        return keyword.trim()
            .replace('\\', '\\\\')
            .replace('%', '\\%')
            .replace('_', '\\_');
    }

    private static BroadcastCursor parseCursor(String cursor) {
        if (String.isBlank(cursor)) return null;
        try {
            return (BroadcastCursor) JSON.deserialize(cursor, BroadcastCursor.class);
        } catch (Exception ex) {
            throw new CommunicatorException('Cursor de comunicado inválido.');
        }
    }

    private static String serializeCursor(Datetime timestampValue, Id recordId) {
        if (timestampValue == null || recordId == null) return null;
        BroadcastCursor cursor = new BroadcastCursor();
        cursor.timestampValue = timestampValue;
        cursor.recordId = recordId;
        return JSON.serialize(cursor);
    }

    private static Integer safeInteger(Integer value) {
        return value == null || value < 0 ? 0 : value;
    }
}