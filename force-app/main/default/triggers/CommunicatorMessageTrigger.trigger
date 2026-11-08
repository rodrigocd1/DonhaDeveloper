/**
 * @description Trigger on CommunicatorMessage__c.
 *              Populates SearchBody__c with the first 255 characters of Body__c
 *              so that SOQL LIKE filtering is possible (LongTextArea is not filterable).
 */
trigger CommunicatorMessageTrigger on CommunicatorMessage__c (before insert, before update, before delete) {
    if (Trigger.isInsert) {
        CommunicatorBroadcastDmlGuardHandler.beforeMessageDml('INSERT', Trigger.new, null);
    } else if (Trigger.isUpdate) {
        CommunicatorBroadcastDmlGuardHandler.beforeMessageDml('UPDATE', Trigger.new, Trigger.old);
    } else {
        CommunicatorBroadcastDmlGuardHandler.beforeMessageDml('DELETE', null, Trigger.old);
    }
    if (!Trigger.isDelete) {
        for (CommunicatorMessage__c msg : Trigger.new) {
            if (msg.Body__c != null) {
                msg.SearchBody__c = msg.Body__c.length() > 255
                    ? msg.Body__c.substring(0, 255)
                    : msg.Body__c;
            } else {
                msg.SearchBody__c = '';
            }
        }
    }
}