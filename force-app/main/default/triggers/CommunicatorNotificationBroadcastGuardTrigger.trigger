trigger CommunicatorNotificationBroadcastGuardTrigger on CommunicatorNotification__c (
    before insert, before update, before delete
) {
    if (Trigger.isInsert) {
        CommunicatorBroadcastDmlGuardHandler.beforeNotificationDml('INSERT', Trigger.new, null);
    } else if (Trigger.isUpdate) {
        CommunicatorBroadcastDmlGuardHandler.beforeNotificationDml('UPDATE', Trigger.new, Trigger.old);
    } else {
        CommunicatorBroadcastDmlGuardHandler.beforeNotificationDml('DELETE', null, Trigger.old);
    }
}