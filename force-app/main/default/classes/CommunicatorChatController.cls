/**
 * @description Controller layer for the Communicator Chat system.
 *              Exposes AuraEnabled methods consumed by LWC components.
 *              All business logic is delegated to service classes.
 *
 *              Thread is record-agnostic: any SObject Id can be used.
 */
public with sharing class CommunicatorChatController {

    // ─────────────────────────────────────────
    // Thread
    // ─────────────────────────────────────────

    /**
     * @description Returns or creates the thread for a given record Id.
     * @param recordId   Id of any SObject (Opportunity, Account, Case, etc.)
     * @param objectType API name of the SObject. Defaults to empty string if not provided.
     * @return CommunicatorThread__c record.
     */
    @AuraEnabled(cacheable=false)
    public static CommunicatorThread__c getOrCreateThread(String recordId, String objectType) {
        try {
            String objType = String.isBlank(objectType) ? '' : objectType;
            return CommunicatorThreadService.getOrCreateThread(recordId, objType);
        } catch (Exception ex) {
            throw new AuraHandledException(ex.getMessage());
        }
    }

    // ─────────────────────────────────────────
    // Messages
    // ─────────────────────────────────────────

    @AuraEnabled(cacheable=false)
    public static List<CommunicatorMessage__c> getMessages(Id threadId, Integer pageSize, Integer offsetVal) {
        try {
            return CommunicatorMessageService.getMessages(threadId, pageSize, offsetVal);
        } catch (Exception ex) {
            throw new AuraHandledException(ex.getMessage());
        }
    }

    @AuraEnabled(cacheable=false)
    public static CommunicatorMessage__c sendMessage(Id threadId, String messageBody) {
        try {
            return CommunicatorMessageService.sendMessage(threadId, messageBody);
        } catch (Exception ex) {
            throw new AuraHandledException(ex.getMessage());
        }
    }

    @AuraEnabled(cacheable=false)
    public static CommunicatorMessage__c sendMessageWithAttachment(Id threadId, String messageBody, Id contentDocumentId) {
        try {
            return CommunicatorMessageService.sendMessageWithAttachment(threadId, messageBody, contentDocumentId);
        } catch (Exception ex) {
            throw new AuraHandledException(ex.getMessage());
        }
    }

    @AuraEnabled(cacheable=false)
    public static Integer getMessageCount(Id threadId) {
        try {
            return CommunicatorMessageService.getMessageCount(threadId);
        } catch (Exception ex) {
            throw new AuraHandledException(ex.getMessage());
        }
    }

    @AuraEnabled(cacheable=false)
    public static List<CommunicatorMessage__c> pollNewMessages(Id threadId, String lastTimestamp) {
        try {
            DateTime sinceDateTime = (DateTime) JSON.deserialize('"' + lastTimestamp + '"', DateTime.class);
            return CommunicatorMessageService.getMessagesSince(threadId, sinceDateTime);
        } catch (Exception ex) {
            throw new AuraHandledException(ex.getMessage());
        }
    }

    // ─────────────────────────────────────────
    // Search
    // ─────────────────────────────────────────

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

    @AuraEnabled(cacheable=false)
    public static Integer getUnreadCount(Id threadId) {
        try {
            return CommunicatorNotificationService.getUnreadCount(threadId);
        } catch (Exception ex) {
            throw new AuraHandledException(ex.getMessage());
        }
    }

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

    @AuraEnabled(cacheable=false)
    public static List<CommunicatorParticipant__c> getParticipants(Id threadId) {
        try {
            return CommunicatorParticipantService.getParticipants(threadId);
        } catch (Exception ex) {
            throw new AuraHandledException(ex.getMessage());
        }
    }

    // ─────────────────────────────────────────
    // Record name (generic — any SObject)
    // ─────────────────────────────────────────

    /**
     * @description Returns the Name field of any SObject record dynamically.
     *              Used by LWC pickers to display record names without
     *              hardcoding the object type.
     * @param recordId Id of any SObject with a Name field.
     * @return The Name field value.
     */
    @AuraEnabled(cacheable=true)
    public static String getRecordName(String recordId) {
        try {
            if (String.isBlank(recordId)) return '';

            Id sfId = (Id) recordId;
            Schema.SObjectType sObjectType = sfId.getSObjectType();
            String objectName = sObjectType.getDescribe().getName();

            List<SObject> records = Database.query(
                'SELECT Name FROM ' + objectName + ' WHERE Id = :sfId LIMIT 1'
            );
            return records.isEmpty() ? '' : (String) records[0].get('Name');
        } catch (Exception ex) {
            throw new AuraHandledException(ex.getMessage());
        }
    }

    // ─────────────────────────────────────────
    // Configuration
    // ─────────────────────────────────────────

    /**
     * @description Returns all Communicator settings from CommunicatorConfig__mdt.
     *              Cached per transaction. Used by LWC to read config on init.
     */
    @AuraEnabled(cacheable=true)
    public static CommunicatorDTOs.SettingsDTO getSettings() {
        try {
            CommunicatorDTOs.SettingsDTO dto = new CommunicatorDTOs.SettingsDTO();
            dto.objectApiNames    = CommunicatorConfigService.getObjectApiNames();
            dto.filterOpenOnly    = CommunicatorConfigService.getFilterOpenOnly();
            dto.maxSearchResults  = CommunicatorConfigService.getMaxSearchResults();
            dto.maxRecentRecords  = CommunicatorConfigService.getMaxRecentRecords();
            dto.pollingIntervalMs = CommunicatorConfigService.getPollingIntervalMs();
            dto.messagesPerPage   = CommunicatorConfigService.getMessagesPerPage();
            return dto;
        } catch (Exception ex) {
            throw new AuraHandledException(ex.getMessage());
        }
    }

    // ─────────────────────────────────────────
    // Multi-object record search
    // ─────────────────────────────────────────

    /**
     * @description Searches for records across all configured SObject types.
     * @param keyword Search term.
     * @return List of CommunicatorDTOs.RecordResultDTO grouped by object type.
     */
    @AuraEnabled(cacheable=false)
    public static List<CommunicatorDTOs.RecordResultDTO> searchRecords(String keyword) {
        try {
            return CommunicatorRecordSearchService.searchRecords(keyword);
        } catch (Exception ex) {
            throw new AuraHandledException(ex.getMessage());
        }
    }
}