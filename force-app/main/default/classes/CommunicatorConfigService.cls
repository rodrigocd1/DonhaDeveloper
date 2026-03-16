/**
 * @description Service responsible for reading Communicator configuration
 *              from CommunicatorConfig__mdt Custom Metadata.
 *
 *              Configuration is cached in a static variable for the duration
 *              of the Apex transaction — no repeated SOQL per request.
 *
 *              To change settings: Setup → Custom Metadata Types →
 *              Communicator Config → Manage Records → Default → Edit
 */
public with sharing class CommunicatorConfigService {

    // ─────────────────────────────────────────
    // Cache — one SOQL per transaction
    // ─────────────────────────────────────────

    @TestVisible
    private static CommunicatorConfig__mdt cachedConfig;

    // ─────────────────────────────────────────
    // Public API
    // ─────────────────────────────────────────

    /**
     * @description Returns the active configuration record.
     *              Falls back to safe defaults if no record is found.
     */
    public static CommunicatorConfig__mdt getConfig() {
        if (cachedConfig != null) return cachedConfig;

        List<CommunicatorConfig__mdt> configs = [
            SELECT  ObjectApiNames__c,
                    FilterOpenOnly__c,
                    MaxSearchResults__c,
                    MaxRecentRecords__c,
                    PollingIntervalSeconds__c,
                    MaxMessagesPerPage__c
            FROM    CommunicatorConfig__mdt
            WHERE   DeveloperName = 'Default'
            LIMIT   1
        ];

        cachedConfig = configs.isEmpty() ? buildDefaults() : configs[0];
        return cachedConfig;
    }

    /**
     * @description Returns the list of configured SObject API names.
     *              Example: ['Opportunity', 'Account', 'Case']
     */
    public static List<String> getObjectApiNames() {
        String raw = getConfig().ObjectApiNames__c;
        if (String.isBlank(raw)) return new List<String>{ 'Opportunity' };

        List<String> result = new List<String>();
        for (String name : raw.split(',')) {
            String trimmed = name.trim();
            if (String.isNotBlank(trimmed)) result.add(trimmed);
        }
        return result;
    }

    /**
     * @description Returns the max search results per object.
     */
    public static Integer getMaxSearchResults() {
        Decimal val = getConfig().MaxSearchResults__c;
        return (val != null && val > 0) ? val.intValue() : 10;
    }

    /**
     * @description Returns the max recent records to store.
     */
    public static Integer getMaxRecentRecords() {
        Decimal val = getConfig().MaxRecentRecords__c;
        return (val != null && val > 0) ? val.intValue() : 5;
    }

    /**
     * @description Returns the polling interval in milliseconds.
     */
    public static Integer getPollingIntervalMs() {
        Decimal val = getConfig().PollingIntervalSeconds__c;
        Integer seconds = (val != null && val >= 3) ? val.intValue() : 6;
        return seconds * 1000;
    }

    /**
     * @description Returns the number of messages per page.
     */
    public static Integer getMessagesPerPage() {
        Decimal val = getConfig().MaxMessagesPerPage__c;
        return (val != null && val > 0) ? val.intValue() : 20;
    }

    /**
     * @description Returns whether open-only filter is enabled.
     */
    public static Boolean getFilterOpenOnly() {
        return getConfig().FilterOpenOnly__c == true;
    }

    // ─────────────────────────────────────────
    // Private helpers
    // ─────────────────────────────────────────

    private static CommunicatorConfig__mdt buildDefaults() {
        CommunicatorConfig__mdt defaults      = new CommunicatorConfig__mdt();
        defaults.ObjectApiNames__c            = 'Opportunity';
        defaults.FilterOpenOnly__c            = true;
        defaults.MaxSearchResults__c          = 10;
        defaults.MaxRecentRecords__c          = 5;
        defaults.PollingIntervalSeconds__c    = 6;
        defaults.MaxMessagesPerPage__c        = 20;
        return defaults;
    }
}
