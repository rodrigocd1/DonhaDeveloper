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

    private static final String DEFAULT_CHATTER_HISTORY_EMPTY_MESSAGE =
        'Esta oportunidade não possui Histórico Chatter elegível no conjunto atual.';

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
                    MaxMessagesPerPage__c,
                    MaxThreadsPerPage__c,
                    StatusFieldApiName__c,
                    EnableChatterBlock__c,
                    EnableSystemEventDedup__c,
                    SystemEventDedupWindowMinutes__c,
                    UseChatterSystemEvents__c,
                    ReadNotificationRetentionDays__c,
                    UnreadNotificationRetentionDays__c,
                    BlockedChatterObjectApiNames__c,
                    ChatterBlockedMessage__c,
                    ChatterHistoryEmptyMessage__c,
                    BypassChatterBlockPermission__c,
                    MensagemDeErroUsuarioSemPermissao__c,
                    MaxUploadFileSizeMB__c,
                    MaxUploadBroadcastFileSizeMB__c,
                    MaxClipboardBroadcastImageSizeMB__c,
                    BroadcastEditLimitDays__c,
                    MensagemErroArquivoGrande__c,
                    BroadcastNotificationMessage__c,
                    BroadcastCommunityNotificationMessage__c
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
     * @description Returns the number of messages per page in the timeline.
     */
    public static Integer getMessagesPerPage() {
        Decimal val = getConfig().MaxMessagesPerPage__c;
        return (val != null && val > 0) ? val.intValue() : 20;
    }

    /**
     * @description Returns the number of threads per page in the history list.
     */
    public static Integer getThreadsPerPage() {
        Decimal val = getConfig().MaxThreadsPerPage__c;
        return (val != null && val > 0) ? val.intValue() : 10;
    }

    /**
     * @description Returns whether open-only filter is enabled.
     */
    public static Boolean getFilterOpenOnly() {
        return getConfig().FilterOpenOnly__c == true;
    }

    /**
     * @description Returns the API name of the status field for a given SObject type.
     *              Reads from the StatusFieldApiName__c JSON map in CommunicatorConfig__mdt.
     *
     *              Example config value:
     *              {"Opportunity":"StageName","Case":"Status","Account":"Type"}
     *
     * @param objectApiName  The SObject API name (e.g. 'Opportunity').
     * @return The field API name to read, or null if not configured for this object.
     */
    public static String getStatusFieldName(String objectApiName) {
        String raw = getConfig().StatusFieldApiName__c;
        if (String.isBlank(raw) || String.isBlank(objectApiName)) return null;

        try {
            Map<String, Object> fieldMap =
                (Map<String, Object>) JSON.deserializeUntyped(raw);
            Object fieldName = fieldMap.get(objectApiName);
            if (fieldName == null) return null;
            String result = String.valueOf(fieldName).trim();
            return String.isBlank(result) ? null : result;
        } catch (Exception ex) {
            System.debug(LoggingLevel.WARN,
                'CommunicatorConfigService.getStatusFieldName: invalid JSON — ' + ex.getMessage());
            return null;
        }
    }

    /**
     * @description Returns whether Chatter post/comment block is enabled.
     */
    public static Boolean getEnableChatterBlock() {
        return getConfig().EnableChatterBlock__c == true;
    }

    /**
     * @description Returns whether duplicate system events should be suppressed.
     */
    public static Boolean isSystemEventDedupEnabled() {
        return getConfig().EnableSystemEventDedup__c == true;
    }

    /**
     * @description Returns the duplicate system-event window in minutes.
     */
    public static Integer getSystemEventDedupWindowMinutes() {
        Decimal val = getConfig().SystemEventDedupWindowMinutes__c;
        return (val != null && val > 0) ? val.intValue() : 5;
    }

    /**
     * @description Returns whether system events should be published as Chatter posts.
     */
    public static Boolean useChatterSystemEvents() {
        return getConfig().UseChatterSystemEvents__c == true;
    }

    /**
     * @description Returns how many days read notifications are retained.
     */
    public static Integer getReadNotificationRetentionDays() {
        Decimal val = getConfig().ReadNotificationRetentionDays__c;
        return (val != null && val > 0) ? val.intValue() : 7;
    }

    /**
     * @description Returns how many days unread notifications are retained.
     */
    public static Integer getUnreadNotificationRetentionDays() {
        Decimal val = getConfig().UnreadNotificationRetentionDays__c;
        return (val != null && val > 0) ? val.intValue() : 30;
    }

    /**
     * @description Returns comma-separated object api names configured for chatter block.
     */
    public static String getBlockedChatterObjectApiNames() {
        return getConfig().BlockedChatterObjectApiNames__c;
    }

    /**
     * @description Returns the configured message shown when a chatter post/comment is blocked.
     */
    public static String getChatterBlockedMessage() {
        return getConfig().ChatterBlockedMessage__c;
    }

    /**
     * @description Returns the configured empty-state message shown when the Chatter history has no posts.
     */
    public static String getChatterHistoryEmptyMessage() {
        String msg = getConfig().ChatterHistoryEmptyMessage__c;
        return String.isNotBlank(msg)
            ? msg
            : DEFAULT_CHATTER_HISTORY_EMPTY_MESSAGE;
    }

    /**
     * @description Returns the custom permission name used to bypass chatter block.
     */
    public static String getBypassChatterBlockPermission() {
        return getConfig().BypassChatterBlockPermission__c;
    }

    /**
     * @description Returns the error message shown when the user lacks the CommunicatorChat Permission Set.
     */
    public static String getMensagemErroSemPermissao() {
        String msg = getConfig().MensagemDeErroUsuarioSemPermissao__c;
        return String.isNotBlank(msg)
            ? msg
            : 'Você não tem permissão para acessar as funcionalidades do canal de mensagens. Por favor, entre em contato com o Suporte.';
    }

    /**
     * @description Returns the maximum allowed upload file size in megabytes. Default: 10 MB.
     */
    public static Integer getMaxUploadFileSizeMB() {
        Decimal val = getConfig().MaxUploadFileSizeMB__c;
        return (val != null && val > 0) ? val.intValue() : 10;
    }

    public static Integer getMaxUploadBroadcastFileSizeMB() {
        Decimal val = getConfig().MaxUploadBroadcastFileSizeMB__c;
        if (val == null || val <= 0) {
            throw new CommunicatorException(
                'A configuração de tamanho máximo de upload de comunicado é inválida.'
            );
        }
        return val.intValue();
    }

    public static Decimal getMaxClipboardBroadcastImageSizeMB() {
        Decimal val = getConfig().MaxClipboardBroadcastImageSizeMB__c;
        return (val != null && val > 0) ? val : 1.5;
    }

    public static Integer getBroadcastEditLimitDays() {
        Decimal val = getConfig().BroadcastEditLimitDays__c;
        if (val == null || val < 0 || val != Decimal.valueOf(String.valueOf(val.intValue()))) {
            throw new CommunicatorException(
                'A configuração de prazo para edição de Comunicados é inválida.'
            );
        }
        return val.intValue();
    }

    /**
     * @description Returns the error message shown when an uploaded file exceeds the size limit.
     */
    public static String getMensagemErroArquivoGrande() {
        String msg = getConfig().MensagemErroArquivoGrande__c;
        return String.isNotBlank(msg)
            ? msg
            : 'O arquivo selecionado ultrapassa o tamanho máximo permitido para envio.';
    }

    /**
     * @description Returns the configured complementary message for new broadcast notifications.
     */
    public static String getBroadcastNotificationMessage() {
        String msg = getConfig().BroadcastNotificationMessage__c;
        return String.isNotBlank(msg)
            ? msg
            : 'Para visualizar, acesse o canal de mensagens';
    }

    /**
     * @description Returns the configured complementary message for new broadcast notifications sent to Community users.
     */
    public static String getBroadcastCommunityNotificationMessage() {
        String msg = getConfig().BroadcastCommunityNotificationMessage__c;
        return String.isNotBlank(msg)
            ? msg
            : 'Para visualizar, acesse o canal de mensagens';
    }

    // ─────────────────────────────────────────
    // Private helpers
    // ─────────────────────────────────────────

    @TestVisible
    private static CommunicatorConfig__mdt buildDefaults() {
        CommunicatorConfig__mdt defaults      = new CommunicatorConfig__mdt();
        defaults.ObjectApiNames__c            = 'Opportunity';
        defaults.FilterOpenOnly__c            = true;
        defaults.MaxSearchResults__c          = 10;
        defaults.MaxRecentRecords__c          = 5;
        defaults.PollingIntervalSeconds__c    = 6;
        defaults.MaxMessagesPerPage__c        = 20;
        defaults.MaxThreadsPerPage__c         = 10;
        defaults.StatusFieldApiName__c        = null;
        defaults.EnableChatterBlock__c        = false;
        defaults.EnableSystemEventDedup__c = false;
        defaults.SystemEventDedupWindowMinutes__c = 5;
        defaults.UseChatterSystemEvents__c = false;
        defaults.ReadNotificationRetentionDays__c = 7;
        defaults.UnreadNotificationRetentionDays__c = 30;
        defaults.BlockedChatterObjectApiNames__c = null;
        defaults.ChatterBlockedMessage__c =
            'O envio de novas mensagens via Chatter foi descontinuado para este processo. Utilize o Comunicador para novas interações relacionadas a este registro.';
        defaults.ChatterHistoryEmptyMessage__c = DEFAULT_CHATTER_HISTORY_EMPTY_MESSAGE;
        defaults.BypassChatterBlockPermission__c = 'CommunicatorChatGroup';
        defaults.MensagemDeErroUsuarioSemPermissao__c =
            'Você não tem permissão para acessar as funcionalidades do canal de mensagens. Por favor, entre em contato com o Suporte.';
        defaults.MaxUploadFileSizeMB__c = 10;
        defaults.MaxUploadBroadcastFileSizeMB__c = null;
        defaults.MaxClipboardBroadcastImageSizeMB__c = 1.5;
        defaults.BroadcastEditLimitDays__c = null;
        defaults.MensagemErroArquivoGrande__c =
            'O arquivo selecionado ultrapassa o tamanho máximo permitido para envio.';
        defaults.BroadcastNotificationMessage__c =
            'Para visualizar, acesse o canal de mensagens';
        defaults.BroadcastCommunityNotificationMessage__c =
            'Para visualizar, acesse o canal de mensagens';
        return defaults;
    }
}