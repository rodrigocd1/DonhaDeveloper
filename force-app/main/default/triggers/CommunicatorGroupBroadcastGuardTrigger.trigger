trigger CommunicatorGroupBroadcastGuardTrigger on CommunicatorGroup__c (
    before insert,
    before update,
    before delete
) {
    if (Trigger.isInsert) {
        CommunicatorBroadcastDmlGuardHandler.beforeGroupInsert(Trigger.new);
    } else if (Trigger.isUpdate) {
        CommunicatorBroadcastDmlGuardHandler.beforeGroupUpdate(Trigger.new, Trigger.oldMap);
    } else {
        CommunicatorBroadcastDmlGuardHandler.beforeGroupDelete(Trigger.old);
    }
}