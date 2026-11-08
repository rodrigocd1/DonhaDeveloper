/**
 * @description Service responsible for CommunicatorMessage__c business logic.
 */
public without sharing class CommunicatorMessageService {

    private static final Integer DEFAULT_PAGE_SIZE = 20;
    private static final String OPP_CLOSED_STAGE   = 'Contrato Assinado - Oppty Ganha';
    private static final String OPP_LOST_STAGE     = 'Fechado e perdido';
    private static final Set<String> REPASSE_MACRO_PHASES = new Set<String>{
        'Aguardando início',
        'Formulário',
        'Conferência de dossiê',
        'Pendências',
        'Assinatura do repasse',
        'Retenção',
        'Triagem',
        'Outros'
    };

    // ─────────────────────────────────────────
    // Queries
    // ─────────────────────────────────────────

    /**
     * @description Returns a paginated list of messages for a thread, ordered oldest-first.
     */
    public static List<CommunicatorMessage__c> getMessages(Id threadId, Integer pageSize, Integer offsetVal) {
        Integer size   = (pageSize  != null && pageSize  > 0) ? pageSize  : DEFAULT_PAGE_SIZE;
        Integer offset = (offsetVal != null && offsetVal > 0) ? offsetVal : 0;
        Integer window = offset + size;

        List<CommunicatorMessage__c> msgs = [
            SELECT Id, Name, Body__c, Status__c, HasAttachment__c, ContentDocumentId__c,
                   SentAt__c, ExternalId__c, RecordStatus__c, IsSystemMessage__c, HasMention__c,
                   MentionedUserIds__c, SourceThreadId__c, ParentMessage__c,
                   Sender__c, Sender__r.Name, Sender__r.SmallPhotoUrl,
                   CreatedById, CreatedBy.Name, CreatedBy.SmallPhotoUrl,
                   Thread__c
            FROM CommunicatorMessage__c
            WHERE Thread__c = :threadId
            ORDER BY SentAt__c ASC, Id ASC
            LIMIT :window
        ];
        return sliceMessages(
            mergeWithSystemEvents(msgs, new Set<Id>{ threadId }, null, window), offset, size
        );
    }

    /**
     * @description Returns a paginated list of messages across multiple threads, ordered oldest-first.
     */
    public static List<CommunicatorMessage__c> getMessagesAcrossThreads(
        List<Id> threadIds,
        Integer pageSize,
        Integer offsetVal
    ) {
        Set<Id> ids = sanitizeThreadIds(threadIds);
        if (ids.isEmpty()) return new List<CommunicatorMessage__c>();

        Integer size   = (pageSize  != null && pageSize  > 0) ? pageSize  : DEFAULT_PAGE_SIZE;
        Integer offset = (offsetVal != null && offsetVal > 0) ? offsetVal : 0;
        Integer window = offset + size;

        List<CommunicatorMessage__c> msgs = [
            SELECT Id, Name, Body__c, Status__c, HasAttachment__c, ContentDocumentId__c,
                   SentAt__c, ExternalId__c, RecordStatus__c, IsSystemMessage__c, HasMention__c,
                   MentionedUserIds__c, SourceThreadId__c, ParentMessage__c,
                   Sender__c, Sender__r.Name, Sender__r.SmallPhotoUrl,
                   CreatedById, CreatedBy.Name, CreatedBy.SmallPhotoUrl,
                   Thread__c
            FROM CommunicatorMessage__c
            WHERE Thread__c IN :ids
            ORDER BY SentAt__c ASC, Id ASC
            LIMIT :window
        ];
        return sliceMessages(mergeWithSystemEvents(msgs, ids, null, window), offset, size);
    }

    /**
     * @description Returns messages created after a specific timestamp (for polling).
     */
    public static List<CommunicatorMessage__c> getMessagesSince(Id threadId, DateTime sinceDateTime) {
        List<CommunicatorMessage__c> msgs = [
            SELECT Id, Name, Body__c, Status__c, HasAttachment__c, ContentDocumentId__c,
                   SentAt__c, ExternalId__c, RecordStatus__c, IsSystemMessage__c, HasMention__c,
                   MentionedUserIds__c, SourceThreadId__c, ParentMessage__c,
                   Sender__c, Sender__r.Name, Sender__r.SmallPhotoUrl,
                   CreatedById, CreatedBy.Name, CreatedBy.SmallPhotoUrl,
                   Thread__c
            FROM CommunicatorMessage__c
            WHERE Thread__c = :threadId
            AND SentAt__c > :sinceDateTime
            ORDER BY SentAt__c ASC, Id ASC
            LIMIT 50
        ];
        return sliceMessages(
            mergeWithSystemEvents(msgs, new Set<Id>{ threadId }, sinceDateTime, 50), 0, 50
        );
    }

    /**
     * @description Returns messages created after a specific timestamp across multiple threads.
     */
    public static List<CommunicatorMessage__c> getMessagesSinceAcrossThreads(
        List<Id> threadIds,
        DateTime sinceDateTime
    ) {
        Set<Id> ids = sanitizeThreadIds(threadIds);
        if (ids.isEmpty()) return new List<CommunicatorMessage__c>();

        List<CommunicatorMessage__c> msgs = [
            SELECT Id, Name, Body__c, Status__c, HasAttachment__c, ContentDocumentId__c,
                   SentAt__c, ExternalId__c, RecordStatus__c, IsSystemMessage__c, HasMention__c,
                   MentionedUserIds__c, SourceThreadId__c, ParentMessage__c,
                   Sender__c, Sender__r.Name, Sender__r.SmallPhotoUrl,
                   CreatedById, CreatedBy.Name, CreatedBy.SmallPhotoUrl,
                   Thread__c
            FROM CommunicatorMessage__c
            WHERE Thread__c IN :ids
            AND SentAt__c > :sinceDateTime
            ORDER BY SentAt__c ASC, Id ASC
            LIMIT 50
        ];
        return sliceMessages(mergeWithSystemEvents(msgs, ids, sinceDateTime, 50), 0, 50);
    }

    /** Paged internal polling across stored messages and Chatter system events. */
    public static CommunicatorDTOs.MessagePollPageDTO pollTimeline(
        Id threadId,
        List<Id> threadIds,
        String cursorValue,
        Integer pageSize
    ) {
        CommunicatorDTOs.MessagePollPageDTO page = new CommunicatorDTOs.MessagePollPageDTO();
        page.messages = new List<CommunicatorMessage__c>();
        page.hasMore = false;

        Set<Id> ids = threadId == null ? sanitizeThreadIds(threadIds) : new Set<Id>{ threadId };
        if (ids.isEmpty()) return page;

        Integer requestedSize = pageSize == null || pageSize <= 0 ? 50 : Math.min(pageSize, 100);
        Integer scanLimit = requestedSize + 1;
        CommunicatorDTOs.MessagePollCursorDTO cursor = parsePollCursor(cursorValue);
        if (!String.isBlank(cursorValue) && cursor == null) return page;

        List<CommunicatorMessage__c> storedMessages = queryPollMessages(ids, cursor, scanLimit);
        List<FeedItem> feedItems = queryPollFeedItems(ids, cursor, scanLimit);
        List<CommunicatorMessage__c> validItems = new List<CommunicatorMessage__c>();

        Integer messageIndex = 0;
        Integer feedIndex = 0;
        while (messageIndex < storedMessages.size() || feedIndex < feedItems.size()) {
            Boolean takeMessage = feedIndex >= feedItems.size()
                || (messageIndex < storedMessages.size()
                    && isMessageBeforeFeedItem(storedMessages[messageIndex], feedItems[feedIndex]));
            if (takeMessage) {
                validItems.add(storedMessages[messageIndex]);
                messageIndex++;
            } else {
                FeedItem item = feedItems[feedIndex++];
                if (CommunicatorSystemEventService.isSystemEventPost(item.Body)) {
                    validItems.add(toPollMessage(item));
                }
            }
            if (validItems.size() > requestedSize) break;
        }

        if (validItems.size() > requestedSize) {
            page.hasMore = true;
            for (Integer index = 0; index < requestedSize; index++) page.messages.add(validItems[index]);
            page.nextCursor = serializePollCursor(cursorForTimelineMessage(page.messages[page.messages.size() - 1]));
            return page;
        }

        page.messages.addAll(validItems);
        Boolean messagesTruncated = storedMessages.size() == scanLimit;
        Boolean feedItemsTruncated = feedItems.size() == scanLimit;
        if (messagesTruncated || feedItemsTruncated) {
            page.hasMore = true;
            CommunicatorDTOs.MessagePollCursorDTO messageBoundary = messagesTruncated
                ? cursorForStoredMessage(storedMessages[storedMessages.size() - 1])
                : null;
            CommunicatorDTOs.MessagePollCursorDTO feedBoundary = feedItemsTruncated
                ? cursorForFeedItem(feedItems[feedItems.size() - 1])
                : null;
            page.nextCursor = serializePollCursor(earlierPollCursor(messageBoundary, feedBoundary));
        } else if (!page.messages.isEmpty()) {
            page.nextCursor = serializePollCursor(cursorForTimelineMessage(page.messages[page.messages.size() - 1]));
        }
        return page;
    }

    private static List<CommunicatorMessage__c> queryPollMessages(
        Set<Id> threadIds,
        CommunicatorDTOs.MessagePollCursorDTO cursor,
        Integer scanLimit
    ) {
        if (cursor == null) {
            return [
                SELECT Id, Name, Body__c, Status__c, HasAttachment__c, ContentDocumentId__c,
                       SentAt__c, ExternalId__c, RecordStatus__c, IsSystemMessage__c, HasMention__c,
                       MentionedUserIds__c, SourceThreadId__c, ParentMessage__c,
                       Sender__c, Sender__r.Name, Sender__r.SmallPhotoUrl,
                       CreatedById, CreatedBy.Name, CreatedBy.SmallPhotoUrl, Thread__c
                FROM CommunicatorMessage__c
                WHERE Thread__c IN :threadIds AND SentAt__c != null
                ORDER BY SentAt__c ASC, Id ASC
                LIMIT :scanLimit
            ];
        }
        Datetime cursorAt = cursor.timestamp;
        Id cursorId = (Id) cursor.itemId;
        if (cursor.source == 'Message') {
            return [
                SELECT Id, Name, Body__c, Status__c, HasAttachment__c, ContentDocumentId__c,
                       SentAt__c, ExternalId__c, RecordStatus__c, IsSystemMessage__c, HasMention__c,
                       MentionedUserIds__c, SourceThreadId__c, ParentMessage__c,
                       Sender__c, Sender__r.Name, Sender__r.SmallPhotoUrl,
                       CreatedById, CreatedBy.Name, CreatedBy.SmallPhotoUrl, Thread__c
                FROM CommunicatorMessage__c
                WHERE Thread__c IN :threadIds
                    AND (SentAt__c > :cursorAt OR (SentAt__c = :cursorAt AND Id > :cursorId))
                ORDER BY SentAt__c ASC, Id ASC
                LIMIT :scanLimit
            ];
        }
        return [
            SELECT Id, Name, Body__c, Status__c, HasAttachment__c, ContentDocumentId__c,
                   SentAt__c, ExternalId__c, RecordStatus__c, IsSystemMessage__c, HasMention__c,
                   MentionedUserIds__c, SourceThreadId__c, ParentMessage__c,
                   Sender__c, Sender__r.Name, Sender__r.SmallPhotoUrl,
                   CreatedById, CreatedBy.Name, CreatedBy.SmallPhotoUrl, Thread__c
            FROM CommunicatorMessage__c
            WHERE Thread__c IN :threadIds AND SentAt__c > :cursorAt
            ORDER BY SentAt__c ASC, Id ASC
            LIMIT :scanLimit
        ];
    }

    private static List<FeedItem> queryPollFeedItems(
        Set<Id> threadIds,
        CommunicatorDTOs.MessagePollCursorDTO cursor,
        Integer scanLimit
    ) {
        if (cursor == null) {
            return [
                SELECT Id, ParentId, Body, CreatedDate
                FROM FeedItem
                WHERE ParentId IN :threadIds AND Type = 'TextPost'
                ORDER BY CreatedDate ASC, Id ASC
                LIMIT :scanLimit
            ];
        }
        Datetime cursorAt = cursor.timestamp;
        Id cursorId = (Id) cursor.itemId;
        if (cursor.source == 'Message') {
            return [
                SELECT Id, ParentId, Body, CreatedDate
                FROM FeedItem
                WHERE ParentId IN :threadIds AND Type = 'TextPost'
                    AND CreatedDate >= :cursorAt
                ORDER BY CreatedDate ASC, Id ASC
                LIMIT :scanLimit
            ];
        }
        return [
            SELECT Id, ParentId, Body, CreatedDate
            FROM FeedItem
            WHERE ParentId IN :threadIds AND Type = 'TextPost'
                AND (CreatedDate > :cursorAt OR (CreatedDate = :cursorAt AND Id > :cursorId))
            ORDER BY CreatedDate ASC, Id ASC
            LIMIT :scanLimit
        ];
    }

    private static Boolean isMessageBeforeFeedItem(CommunicatorMessage__c message, FeedItem item) {
        Datetime messageAt = message.SentAt__c == null ? Datetime.newInstance(0) : message.SentAt__c;
        if (messageAt != item.CreatedDate) return messageAt < item.CreatedDate;
        return true;
    }

    private static CommunicatorMessage__c toPollMessage(FeedItem item) {
        return new CommunicatorMessage__c(
            Thread__c = item.ParentId,
            Body__c = CommunicatorSystemEventService.extractDisplayBody(item.Body),
            SentAt__c = item.CreatedDate,
            Status__c = 'Sent',
            IsSystemMessage__c = true,
            RecordStatus__c = CommunicatorSystemEventService.extractStatus(item.Body),
            ExternalId__c = item.Id
        );
    }

    private static CommunicatorDTOs.MessagePollCursorDTO parsePollCursor(String cursorValue) {
        if (String.isBlank(cursorValue)) return null;
        try {
            CommunicatorDTOs.MessagePollCursorDTO cursor = (CommunicatorDTOs.MessagePollCursorDTO)
                JSON.deserialize(cursorValue, CommunicatorDTOs.MessagePollCursorDTO.class);
            if (cursor.timestamp == null || String.isBlank(cursor.itemId)) return null;
            Id cursorId = (Id) cursor.itemId;
            if (cursor.source == 'Message' && cursorId.getSObjectType() == CommunicatorMessage__c.SObjectType) return cursor;
            if (cursor.source == 'FeedItem' && cursorId.getSObjectType() == FeedItem.SObjectType) return cursor;
        } catch (Exception ex) {
            return null;
        }
        return null;
    }

    private static String serializePollCursor(CommunicatorDTOs.MessagePollCursorDTO cursor) {
        return cursor == null ? null : JSON.serialize(cursor);
    }

    private static CommunicatorDTOs.MessagePollCursorDTO cursorForStoredMessage(CommunicatorMessage__c message) {
        CommunicatorDTOs.MessagePollCursorDTO cursor = new CommunicatorDTOs.MessagePollCursorDTO();
        cursor.timestamp = message.SentAt__c;
        cursor.source = 'Message';
        cursor.itemId = String.valueOf(message.Id);
        return cursor;
    }

    private static CommunicatorDTOs.MessagePollCursorDTO cursorForFeedItem(FeedItem item) {
        CommunicatorDTOs.MessagePollCursorDTO cursor = new CommunicatorDTOs.MessagePollCursorDTO();
        cursor.timestamp = item.CreatedDate;
        cursor.source = 'FeedItem';
        cursor.itemId = String.valueOf(item.Id);
        return cursor;
    }

    private static CommunicatorDTOs.MessagePollCursorDTO cursorForTimelineMessage(CommunicatorMessage__c messageOrEvent) {
        if (messageOrEvent.Id != null) return cursorForStoredMessage(messageOrEvent);
        CommunicatorDTOs.MessagePollCursorDTO cursor = new CommunicatorDTOs.MessagePollCursorDTO();
        cursor.timestamp = messageOrEvent.SentAt__c;
        cursor.source = 'FeedItem';
        cursor.itemId = messageOrEvent.ExternalId__c;
        return cursor;
    }

    private static CommunicatorDTOs.MessagePollCursorDTO earlierPollCursor(
        CommunicatorDTOs.MessagePollCursorDTO left,
        CommunicatorDTOs.MessagePollCursorDTO right
    ) {
        if (left == null) return right;
        if (right == null) return left;
        if (left.timestamp != right.timestamp) return left.timestamp < right.timestamp ? left : right;
        if (left.source != right.source) return left.source == 'Message' ? left : right;
        return left.itemId.compareTo(right.itemId) <= 0 ? left : right;
    }

    /**
     * @description Returns the total count of messages in a thread.
     */
    public static Integer getMessageCount(Id threadId) {
        Integer messageCount = [
            SELECT COUNT()
            FROM CommunicatorMessage__c
            WHERE Thread__c = :threadId
        ];
        return messageCount + CommunicatorSystemEventService.countEvents(new Set<Id>{ threadId }, null);
    }

    /**
     * @description Returns the total count of messages across multiple threads.
     */
    public static Integer getMessageCountAcrossThreads(List<Id> threadIds) {
        Set<Id> ids = sanitizeThreadIds(threadIds);
        if (ids.isEmpty()) return 0;

        Integer messageCount = [
            SELECT COUNT()
            FROM CommunicatorMessage__c
            WHERE Thread__c IN :ids
        ];
        return messageCount + CommunicatorSystemEventService.countEvents(ids, null);
    }

    /**
     * @description Returns unique participant user Ids for a thread.
     *              Uses message history and active thread memberships.
     */
    public static List<Id> getThreadHistoryParticipantIds(Id threadId) {
        if (threadId == null) return new List<Id>();
        Set<Id> threadIds = new Set<Id>{ threadId };
        Set<Id> participantIds = getMessageHistoryParticipantIdsByThreadIds(threadIds);
        addActiveThreadParticipantIds(participantIds, threadIds);
        return new List<Id>(participantIds);
    }

    /**
     * @description Returns unique participant user Ids across threads.
     *              Uses message history and active thread memberships.
     */
    public static List<Id> getThreadHistoryParticipantIdsAcrossThreads(List<Id> threadIds) {
        Set<Id> ids = sanitizeThreadIds(threadIds);
        if (ids.isEmpty()) return new List<Id>();

        Set<Id> participantIds = getMessageHistoryParticipantIdsByThreadIds(ids);
        addActiveThreadParticipantIds(participantIds, ids);
        return new List<Id>(participantIds);
    }

    /**
     * @description Returns the zero-based index of a message within its thread (ordered by SentAt__c ASC).
     *              Used by the timeline to jump directly to the page containing the target message.
     * @return Index >= 0, or -1 if the message is not found in the thread.
     */
    public static Integer getMessageOffset(Id threadId, Id messageId) {
        List<CommunicatorMessage__c> targetMessages = [
            SELECT Id, SentAt__c FROM CommunicatorMessage__c
            WHERE Id = :messageId AND Thread__c = :threadId
            LIMIT 1
        ];
        Set<Id> threadIds = new Set<Id>{ threadId };
        if (!targetMessages.isEmpty()) {
            return getMessageTargetOffset(threadIds, targetMessages[0]);
        }
        List<FeedItem> targetPosts = [
            SELECT Id, ParentId, CreatedDate, Body
            FROM FeedItem
            WHERE Id = :messageId AND ParentId = :threadId AND Type = 'TextPost'
            LIMIT 1
        ];
        if (targetPosts.isEmpty() || !CommunicatorSystemEventService.isSystemEventPost(targetPosts[0].Body)) {
            return -1;
        }
        return getFeedItemTargetOffset(threadIds, targetPosts[0]);
    }

    /**
     * @description Returns the zero-based index of a message across multiple threads (ordered by SentAt__c ASC).
     * @return Index >= 0, or -1 if the message is not found in the informed threads.
     */
    public static Integer getMessageOffsetAcrossThreads(List<Id> threadIds, Id messageId) {
        Set<Id> ids = sanitizeThreadIds(threadIds);
        if (ids.isEmpty()) return -1;

        List<CommunicatorMessage__c> targetMessages = [
            SELECT Id, SentAt__c
            FROM CommunicatorMessage__c
            WHERE Id = :messageId
            AND Thread__c IN :ids
            LIMIT 1
        ];
        if (!targetMessages.isEmpty()) {
            return getMessageTargetOffset(ids, targetMessages[0]);
        }
        List<FeedItem> targetPosts = [
            SELECT Id, ParentId, CreatedDate, Body
            FROM FeedItem
            WHERE Id = :messageId AND ParentId IN :ids AND Type = 'TextPost'
            LIMIT 1
        ];
        if (targetPosts.isEmpty() || !CommunicatorSystemEventService.isSystemEventPost(targetPosts[0].Body)) {
            return -1;
        }
        return getFeedItemTargetOffset(ids, targetPosts[0]);
    }

    private static Integer getMessageTargetOffset(Set<Id> threadIds, CommunicatorMessage__c target) {
        Integer messageOffset;
        if (target.SentAt__c == null) {
            messageOffset = [
                SELECT COUNT()
                FROM CommunicatorMessage__c
                WHERE Thread__c IN :threadIds AND SentAt__c = null AND Id < :target.Id
            ];
        } else {
            messageOffset = [
                SELECT COUNT()
                FROM CommunicatorMessage__c
                WHERE Thread__c IN :threadIds
                    AND (SentAt__c = null OR SentAt__c < :target.SentAt__c
                        OR (SentAt__c = :target.SentAt__c AND Id < :target.Id))
            ];
        }
        if (target.SentAt__c != null) {
            messageOffset += CommunicatorSystemEventService.countEvents(threadIds, target.SentAt__c);
        }
        return messageOffset;
    }

    private static Integer getFeedItemTargetOffset(Set<Id> threadIds, FeedItem target) {
        Integer messageOffset = target.CreatedDate == null
            ? [SELECT COUNT() FROM CommunicatorMessage__c WHERE Thread__c IN :threadIds AND SentAt__c = null]
            : [
                SELECT COUNT()
                FROM CommunicatorMessage__c
                WHERE Thread__c IN :threadIds
                    AND (SentAt__c = null OR SentAt__c <= :target.CreatedDate)
            ];
        Integer eventOffset = CommunicatorSystemEventService.countEvents(threadIds, target.CreatedDate);
        eventOffset += [
            SELECT COUNT()
            FROM FeedItem
            WHERE ParentId IN :threadIds
                AND Type = 'TextPost'
                AND CreatedDate = :target.CreatedDate
                AND Id < :target.Id
        ];
        return messageOffset + eventOffset;
    }

    private static List<CommunicatorMessage__c> mergeWithSystemEvents(
        List<CommunicatorMessage__c> messages,
        Set<Id> threadIds,
        Datetime sinceDateTime,
        Integer maxRows
    ) {
        List<CommunicatorMessage__c> events =
            CommunicatorSystemEventService.getEventsAsMessages(threadIds, sinceDateTime, maxRows);
        if (events.isEmpty()) return messages;
        List<CommunicatorMessage__c> merged = new List<CommunicatorMessage__c>();
        Integer i = 0;
        Integer j = 0;
        while (i < messages.size() || j < events.size()) {
            Boolean takeMessage = j >= events.size()
                || (i < messages.size() && sentAtOf(messages[i]) <= sentAtOf(events[j]));
            if (takeMessage) {
                merged.add(messages[i]);
                i++;
            } else {
                merged.add(events[j]);
                j++;
            }
        }
        return merged;
    }

    private static Datetime sentAtOf(CommunicatorMessage__c message) {
        return message.SentAt__c != null ? message.SentAt__c : Datetime.newInstance(0);
    }

    private static List<CommunicatorMessage__c> sliceMessages(
        List<CommunicatorMessage__c> source,
        Integer offset,
        Integer size
    ) {
        List<CommunicatorMessage__c> page = new List<CommunicatorMessage__c>();
        for (Integer index = offset; index < source.size() && page.size() < size; index++) {
            page.add(source[index]);
        }
        return page;
    }

    // ─────────────────────────────────────────
    // Write operations
    // ─────────────────────────────────────────

    /**
     * @description Creates and persists a new text message.
     */
    public static CommunicatorMessage__c sendMessage(Id threadId, String messageBody) {
        return sendMessage(threadId, messageBody, null);
    }

    /**
     * @description Creates and persists a new text message, optionally resolving mentions.
     */
    public static CommunicatorMessage__c sendMessage(Id threadId, String messageBody, String mentionIds) {
        validateThreadAccess(threadId);
        validateOpportunityMessagingIsOpen(threadId);

        if (String.isBlank(messageBody)) {
            throw new CommunicatorException('Message body cannot be empty.');
        }

        MentionResolution resolution = resolveMentionsWithGroups(mentionIds);
        String  recordStatus    = resolveRecordStatus(threadId);
        Boolean hasMention = !resolution.userIds.isEmpty() || !resolution.groupIds.isEmpty();

        CommunicatorParticipantService.ensureParticipants(threadId, resolution.userIds, 'Member');

        CommunicatorMessage__c msg = buildMessage(
            threadId, messageBody, false, null, recordStatus,
            resolution.userIds, hasMention, resolution.groupIds
        );
        insert msg;

        updateThreadLastMessage(threadId);

        if (!resolution.groupIds.isEmpty()) {
            mirrorMessageToGroupThreads(msg, resolution.groupIds);
        }

        CommunicatorNotificationService.notifyParticipants(threadId, msg.Id, resolution.userIds);
        publishExternalNewMessageEvent(msg, resolution.userIds);

        return queryById(msg.Id);
    }

    /**
     * @description Creates attachment from base64 and links it for communicator access.
     */
    public static Id uploadAttachmentFromBase64(Id threadId, String fileName, String base64Data) {
        validateThreadAccess(threadId);
        validateOpportunityMessagingIsOpen(threadId);
        if (String.isBlank(fileName) || String.isBlank(base64Data)) {
            throw new CommunicatorException('File name and file body are required.');
        }

        Id opportunityId = resolveThreadOpportunityId(threadId);
        if (opportunityId == null) {
            throw new CommunicatorException('Opportunity context is required for file upload.');
        }

        ContentVersion version = buildUploadContentVersion(fileName, base64Data, opportunityId);
        insert version;

        Id contentDocumentId = resolveInsertedContentDocumentId(version.Id);
        CommunicatorFileShareService.ensureAccessForAttachment(contentDocumentId, threadId, opportunityId);
        return contentDocumentId;
    }

    /**
     * @description Creates and persists a message with one or more file attachments.
     * @param mentionIds Optional semicolon-separated mention IDs.
     */
    public static CommunicatorMessage__c sendMessageWithAttachments(
        Id threadId,
        String messageBody,
        List<Id> contentDocumentIds,
        String mentionIds
    ) {
        validateThreadAccess(threadId);
        validateOpportunityMessagingIsOpen(threadId);

        List<Id> attachmentIds = sanitizeAttachmentDocumentIds(contentDocumentIds);
        if (attachmentIds.isEmpty()) {
            throw new CommunicatorException('At least one ContentDocument Id is required for attachment messages.');
        }

        Id opportunityId = resolveThreadOpportunityId(threadId);
        MentionResolution resolution = resolveMentionsWithGroups(mentionIds);
        String recordStatus = resolveRecordStatus(threadId);
        Boolean hasMention = !resolution.userIds.isEmpty() || !resolution.groupIds.isEmpty();

        CommunicatorParticipantService.ensureParticipants(threadId, resolution.userIds, 'Member');

        CommunicatorMessage__c msg = buildMessage(
            threadId,
            messageBody,
            true,
            String.valueOf(attachmentIds[0]),
            recordStatus,
            resolution.userIds,
            hasMention,
            resolution.groupIds
        );
        insert msg;

        ensureAttachmentAccessAndMessageLinks(msg.Id, threadId, opportunityId, attachmentIds);
        updateThreadLastMessage(threadId);

        if (!resolution.groupIds.isEmpty()) {
            mirrorMessageToGroupThreads(msg, resolution.groupIds);
        }

        CommunicatorNotificationService.notifyParticipants(threadId, msg.Id, resolution.userIds);
        publishExternalNewMessageEvent(msg, resolution.userIds);

        return queryById(msg.Id);
    }

    /**
     * @description Creates and persists a message with a file attachment.
     * @param mentionIds Optional semicolon-separated mention IDs.
     */
    public static CommunicatorMessage__c sendMessageWithAttachment(
        Id threadId, String messageBody, Id contentDocumentId, String mentionIds
    ) {
        return sendMessageWithAttachments(
            threadId,
            messageBody,
            new List<Id>{ contentDocumentId },
            mentionIds
        );
    }

    /**
     * @description Creates and persists a message with a file attachment.
     */
    public static CommunicatorMessage__c sendMessageWithAttachment(
        Id threadId, String messageBody, Id contentDocumentId
    ) {
        return sendMessageWithAttachment(threadId, messageBody, contentDocumentId, null);
    }

    public static CommunicatorDTOs.AttachmentFileDTO getAttachmentFile(
        String contentDocumentId,
        String contentVersionId,
        Id threadId,
        Id messageId,
        Id opportunityId
    ) {
        Id resolvedThreadId = resolveThreadIdForAttachment(threadId, messageId);
        Id resolvedOpportunityId = resolveOpportunityIdForAttachment(opportunityId, resolvedThreadId);
        validateAttachmentContextAccess(resolvedThreadId, resolvedOpportunityId);

        Id resolvedContentDocumentId = resolveContentDocumentForAttachment(contentDocumentId, contentVersionId);
        validateAttachmentContextBinding(
            resolvedContentDocumentId,
            resolvedThreadId,
            messageId,
            resolvedOpportunityId
        );

        ContentVersion version = queryLatestAttachmentVersion(resolvedContentDocumentId);
        return buildAttachmentFileDto(version);
    }

    public static CommunicatorDTOs.AttachmentFileDTO getAttachmentFileForAuthorizedBroadcast(
        String contentDocumentId,
        String contentVersionId,
        Id threadId,
        Id messageId
    ) {
        if (threadId == null || messageId == null) {
            throw new CommunicatorException('Thread e mensagem são obrigatórios para baixar o anexo.');
        }
        List<CommunicatorMessage__c> messages = [
            SELECT Id, Thread__c, ContentDocumentId__c
            FROM CommunicatorMessage__c
            WHERE Id = :messageId
            AND Thread__c = :threadId
            LIMIT 1
        ];
        if (messages.isEmpty()) {
            throw new CommunicatorException('O anexo não pertence à mensagem informada.');
        }

        Id documentId = resolveContentDocumentForAttachment(contentDocumentId, contentVersionId);
        Boolean isLegacyAttachment = messages[0].ContentDocumentId__c == String.valueOf(documentId);
        if (!isLegacyAttachment && !isAttachmentLinkedToEntity(documentId, messageId)) {
            throw new CommunicatorException('O anexo não pertence à mensagem informada.');
        }
        return buildAttachmentFileDto(queryLatestAttachmentVersion(documentId));
    }

    public static void linkAttachmentsForAuthorizedBroadcast(
        Id messageId,
        Id threadId,
        List<Id> contentDocumentIds
    ) {
        List<Id> attachmentIds = sanitizeAttachmentDocumentIds(contentDocumentIds);
        CommunicatorFileShareService.ensureAccessForAttachments(attachmentIds, threadId);
        createMessageAttachmentLinks(messageId, attachmentIds);
        verifyBroadcastAttachmentLinks(messageId, threadId, attachmentIds, Network.getNetworkId());
    }

    public static List<CommunicatorDTOs.MessageAttachmentDTO> getMessageAttachments(List<Id> messageIds) {
        Set<Id> ids = sanitizeMessageIds(messageIds);
        if (ids.isEmpty()) return new List<CommunicatorDTOs.MessageAttachmentDTO>();

        List<CommunicatorMessage__c> messages = [
            SELECT Id, ContentDocumentId__c
            FROM CommunicatorMessage__c
            WHERE Id IN :ids
        ];
        if (messages.isEmpty()) return new List<CommunicatorDTOs.MessageAttachmentDTO>();

        Map<Id, List<Id>> orderedAttachmentIdsByMessage = new Map<Id, List<Id>>();
        Map<Id, Set<Id>> dedupeAttachmentIdsByMessage = new Map<Id, Set<Id>>();
        Set<Id> allDocumentIds = new Set<Id>();

        for (CommunicatorMessage__c message : messages) {
            orderedAttachmentIdsByMessage.put(message.Id, new List<Id>());
            dedupeAttachmentIdsByMessage.put(message.Id, new Set<Id>());
            Id legacyDocumentId = tryParseDocumentId(message.ContentDocumentId__c);
            addAttachmentToMessage(orderedAttachmentIdsByMessage, dedupeAttachmentIdsByMessage, message.Id, legacyDocumentId);
            if (legacyDocumentId != null) allDocumentIds.add(legacyDocumentId);
        }

        for (ContentDocumentLink link : [
            SELECT LinkedEntityId, ContentDocumentId
            FROM ContentDocumentLink
            WHERE LinkedEntityId IN :ids
            AND ContentDocumentId != null
            ORDER BY ContentDocumentId ASC
        ]) {
            Id messageId = link.LinkedEntityId;
            if (!orderedAttachmentIdsByMessage.containsKey(messageId)) continue;
            addAttachmentToMessage(orderedAttachmentIdsByMessage, dedupeAttachmentIdsByMessage, messageId, link.ContentDocumentId);
            allDocumentIds.add(link.ContentDocumentId);
        }

        Map<Id, AttachmentDisplayMetadata> metadataByDocumentId = loadAttachmentDisplayMetadata(allDocumentIds);
        List<CommunicatorDTOs.MessageAttachmentDTO> response = new List<CommunicatorDTOs.MessageAttachmentDTO>();

        for (CommunicatorMessage__c message : messages) {
            List<Id> orderedIds = orderedAttachmentIdsByMessage.get(message.Id);
            if (orderedIds == null || orderedIds.isEmpty()) continue;
            for (Id documentId : orderedIds) {
                CommunicatorDTOs.MessageAttachmentDTO dto = new CommunicatorDTOs.MessageAttachmentDTO();
                dto.messageId = String.valueOf(message.Id);
                dto.contentDocumentId = String.valueOf(documentId);
                AttachmentDisplayMetadata metadata = metadataByDocumentId.get(documentId);
                dto.fileName = metadata != null && String.isNotBlank(metadata.fileName)
                    ? metadata.fileName
                    : 'arquivo';
                dto.fileExtension = metadata != null && String.isNotBlank(metadata.fileExtension)
                    ? metadata.fileExtension
                    : '';
                response.add(dto);
            }
        }

        return response;
    }

    /**
     * @description Reconciles an inbound socket event into the official Communicator flow.
     *              The method is idempotent by messageId (Salesforce Id or ExternalId__c).
     */
    public static CommunicatorDTOs.SocketInboundResultDTO reconcileSocketInboundMessage(
        Id threadId,
        String threadExternalId,
        String messageId,
        String messageBody,
        String userIdsJson,
        String senderExternalId
    ) {
        CommunicatorDTOs.SocketInboundResultDTO result = new CommunicatorDTOs.SocketInboundResultDTO();
        result.success = false;
        result.created = false;
        result.messageId = null;
        result.status = 'ERROR';
        result.errorMessage = null;

        if (String.isBlank(messageId)) {
            result.status = 'MISSING_MESSAGE_ID';
            result.errorMessage = 'messageId is required.';
            return result;
        }

        Set<Id> payloadRecipientIds = parseSocketRecipientUserIds(userIdsJson);
        CommunicatorMessage__c existingMessage = findExistingSocketMessage(messageId);
        if (existingMessage != null && CommunicatorBroadcastService.isBroadcastThread(existingMessage.Thread__c)) {
            result.status = 'BROADCAST_NOT_SUPPORTED';
            result.errorMessage = 'Mensagens de comunicado não são processadas pelo socket convencional.';
            return result;
        }

        if (existingMessage == null) {
            Id resolvedThreadId = resolveSocketThreadId(threadId, threadExternalId);
            if (resolvedThreadId == null) {
                result.status = 'THREAD_NOT_RESOLVED';
                result.errorMessage = 'Thread could not be resolved for inbound socket message.';
                return result;
            }
            if (CommunicatorBroadcastService.isBroadcastThread(resolvedThreadId)) {
                result.status = 'BROADCAST_NOT_SUPPORTED';
                result.errorMessage = 'Mensagens de comunicado não são processadas pelo socket convencional.';
                return result;
            }

            Id senderUserId = resolveSocketSenderId(senderExternalId);
            CommunicatorMessage__c inboundMessage = new CommunicatorMessage__c(
                Thread__c = resolvedThreadId,
                Body__c = String.isBlank(messageBody) ? null : messageBody,
                Sender__c = senderUserId,
                SentAt__c = System.now(),
                Status__c = 'Sent',
                RecordStatus__c = resolveRecordStatus(resolvedThreadId),
                ExternalId__c = messageId
            );

            Database.SaveResult saveResult = Database.insert(inboundMessage, false);
            if (!saveResult.isSuccess()) {
                if (!isDuplicateValueError(saveResult.getErrors())) {
                    result.status = 'DML_ERROR';
                    result.errorMessage = (saveResult.getErrors() != null && !saveResult.getErrors().isEmpty())
                        ? saveResult.getErrors()[0].getMessage()
                        : 'Unknown DML error';
                    return result;
                }
            }

            existingMessage = saveResult.isSuccess()
                ? new CommunicatorMessage__c(
                    Id = saveResult.getId(),
                    Thread__c = resolvedThreadId,
                    Sender__c = senderUserId
                )
                : findExistingSocketMessage(messageId);

            if (existingMessage == null) {
                result.status = 'RECONCILIATION_NOT_FOUND';
                result.errorMessage = 'Unable to resolve message after duplicate detection.';
                return result;
            }

            try {
                updateThreadLastMessage(existingMessage.Thread__c);
            } catch (Exception ex) {
                System.debug(LoggingLevel.WARN,
                    'CommunicatorMessageService.reconcileSocketInboundMessage updateThreadLastMessage warning: '
                    + ex.getMessage());
            }

            result.created = saveResult.isSuccess();
        }

        Set<Id> recipientIds = resolveSocketRecipients(existingMessage.Thread__c, payloadRecipientIds);
        if (existingMessage.Sender__c != null) {
            recipientIds.remove(existingMessage.Sender__c);
        }

        if (!recipientIds.isEmpty()) {
            try {
                CommunicatorNotificationService.notifyExplicitRecipients(
                    existingMessage.Thread__c,
                    existingMessage.Id,
                    recipientIds,
                    new Set<Id>()
                );
            } catch (Exception ex) {
                // Notification failures must not invalidate message reconciliation.
                result.errorMessage = ex.getMessage();
                result.status = result.created ? 'CREATED_NOTIFICATION_FAILED' : 'RECONCILED_NOTIFICATION_FAILED';
                result.success = true;
                result.messageId = String.valueOf(existingMessage.Id);
                return result;
            }
        }

        result.success = true;
        result.messageId = String.valueOf(existingMessage.Id);
        result.status = result.created ? 'CREATED' : 'RECONCILED';
        return result;
    }

    // ─────────────────────────────────────────
    // Private helpers
    // ─────────────────────────────────────────

    private class MentionResolution {
        public Set<Id> userIds  = new Set<Id>();
        public Set<Id> groupIds = new Set<Id>();
    }

    private static Set<Id> sanitizeThreadIds(List<Id> threadIds) {
        Set<Id> ids = new Set<Id>();
        if (threadIds == null || threadIds.isEmpty()) return ids;
        for (Id threadId : threadIds) {
            if (threadId != null) ids.add(threadId);
        }
        return ids;
    }

    private static Set<Id> getMessageHistoryParticipantIdsByThreadIds(Set<Id> threadIds) {
        Set<Id> participantIds = new Set<Id>();
        if (threadIds == null || threadIds.isEmpty()) return participantIds;

        for (AggregateResult row : [
            SELECT Sender__c senderId
            FROM CommunicatorMessage__c
            WHERE Thread__c IN :threadIds
            AND Sender__c != null
            GROUP BY Sender__c
        ]) {
            Id senderId = (Id) row.get('senderId');
            if (senderId != null) participantIds.add(senderId);
        }
        for (AggregateResult row : [
            SELECT CreatedById createdById
            FROM CommunicatorMessage__c
            WHERE Thread__c IN :threadIds
            AND Sender__c = null
            GROUP BY CreatedById
        ]) {
            Id createdById = (Id) row.get('createdById');
            if (createdById != null) participantIds.add(createdById);
        }
        return participantIds;
    }

    private static void addActiveThreadParticipantIds(Set<Id> participantIds, Set<Id> threadIds) {
        if (participantIds == null || threadIds == null || threadIds.isEmpty()) return;
        for (CommunicatorParticipant__c participant : [
            SELECT User__c
            FROM CommunicatorParticipant__c
            WHERE Thread__c IN :threadIds
            AND IsActive__c = true
            AND User__c != null
        ]) {
            participantIds.add(participant.User__c);
        }
    }

    private static List<Id> sanitizeAttachmentDocumentIds(List<Id> rawIds) {
        List<Id> orderedIds = new List<Id>();
        Set<Id> seen = new Set<Id>();
        if (rawIds == null) return orderedIds;

        for (Id rawId : rawIds) {
            if (rawId == null || seen.contains(rawId)) continue;
            if (!String.valueOf(rawId).startsWith('069')) continue;
            seen.add(rawId);
            orderedIds.add(rawId);
        }
        return orderedIds;
    }

    private static Set<Id> sanitizeMessageIds(List<Id> rawIds) {
        Set<Id> ids = new Set<Id>();
        if (rawIds == null) return ids;
        for (Id rawId : rawIds) {
            if (rawId != null) ids.add(rawId);
        }
        return ids;
    }

    private static void ensureAttachmentAccessAndMessageLinks(
        Id messageId,
        Id threadId,
        Id opportunityId,
        List<Id> attachmentIds
    ) {
        if (messageId == null || attachmentIds == null || attachmentIds.isEmpty()) return;

        for (Id attachmentId : attachmentIds) {
            CommunicatorFileShareService.ensureAccessForAttachment(attachmentId, threadId, opportunityId);
        }
        createMessageAttachmentLinks(messageId, attachmentIds);
    }

    private static void createMessageAttachmentLinks(Id messageId, List<Id> attachmentIds) {
        if (messageId == null || attachmentIds == null || attachmentIds.isEmpty()) return;

        Set<Id> desiredAttachmentIds = new Set<Id>(attachmentIds);
        Set<Id> existingAttachmentIds = new Set<Id>();

        for (ContentDocumentLink link : [
            SELECT ContentDocumentId
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :messageId
            AND ContentDocumentId IN :desiredAttachmentIds
        ]) {
            existingAttachmentIds.add(link.ContentDocumentId);
        }

        List<ContentDocumentLink> inserts = new List<ContentDocumentLink>();
        for (Id attachmentId : attachmentIds) {
            if (existingAttachmentIds.contains(attachmentId)) continue;
            inserts.add(new ContentDocumentLink(
                ContentDocumentId = attachmentId,
                LinkedEntityId = messageId,
                ShareType = 'V',
                Visibility = 'AllUsers'
            ));
        }

        if (!inserts.isEmpty()) {
            Database.insert(inserts, false);
        }
    }

    private static void verifyBroadcastAttachmentLinks(
        Id messageId,
        Id threadId,
        List<Id> attachmentIds,
        Id networkId
    ) {
        if (attachmentIds == null || attachmentIds.isEmpty()) return;
        Set<Id> requiredEntityIds = new Set<Id>{ messageId, threadId };
        if (networkId != null) requiredEntityIds.add(networkId);
        Map<Id, Set<Id>> linkedEntitiesByDocumentId = new Map<Id, Set<Id>>();
        for (Id attachmentId : attachmentIds) {
            linkedEntitiesByDocumentId.put(attachmentId, new Set<Id>());
        }
        for (ContentDocumentLink link : [
            SELECT ContentDocumentId, LinkedEntityId
            FROM ContentDocumentLink
            WHERE ContentDocumentId IN :attachmentIds
            AND LinkedEntityId IN :requiredEntityIds
        ]) {
            linkedEntitiesByDocumentId.get(link.ContentDocumentId).add(link.LinkedEntityId);
        }
        for (Id attachmentId : attachmentIds) {
            if (!linkedEntitiesByDocumentId.get(attachmentId).containsAll(requiredEntityIds)) {
                throw new CommunicatorException('Não foi possível vincular todos os anexos do comunicado.');
            }
        }
    }

    private static List<Id> getAttachmentDocumentIdsForMessage(Id messageId, String fallbackDocumentId) {
        List<Id> orderedAttachmentIds = new List<Id>();
        Set<Id> dedupe = new Set<Id>();

        Id parsedFallbackId = tryParseDocumentId(fallbackDocumentId);
        if (parsedFallbackId != null) {
            dedupe.add(parsedFallbackId);
            orderedAttachmentIds.add(parsedFallbackId);
        }
        if (messageId == null) return orderedAttachmentIds;

        for (ContentDocumentLink link : [
            SELECT ContentDocumentId
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :messageId
            AND ContentDocumentId != null
            ORDER BY ContentDocumentId ASC
        ]) {
            if (dedupe.contains(link.ContentDocumentId)) continue;
            dedupe.add(link.ContentDocumentId);
            orderedAttachmentIds.add(link.ContentDocumentId);
        }
        return orderedAttachmentIds;
    }

    private static void addAttachmentToMessage(
        Map<Id, List<Id>> orderedAttachmentIdsByMessage,
        Map<Id, Set<Id>> dedupeAttachmentIdsByMessage,
        Id messageId,
        Id attachmentId
    ) {
        if (messageId == null || attachmentId == null) return;
        if (!orderedAttachmentIdsByMessage.containsKey(messageId)) return;

        Set<Id> dedupeIds = dedupeAttachmentIdsByMessage.get(messageId);
        if (dedupeIds == null) {
            dedupeIds = new Set<Id>();
            dedupeAttachmentIdsByMessage.put(messageId, dedupeIds);
        }
        if (dedupeIds.contains(attachmentId)) return;

        dedupeIds.add(attachmentId);
        orderedAttachmentIdsByMessage.get(messageId).add(attachmentId);
    }

    private class AttachmentDisplayMetadata {
        String fileName;
        String fileExtension;
    }

    private static Map<Id, AttachmentDisplayMetadata> loadAttachmentDisplayMetadata(Set<Id> contentDocumentIds) {
        Map<Id, AttachmentDisplayMetadata> metadataByDocumentId = new Map<Id, AttachmentDisplayMetadata>();
        if (contentDocumentIds == null || contentDocumentIds.isEmpty()) return metadataByDocumentId;

        for (ContentVersion version : [
            SELECT ContentDocumentId, PathOnClient, Title, FileExtension
            FROM ContentVersion
            WHERE ContentDocumentId IN :contentDocumentIds
            AND IsLatest = true
        ]) {
            AttachmentDisplayMetadata metadata = new AttachmentDisplayMetadata();
            metadata.fileName = resolveAttachmentDisplayName(
                version.PathOnClient,
                version.Title,
                version.FileExtension
            );
            metadata.fileExtension = String.isNotBlank(version.FileExtension)
                ? version.FileExtension
                : '';
            metadataByDocumentId.put(version.ContentDocumentId, metadata);
        }
        return metadataByDocumentId;
    }

    private static String resolveAttachmentDisplayName(
        String pathOnClient,
        String title,
        String extension
    ) {
        if (String.isNotBlank(pathOnClient)) {
            return pathOnClient.trim();
        }
        return buildAttachmentFileName(title, extension);
    }

    private static ContentVersion buildUploadContentVersion(
        String fileName,
        String base64Data,
        Id opportunityId
    ) {
        ContentVersion version = new ContentVersion(
            Title = buildContentVersionTitle(fileName),
            PathOnClient = fileName,
            VersionData = decodeBase64Body(base64Data),
            IsMajorVersion = true,
            FirstPublishLocationId = opportunityId
        );
        applyUploadContentVersionSecurity(version);
        return version;
    }

    private static Id resolveInsertedContentDocumentId(Id contentVersionId) {
        ContentVersion insertedVersion = [
            SELECT ContentDocumentId
            FROM ContentVersion
            WHERE Id = :contentVersionId
            LIMIT 1
        ];
        if (insertedVersion.ContentDocumentId == null) {
            throw new CommunicatorException('Unable to resolve uploaded file id.');
        }
        return insertedVersion.ContentDocumentId;
    }

    private static Id resolveThreadOpportunityId(Id threadId) {
        List<CommunicatorThread__c> threadRows = [
            SELECT RecordId__c, RecordType__c
            FROM CommunicatorThread__c
            WHERE Id = :threadId
            LIMIT 1
        ];
        if (threadRows.isEmpty() || String.isBlank(threadRows[0].RecordId__c)) return null;
        String recordId = threadRows[0].RecordId__c;
        if (threadRows[0].RecordType__c == 'Opportunity' && recordId.startsWith('006')) return (Id) recordId;
        if (threadRows[0].RecordType__c == 'Repasse__c') {
            String resolvedOpportunityId = CommunicatorThreadService.resolveOpportunityIdIfRepasse(recordId);
            if (String.isNotBlank(resolvedOpportunityId) && resolvedOpportunityId.startsWith('006')) {
                return (Id) resolvedOpportunityId;
            }
        }
        return recordId.startsWith('006') ? (Id) recordId : null;
    }

    private static Id resolveThreadIdForAttachment(Id threadId, Id messageId) {
        if (threadId != null) return threadId;
        if (messageId == null) return null;
        List<CommunicatorMessage__c> rows = [
            SELECT Thread__c
            FROM CommunicatorMessage__c
            WHERE Id = :messageId
            LIMIT 1
        ];
        return rows.isEmpty() ? null : rows[0].Thread__c;
    }

    private static Id resolveOpportunityIdForAttachment(Id opportunityId, Id threadId) {
        if (opportunityId != null) return opportunityId;
        if (threadId == null) return null;
        return resolveThreadOpportunityId(threadId);
    }

    private static Id resolveContentDocumentForAttachment(String contentDocumentId, String contentVersionId) {
        Id docId = tryParseDocumentId(contentDocumentId);
        if (docId != null) return docId;
        Id versionId = tryParseVersionId(contentVersionId);
        if (versionId == null) {
            throw new CommunicatorException('Attachment id is required.');
        }
        List<ContentVersion> rows = [
            SELECT ContentDocumentId
            FROM ContentVersion
            WHERE Id = :versionId
            LIMIT 1
        ];
        if (rows.isEmpty() || rows[0].ContentDocumentId == null) {
            throw new CommunicatorException('Attachment not found.');
        }
        return rows[0].ContentDocumentId;
    }

    private static Id tryParseDocumentId(String rawId) {
        if (String.isBlank(rawId)) return null;
        try {
            Id value = (Id) rawId;
            return String.valueOf(value).startsWith('069') ? value : null;
        } catch (Exception ex) {
            return null;
        }
    }

    private static Id tryParseVersionId(String rawId) {
        if (String.isBlank(rawId)) return null;
        try {
            Id value = (Id) rawId;
            return String.valueOf(value).startsWith('068') ? value : null;
        } catch (Exception ex) {
            return null;
        }
    }

    private static void validateAttachmentContextAccess(Id threadId, Id opportunityId) {
        Boolean hasThreadAccess = hasThreadAccessForCurrentUser(threadId);
        Boolean hasOpportunityAccess = hasOpportunityAccessForCurrentUser(opportunityId);
        if (!hasThreadAccess && !hasOpportunityAccess) {
            throw new CommunicatorException('You do not have access to this attachment.');
        }
    }

    private static Boolean hasThreadAccessForCurrentUser(Id threadId) {
        if (threadId == null) return false;
        Integer participantCount = [
            SELECT COUNT()
            FROM CommunicatorParticipant__c
            WHERE Thread__c = :threadId
            AND User__c = :UserInfo.getUserId()
            AND IsActive__c = true
        ];
        return participantCount > 0;
    }

    private static Boolean hasOpportunityAccessForCurrentUser(Id opportunityId) {
        if (opportunityId == null) return false;
        Set<Id> visibleIds = CommunicatorOpportunityAccessService.getVisibleOpportunityIds(
            new Set<Id>{ opportunityId }
        );
        return visibleIds.contains(opportunityId);
    }

    private static void validateAttachmentContextBinding(
        Id contentDocumentId,
        Id threadId,
        Id messageId,
        Id opportunityId
    ) {
        if (isAttachmentLinkedToMessage(contentDocumentId, messageId)) return;
        if (isAttachmentLinkedToEntity(contentDocumentId, threadId)) return;
        if (isAttachmentLinkedToEntity(contentDocumentId, opportunityId)) return;
        throw new CommunicatorException('Attachment is not linked to this context.');
    }

    private static Boolean isAttachmentLinkedToMessage(Id contentDocumentId, Id messageId) {
        if (contentDocumentId == null || messageId == null) return false;
        List<CommunicatorMessage__c> rows = [
            SELECT ContentDocumentId__c
            FROM CommunicatorMessage__c
            WHERE Id = :messageId
            LIMIT 1
        ];
        if (!rows.isEmpty() && rows[0].ContentDocumentId__c == String.valueOf(contentDocumentId)) return true;
        return isAttachmentLinkedToEntity(contentDocumentId, messageId);
    }

    private static Boolean isAttachmentLinkedToEntity(Id contentDocumentId, Id linkedEntityId) {
        if (contentDocumentId == null || linkedEntityId == null) return false;
        Integer linkCount = [
            SELECT COUNT()
            FROM ContentDocumentLink
            WHERE ContentDocumentId = :contentDocumentId
            AND LinkedEntityId = :linkedEntityId
        ];
        return linkCount > 0;
    }

    private static ContentVersion queryLatestAttachmentVersion(Id contentDocumentId) {
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

    private static CommunicatorDTOs.AttachmentFileDTO buildAttachmentFileDto(ContentVersion version) {
        CommunicatorDTOs.AttachmentFileDTO dto = new CommunicatorDTOs.AttachmentFileDTO();
        dto.fileName = resolveAttachmentDisplayName(
            version.PathOnClient,
            version.Title,
            version.FileExtension
        );
        dto.contentType = String.isNotBlank(version.FileType) ? version.FileType : 'UNKNOWN';
        dto.fileExtension = String.isNotBlank(version.FileExtension) ? version.FileExtension : '';
        dto.base64Data = EncodingUtil.base64Encode(version.VersionData);
        return dto;
    }

    private static String buildAttachmentFileName(String title, String extension) {
        String safeTitle = String.isNotBlank(title) ? title.trim() : 'arquivo';
        String safeExtension = String.isNotBlank(extension) ? extension.trim() : '';
        if (String.isBlank(safeExtension)) return safeTitle;
        String lowerTitle = safeTitle.toLowerCase();
        String expectedSuffix = '.' + safeExtension.toLowerCase();
        if (lowerTitle.endsWith(expectedSuffix)) return safeTitle;
        return safeTitle + '.' + safeExtension;
    }

    private static Blob decodeBase64Body(String base64Data) {
        String rawContent = String.valueOf(base64Data);
        Integer commaIndex = rawContent.indexOf(',');
        String normalizedContent = commaIndex >= 0
            ? rawContent.substring(commaIndex + 1)
            : rawContent;
        try {
            return EncodingUtil.base64Decode(normalizedContent);
        } catch (Exception ex) {
            throw new CommunicatorException('Invalid file body.');
        }
    }

    private static String buildContentVersionTitle(String fileName) {
        String normalizedName = String.valueOf(fileName).trim();
        if (String.isBlank(normalizedName)) return 'arquivo';
        Integer extensionSeparator = normalizedName.lastIndexOf('.');
        if (extensionSeparator <= 0) return normalizedName;
        return normalizedName.substring(0, extensionSeparator);
    }

    private static void applyUploadContentVersionSecurity(ContentVersion version) {
        if (version == null) return;
        if (ContentVersion.PublishStatus.getDescribe().isCreateable()) {
            version.put('PublishStatus', 'P');
        }
        if (ContentVersion.Origin.getDescribe().isCreateable()) {
            version.put('Origin', 'H');
        }
        if (ContentVersion.NetworkId.getDescribe().isCreateable()) {
            version.put('NetworkId', null);
        }
    }

    private static MentionResolution resolveMentionsWithGroups(String mentionIds) {
        MentionResolution result = new MentionResolution();
        if (String.isBlank(mentionIds)) return result;
        Set<Id> rawIds = CommunicatorMentionService.deserializeUserIds(mentionIds);
        result.groupIds = CommunicatorMentionService.extractGroupIds(rawIds);
        result.userIds  = CommunicatorMentionService.resolveUserIds(rawIds);
        return result;
    }

    private static Set<Id> parseSocketRecipientUserIds(String userIdsJson) {
        Set<Id> userIds = new Set<Id>();
        if (String.isBlank(userIdsJson)) return userIds;

        Object raw;
        try {
            raw = JSON.deserializeUntyped(userIdsJson);
        } catch (Exception ex) {
            return userIds;
        }

        if (raw instanceof List<Object>) {
            for (Object value : (List<Object>) raw) {
                Id parsed = tryCastUserId(value == null ? null : String.valueOf(value));
                if (parsed != null) userIds.add(parsed);
            }
            return userIds;
        }

        if (raw instanceof String) {
            for (String token : String.valueOf(raw).split('[,;]')) {
                Id parsed = tryCastUserId(token);
                if (parsed != null) userIds.add(parsed);
            }
        }
        return userIds;
    }

    private static CommunicatorMessage__c findExistingSocketMessage(String messageId) {
        Id typedMessageId = tryCastCommunicatorMessageId(messageId);
        if (typedMessageId != null) {
            List<CommunicatorMessage__c> byId = [
                SELECT Id, Thread__c, Sender__c, ExternalId__c
                FROM CommunicatorMessage__c
                WHERE Id = :typedMessageId
                LIMIT 1
            ];
            if (!byId.isEmpty()) return byId[0];
        }

        List<CommunicatorMessage__c> byExternalId = [
            SELECT Id, Thread__c, Sender__c, ExternalId__c
            FROM CommunicatorMessage__c
            WHERE ExternalId__c = :messageId
            LIMIT 1
        ];
        return byExternalId.isEmpty() ? null : byExternalId[0];
    }

    private static Id resolveSocketThreadId(Id threadId, String threadExternalId) {
        if (threadId != null) {
            List<CommunicatorThread__c> byId = [
                SELECT Id
                FROM CommunicatorThread__c
                WHERE Id = :threadId
                LIMIT 1
            ];
            if (!byId.isEmpty()) return byId[0].Id;
        }

        if (String.isBlank(threadExternalId)) return null;
        List<CommunicatorThread__c> byExternalId = [
            SELECT Id
            FROM CommunicatorThread__c
            WHERE ExternalId__c = :threadExternalId
            LIMIT 1
        ];
        return byExternalId.isEmpty() ? null : byExternalId[0].Id;
    }

    private static Set<Id> resolveSocketRecipients(Id threadId, Set<Id> payloadRecipientIds) {
        Set<Id> participantIds = new Set<Id>();
        if (threadId == null) return participantIds;

        for (CommunicatorParticipant__c participant : [
            SELECT User__c
            FROM CommunicatorParticipant__c
            WHERE Thread__c = :threadId
            AND IsActive__c = true
            AND User__c != null
        ]) {
            participantIds.add(participant.User__c);
        }

        if (payloadRecipientIds == null || payloadRecipientIds.isEmpty()) {
            return participantIds;
        }

        participantIds.retainAll(payloadRecipientIds);
        return participantIds;
    }

    private static Id resolveSocketSenderId(String senderExternalId) {
        Id senderId = tryCastUserId(senderExternalId);
        if (senderId == null) return null;

        List<User> users = [
            SELECT Id
            FROM User
            WHERE Id = :senderId
            LIMIT 1
        ];
        return users.isEmpty() ? null : users[0].Id;
    }

    private static Id tryCastCommunicatorMessageId(String value) {
        if (String.isBlank(value)) return null;
        try {
            Id typedId = (Id) value;
            return typedId.getSObjectType() == CommunicatorMessage__c.SObjectType ? typedId : null;
        } catch (Exception ex) {
            return null;
        }
    }

    private static Id tryCastUserId(String value) {
        if (String.isBlank(value)) return null;
        try {
            Id typedId = (Id) value;
            return typedId.getSObjectType() == User.SObjectType ? typedId : null;
        } catch (Exception ex) {
            return null;
        }
    }

    private static Boolean isDuplicateValueError(List<Database.Error> errors) {
        if (errors == null || errors.isEmpty()) return false;
        for (Database.Error err : errors) {
            if (err != null && err.getStatusCode() == StatusCode.DUPLICATE_VALUE) {
                return true;
            }
        }
        return false;
    }

    /**
     * @description Notifies the existing Heroku socket integration after message persistence.
     *              This must not affect the primary message transaction.
     */
    private static void publishExternalNewMessageEvent(
        CommunicatorMessage__c msg,
        Set<Id> mentionedUserIds
    ) {
        if (msg == null || msg.Id == null) return;
        Set<Id> recipientUserIds = resolveExternalRecipients(msg.Thread__c, mentionedUserIds);
        CommunicatorIntegrationService.publishNewMessageEventAsync(
            msg.Id,
            msg.Thread__c,
            msg.Body__c,
            recipientUserIds,
            msg.HasAttachment__c
        );
    }

    private static Set<Id> resolveExternalRecipients(Id threadId, Set<Id> mentionedUserIds) {
        Set<Id> recipientUserIds = new Set<Id>();
        if (threadId == null) return recipientUserIds;

        if (mentionedUserIds != null && !mentionedUserIds.isEmpty()) {
            recipientUserIds.addAll(mentionedUserIds);
            Id recordOwnerId = resolveThreadRecordOwnerUserId(threadId);
            if (recordOwnerId != null) {
                recipientUserIds.add(recordOwnerId);
            }
        }

        for (CommunicatorParticipant__c participant : [
            SELECT User__c
            FROM CommunicatorParticipant__c
            WHERE Thread__c = :threadId
            AND IsActive__c = true
            AND User__c != :UserInfo.getUserId()
        ]) {
            if (participant.User__c != null) {
                recipientUserIds.add(participant.User__c);
            }
        }

        recipientUserIds.remove(UserInfo.getUserId());
        return recipientUserIds;
    }

    private static Id resolveThreadRecordOwnerUserId(Id threadId) {
        if (threadId == null) return null;
        List<CommunicatorThread__c> threadRows = [
            SELECT RecordId__c
            FROM CommunicatorThread__c
            WHERE Id = :threadId
            LIMIT 1
        ];
        if (threadRows.isEmpty() || threadRows[0].RecordId__c == null) return null;

        Id recordId = threadRows[0].RecordId__c;
        String objectApiName = recordId.getSObjectType().getDescribe().getName();
        try {
            List<SObject> rows = Database.query('SELECT OwnerId FROM ' + objectApiName + ' WHERE Id = :recordId LIMIT 1');
            if (rows.isEmpty()) return null;
            return tryCastUserId(String.valueOf(rows[0].get('OwnerId')));
        } catch (Exception ex) {
            return null;
        }
    }

    private static CommunicatorMessage__c buildMessage(
        Id      threadId,          String  body,              Boolean hasAttachment,
        String  contentDocumentId, String  recordStatus,
        Set<Id> mentionedUserIds,  Boolean hasMention,        Set<Id> mentionedGroupIds
    ) {
        return new CommunicatorMessage__c(
            Thread__c             = threadId,
            Body__c               = body,
            Sender__c             = UserInfo.getUserId(),
            SentAt__c             = System.now(),
            Status__c             = 'Sent',
            HasAttachment__c      = hasAttachment,
            ContentDocumentId__c  = contentDocumentId,
            RecordStatus__c       = recordStatus,
            HasMention__c         = hasMention,
            MentionedUserIds__c   = CommunicatorMentionService.serializeUserIds(mentionedUserIds),
            MentionedGroupIds__c  = CommunicatorMentionService.serializeUserIds(mentionedGroupIds)
        );
    }

    private static void updateThreadLastMessage(Id threadId) {
        update new CommunicatorThread__c(
            Id              = threadId,
            LastMessageAt__c = System.now()
        );
    }

    private static CommunicatorMessage__c queryById(Id msgId) {
        List<CommunicatorMessage__c> messages = [
            SELECT Id, Name, Body__c, Status__c, HasAttachment__c, ContentDocumentId__c,
                   SentAt__c, ExternalId__c, RecordStatus__c, HasMention__c, IsSystemMessage__c,
                   MentionedUserIds__c, SourceThreadId__c, ParentMessage__c,
                   Sender__c, Sender__r.Name, Sender__r.SmallPhotoUrl,
                   CreatedById, CreatedBy.Name, CreatedBy.SmallPhotoUrl,
                   Thread__c
            FROM CommunicatorMessage__c
            WHERE Id = :msgId
            LIMIT 1
        ];
        return messages.isEmpty() ? null : messages[0];
    }

    /**
     * @description Reads the current status of the record linked to the thread.
     *              Returns null gracefully if not configured or not accessible.
     */
    private static String resolveRecordStatus(Id threadId) {
        List<CommunicatorThread__c> threads = [
            SELECT RecordId__c, RecordType__c, Stage__c
            FROM   CommunicatorThread__c
            WHERE  Id = :threadId
            LIMIT  1
        ];
        if (threads.isEmpty()) return null;
        CommunicatorThread__c thread = threads[0];
        if (String.isBlank(thread.RecordId__c) || String.isBlank(thread.RecordType__c)) return null;
        if (String.isNotBlank(thread.Stage__c)) return thread.Stage__c;

        // Compact-chat safety: if this thread is linked to an Opportunity that currently has
        // an active Repasse macro-phase, persist that phase as RecordStatus__c.
        if (thread.RecordType__c == 'Opportunity') {
            try {
                String repassePhase = CommunicatorRepassePhaseHelper.getRepasseMacroPhaseByOppId((Id) thread.RecordId__c);
                if (String.isNotBlank(repassePhase)) return repassePhase;
            } catch (Exception ex) {
                // Fallback to standard status lookup below.
            }
        }

        if (thread.RecordType__c == 'Repasse__c') {
            try {
                String resolvedOpportunityId = CommunicatorThreadService.resolveOpportunityIdIfRepasse(thread.RecordId__c);
                if (String.isNotBlank(resolvedOpportunityId)) {
                    String repassePhase = CommunicatorRepassePhaseHelper.getRepasseMacroPhaseByOppId((Id) resolvedOpportunityId);
                    if (String.isNotBlank(repassePhase)) return repassePhase;
                }
            } catch (Exception ex) {
                // Fallback to standard status lookup below.
            }
        }

        return CommunicatorRecordStatusService.getRecordStatus(
            thread.RecordId__c,
            thread.RecordType__c
        );
    }

    private static void validateThreadAccess(Id threadId) {
        List<CommunicatorThread__c> threads = [
            SELECT Id FROM CommunicatorThread__c WHERE Id = :threadId LIMIT 1
        ];
        if (threads.isEmpty()) {
            throw new CommunicatorException('Thread not found or not accessible.');
        }
    }

    private static void validateOpportunityMessagingIsOpen(Id threadId) {
        List<CommunicatorThread__c> threadRows = [
            SELECT RecordType__c, RecordId__c, Stage__c
            FROM CommunicatorThread__c
            WHERE Id = :threadId
            LIMIT 1
        ];
        if (threadRows.isEmpty()) return;

        CommunicatorThread__c thread = threadRows[0];
        if (thread.RecordType__c != 'Opportunity' || thread.RecordId__c == null) return;
        if (isRepasseThreadStage(thread.Stage__c)) return;

        List<Opportunity> oppRows = [
            SELECT StageName
            FROM Opportunity
            WHERE Id = :thread.RecordId__c
            LIMIT 1
        ];
        if (oppRows.isEmpty()) return;
        String currentStage = oppRows[0].StageName;
        if (currentStage == OPP_CLOSED_STAGE) {
            throw new CommunicatorException(
                'Envio de mensagens bloqueado: oportunidade encerrada e em etapa de repasse.'
            );
        }
        if (currentStage == OPP_LOST_STAGE) {
            throw new CommunicatorException(
                'Envio de mensagens bloqueado: oportunidade encerrada e perdida.'
            );
        }
    }

    private static Boolean isRepasseThreadStage(String stageName) {
        if (String.isBlank(stageName)) return false;
        return REPASSE_MACRO_PHASES.contains(stageName.trim());
    }

    // ─────────────────────────────────────────
    // Group thread mirroring
    // ─────────────────────────────────────────

    /**
     * @description Espelha uma mensagem (com menção a grupos) para a group thread de cada grupo.
     *              O campo SourceThreadId__c guarda a thread de origem para permitir
     *              o espelho de volta quando o usuário responde pelo grupo.
     */
    private static void mirrorMessageToGroupThreads(CommunicatorMessage__c original, Set<Id> groupIds) {
        if (groupIds == null || groupIds.isEmpty()) return;
        List<CommunicatorMessage__c> mirrors = new List<CommunicatorMessage__c>();
        List<Id> groupThreadIds = new List<Id>();
        for (Id groupId : groupIds) {
            CommunicatorThread__c groupThread = CommunicatorThreadService.getOrCreateGroupThread(groupId);
            mirrors.add(new CommunicatorMessage__c(
                Thread__c            = groupThread.Id,
                Body__c              = original.Body__c,
                Sender__c            = original.Sender__c,
                SentAt__c            = original.SentAt__c,
                Status__c            = 'Sent',
                IsSystemMessage__c   = false,
                HasMention__c        = false,
                HasAttachment__c     = original.HasAttachment__c,
                ContentDocumentId__c = original.ContentDocumentId__c,
                RecordStatus__c      = original.RecordStatus__c,
                SourceThreadId__c    = String.valueOf(original.Thread__c)
            ));
            groupThreadIds.add(groupThread.Id);
            updateThreadLastMessage(groupThread.Id);
        }
        if (!mirrors.isEmpty()) insert mirrors;

        List<Id> attachmentIds = original.HasAttachment__c
            ? getAttachmentDocumentIdsForMessage(original.Id, original.ContentDocumentId__c)
            : new List<Id>();
        if (!attachmentIds.isEmpty()) {
            List<ContentDocumentLink> mirrorAttachmentLinks = new List<ContentDocumentLink>();
            for (Integer i = 0; i < mirrors.size(); i += 1) {
                Id groupThreadId = groupThreadIds[i];
                Id mirrorMessageId = mirrors[i].Id;
                for (Id attachmentId : attachmentIds) {
                    CommunicatorFileShareService.ensureAccessForAttachment(attachmentId, groupThreadId);
                    mirrorAttachmentLinks.add(new ContentDocumentLink(
                        ContentDocumentId = attachmentId,
                        LinkedEntityId = mirrorMessageId,
                        ShareType = 'V',
                        Visibility = 'AllUsers'
                    ));
                }
            }
            if (!mirrorAttachmentLinks.isEmpty()) {
                Database.insert(mirrorAttachmentLinks, false);
            }
        }
    }

    /**
     * @description Envia uma resposta a partir da aba de grupos.
     *              Cria uma mensagem na group thread e espelha de volta na opp thread original.
     * @param groupId         Id do grupo ao qual o usuário está respondendo.
     * @param messageBody     Corpo da mensagem.
     * @param sourceMessageId Id da mensagem de menção original (tem SourceThreadId__c = opp thread).
     * @return A mensagem criada na group thread.
     */
    public static CommunicatorMessage__c sendGroupMessage(Id groupId, String messageBody, Id sourceMessageId) {
        if (String.isBlank(messageBody)) {
            throw new CommunicatorException('Message body cannot be empty.');
        }

        // sourceMessageId is the mirror message in the group thread (SourceThreadId__c = opp thread)
        List<CommunicatorMessage__c> sourceRows = [
            SELECT Id, Thread__c, SourceThreadId__c, Body__c, Sender__c, SentAt__c
            FROM   CommunicatorMessage__c
            WHERE  Id = :sourceMessageId
            LIMIT  1
        ];
        if (sourceRows.isEmpty()) {
            throw new CommunicatorException('Source message not found.');
        }
        CommunicatorMessage__c sourceMsg = sourceRows[0];

        String oppThreadId = sourceMsg.SourceThreadId__c;
        if (String.isBlank(oppThreadId)) {
            throw new CommunicatorException('Source message is not linked to an opportunity thread.');
        }

        CommunicatorThread__c groupThread = CommunicatorThreadService.getOrCreateGroupThread(groupId);

        // Reply in group thread linked to original mention via ParentMessage__c
        CommunicatorMessage__c groupMsg = new CommunicatorMessage__c(
            Thread__c          = groupThread.Id,
            Body__c            = messageBody,
            Sender__c          = UserInfo.getUserId(),
            SentAt__c          = System.now(),
            Status__c          = 'Sent',
            IsSystemMessage__c = false,
            HasMention__c      = false,
            ParentMessage__c   = String.valueOf(sourceMessageId)
        );
        insert groupMsg;
        updateThreadLastMessage(groupThread.Id);

        // Find original parent mention in opportunity thread (message that was mirrored to group thread)
        Id oppParentMessageId = null;
        List<CommunicatorMessage__c> oppParentRows = [
            SELECT Id
            FROM   CommunicatorMessage__c
            WHERE  Thread__c = :oppThreadId
            AND    Sender__c = :sourceMsg.Sender__c
            AND    SentAt__c = :sourceMsg.SentAt__c
            AND    HasMention__c = true
            ORDER BY CreatedDate ASC
            LIMIT  1
        ];
        if (!oppParentRows.isEmpty()) {
            oppParentMessageId = oppParentRows[0].Id;
        }

        // Mirror reply in opportunity thread, linked to parent mention when available
        CommunicatorMessage__c oppMirror = new CommunicatorMessage__c(
            Thread__c          = (Id) oppThreadId,
            Body__c            = messageBody,
            Sender__c          = UserInfo.getUserId(),
            SentAt__c          = System.now(),
            Status__c          = 'Sent',
            IsSystemMessage__c = false,
            HasMention__c      = false,
            SourceThreadId__c  = String.valueOf(groupThread.Id),
            ParentMessage__c   = (oppParentMessageId == null ? null : String.valueOf(oppParentMessageId))
        );
        insert oppMirror;
        updateThreadLastMessage((Id) oppThreadId);

        return queryById(groupMsg.Id);
    }
}