trigger CommunicatorThreadBroadcastGuardTrigger on CommunicatorThread__c (
    before insert, before update, before delete
) {
    if (Trigger.isInsert) {
        CommunicatorBroadcastDmlGuardHandler.beforeThreadDml('INSERT', Trigger.new, null);
    } else if (Trigger.isUpdate) {
        CommunicatorBroadcastDmlGuardHandler.beforeThreadDml('UPDATE', Trigger.new, Trigger.old);
    } else {
        CommunicatorBroadcastDmlGuardHandler.beforeThreadDml('DELETE', null, Trigger.old);
    }
}