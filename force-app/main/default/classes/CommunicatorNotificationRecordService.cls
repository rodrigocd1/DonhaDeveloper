/**
 * @description Service responsible for CommunicatorNotification__c records.
 *              These provide per-user read/unread tracking beyond what
 *              CommunicatorParticipant__c.LastReadAt__c offers.
 *              Created when a message is sent; marked as read when the
 *              recipient opens the chat thread.
 */
public with sharing class CommunicatorNotificationRecordService {

    @TestVisible private static Boolean failReopenBroadcastNotificationsForTest = false;
    @TestVisible private static Boolean forceDuplicateKeyLookupFallbackForTest = false;
    private static final String BROADCAST_NOTIFICATION_TYPE = 'Broadcast';
    private static final String BROADCAST_NOTIFICATION_KEY_FIELD = 'BroadcastNotificationKey__c';

    // ─────────────────────────────────────────
    // Create
    // ─────────────────────────────────────────

    /**
     * @description Creates CommunicatorNotification__c records for all
     *              recipients of a message. One record per recipient.
     *
     * @param messageId    The new message Id.
     * @param threadId     The thread Id.
     * @param recipientIds User IDs to notify.
     * @param isMention    True if this notification originated from a @mention.
     */
    public static void createNotifications(
        Id          messageId,
        Id          threadId,
        Set<Id>     recipientIds,
        Boolean     isMention
    ) {
        if (recipientIds == null || recipientIds.isEmpty()) return;

        String notifType = isMention ? 'Mention' : 'NewMessage';

        List<CommunicatorNotification__c> toInsert = new List<CommunicatorNotification__c>();
        for (Id userId : recipientIds) {
            toInsert.add(new CommunicatorNotification__c(
                Thread__c    = threadId,
                Message__c   = messageId,
                Recipient__c = userId,
                IsRead__c    = false,
                IsMention__c = isMention,
                Type__c      = notifType
            ));
        }
        insert toInsert;
    }

    /**
     * @description Creates CommunicatorNotification__c records only for recipients
     *              that do not already have a notification for the same message.
     */
    public static void createNotificationsIfMissing(
        Id          messageId,
        Id          threadId,
        Set<Id>     recipientIds,
        Boolean     isMention
    ) {
        if (messageId == null || threadId == null || recipientIds == null || recipientIds.isEmpty()) {
            return;
        }

        Set<Id> targetRecipients = new Set<Id>();
        for (Id recipientId : recipientIds) {
            if (recipientId != null) {
                targetRecipients.add(recipientId);
            }
        }
        if (targetRecipients.isEmpty()) return;

        Set<Id> existingRecipients = new Set<Id>();
        for (CommunicatorNotification__c notif : [
            SELECT Recipient__c
            FROM CommunicatorNotification__c
            WHERE Message__c = :messageId
            AND Recipient__c IN :targetRecipients
        ]) {
            if (notif.Recipient__c != null) {
                existingRecipients.add(notif.Recipient__c);
            }
        }

        targetRecipients.removeAll(existingRecipients);
        if (targetRecipients.isEmpty()) return;

        createNotifications(messageId, threadId, targetRecipients, isMention);
    }

    /**
     * @description Creates read-tracking rows for system Chatter events. Message__c remains
     *              empty and FeedItemId__c links the notification to the published post.
     */
    public static void createSystemEventNotifications(
        Map<Id, Set<Id>> recipientsByThread,
        Map<Id, Id> threadToFeedItemId
    ) {
        if (recipientsByThread == null || recipientsByThread.isEmpty()
            || threadToFeedItemId == null || threadToFeedItemId.isEmpty()) return;

        List<CommunicatorNotification__c> notifications = new List<CommunicatorNotification__c>();
        for (Id threadId : recipientsByThread.keySet()) {
            Id feedItemId = threadToFeedItemId.get(threadId);
            Set<Id> recipientIds = recipientsByThread.get(threadId);
            if (threadId == null || feedItemId == null || recipientIds == null || recipientIds.isEmpty()) continue;
            for (Id recipientId : recipientIds) {
                if (recipientId == null) continue;
                notifications.add(new CommunicatorNotification__c(
                    Thread__c = threadId,
                    Recipient__c = recipientId,
                    IsRead__c = false,
                    IsMention__c = false,
                    Type__c = 'NewMessage',
                    FeedItemId__c = feedItemId
                ));
            }
        }
        if (!notifications.isEmpty()) insert notifications;
    }

    public static void createBroadcastNotifications(
        Id messageId,
        Id threadId,
        Set<Id> recipientIds
    ) {
        if (messageId == null || threadId == null || recipientIds == null || recipientIds.isEmpty()) return;
        List<CommunicatorNotification__c> notifications =
            buildBroadcastNotifications(messageId, threadId, recipientIds, false);
        if (notifications.isEmpty()) return;
        CommunicatorBroadcastDmlGuardHandler.authorizeNotificationDml('INSERT', notifications);
        try {
            insert notifications;
        } finally {
            CommunicatorBroadcastDmlGuardHandler.clearOfficialAuthorization();
        }
    }

    public static void createBroadcastNotificationsIfMissing(
        Id messageId,
        Id threadId,
        Set<Id> recipientIds
    ) {
        if (messageId == null || threadId == null || recipientIds == null || recipientIds.isEmpty()) return;
        Set<Id> targetRecipients = new Set<Id>();
        for (Id recipientId : recipientIds) {
            if (recipientId != null && recipientId != UserInfo.getUserId()) {
                targetRecipients.add(recipientId);
            }
        }
        if (targetRecipients.isEmpty()) return;

        Set<Id> existingRecipients = new Set<Id>();
        for (CommunicatorNotification__c notif : [
            SELECT Recipient__c
            FROM CommunicatorNotification__c
            WHERE Message__c = :messageId
            AND Type__c = :BROADCAST_NOTIFICATION_TYPE
            AND Recipient__c IN :targetRecipients
        ]) {
            if (notif.Recipient__c != null) {
                existingRecipients.add(notif.Recipient__c);
            }
        }

        targetRecipients.removeAll(existingRecipients);
        if (targetRecipients.isEmpty()) return;
        List<CommunicatorNotification__c> notifications =
            buildBroadcastNotifications(messageId, threadId, targetRecipients, true);
        if (notifications.isEmpty()) return;
        insertBroadcastNotificationsAllowingDuplicateKeys(notifications);
    }

    // ─────────────────────────────────────────
    // Mark as read
    // ─────────────────────────────────────────

    /**
     * @description Marks all unread notifications for the current user
     *              in a given thread as read. Called automatically when
     *              the user opens the chat.
     */
    public static void markThreadNotificationsAsRead(Id threadId) {
        Id currentUserId = UserInfo.getUserId();

        List<CommunicatorNotification__c> unread = [
            SELECT Id
            FROM   CommunicatorNotification__c
            WHERE  Thread__c    = :threadId
            AND    Recipient__c = :currentUserId
            AND    IsRead__c    = false
        ];

        if (unread.isEmpty()) return;

        DateTime now = System.now();
        for (CommunicatorNotification__c n : unread) {
            n.IsRead__c = true;
            n.ReadAt__c = now;
        }
        update unread;
    }

    public static void markBroadcastNotificationsAsRead(Id threadId) {
        List<CommunicatorNotification__c> unread = [
            SELECT Id, Thread__c, Message__c, Recipient__c, Type__c,
                   IsRead__c, ReadAt__c, IsMention__c
            FROM CommunicatorNotification__c
            WHERE Thread__c = :threadId
            AND Recipient__c = :UserInfo.getUserId()
            AND Type__c = :BROADCAST_NOTIFICATION_TYPE
            AND IsRead__c = false
            AND Message__r.Status__c = 'Sent'
        ];
        if (unread.isEmpty()) return;
        Datetime readAt = System.now();
        for (CommunicatorNotification__c notification : unread) {
            notification.IsRead__c = true;
            notification.ReadAt__c = readAt;
        }
        CommunicatorBroadcastDmlGuardHandler.authorizeNotificationDml('UPDATE', unread);
        try {
            update unread;
        } finally {
            CommunicatorBroadcastDmlGuardHandler.clearOfficialAuthorization();
        }
    }

    public static Integer reopenReadBroadcastNotificationsForMessage(
        Id messageId,
        Id threadId,
        Id senderId
    ) {
        if (messageId == null || threadId == null) return 0;
        if (Test.isRunningTest() && failReopenBroadcastNotificationsForTest) {
            throw new CommunicatorException('Falha simulada na reabertura de notificacoes Broadcast.');
        }

        List<CommunicatorNotification__c> readNotifications = [
            SELECT Id, Thread__c, Message__c, Recipient__c, Type__c,
                   IsRead__c, ReadAt__c, IsMention__c
            FROM CommunicatorNotification__c
            WHERE Message__c = :messageId
            AND Thread__c = :threadId
            AND Type__c = :BROADCAST_NOTIFICATION_TYPE
            AND IsRead__c = true
        ];
        List<CommunicatorNotification__c> toUpdate = new List<CommunicatorNotification__c>();
        for (CommunicatorNotification__c notification : readNotifications) {
            if (senderId != null && notification.Recipient__c == senderId) continue;
            notification.IsRead__c = false;
            notification.ReadAt__c = null;
            toUpdate.add(notification);
        }
        if (toUpdate.isEmpty()) return 0;

        CommunicatorBroadcastDmlGuardHandler.authorizeNotificationDml('UPDATE', toUpdate);
        try {
            update toUpdate;
        } finally {
            CommunicatorBroadcastDmlGuardHandler.clearOfficialAuthorization();
        }
        return toUpdate.size();
    }

    /**
     * @description Marks all unread group-mention notifications as read
     *              for the current user in a given group.
     *              Group mention notifications are linked by Message__c
     *              (not by Thread__c), so markThreadNotificationsAsRead
     *              does not cover them.
     */
    public static void markGroupMentionsAsRead(Id groupId) {
        Id currentUserId = UserInfo.getUserId();

        List<CommunicatorMessage__c> mentionMsgs = [
            SELECT Id, MentionedGroupIds__c
            FROM   CommunicatorMessage__c
            WHERE  HasMention__c = true
            LIMIT  2000
        ];

        Set<Id> msgIds = new Set<Id>();
        for (CommunicatorMessage__c msg : mentionMsgs) {
            Set<Id> groups = CommunicatorMentionService.deserializeUserIds(msg.MentionedGroupIds__c);
            if (groups.contains(groupId)) {
                msgIds.add(msg.Id);
            }
        }

        if (msgIds.isEmpty()) return;

        List<CommunicatorNotification__c> unread = [
            SELECT Id
            FROM   CommunicatorNotification__c
            WHERE  Message__c   IN :msgIds
            AND    Recipient__c  = :currentUserId
            AND    IsRead__c     = false
        ];

        if (unread.isEmpty()) return;

        DateTime now = System.now();
        for (CommunicatorNotification__c n : unread) {
            n.IsRead__c = true;
            n.ReadAt__c = now;
        }
        update unread;
    }

    // ─────────────────────────────────────────
    // Queries
    // ─────────────────────────────────────────

    /**
     * @description Returns total unread notification count for the current user
     *              in a specific thread.
     */
    public static Integer getUnreadCount(Id threadId) {
        return [
            SELECT COUNT()
            FROM   CommunicatorNotification__c
            WHERE  Thread__c    = :threadId
            AND    Recipient__c = :UserInfo.getUserId()
            AND    IsRead__c    = false
        ];
    }

    public static Integer getBroadcastUnreadCount(Id threadId) {
        return [
            SELECT COUNT()
            FROM CommunicatorNotification__c
            WHERE Thread__c = :threadId
            AND Recipient__c = :UserInfo.getUserId()
            AND Type__c = :BROADCAST_NOTIFICATION_TYPE
            AND IsRead__c = false
            AND Message__r.Status__c = 'Sent'
        ];
    }

    private static List<CommunicatorNotification__c> buildBroadcastNotifications(
        Id messageId,
        Id threadId,
        Set<Id> recipientIds,
        Boolean includeIdempotencyKey
    ) {
        List<CommunicatorNotification__c> notifications = new List<CommunicatorNotification__c>();
        for (Id recipientId : recipientIds) {
            if (recipientId == null || recipientId == UserInfo.getUserId()) continue;
            CommunicatorNotification__c notification = new CommunicatorNotification__c(
                Thread__c = threadId,
                Message__c = messageId,
                Recipient__c = recipientId,
                Type__c = BROADCAST_NOTIFICATION_TYPE,
                IsRead__c = false,
                IsMention__c = false
            );
            if (includeIdempotencyKey == true) {
                notification.BroadcastNotificationKey__c =
                    buildBroadcastNotificationKey(messageId, recipientId);
            }
            notifications.add(notification);
        }
        return notifications;
    }

    private static void insertBroadcastNotificationsAllowingDuplicateKeys(
        List<CommunicatorNotification__c> notifications
    ) {
        Savepoint savepoint = Database.setSavepoint();
        CommunicatorBroadcastDmlGuardHandler.authorizeNotificationDml('INSERT', notifications);
        try {
            List<Database.SaveResult> saveResults = Database.insert(notifications, false);
            Map<Integer, String> duplicateKeysNeedingLookup = new Map<Integer, String>();
            List<CommunicatorNotification__c> fatalNotifications = new List<CommunicatorNotification__c>();
            for (Integer index = 0; index < saveResults.size(); index++) {
                Database.SaveResult saveResult = saveResults[index];
                if (saveResult.isSuccess()) continue;
                if (isBroadcastNotificationKeyDuplicateByField(saveResult.getErrors())) continue;
                if (isBroadcastNotificationKeyDuplicateRequiringLookup(saveResult.getErrors())) {
                    String expectedKey = notifications[index].BroadcastNotificationKey__c;
                    if (String.isBlank(expectedKey)) {
                        fatalNotifications.add(notifications[index]);
                    } else {
                        duplicateKeysNeedingLookup.put(index, expectedKey);
                    }
                    continue;
                }
                fatalNotifications.add(notifications[index]);
            }

            if (!duplicateKeysNeedingLookup.isEmpty()) {
                Set<String> existingKeys = loadExistingBroadcastNotificationKeys(
                    new Set<String>(duplicateKeysNeedingLookup.values())
                );
                for (Integer index : duplicateKeysNeedingLookup.keySet()) {
                    if (!existingKeys.contains(duplicateKeysNeedingLookup.get(index))) {
                        fatalNotifications.add(notifications[index]);
                    }
                }
            }

            if (!fatalNotifications.isEmpty()) {
                CommunicatorBroadcastDmlGuardHandler.clearOfficialAuthorization();
                Database.rollback(savepoint);
                rethrowBroadcastInsertFailure(fatalNotifications);
            }
        } finally {
            CommunicatorBroadcastDmlGuardHandler.clearOfficialAuthorization();
        }
    }

    private static Boolean isBroadcastNotificationKeyDuplicateByField(List<Database.Error> errors) {
        if (errors == null || errors.isEmpty()) return false;
        for (Database.Error err : errors) {
            if (err == null || err.getStatusCode() != StatusCode.DUPLICATE_VALUE) return false;
            if (!isBroadcastNotificationKeyField(getDuplicateErrorFields(err))) {
                return false;
            }
        }
        return true;
    }

    private static Boolean isBroadcastNotificationKeyDuplicateRequiringLookup(List<Database.Error> errors) {
        if (errors == null || errors.isEmpty()) return false;
        for (Database.Error err : errors) {
            if (err == null || err.getStatusCode() != StatusCode.DUPLICATE_VALUE) {
                return false;
            }
            List<String> fieldNames = getDuplicateErrorFields(err);
            if (fieldNames != null && !fieldNames.isEmpty()) {
                return false;
            }
        }
        return true;
    }

    private static List<String> getDuplicateErrorFields(Database.Error err) {
        if (err == null) return null;
        if (Test.isRunningTest() && forceDuplicateKeyLookupFallbackForTest) {
            return new List<String>();
        }
        return err.getFields();
    }

    private static Set<String> loadExistingBroadcastNotificationKeys(Set<String> notificationKeys) {
        Set<String> existingKeys = new Set<String>();
        if (notificationKeys == null || notificationKeys.isEmpty()) return existingKeys;
        for (CommunicatorNotification__c notification : [
            SELECT BroadcastNotificationKey__c
            FROM CommunicatorNotification__c
            WHERE BroadcastNotificationKey__c IN :notificationKeys
        ]) {
            if (!String.isBlank(notification.BroadcastNotificationKey__c)) {
                existingKeys.add(notification.BroadcastNotificationKey__c);
            }
        }
        return existingKeys;
    }

    private static void rethrowBroadcastInsertFailure(
        List<CommunicatorNotification__c> fatalNotifications
    ) {
        List<CommunicatorNotification__c> recordsToInsert = new List<CommunicatorNotification__c>();
        for (CommunicatorNotification__c notification : fatalNotifications) {
            recordsToInsert.add(cloneBroadcastNotificationForInsert(notification));
        }
        CommunicatorBroadcastDmlGuardHandler.authorizeNotificationDml('INSERT', recordsToInsert);
        insert recordsToInsert;
    }

    private static CommunicatorNotification__c cloneBroadcastNotificationForInsert(
        CommunicatorNotification__c notification
    ) {
        return new CommunicatorNotification__c(
            Thread__c = notification.Thread__c,
            Message__c = notification.Message__c,
            Recipient__c = notification.Recipient__c,
            Type__c = notification.Type__c,
            BroadcastNotificationKey__c = notification.BroadcastNotificationKey__c,
            IsRead__c = notification.IsRead__c,
            IsMention__c = notification.IsMention__c
        );
    }

    private static Boolean isBroadcastNotificationKeyField(List<String> fieldNames) {
        if (fieldNames == null || fieldNames.isEmpty()) return false;
        for (String fieldName : fieldNames) {
            if (fieldName == BROADCAST_NOTIFICATION_KEY_FIELD) {
                return true;
            }
        }
        return false;
    }

    private static String buildBroadcastNotificationKey(Id messageId, Id recipientId) {
        return String.valueOf(messageId) + ':' + String.valueOf(recipientId) + ':' + BROADCAST_NOTIFICATION_TYPE;
    }

    /**
     * @description Returns unread total aligned with the compact unread tab list
     *              (sum of unreadCount from visible unread chat cards query source).
     */
    public static Integer getOpportunityUnreadMessageTotal(
        Integer pageSize,
        Integer offsetVal,
        String keyword
    ) {
        Integer total = 0;
        List<CommunicatorDTOs.ThreadListItemDTO> unreadCards =
            CommunicatorThreadService.getOpportunityChatList(pageSize, offsetVal, 'unread', keyword);
        for (CommunicatorDTOs.ThreadListItemDTO card : unreadCards) {
            total += (card != null && card.unreadCount != null) ? card.unreadCount : 0;
        }
        return total;
    }

    /**
     * @description Returns total unread notification count for the current user
     *              restricted to threads where they are an active participant.
     *              Lightweight alternative to getOpportunityUnreadMessageTotal
     *              for the global FAB badge — keeps badge in sync with the list.
     */
    public static Integer getGlobalUnreadNotificationCount() {
        Id userId = UserInfo.getUserId();
        Set<Id> participantThreadIds = new Set<Id>();
        for (CommunicatorParticipant__c p : [
            SELECT Thread__c FROM CommunicatorParticipant__c
            WHERE User__c = :userId AND IsActive__c = true
        ]) {
            participantThreadIds.add(p.Thread__c);
        }
        if (participantThreadIds.isEmpty()) return 0;

        // Apply the same access filter that getThreadList/getThreadCount use for
        // Salesforce Platform (assessoria) users — keeps badge in sync with visible cards.
        // Without this filter, assessoria users with a notification on a thread they cannot
        // see (e.g. individual mention on an Opportunity outside their AR queue) would see
        // the bell badge but no corresponding card.
        participantThreadIds = CommunicatorThreadService.filterVisibleThreadIdsForCurrentUser(participantThreadIds);
        if (participantThreadIds.isEmpty()) return 0;

        return [
            SELECT COUNT()
            FROM CommunicatorNotification__c
            WHERE Recipient__c = :userId
            AND   IsRead__c    = false
            AND   Thread__c    IN :participantThreadIds
            AND   Thread__r.Status__c     != 'Archived'
            AND   Thread__r.RecordType__c != 'CommunicatorGroup__c'
        ];
    }

    /**
     * @description Returns unread mention count specifically for the current user
     *              in a thread (for highlight badge).
     */
    public static Integer getUnreadMentionCount(Id threadId) {
        return [
            SELECT COUNT()
            FROM   CommunicatorNotification__c
            WHERE  Thread__c    = :threadId
            AND    Recipient__c = :UserInfo.getUserId()
            AND    IsRead__c    = false
            AND    IsMention__c = true
        ];
    }
}