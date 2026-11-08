/**
 * @description Group mention search queries that must ignore record sharing,
 *              so any active group can be mentioned by any user.
 */
public without sharing class CommunicatorGroupMentionQueryService {

    public static List<CommunicatorGroup__c> getActiveGroupsForMention() {
        return [
            SELECT Id, Name, MemberCount__c
            FROM   CommunicatorGroup__c
            WHERE  IsActive__c = true
            AND    (Type__c = null OR Type__c = 'Conventional')
            ORDER BY Name ASC
        ];
    }

    public static List<CommunicatorGroup__c> searchGroupsForMention(String keyword) {
        if (String.isBlank(keyword)) return getActiveGroupsForMention();

        String pattern = '%' + keyword.trim().replace('%', '\\%').replace('_', '\\_') + '%';
        return [
            SELECT Id, Name, MemberCount__c
            FROM   CommunicatorGroup__c
            WHERE  IsActive__c = true
            AND    (Type__c = null OR Type__c = 'Conventional')
            AND    Name LIKE :pattern
            ORDER BY Name ASC
            LIMIT  20
        ];
    }
}