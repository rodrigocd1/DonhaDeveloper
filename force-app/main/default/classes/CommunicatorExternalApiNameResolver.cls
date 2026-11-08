public with sharing class CommunicatorExternalApiNameResolver {

    public static Map<Id, String> getUserNames(Set<Id> userIds) {
        Map<Id, String> result = new Map<Id, String>();
        if (userIds == null || userIds.isEmpty()) return result;
        for (User userRecord : [
            SELECT Id, Name
            FROM User
            WHERE Id IN :userIds
        ]) {
            result.put(userRecord.Id, userRecord.Name);
        }
        return result;
    }

    public static Map<Id, String> getGroupNames(Set<Id> groupIds) {
        Map<Id, String> result = new Map<Id, String>();
        if (groupIds == null || groupIds.isEmpty()) return result;
        for (CommunicatorGroup__c groupRecord : [
            SELECT Id, Name
            FROM CommunicatorGroup__c
            WHERE Id IN :groupIds
        ]) {
            result.put(groupRecord.Id, groupRecord.Name);
        }
        return result;
    }

    public static String getRecordName(Id recordId) {
        if (recordId == null) return null;
        String objectApiName = recordId.getSObjectType().getDescribe().getName();
        try {
            List<SObject> rows = Database.query(
                'SELECT Name FROM ' + objectApiName + ' WHERE Id = :recordId LIMIT 1'
            );
            return rows.isEmpty() ? null : String.valueOf(rows[0].get('Name'));
        } catch (Exception ex) {
            return null;
        }
    }
}