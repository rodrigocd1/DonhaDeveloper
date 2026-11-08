/**
 * @description Service responsible for reading the current status value
 *              of any SObject record, based on the field mapping configured
 *              in CommunicatorConfig__mdt (StatusFieldApiName__c).
 *
 *              Usage: called when a message is sent to snapshot the record
 *              status at that point in time into CommunicatorMessage__c.RecordStatus__c.
 */
public with sharing class CommunicatorRecordStatusService {

    /**
     * @description Reads the configured status field value for a given record.
     *
     * @param recordId      Id of the SObject record.
     * @param objectApiName API name of the SObject (e.g. 'Opportunity').
     * @return The current value of the status field, or null if not configured
     *         or not accessible.
     */
    public static String getRecordStatus(String recordId, String objectApiName) {
        if (String.isBlank(recordId) || String.isBlank(objectApiName)) return null;

        String statusField = CommunicatorConfigService.getStatusFieldName(objectApiName);
        if (String.isBlank(statusField)) return null;

        try {
            Id sfId = (Id) recordId;

            // Dynamic SOQL — safe because statusField comes from admin-controlled
            // Custom Metadata, not from user input
            String soql = 'SELECT ' + statusField + ' FROM ' + objectApiName
                        + ' WHERE Id = :sfId LIMIT 1';

            List<SObject> records = Database.query(soql);
            if (records.isEmpty()) return null;

            Object val = records[0].get(statusField);
            return val != null ? String.valueOf(val) : null;

        } catch (Exception ex) {
            // Non-fatal: log and return null so the message is still sent
            System.debug(LoggingLevel.WARN,
                'CommunicatorRecordStatusService.getRecordStatus: ' + ex.getMessage());
            return null;
        }
    }
}