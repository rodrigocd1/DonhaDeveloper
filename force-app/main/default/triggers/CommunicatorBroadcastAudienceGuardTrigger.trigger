trigger CommunicatorBroadcastAudienceGuardTrigger on CommunicatorBroadcastAudience__c (
    before insert,
    before update,
    before delete
) {
    if (Trigger.isInsert) {
        CommunicatorBroadcastDmlGuardHandler.beforeAudienceDml('INSERT', Trigger.new);
    } else if (Trigger.isUpdate) {
        CommunicatorBroadcastDmlGuardHandler.beforeAudienceDml('UPDATE', Trigger.new);
    } else {
        CommunicatorBroadcastDmlGuardHandler.beforeAudienceDml('DELETE', Trigger.old);
    }
}