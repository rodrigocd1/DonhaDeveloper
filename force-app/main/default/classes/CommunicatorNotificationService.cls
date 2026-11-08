/**
 * @description Service responsible for sending notifications and managing unread counts.
 */
public with sharing class CommunicatorNotificationService {

    private static final String NOTIFICATION_TYPE_NAME = 'CommunicatorNewMessage';
    private static final Integer CUSTOM_NOTIFICATION_BODY_MAX_LENGTH = 255;
    @TestVisible private static Map<Id, RecipientUserContext> recipientContextByUserId = new Map<Id, RecipientUserContext>();
    @TestVisible private static Map<Id, CommunicatorThread__c> threadByIdCache = new Map<Id, CommunicatorThread__c>();
    @TestVisible private static Map<Id, CommunicatorMessage__c> messageByIdCache = new Map<Id, CommunicatorMessage__c>();
    @TestVisible private static Id notificationTypeIdCache;
    @TestVisible private static Map<Id, String> userLicenseOverrideByIdForTest;
    @TestVisible private static Map<Id, Boolean> userIsActiveOverrideByIdForTest;

    // ─────────────────────────────────────────
    // Notifications
    // ─────────────────────────────────────────

    /**
     * @description Sends a Salesforce bell notification to all thread participants
     *              except the current sender, and creates CommunicatorNotification__c
     *              records for read/unread tracking.
     *
     * @param mentionedUserIds  Resolved set of mentioned user IDs (may be empty).
     */
    public static void notifyParticipants(Id threadId, Id messageId) {
        notifyParticipants(threadId, messageId, new Set<Id>());
    }

    /**
     * @description Sends a Salesforce bell notification to all thread participants
     *              except the current sender, and creates CommunicatorNotification__c
     *              records for read/unread tracking.
     *
     * @param mentionedUserIds  Resolved set of mentioned user IDs (may be empty).
     */
    public static void notifyParticipants(Id threadId, Id messageId, Set<Id> mentionedUserIds) {
        List<CommunicatorParticipant__c> participants = [
            SELECT Id, User__c
            FROM CommunicatorParticipant__c
            WHERE Thread__c = :threadId
            AND IsActive__c = true
            AND User__c != :UserInfo.getUserId()
        ];

        Set<Id> participantUserIds = new Set<Id>();
        for (CommunicatorParticipant__c p : participants) {
            if (p.User__c != null) {
                participantUserIds.add(p.User__c);
            }
        }

        notifyExplicitRecipients(threadId, messageId, participantUserIds, mentionedUserIds);
    }

    public static void notifyParticipantsBulk(Map<Id, Id> threadToMessageId) {
        if (threadToMessageId == null || threadToMessageId.isEmpty()) return;

        Map<Id, Set<Id>> participantsByThreadId = new Map<Id, Set<Id>>();
        Set<Id> threadIds = new Set<Id>(threadToMessageId.keySet());
        for (CommunicatorParticipant__c participant : [
            SELECT Thread__c, User__c
            FROM CommunicatorParticipant__c
            WHERE Thread__c IN :threadIds
            AND IsActive__c = true
            AND User__c != :UserInfo.getUserId()
        ]) {
            if (participant.Thread__c == null || participant.User__c == null) continue;
            if (!participantsByThreadId.containsKey(participant.Thread__c)) {
                participantsByThreadId.put(participant.Thread__c, new Set<Id>());
            }
            participantsByThreadId.get(participant.Thread__c).add(participant.User__c);
        }

        getThreadMap(threadIds);
        loadRecipientContexts(collectRecipientIds(participantsByThreadId.values()));

        for (Id threadId : threadToMessageId.keySet()) {
            Set<Id> participantUserIds = participantsByThreadId.containsKey(threadId)
                ? participantsByThreadId.get(threadId)
                : new Set<Id>();
            notifyExplicitRecipientsInternal(
                getThreadById(threadId),
                threadToMessageId.get(threadId),
                participantUserIds,
                new Set<Id>()
            );
        }
    }

    /**
     * @description Sends custom notifications and creates read-tracking records for system
     *              Chatter events. System event records reference the FeedItem and have no message.
     */
    public static void notifySystemEventsBulk(Map<Id, Id> threadToFeedItemId, Map<Id, String> threadToBody) {
        if (threadToFeedItemId == null || threadToFeedItemId.isEmpty()) return;

        Map<Id, Id> feedItemIdsByValidThread = new Map<Id, Id>();
        for (Id threadId : threadToFeedItemId.keySet()) {
            if (threadId != null && threadToFeedItemId.get(threadId) != null) {
                feedItemIdsByValidThread.put(threadId, threadToFeedItemId.get(threadId));
            }
        }
        if (feedItemIdsByValidThread.isEmpty()) return;

        Set<Id> threadIds = new Set<Id>(feedItemIdsByValidThread.keySet());
        Map<Id, Set<Id>> participantsByThreadId = new Map<Id, Set<Id>>();
        for (CommunicatorParticipant__c participant : [
            SELECT Thread__c, User__c
            FROM CommunicatorParticipant__c
            WHERE Thread__c IN :threadIds
            AND IsActive__c = true
            AND User__c != :UserInfo.getUserId()
        ]) {
            if (participant.Thread__c == null || participant.User__c == null) continue;
            if (!participantsByThreadId.containsKey(participant.Thread__c)) {
                participantsByThreadId.put(participant.Thread__c, new Set<Id>());
            }
            participantsByThreadId.get(participant.Thread__c).add(participant.User__c);
        }

        Map<Id, CommunicatorThread__c> threadsById = getThreadMap(threadIds);
        loadRecipientContexts(collectRecipientIds(participantsByThreadId.values()));
        Map<Id, Set<Id>> recipientsByThread = new Map<Id, Set<Id>>();
        Map<Id, Set<Id>> platformRecipientsByThread = new Map<Id, Set<Id>>();
        Map<Id, Set<Id>> nonPlatformRecipientsByThread = new Map<Id, Set<Id>>();

        for (Id threadId : threadIds) {
            CommunicatorThread__c thread = threadsById.get(threadId);
            if (thread == null) continue;
            Set<Id> candidates = participantsByThreadId.containsKey(threadId)
                ? participantsByThreadId.get(threadId)
                : new Set<Id>();
            Set<Id> activeRecipients = new Set<Id>();
            Set<Id> platformRecipients = new Set<Id>();
            Set<Id> nonPlatformRecipients = new Set<Id>();
            for (Id candidateId : candidates) {
                if (candidateId == null || candidateId == UserInfo.getUserId()) continue;
                RecipientUserContext context = recipientContextByUserId.get(candidateId);
                if (context == null || context.isActive != true) continue;
                activeRecipients.add(candidateId);
                if (context.isPlatform == true) platformRecipients.add(candidateId);
                else nonPlatformRecipients.add(candidateId);
            }
            if (!activeRecipients.isEmpty()) recipientsByThread.put(threadId, activeRecipients);
            if (!platformRecipients.isEmpty()) platformRecipientsByThread.put(threadId, platformRecipients);
            if (!nonPlatformRecipients.isEmpty()) nonPlatformRecipientsByThread.put(threadId, nonPlatformRecipients);
        }

        Map<Id, Set<Id>> eligiblePlatformByThread = CommunicatorThreadService.getAssessoriaUsersWithThreadAccessBulk(
            platformRecipientsByThread,
            new Map<Id, Set<Id>>()
        );
        for (Id threadId : threadIds) {
            CommunicatorThread__c thread = threadsById.get(threadId);
            if (thread == null) continue;
            Set<Id> bellRecipients = new Set<Id>();
            if (nonPlatformRecipientsByThread.containsKey(threadId)) {
                bellRecipients.addAll(nonPlatformRecipientsByThread.get(threadId));
            }
            if (eligiblePlatformByThread.containsKey(threadId)) {
                bellRecipients.addAll(eligiblePlatformByThread.get(threadId));
            }
            if (bellRecipients.isEmpty()) continue;
            Set<String> recipientIds = new Set<String>();
            for (Id recipientId : bellRecipients) recipientIds.add(String.valueOf(recipientId));
            String body = threadToBody == null ? null : threadToBody.get(threadId);
            sendCustomNotificationText(recipientIds, buildTargetPageRef(thread), body);
        }

        CommunicatorNotificationRecordService.createSystemEventNotifications(
            recipientsByThread,
            feedItemIdsByValidThread
        );
    }

    /**
     * @description Sends notifications to an explicit recipient set. Used by
     *              inbound socket reconciliation where recipients come from payload.
     */
    public static void notifyExplicitRecipients(
        Id threadId,
        Id messageId,
        Set<Id> recipientUserIds,
        Set<Id> mentionedUserIds
    ) {
        notifyExplicitRecipientsInternal(getThreadById(threadId), messageId, recipientUserIds, mentionedUserIds);
    }

    private static void notifyExplicitRecipientsInternal(
        CommunicatorThread__c thread,
        Id messageId,
        Set<Id> recipientUserIds,
        Set<Id> mentionedUserIds
    ) {
        if (thread == null || thread.Id == null || messageId == null || recipientUserIds == null || recipientUserIds.isEmpty()) return;

        Set<Id> recipients = new Set<Id>();
        for (Id recipientId : recipientUserIds) {
            if (recipientId != null) {
                recipients.add(recipientId);
            }
        }
        recipients.remove(UserInfo.getUserId());
        if (recipients.isEmpty()) return;

        loadRecipientContexts(recipients);

        Set<Id> activeRecipients = new Set<Id>();
        Set<Id> platformUserIds = new Set<Id>();
        Set<Id> nonPlatformUserIds = new Set<Id>();
        for (Id recipientId : recipients) {
            RecipientUserContext recipientContext = recipientContextByUserId.get(recipientId);
            if (recipientContext == null || recipientContext.isActive != true) continue;
            activeRecipients.add(recipientId);
            if (recipientContext.isPlatform == true) {
                platformUserIds.add(recipientId);
            } else {
                nonPlatformUserIds.add(recipientId);
            }
        }
        if (activeRecipients.isEmpty()) return;

        Set<Id> mentions = new Set<Id>();
        if (mentionedUserIds != null && !mentionedUserIds.isEmpty()) {
            mentions.addAll(mentionedUserIds);
            mentions.retainAll(activeRecipients);
        }

        if (!mentions.isEmpty()) {
            CommunicatorNotificationRecordService.createNotificationsIfMissing(
                messageId, thread.Id, mentions, true
            );
        }

        Set<Id> standardRecipients = activeRecipients.clone();
        standardRecipients.removeAll(mentions);
        if (!standardRecipients.isEmpty()) {
            CommunicatorNotificationRecordService.createNotificationsIfMissing(
                messageId, thread.Id, standardRecipients, false
            );
        }

        Set<Id> bellRecipients = new Set<Id>(nonPlatformUserIds);
        if (!platformUserIds.isEmpty()) {
            Set<Id> directlyMentionedPlatformUserIds = new Set<Id>(platformUserIds);
            directlyMentionedPlatformUserIds.retainAll(mentions);
            bellRecipients.addAll(
                CommunicatorThreadService.getAssessoriaUsersWithThreadAccess(
                    thread.Id,
                    platformUserIds,
                    directlyMentionedPlatformUserIds
                )
            );
        }

        if (bellRecipients.isEmpty()) return;

        Set<String> recipientIds = new Set<String>();
        for (Id uid : bellRecipients) {
            recipientIds.add(uid);
        }

        String targetPageRef = buildTargetPageRef(thread);
        sendCustomNotification(recipientIds, targetPageRef, messageId);
    }

    // ─────────────────────────────────────────
    // Unread count
    // ─────────────────────────────────────────

    /**
     * @description Returns the number of unread notifications for the current user
     *              in a thread, using CommunicatorNotification__c for precise tracking.
     */
    public static Integer getUnreadCount(Id threadId) {
        return CommunicatorNotificationRecordService.getUnreadCount(threadId);
    }

    /**
     * @description Returns the total unread message count for the current user
      *              across communicator opportunity chats.
     */
    public static Integer getOpportunityUnreadMessageTotal(
        Integer pageSize,
        Integer offsetVal,
        String keyword
    ) {
        return CommunicatorNotificationRecordService.getOpportunityUnreadMessageTotal(
            pageSize,
            offsetVal,
            keyword
        );
    }

    /**
     * @description Marks all unread notifications as read for the current user
     *              in a thread. Called automatically when the user opens the chat.
     */
    public static void markThreadAsRead(Id threadId) {
        Id currentUserId = UserInfo.getUserId();

        // Update participant LastReadAt (legacy support)
        List<CommunicatorParticipant__c> participants = [
            SELECT Id FROM CommunicatorParticipant__c
            WHERE Thread__c = :threadId AND User__c = :currentUserId LIMIT 1
        ];
        if (participants.isEmpty()) {
            insert new CommunicatorParticipant__c(
                Thread__c     = threadId,
                User__c       = currentUserId,
                IsActive__c   = true,
                LastReadAt__c = System.now()
            );
        } else {
            update new CommunicatorParticipant__c(
                Id            = participants[0].Id,
                LastReadAt__c = System.now()
            );
        }

        // Mark CommunicatorNotification__c records as read
        CommunicatorNotificationRecordService.markThreadNotificationsAsRead(threadId);
    }

    // ─────────────────────────────────────────
    // Private helpers
    // ─────────────────────────────────────────

    private static void sendCustomNotification(Set<String> recipientIds, String targetPageRef, Id messageId) {
        try {
            Messaging.CustomNotification notification = new Messaging.CustomNotification();
            notification.setTitle('Nova mensagem no canal');
            notification.setBody(buildNotificationBody(getMessageById(messageId)));
            notification.setNotificationTypeId(getNotificationTypeId());
            notification.setTargetPageRef(targetPageRef);
            notification.send(recipientIds);
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, 'CommunicatorNotificationService.sendCustomNotification error: ' + ex.getMessage());
        }
    }

    private static void sendCustomNotificationText(Set<String> recipientIds, String targetPageRef, String body) {
        try {
            Messaging.CustomNotification notification = new Messaging.CustomNotification();
            notification.setTitle('Nova mensagem no canal');
            notification.setBody(String.isBlank(body) ? 'Nova movimentação' : body.abbreviate(CUSTOM_NOTIFICATION_BODY_MAX_LENGTH));
            notification.setNotificationTypeId(getNotificationTypeId());
            notification.setTargetPageRef(targetPageRef);
            notification.send(recipientIds);
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, 'CommunicatorNotificationService.sendCustomNotificationText error: ' + ex.getMessage());
        }
    }

    private static CommunicatorThread__c getThreadById(Id threadId) {
        if (threadId == null) return null;
        if (!threadByIdCache.containsKey(threadId)) {
            List<CommunicatorThread__c> threads = [
                SELECT Id, RecordId__c, RecordType__c
                FROM CommunicatorThread__c
                WHERE Id = :threadId
                LIMIT 1
            ];
            threadByIdCache.put(threadId, threads.isEmpty() ? null : threads[0]);
        }
        return threadByIdCache.get(threadId);
    }

    private static CommunicatorMessage__c getMessageById(Id messageId) {
        if (messageId == null) return null;
        if (!messageByIdCache.containsKey(messageId)) {
            List<CommunicatorMessage__c> messages = [
                SELECT Id, Body__c, HasAttachment__c
                FROM CommunicatorMessage__c
                WHERE Id = :messageId
                LIMIT 1
            ];
            messageByIdCache.put(messageId, messages.isEmpty() ? null : messages[0]);
        }
        return messageByIdCache.get(messageId);
    }

    private static Map<Id, CommunicatorThread__c> getThreadMap(Set<Id> threadIds) {
        Set<Id> missingThreadIds = new Set<Id>();
        for (Id threadId : threadIds) {
            if (threadId != null && !threadByIdCache.containsKey(threadId)) {
                missingThreadIds.add(threadId);
            }
        }
        if (!missingThreadIds.isEmpty()) {
            for (CommunicatorThread__c thread : [
                SELECT Id, RecordId__c, RecordType__c
                FROM CommunicatorThread__c
                WHERE Id IN :missingThreadIds
            ]) {
                threadByIdCache.put(thread.Id, thread);
            }
            for (Id missingThreadId : missingThreadIds) {
                if (!threadByIdCache.containsKey(missingThreadId)) {
                    threadByIdCache.put(missingThreadId, null);
                }
            }
        }
        return threadByIdCache;
    }

    private static void loadRecipientContexts(Set<Id> userIds) {
        Set<Id> missingUserIds = new Set<Id>();
        for (Id userId : userIds) {
            if (userId != null && !recipientContextByUserId.containsKey(userId)) {
                missingUserIds.add(userId);
            }
        }
        if (missingUserIds.isEmpty()) return;

        for (User userRecord : [
            SELECT Id, IsActive, UserRoleId, Profile.UserLicense.Name
            FROM User
            WHERE Id IN :missingUserIds
        ]) {
            RecipientUserContext context = new RecipientUserContext();
            context.userId = userRecord.Id;
            context.isActive = userRecord.IsActive;
            context.isPlatform = userRecord.Profile?.UserLicense?.Name == 'Salesforce Platform';
            context.userRoleId = userRecord.UserRoleId;
            if (Test.isRunningTest() && userLicenseOverrideByIdForTest != null && userLicenseOverrideByIdForTest.containsKey(userRecord.Id)) {
                context.isPlatform = userLicenseOverrideByIdForTest.get(userRecord.Id) == 'Salesforce Platform';
            }
            if (Test.isRunningTest() && userIsActiveOverrideByIdForTest != null && userIsActiveOverrideByIdForTest.containsKey(userRecord.Id)) {
                context.isActive = userIsActiveOverrideByIdForTest.get(userRecord.Id);
            }
            recipientContextByUserId.put(userRecord.Id, context);
        }

        for (Id missingUserId : missingUserIds) {
            if (!recipientContextByUserId.containsKey(missingUserId)) {
                recipientContextByUserId.put(missingUserId, null);
            }
        }
    }

    private static Set<Id> collectRecipientIds(List<Set<Id>> recipientSets) {
        Set<Id> recipientIds = new Set<Id>();
        if (recipientSets == null) return recipientIds;
        for (Set<Id> recipientSet : recipientSets) {
            if (recipientSet != null) recipientIds.addAll(recipientSet);
        }
        return recipientIds;
    }

    private static Id getNotificationTypeId() {
        if (notificationTypeIdCache == null) {
            notificationTypeIdCache = [
                SELECT Id
                FROM CustomNotificationType
                WHERE DeveloperName = :NOTIFICATION_TYPE_NAME
                LIMIT 1
            ].Id;
        }
        return notificationTypeIdCache;
    }

    @TestVisible
    private static String buildNotificationBody(CommunicatorMessage__c messageRecord) {
        if (messageRecord == null) {
            return 'Você recebeu uma nova mensagem. Clique para visualizar.';
        }

        String rawBody = messageRecord.Body__c == null ? '' : messageRecord.Body__c;
        String normalizedBody = rawBody
            .replace('\r', ' ')
            .replace('\n', ' ')
            .trim();

        while (normalizedBody.contains('  ')) {
            normalizedBody = normalizedBody.replace('  ', ' ');
        }

        if (String.isBlank(normalizedBody)) {
            return messageRecord.HasAttachment__c == true
                ? 'Você recebeu um novo anexo. Clique para visualizar.'
                : 'Você recebeu uma nova mensagem. Clique para visualizar.';
        }

        if (normalizedBody.length() > CUSTOM_NOTIFICATION_BODY_MAX_LENGTH) {
            return normalizedBody.substring(0, CUSTOM_NOTIFICATION_BODY_MAX_LENGTH - 3) + '...';
        }

        return normalizedBody;
    }

    private static String buildTargetPageRef(CommunicatorThread__c thread) {
        if (thread == null || String.isBlank(thread.RecordId__c)) return '{}';
        // Navigate to the linked record (generic — works for any SObject)
        return '{"type":"standard__recordPage","attributes":{"recordId":"' + thread.RecordId__c + '","actionName":"view"}}';
    }

    private class RecipientUserContext {
        Id userId;
        Boolean isActive;
        Boolean isPlatform;
        Id userRoleId;
    }
}