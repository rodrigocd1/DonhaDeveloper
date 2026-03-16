/**
 * @description Wrapper class holding all Communicator DTOs as inner classes.
 *              Apex requires all top-level types in a file to share the same name as the file.
 *              DTOs are declared here as inner classes to avoid multiple top-level class files.
 */
public class CommunicatorDTOs {

    // ─────────────────────────────────────────
    // Outbound DTOs
    // ─────────────────────────────────────────

    /**
     * @description DTO for outbound new message event notifications.
     */
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
    // Inbound DTOs
    // ─────────────────────────────────────────

    /**
     * @description DTO for external message history response.
     */
    public class ExternalHistoryDTO {
        public String              threadId;
        public List<ExternalMessageDTO> messages;
        public Integer             totalCount;
    }

    /**
     * @description DTO for a single external message.
     */
    public class ExternalMessageDTO {
        public String  externalId;
        public String  body;
        public String  senderId;
        public String  senderName;
        public String  sentAt;
        public Boolean hasAttachment;
    }

    /**
     * @description DTO for integration HTTP response.
     */
    public class IntegrationResponseDTO {
        @AuraEnabled public Integer statusCode;
        @AuraEnabled public Boolean success;
        @AuraEnabled public String  rawBody;
    }
}
