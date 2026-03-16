/**
 * @description Wrapper class holding all Communicator DTOs as inner classes.
 *              Apex requires all top-level types in a file to share the same name as the file.
 *              DTOs are declared here as inner classes to avoid multiple top-level class files.
 */
public class CommunicatorDTOs {

    // ─────────────────────────────────────────
    // Integration — Outbound
    // ─────────────────────────────────────────

    public class MessageEventDTO {
        @AuraEnabled public String  threadExternalId;
        @AuraEnabled public String  messageId;
        @AuraEnabled public String  senderId;
        @AuraEnabled public String  senderName;
        @AuraEnabled public String  messageBody;
        @AuraEnabled public String  sentAt;
        @AuraEnabled public Boolean hasAttachment;
    }

    // ─────────────────────────────────────────
    // Integration — Inbound
    // ─────────────────────────────────────────

    public class ExternalHistoryDTO {
        public String                   threadId;
        public List<ExternalMessageDTO> messages;
        public Integer                  totalCount;
    }

    public class ExternalMessageDTO {
        public String  externalId;
        public String  body;
        public String  senderId;
        public String  senderName;
        public String  sentAt;
        public Boolean hasAttachment;
    }

    public class IntegrationResponseDTO {
        @AuraEnabled public Integer statusCode;
        @AuraEnabled public Boolean success;
        @AuraEnabled public String  rawBody;
    }

    // ─────────────────────────────────────────
    // Record Search
    // ─────────────────────────────────────────

    /** Group of search results for one SObject type. */
    public class RecordResultDTO {
        @AuraEnabled public String              objectApiName;
        @AuraEnabled public String              objectLabel;
        @AuraEnabled public List<RecordItemDTO> records;
    }

    /** Single record result item. */
    public class RecordItemDTO {
        @AuraEnabled public String recordId;
        @AuraEnabled public String name;
        @AuraEnabled public String objectType;
    }

    // ─────────────────────────────────────────
    // Configuration
    // ─────────────────────────────────────────

    /** Settings read from CommunicatorConfig__mdt, sent to LWC on init. */
    public class SettingsDTO {
        @AuraEnabled public List<String> objectApiNames;
        @AuraEnabled public Boolean      filterOpenOnly;
        @AuraEnabled public Integer      maxSearchResults;
        @AuraEnabled public Integer      maxRecentRecords;
        @AuraEnabled public Integer      pollingIntervalMs;
        @AuraEnabled public Integer      messagesPerPage;
    }
}
