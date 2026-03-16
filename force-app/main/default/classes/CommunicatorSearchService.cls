/**
 * @description Service responsible for in-thread message search.
 *
 * Strategy:
 * - CommunicatorMessage__c.Body__c is LongTextArea — not filterable in SOQL.
 * - CommunicatorMessage__c.SearchBody__c is Text(255) — filterable with LIKE.
 * - A before insert/update trigger mirrors the first 255 chars of Body__c into SearchBody__c.
 * - Search queries use LIKE on SearchBody__c, then return the full Body__c.
 */
public with sharing class CommunicatorSearchService {

    private static final Integer MAX_SEARCH_RESULTS = 50;

    /**
     * @description Searches messages in a thread using the SearchBody__c index field.
     * @param threadId Thread record Id.
     * @param keyword  Search term (matched with LIKE, case-insensitive).
     * @return List of matching CommunicatorMessage__c records ordered by SentAt__c ASC.
     */
    public static List<CommunicatorMessage__c> searchMessages(Id threadId, String keyword) {
        if (String.isBlank(keyword)) {
            throw new CommunicatorException('Search keyword cannot be empty.');
        }

        validateThreadAccess(threadId);

        String likePattern = '%' + sanitizeKeyword(keyword) + '%';

        return [
            SELECT Id, Name, Body__c, SearchBody__c, SentAt__c, Status__c,
                   HasAttachment__c, Thread__c,
                   Sender__c, Sender__r.Name, Sender__r.SmallPhotoUrl
            FROM CommunicatorMessage__c
            WHERE Thread__c = :threadId
            AND   SearchBody__c LIKE :likePattern
            ORDER BY SentAt__c ASC
            LIMIT :MAX_SEARCH_RESULTS
        ];
    }

    // ─────────────────────────────────────────
    // Private helpers
    // ─────────────────────────────────────────

    private static String sanitizeKeyword(String keyword) {
        return keyword.trim()
                      .replace('\\', '\\\\')
                      .replace('%',  '\\%')
                      .replace('_',  '\\_');
    }

    private static void validateThreadAccess(Id threadId) {
        List<CommunicatorThread__c> threads = [
            SELECT Id FROM CommunicatorThread__c WHERE Id = :threadId LIMIT 1
        ];
        if (threads.isEmpty()) {
            throw new CommunicatorException('Thread not found or not accessible.');
        }
    }
}
