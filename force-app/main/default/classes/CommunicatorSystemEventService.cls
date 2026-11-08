/**
 * @description POC service for communicator system events. It suppresses repeated
 *              system messages and will also own Chatter event persistence later.
 *              The caller resolves the communicator threads before invoking it.
 */
public without sharing class CommunicatorSystemEventService {

    private static final String HEADER_MARK = '] Evento: ';
    private static final String STATUS_MARK = ' | Status: ';
    private static final Integer MAX_BODY = 10000;

    /** Set only while this service inserts its own system-event posts. */
    public static Boolean isPublishingSystemEvents { get; private set; }

    /**
     * @description Publishes one Chatter TextPost for each resolved thread and updates
     *              the thread activity timestamp.
     */
    public static Map<Id, Id> publishEvents(Map<Id, String> threadToBody, String eventType) {
        Map<Id, Id> threadToFeedItemId = new Map<Id, Id>();
        if (threadToBody == null || threadToBody.isEmpty()) return threadToFeedItemId;

        Map<Id, CommunicatorThread__c> threadById = new Map<Id, CommunicatorThread__c>([
            SELECT Id, RecordId__c, RecordType__c, Stage__c
            FROM CommunicatorThread__c
            WHERE Id IN :threadToBody.keySet()
        ]);

        Datetime now = System.now();
        List<FeedItem> posts = new List<FeedItem>();
        for (Id threadId : threadToBody.keySet()) {
            String body = threadToBody.get(threadId);
            CommunicatorThread__c thread = threadById.get(threadId);
            if (String.isBlank(body) || thread == null) continue;
            posts.add(new FeedItem(
                ParentId = threadId,
                Type = 'TextPost',
                Visibility = 'AllUsers',
                Body = buildPostBody(now, eventType, thread, body)
            ));
        }
        if (posts.isEmpty()) return threadToFeedItemId;

        isPublishingSystemEvents = true;
        try {
            insert posts;
        } finally {
            isPublishingSystemEvents = false;
        }

        List<CommunicatorThread__c> threadsToUpdate = new List<CommunicatorThread__c>();
        for (FeedItem post : posts) {
            threadToFeedItemId.put(post.ParentId, post.Id);
            threadsToUpdate.add(new CommunicatorThread__c(Id = post.ParentId, LastMessageAt__c = now));
        }
        update threadsToUpdate;
        return threadToFeedItemId;
    }

    /** Builds a stable header that downstream timeline code can identify and parse. */
    public static String buildPostBody(
        Datetime ts,
        String eventType,
        CommunicatorThread__c thread,
        String body
    ) {
        String header = '[' + ts.format('dd/MM/yyyy HH:mm:ss', 'America/Sao_Paulo') + ' BRT'
            + HEADER_MARK + (String.isBlank(eventType) ? 'Movimentação' : eventType)
            + STATUS_MARK + (String.isBlank(thread.Stage__c) ? '-' : thread.Stage__c)
            + ' | Origem: ' + thread.RecordType__c + ' ' + thread.RecordId__c
            + ' | Usuário: ' + UserInfo.getName() + ' (' + UserInfo.getUserId() + ')';
        String full = header + '\n' + body;
        return full.length() > MAX_BODY ? full.substring(0, MAX_BODY) : full;
    }

    public static Boolean isSystemEventPost(String raw) {
        return raw != null && raw.startsWith('[') && raw.contains(HEADER_MARK);
    }

    public static String extractDisplayBody(String raw) {
        if (!isSystemEventPost(raw)) return raw;
        Integer idx = raw.indexOf('\n');
        return idx > 0 ? raw.substring(idx + 1) : raw;
    }

    public static String extractStatus(String raw) {
        if (!isSystemEventPost(raw)) return null;
        String firstLine = raw.contains('\n') ? raw.substringBefore('\n') : raw;
        String status = firstLine.substringAfter(STATUS_MARK).substringBefore(' | ');
        return (String.isBlank(status) || status == '-') ? null : status;
    }

    /**
     * @description Removes threads whose latest system message inside the configured
     *              window has the same normalized body as the incoming event.
     */
    public static Map<Id, String> filterDuplicateEvents(Map<Id, String> threadToBody) {
        if (threadToBody == null || threadToBody.isEmpty()
            || !CommunicatorConfigService.isSystemEventDedupEnabled()) {
            return threadToBody;
        }

        Datetime cutoff = System.now().addMinutes(
            -CommunicatorConfigService.getSystemEventDedupWindowMinutes()
        );
        Set<Id> threadIds = threadToBody.keySet();
        Map<Id, Datetime> lastAtByThread = new Map<Id, Datetime>();
        Map<Id, String> lastBodyByThread = new Map<Id, String>();

        for (CommunicatorMessage__c msg : [
            SELECT Thread__c, Body__c, SentAt__c
            FROM CommunicatorMessage__c
            WHERE Thread__c IN :threadIds
                AND IsSystemMessage__c = true
                AND SentAt__c >= :cutoff
            ORDER BY SentAt__c DESC, CreatedDate DESC, Id DESC
        ]) {
            if (lastAtByThread.containsKey(msg.Thread__c)) continue;
            lastAtByThread.put(msg.Thread__c, msg.SentAt__c);
            lastBodyByThread.put(msg.Thread__c, msg.Body__c);
        }

        for (FeedItem item : [
            SELECT ParentId, Body, CreatedDate
            FROM FeedItem
            WHERE ParentId IN :threadIds
                AND Type = 'TextPost'
                AND CreatedDate >= :cutoff
            ORDER BY CreatedDate DESC, Id DESC
        ]) {
            if (!isSystemEventPost(item.Body)) continue;
            Datetime current = lastAtByThread.get(item.ParentId);
            if (current != null && current >= item.CreatedDate) continue;
            lastAtByThread.put(item.ParentId, item.CreatedDate);
            lastBodyByThread.put(item.ParentId, extractDisplayBody(item.Body));
        }

        Map<Id, String> result = new Map<Id, String>();
        for (Id threadId : threadToBody.keySet()) {
            String body = threadToBody.get(threadId);
            String lastBody = lastBodyByThread.get(threadId);
            if (lastBody != null && body != null && lastBody.trim().equals(body.trim())) continue;
            result.put(threadId, body);
        }
        return result;
    }

    /** Returns system-event posts converted to unsaved message DTOs in ascending order. */
    public static List<CommunicatorMessage__c> getEventsAsMessages(
        Set<Id> threadIds,
        Datetime sinceDateTime,
        Integer maxRows
    ) {
        List<CommunicatorMessage__c> result = new List<CommunicatorMessage__c>();
        if (threadIds == null || threadIds.isEmpty() || maxRows == null || maxRows <= 0) return result;

        List<FeedItem> items = sinceDateTime == null
            ? [
                SELECT Id, ParentId, Body, CreatedDate
                FROM FeedItem
                WHERE ParentId IN :threadIds AND Type = 'TextPost'
                ORDER BY CreatedDate ASC, Id ASC
                LIMIT :maxRows
            ]
            : [
                SELECT Id, ParentId, Body, CreatedDate
                FROM FeedItem
                WHERE ParentId IN :threadIds
                    AND Type = 'TextPost'
                    AND CreatedDate > :sinceDateTime
                ORDER BY CreatedDate ASC, Id ASC
                LIMIT :maxRows
            ];
        for (FeedItem item : items) {
            if (!isSystemEventPost(item.Body)) continue;
            result.add(toMessage(item));
        }
        return result;
    }

    public static Integer countEvents(Set<Id> threadIds, Datetime beforeDateTime) {
        if (threadIds == null || threadIds.isEmpty()) return 0;
        return beforeDateTime == null
            ? [SELECT COUNT() FROM FeedItem WHERE ParentId IN :threadIds AND Type = 'TextPost']
            : [
                SELECT COUNT()
                FROM FeedItem
                WHERE ParentId IN :threadIds AND Type = 'TextPost' AND CreatedDate < :beforeDateTime
            ];
    }

    public static Map<Id, CommunicatorMessage__c> getLatestEventByThread(Set<Id> threadIds) {
        Map<Id, CommunicatorMessage__c> result = new Map<Id, CommunicatorMessage__c>();
        if (threadIds == null || threadIds.isEmpty()) return result;
        for (FeedItem item : [
            SELECT Id, ParentId, Body, CreatedDate
            FROM FeedItem
            WHERE ParentId IN :threadIds AND Type = 'TextPost'
            ORDER BY CreatedDate DESC, Id DESC
            LIMIT 2000
        ]) {
            if (result.containsKey(item.ParentId) || !isSystemEventPost(item.Body)) continue;
            result.put(item.ParentId, toMessage(item));
        }
        return result;
    }

    private static CommunicatorMessage__c toMessage(FeedItem item) {
        return new CommunicatorMessage__c(
            Thread__c = item.ParentId,
            Body__c = extractDisplayBody(item.Body),
            SentAt__c = item.CreatedDate,
            Status__c = 'Sent',
            IsSystemMessage__c = true,
            RecordStatus__c = extractStatus(item.Body),
            ExternalId__c = item.Id
        );
    }
}