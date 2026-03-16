/**
 * @description Controller layer for the Communicator Chat system.
 *              Exposes AuraEnabled methods consumed by LWC components.
 *              All business logic is delegated to service classes.
 */
public with sharing class CommunicatorChatController {

    // ─────────────────────────────────────────
    // Thread
    // ─────────────────────────────────────────

    /**
     * @description Returns or creates the thread for a given Opportunity.
     * @param opportunityId The Opportunity record Id.
     * @return CommunicatorThread__c record.
     */
    @AuraEnabled(cacheable=false)
    public static CommunicatorThread__c getOrCreateThread(Id opportunityId) {
        try {
            return CommunicatorThreadService.getOrCreateThread(opportunityId);
        } catch (Exception ex) {
            throw new AuraHandledException(ex.getMessage());
        }
    }

    // ─────────────────────────────────────────
    // Messages
    // ─────────────────────────────────────────

    /**
     * @description Returns a paginated list of messages for a thread.
     * @param threadId   Thread record Id.
     * @param pageSize   Number of messages per page.
     * @param offsetVal  Offset for pagination.
     * @return List of CommunicatorMessage__c records.
     */
    @AuraEnabled(cacheable=false)
    public static List<CommunicatorMessage__c> getMessages(Id threadId, Integer pageSize, Integer offsetVal) {
        try {
            return CommunicatorMessageService.getMessages(threadId, pageSize, offsetVal);
        } catch (Exception ex) {
            throw new AuraHandledException(ex.getMessage());
        }
    }

    /**
     * @description Sends a new text message in a thread.
     * @param threadId    Thread record Id.
     * @param messageBody Text content of the message.
     * @return The saved CommunicatorMessage__c record.
     */
    @AuraEnabled(cacheable=false)
    public static CommunicatorMessage__c sendMessage(Id threadId, String messageBody) {
        try {
            return CommunicatorMessageService.sendMessage(threadId, messageBody);
        } catch (Exception ex) {
            throw new AuraHandledException(ex.getMessage());
        }
    }

    /**
     * @description Sends a message with a file attachment.
     * @param threadId         Thread record Id.
     * @param messageBody      Optional text content.
     * @param contentDocumentId ContentDocument Id of the uploaded file.
     * @return The saved CommunicatorMessage__c record.
     */
    @AuraEnabled(cacheable=false)
    public static CommunicatorMessage__c sendMessageWithAttachment(Id threadId, String messageBody, Id contentDocumentId) {
        try {
            return CommunicatorMessageService.sendMessageWithAttachment(threadId, messageBody, contentDocumentId);
        } catch (Exception ex) {
            throw new AuraHandledException(ex.getMessage());
        }
    }

    /**
     * @description Returns the total message count for a thread (for pagination).
     * @param threadId Thread record Id.
     * @return Integer count.
     */
    @AuraEnabled(cacheable=false)
    public static Integer getMessageCount(Id threadId) {
        try {
            return CommunicatorMessageService.getMessageCount(threadId);
        } catch (Exception ex) {
            throw new AuraHandledException(ex.getMessage());
        }
    }

    // ─────────────────────────────────────────
    // Search
    // ─────────────────────────────────────────

    /**
     * @description Searches messages inside a thread by keyword.
     * @param threadId Thread record Id.
     * @param keyword  Search keyword.
     * @return List of matching CommunicatorMessage__c records.
     */
    @AuraEnabled(cacheable=false)
    public static List<CommunicatorMessage__c> searchMessages(Id threadId, String keyword) {
        try {
            return CommunicatorSearchService.searchMessages(threadId, keyword);
        } catch (Exception ex) {
            throw new AuraHandledException(ex.getMessage());
        }
    }

    // ─────────────────────────────────────────
    // Notifications
    // ─────────────────────────────────────────

    /**
     * @description Returns unread message count for the current user in a thread.
     * @param threadId Thread record Id.
     * @return Integer unread count.
     */
    @AuraEnabled(cacheable=false)
    public static Integer getUnreadCount(Id threadId) {
        try {
            return CommunicatorNotificationService.getUnreadCount(threadId);
        } catch (Exception ex) {
            throw new AuraHandledException(ex.getMessage());
        }
    }

    /**
     * @description Marks all messages in a thread as read for the current user.
     * @param threadId Thread record Id.
     */
    @AuraEnabled(cacheable=false)
    public static void markThreadAsRead(Id threadId) {
        try {
            CommunicatorNotificationService.markThreadAsRead(threadId);
        } catch (Exception ex) {
            throw new AuraHandledException(ex.getMessage());
        }
    }

    // ─────────────────────────────────────────
    // Participants
    // ─────────────────────────────────────────

    /**
     * @description Returns all active participants for a thread.
     * @param threadId Thread record Id.
     * @return List of CommunicatorParticipant__c records.
     */
    @AuraEnabled(cacheable=false)
    public static List<CommunicatorParticipant__c> getParticipants(Id threadId) {
        try {
            return CommunicatorParticipantService.getParticipants(threadId);
        } catch (Exception ex) {
            throw new AuraHandledException(ex.getMessage());
        }
    }

    /**
     * @description Returns new messages created after the given timestamp (polling).
     * @param threadId      Thread record Id.
     * @param lastTimestamp ISO-formatted DateTime string of the last known message.
     * @return List of new CommunicatorMessage__c records.
     */
    @AuraEnabled(cacheable=false)
    public static List<CommunicatorMessage__c> pollNewMessages(Id threadId, String lastTimestamp) {
        try {
            DateTime sinceDateTime = (DateTime) JSON.deserialize('"' + lastTimestamp + '"', DateTime.class);
            return CommunicatorMessageService.getMessagesSince(threadId, sinceDateTime);
        } catch (Exception ex) {
            throw new AuraHandledException(ex.getMessage());
        }
    }

    /**
     * @description Retorna o nome de uma Opportunity pelo Id.
     *              Usado pelo picker para exibir o nome após seleção no lightning-record-picker.
     * @param opportunityId Id da Opportunity.
     * @return Nome da Opportunity.
     */
    @AuraEnabled(cacheable=true)
    public static String getOpportunityName(Id opportunityId) {
        try {
            List<Opportunity> opps = [
                SELECT Name FROM Opportunity WHERE Id = :opportunityId LIMIT 1
            ];
            return opps.isEmpty() ? '' : opps[0].Name;
        } catch (Exception ex) {
            throw new AuraHandledException(ex.getMessage());
        }
    }
}