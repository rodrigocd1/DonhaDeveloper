/**
 * @description Factory for creating test data used across Communicator test classes.
 */
@IsTest
public class CommunicatorTestFactory {

    public static Account createAccount() {
        Account acc = new Account(Name = 'Test Account');
        insert acc;
        return acc;
    }

    public static Opportunity createOpportunity(Id accountId) {
        Opportunity opp = new Opportunity(
            Name        = 'Test Opportunity',
            AccountId   = accountId,
            StageName   = 'Prospecting',
            CloseDate   = Date.today().addDays(30)
        );
        insert opp;
        return opp;
    }

    public static CommunicatorThread__c createThread(Id recordId) {
        CommunicatorThread__c thread = new CommunicatorThread__c(
            RecordId__c   = String.valueOf(recordId),
            RecordType__c = 'Opportunity',
            Status__c     = 'Active'
        );
        insert thread;
        return thread;
    }

    public static CommunicatorMessage__c createMessage(Id threadId, Id senderId, String body) {
        CommunicatorMessage__c msg = new CommunicatorMessage__c(
            Thread__c  = threadId,
            Sender__c  = senderId,
            Body__c    = body,
            SentAt__c  = System.now(),
            Status__c  = 'Sent'
        );
        insert msg;
        return msg;
    }

    public static CommunicatorParticipant__c createParticipant(Id threadId, Id userId) {
        CommunicatorParticipant__c p = new CommunicatorParticipant__c(
            Thread__c   = threadId,
            User__c     = userId,
            IsActive__c = true
        );
        insert p;
        return p;
    }

    public static List<CommunicatorMessage__c> createMessages(Id threadId, Id senderId, Integer count) {
        List<CommunicatorMessage__c> msgs = new List<CommunicatorMessage__c>();
        for (Integer i = 0; i < count; i++) {
            msgs.add(new CommunicatorMessage__c(
                Thread__c  = threadId,
                Sender__c  = senderId,
                Body__c    = 'Test message ' + i,
                SentAt__c  = System.now().addMinutes(i),
                Status__c  = 'Sent'
            ));
        }
        insert msgs;
        return msgs;
    }
}
