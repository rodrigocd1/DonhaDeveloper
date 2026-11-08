/**
 * @description Isolated trigger guard for Broadcast persistence.
 */
public without sharing class CommunicatorBroadcastDmlGuardHandler {

    private static final String GROUP_TYPE_BROADCAST = 'Broadcast';
    private static final String BROADCAST_CREATOR_PERMISSION = 'CommunicatorBroadcastCreator';
    private static final String DIRECT_GROUP_DML_MESSAGE =
        'Grupos Broadcast devem ser alterados pelo servico oficial de Comunicacao Geral.';
    private static final String DIRECT_AUDIENCE_DML_MESSAGE =
        'Criterios de audiencia Broadcast devem ser alterados pelo servico oficial de Comunicacao Geral.';
    private static final String DIRECT_THREAD_DML_MESSAGE =
        'Threads Broadcast devem ser alteradas pelo servico oficial de Comunicacao Geral.';
    private static final String DIRECT_MESSAGE_DML_MESSAGE =
        'Mensagens Broadcast devem ser alteradas pelo servico oficial de Comunicacao Geral.';
    private static final String DIRECT_NOTIFICATION_DML_MESSAGE =
        'Notificacoes Broadcast devem ser alteradas pelo servico oficial de Comunicacao Geral.';

    private class DmlAuthorization {
        String objectApiName;
        String operation;
        List<String> signatures;
        DmlAuthorization(String objectApiName, String operation, List<String> signatures) {
            this.objectApiName = objectApiName;
            this.operation = operation;
            this.signatures = normalizeSignatures(signatures);
        }
    }

    private static DmlAuthorization pendingOfficialAuthorization;
    private static Set<Id> cachedBroadcastThreadIds = new Set<Id>();
    private static Set<Id> cachedConventionalThreadIds = new Set<Id>();
    @TestVisible private static Integer messageThreadQueryCount = 0;
    public static void beforeGroupInsert(List<CommunicatorGroup__c> newRecords) {
        if (CommunicatorBroadcastAudienceService.consumeGroupDmlAuthorization('INSERT', newRecords)) return;
        if (canBypassAdministrativeBroadcastGuard()) return;
        for (CommunicatorGroup__c groupRecord : newRecords) {
            if (groupRecord.Type__c == GROUP_TYPE_BROADCAST) {
                groupRecord.addError(DIRECT_GROUP_DML_MESSAGE);
            }
        }
    }

    public static void beforeGroupUpdate(
        List<CommunicatorGroup__c> newRecords,
        Map<Id, CommunicatorGroup__c> oldRecordsById
    ) {
        if (CommunicatorBroadcastAudienceService.consumeGroupDmlAuthorization('UPDATE', newRecords)) return;
        if (canBypassAdministrativeBroadcastGuard()) return;
        for (CommunicatorGroup__c groupRecord : newRecords) {
            CommunicatorGroup__c oldRecord = oldRecordsById.get(groupRecord.Id);
            if (groupRecord.Type__c == GROUP_TYPE_BROADCAST ||
                oldRecord.Type__c == GROUP_TYPE_BROADCAST) {
                groupRecord.addError(DIRECT_GROUP_DML_MESSAGE);
            }
        }
    }

    public static void beforeGroupDelete(List<CommunicatorGroup__c> oldRecords) {
        if (CommunicatorBroadcastAudienceService.consumeGroupDmlAuthorization('DELETE', oldRecords)) return;
        if (canBypassAdministrativeBroadcastGuard()) return;
        for (CommunicatorGroup__c groupRecord : oldRecords) {
            if (groupRecord.Type__c == GROUP_TYPE_BROADCAST) {
                groupRecord.addError(DIRECT_GROUP_DML_MESSAGE);
            }
        }
    }

    public static void beforeAudienceDml(
        String operation,
        List<CommunicatorBroadcastAudience__c> records
    ) {
        if (CommunicatorBroadcastAudienceService.consumeAudienceDmlAuthorization(operation, records)) return;
        if (canBypassAdministrativeBroadcastGuard()) return;
        for (CommunicatorBroadcastAudience__c audienceRecord : records) {
            audienceRecord.addError(DIRECT_AUDIENCE_DML_MESSAGE);
        }
    }

    public static void authorizeThreadDml(String operation, List<CommunicatorThread__c> records) {
        registerOfficialAuthorization('CommunicatorThread__c', operation, buildThreadSignatures(records));
    }

    public static void authorizeMessageDml(String operation, List<CommunicatorMessage__c> records) {
        registerOfficialAuthorization('CommunicatorMessage__c', operation, buildMessageSignatures(records));
    }

    public static void authorizeNotificationDml(
        String operation,
        List<CommunicatorNotification__c> records
    ) {
        registerOfficialAuthorization(
            'CommunicatorNotification__c', operation, buildNotificationSignatures(records)
        );
    }

    public static void clearOfficialAuthorization() {
        pendingOfficialAuthorization = null;
    }

    public static void beforeThreadDml(
        String operation,
        List<CommunicatorThread__c> newRecords,
        List<CommunicatorThread__c> oldRecords
    ) {
        List<CommunicatorThread__c> targetRecords = operation == 'DELETE' ? oldRecords : newRecords;
        if (targetRecords == null || targetRecords.isEmpty()) return;

        if (consumeOfficialAuthorization(
            'CommunicatorThread__c', operation, buildThreadSignatures(targetRecords)
        )) return;
        if (canBypassAdministrativeBroadcastGuard()) return;

        List<CommunicatorThread__c> broadcastRecords = new List<CommunicatorThread__c>();
        if (operation == 'INSERT') {
            Set<Id> candidateGroupIds = new Set<Id>();
            for (CommunicatorThread__c record : targetRecords) {
                Id groupId = parseGroupId(record);
                if (groupId != null) candidateGroupIds.add(groupId);
            }
            Set<Id> broadcastGroupIds = loadBroadcastGroupIds(candidateGroupIds);
            for (CommunicatorThread__c record : targetRecords) {
                Id groupId = parseGroupId(record);
                Boolean referencesBroadcast = groupId != null && broadcastGroupIds.contains(groupId);
                if (referencesBroadcast && record.IsBroadcast__c != true) {
                    record.addError(DIRECT_THREAD_DML_MESSAGE);
                } else if (referencesBroadcast || record.IsBroadcast__c == true) {
                    broadcastRecords.add(record);
                }
            }
        } else {
            for (Integer index = 0; index < targetRecords.size(); index++) {
                CommunicatorThread__c target = targetRecords[index];
                CommunicatorThread__c oldRecord = oldRecords != null && index < oldRecords.size()
                    ? oldRecords[index]
                    : null;
                if (target.IsBroadcast__c == true ||
                    (oldRecord != null && oldRecord.IsBroadcast__c == true)) {
                    broadcastRecords.add(target);
                }
            }
        }
        if (broadcastRecords.isEmpty()) return;
        for (CommunicatorThread__c record : broadcastRecords) record.addError(DIRECT_THREAD_DML_MESSAGE);
    }

    public static void beforeMessageDml(
        String operation,
        List<CommunicatorMessage__c> newRecords,
        List<CommunicatorMessage__c> oldRecords
    ) {
        List<CommunicatorMessage__c> targetRecords = operation == 'DELETE' ? oldRecords : newRecords;
        if (targetRecords == null || targetRecords.isEmpty()) return;
        if (consumeOfficialAuthorization(
            'CommunicatorMessage__c', operation, buildMessageSignatures(targetRecords)
        )) return;
        if (canBypassAdministrativeBroadcastGuard()) return;
        Set<Id> threadIds = new Set<Id>();
        collectMessageThreadIds(threadIds, newRecords);
        collectMessageThreadIds(threadIds, oldRecords);
        Set<Id> broadcastThreadIds = resolveBroadcastThreadIds(threadIds);
        List<CommunicatorMessage__c> broadcastRecords = new List<CommunicatorMessage__c>();
        for (Integer index = 0; index < targetRecords.size(); index++) {
            CommunicatorMessage__c target = targetRecords[index];
            CommunicatorMessage__c oldRecord = oldRecords != null && index < oldRecords.size()
                ? oldRecords[index]
                : null;
            if (broadcastThreadIds.contains(target.Thread__c) ||
                (oldRecord != null && broadcastThreadIds.contains(oldRecord.Thread__c))) {
                broadcastRecords.add(target);
            }
        }
        if (broadcastRecords.isEmpty()) return;
        for (CommunicatorMessage__c record : broadcastRecords) record.addError(DIRECT_MESSAGE_DML_MESSAGE);
    }

    public static void beforeNotificationDml(
        String operation,
        List<CommunicatorNotification__c> newRecords,
        List<CommunicatorNotification__c> oldRecords
    ) {
        List<CommunicatorNotification__c> targetRecords = operation == 'DELETE' ? oldRecords : newRecords;
        if (targetRecords == null || targetRecords.isEmpty()) return;
        if (consumeOfficialAuthorization(
            'CommunicatorNotification__c', operation, buildNotificationSignatures(targetRecords)
        )) return;
        if (canBypassAdministrativeBroadcastGuard()) return;
        List<CommunicatorNotification__c> broadcastRecords = new List<CommunicatorNotification__c>();
        for (Integer index = 0; index < targetRecords.size(); index++) {
            CommunicatorNotification__c target = targetRecords[index];
            CommunicatorNotification__c oldRecord = oldRecords != null && index < oldRecords.size()
                ? oldRecords[index]
                : null;
            if (target.Type__c == 'Broadcast' ||
                (oldRecord != null && oldRecord.Type__c == 'Broadcast')) {
                broadcastRecords.add(target);
            }
        }
        if (broadcastRecords.isEmpty()) return;
        for (CommunicatorNotification__c record : broadcastRecords) {
            record.addError(DIRECT_NOTIFICATION_DML_MESSAGE);
        }
    }

    private static Set<Id> loadBroadcastGroupIds(Set<Id> groupIds) {
        Set<Id> result = new Set<Id>();
        if (groupIds == null || groupIds.isEmpty()) return result;
        for (CommunicatorGroup__c groupRecord : [
            SELECT Id FROM CommunicatorGroup__c WHERE Id IN :groupIds AND Type__c = :GROUP_TYPE_BROADCAST
        ]) {
            result.add(groupRecord.Id);
        }
        return result;
    }

    private static Id parseGroupId(CommunicatorThread__c record) {
        if (record == null || record.RecordType__c != 'CommunicatorGroup__c' ||
            String.isBlank(record.RecordId__c)) return null;
        try {
            Id groupId = (Id) record.RecordId__c;
            return groupId.getSObjectType() == CommunicatorGroup__c.SObjectType ? groupId : null;
        } catch (Exception ex) {
            return null;
        }
    }

    private static void collectMessageThreadIds(Set<Id> threadIds, List<CommunicatorMessage__c> records) {
        if (records == null) return;
        for (CommunicatorMessage__c record : records) if (record.Thread__c != null) threadIds.add(record.Thread__c);
    }

    private static Set<Id> resolveBroadcastThreadIds(Set<Id> threadIds) {
        Set<Id> result = new Set<Id>();
        if (threadIds == null || threadIds.isEmpty()) return result;

        Set<Id> uncachedThreadIds = new Set<Id>();
        for (Id threadId : threadIds) {
            if (cachedBroadcastThreadIds.contains(threadId)) {
                result.add(threadId);
            } else if (!cachedConventionalThreadIds.contains(threadId)) {
                uncachedThreadIds.add(threadId);
            }
        }
        if (uncachedThreadIds.isEmpty()) return result;

        cachedConventionalThreadIds.addAll(uncachedThreadIds);
        messageThreadQueryCount++;
        for (CommunicatorThread__c threadRecord : [
            SELECT Id
            FROM CommunicatorThread__c
            WHERE Id IN :uncachedThreadIds
            AND IsBroadcast__c = true
        ]) {
            cachedConventionalThreadIds.remove(threadRecord.Id);
            cachedBroadcastThreadIds.add(threadRecord.Id);
            result.add(threadRecord.Id);
        }
        return result;
    }

    @TestVisible
    private static void resetMessageThreadCache() {
        cachedBroadcastThreadIds.clear();
        cachedConventionalThreadIds.clear();
        messageThreadQueryCount = 0;
    }

    private static Boolean canBypassAdministrativeBroadcastGuard() {
        return FeatureManagement.checkPermission(BROADCAST_CREATOR_PERMISSION);
    }

    private static void registerOfficialAuthorization(
        String objectApiName,
        String operation,
        List<String> signatures
    ) {
        if (pendingOfficialAuthorization != null) {
            throw new CommunicatorException('Existe uma operacao Broadcast controlada ainda nao consumida.');
        }
        pendingOfficialAuthorization = new DmlAuthorization(objectApiName, operation, signatures);
    }

    private static Boolean consumeOfficialAuthorization(
        String objectApiName,
        String operation,
        List<String> signatures
    ) {
        if (pendingOfficialAuthorization == null ||
            pendingOfficialAuthorization.objectApiName != objectApiName ||
            pendingOfficialAuthorization.operation != operation) return false;
        List<String> actual = normalizeSignatures(signatures);
        if (actual.size() != pendingOfficialAuthorization.signatures.size()) return false;
        for (Integer index = 0; index < actual.size(); index++) {
            if (actual[index] != pendingOfficialAuthorization.signatures[index]) return false;
        }
        pendingOfficialAuthorization = null;
        return true;
    }

    private static List<String> buildThreadSignatures(List<CommunicatorThread__c> records) {
        List<String> result = new List<String>();
        if (records == null) return result;
        for (CommunicatorThread__c record : records) {
            result.add(joinSignature(new List<Object>{ record.Id, record.Name, record.RecordId__c,
                record.RecordType__c, record.Status__c, record.Stage__c, record.LastMessageAt__c,
                record.UnreadCount__c, record.IsBroadcast__c }));
        }
        return result;
    }

    private static List<String> buildMessageSignatures(List<CommunicatorMessage__c> records) {
        List<String> result = new List<String>();
        if (records == null) return result;
        for (CommunicatorMessage__c record : records) {
            result.add(joinSignature(new List<Object>{ record.Id, record.Thread__c, record.Body__c,
                record.Sender__c, record.SentAt__c, record.Status__c, record.HasAttachment__c,
                record.ContentDocumentId__c, record.HasMention__c, record.IsSystemMessage__c,
                record.EditedAt__c }));
        }
        return result;
    }

    private static List<String> buildNotificationSignatures(List<CommunicatorNotification__c> records) {
        List<String> result = new List<String>();
        if (records == null) return result;
        for (CommunicatorNotification__c record : records) {
            result.add(joinSignature(new List<Object>{ record.Id, record.Thread__c, record.Message__c,
                record.Recipient__c, record.Type__c, record.IsRead__c, record.ReadAt__c,
                record.IsMention__c }));
        }
        return result;
    }

    private static String joinSignature(List<Object> values) {
        List<String> parts = new List<String>();
        for (Object value : values) parts.add(signaturePart(value));
        return String.join(parts, '|');
    }

    private static String signaturePart(Object value) {
        if (value == null) return '-1:';
        String serialized = String.valueOf(value);
        return String.valueOf(serialized.length()) + ':' + serialized;
    }

    private static List<String> normalizeSignatures(List<String> signatures) {
        List<String> result = new List<String>();
        if (signatures != null) result.addAll(signatures);
        result.sort();
        return result;
    }
}