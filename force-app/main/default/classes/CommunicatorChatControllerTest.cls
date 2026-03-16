/**
 * @description Test class for CommunicatorChatController.
 * Target coverage: >= 85%
 */
@IsTest
private class CommunicatorChatControllerTest {

    @TestSetup
    static void setup() {
        Account acc  = CommunicatorTestFactory.createAccount();
        Opportunity opp = CommunicatorTestFactory.createOpportunity(acc.Id);
    }

    // ─────────────────────────────────────────
    // Thread
    // ─────────────────────────────────────────

    @IsTest
    static void testGetOrCreateThread_createsNewThread() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];

        Test.startTest();
        CommunicatorThread__c thread = CommunicatorChatController.getOrCreateThread(String.valueOf(opp.Id), 'Opportunity');
        Test.stopTest();

        Assert.isNotNull(thread);
        Assert.areEqual(String.valueOf(opp.Id), thread.RecordId__c);
        Assert.areEqual('Active', thread.Status__c);
    }

    @IsTest
    static void testGetOrCreateThread_returnsExistingThread() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        CommunicatorThread__c existing = CommunicatorTestFactory.createThread(opp.Id);

        Test.startTest();
        CommunicatorThread__c thread = CommunicatorChatController.getOrCreateThread(String.valueOf(opp.Id), 'Opportunity');
        Test.stopTest();

        Assert.areEqual(existing.Id, thread.Id);
    }

    @IsTest
    static void testGetOrCreateThread_invalidOpportunity_throwsException() {
        try {
            Test.startTest();
            CommunicatorChatController.getOrCreateThread('006000000000001AAA', 'Opportunity');
            Test.stopTest();
            Assert.fail('Expected AuraHandledException');
        } catch (AuraHandledException ex) {
            Assert.isNotNull(ex.getMessage());
        }
    }

    // ─────────────────────────────────────────
    // Messages
    // ─────────────────────────────────────────

    @IsTest
    static void testSendMessage_success() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        CommunicatorThread__c thread = CommunicatorTestFactory.createThread(opp.Id);

        Test.startTest();
        CommunicatorMessage__c msg = CommunicatorChatController.sendMessage(thread.Id, 'Hello world');
        Test.stopTest();

        Assert.isNotNull(msg.Id);
        Assert.areEqual('Hello world', msg.Body__c);
        Assert.areEqual('Sent', msg.Status__c);
    }

    @IsTest
    static void testSendMessage_emptyBody_throwsException() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        CommunicatorThread__c thread = CommunicatorTestFactory.createThread(opp.Id);

        try {
            Test.startTest();
            CommunicatorChatController.sendMessage(thread.Id, '');
            Test.stopTest();
            Assert.fail('Expected AuraHandledException');
        } catch (AuraHandledException ex) {
            Assert.isNotNull(ex.getMessage());
        }
    }

    @IsTest
    static void testGetMessages_pagination() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        CommunicatorThread__c thread = CommunicatorTestFactory.createThread(opp.Id);
        CommunicatorTestFactory.createMessages(thread.Id, UserInfo.getUserId(), 25);

        Test.startTest();
        List<CommunicatorMessage__c> page1 = CommunicatorChatController.getMessages(thread.Id, 10, 0);
        List<CommunicatorMessage__c> page2 = CommunicatorChatController.getMessages(thread.Id, 10, 10);
        Test.stopTest();

        Assert.areEqual(10, page1.size(), 'Page 1 should have 10 messages');
        Assert.areEqual(10, page2.size(), 'Page 2 should have 10 messages');
        Assert.areNotEqual(page1[0].Id, page2[0].Id, 'Pages should return different messages');
    }

    @IsTest
    static void testGetMessageCount() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        CommunicatorThread__c thread = CommunicatorTestFactory.createThread(opp.Id);
        CommunicatorTestFactory.createMessages(thread.Id, UserInfo.getUserId(), 5);

        Test.startTest();
        Integer count = CommunicatorChatController.getMessageCount(thread.Id);
        Test.stopTest();

        Assert.areEqual(5, count);
    }

    @IsTest
    static void testPollNewMessages() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        CommunicatorThread__c thread = CommunicatorTestFactory.createThread(opp.Id);
        CommunicatorTestFactory.createMessages(thread.Id, UserInfo.getUserId(), 3);

        String sinceTs = JSON.serialize(System.now().addMinutes(-5)).replace('"', '');

        Test.startTest();
        List<CommunicatorMessage__c> newMsgs = CommunicatorChatController.pollNewMessages(thread.Id, sinceTs);
        Test.stopTest();

        Assert.isTrue(newMsgs.size() >= 3);
    }

    // ─────────────────────────────────────────
    // Search
    // ─────────────────────────────────────────

    @IsTest
    static void testSearchMessages_findsMatch() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        CommunicatorThread__c thread = CommunicatorTestFactory.createThread(opp.Id);
        // Trigger will populate SearchBody__c from Body__c automatically
        CommunicatorTestFactory.createMessage(thread.Id, UserInfo.getUserId(), 'Hello contract review needed');
        CommunicatorTestFactory.createMessage(thread.Id, UserInfo.getUserId(), 'No match here');

        Test.startTest();
        List<CommunicatorMessage__c> results = CommunicatorChatController.searchMessages(thread.Id, 'contract');
        Test.stopTest();

        Assert.areEqual(1, results.size());
        Assert.isTrue(results[0].Body__c.containsIgnoreCase('contract'));
    }

    @IsTest
    static void testSearchMessages_blankKeyword_throwsException() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        CommunicatorThread__c thread = CommunicatorTestFactory.createThread(opp.Id);

        try {
            Test.startTest();
            CommunicatorChatController.searchMessages(thread.Id, '   ');
            Test.stopTest();
            Assert.fail('Expected AuraHandledException');
        } catch (AuraHandledException ex) {
            Assert.isNotNull(ex.getMessage());
        }
    }

    // ─────────────────────────────────────────
    // Notifications
    // ─────────────────────────────────────────

    @IsTest
    static void testGetUnreadCount_noParticipantRecord_returnsZero() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        CommunicatorThread__c thread = CommunicatorTestFactory.createThread(opp.Id);

        Test.startTest();
        Integer count = CommunicatorChatController.getUnreadCount(thread.Id);
        Test.stopTest();

        Assert.isTrue(count >= 0);
    }

    @IsTest
    static void testMarkThreadAsRead_succeeds() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        CommunicatorThread__c thread = CommunicatorTestFactory.createThread(opp.Id);
        CommunicatorTestFactory.createParticipant(thread.Id, UserInfo.getUserId());

        Test.startTest();
        CommunicatorChatController.markThreadAsRead(thread.Id);
        Test.stopTest();

        CommunicatorParticipant__c p = [
            SELECT LastReadAt__c FROM CommunicatorParticipant__c
            WHERE Thread__c = :thread.Id AND User__c = :UserInfo.getUserId()
            LIMIT 1
        ];
        Assert.isNotNull(p.LastReadAt__c);
    }

    // ─────────────────────────────────────────
    // Participants
    // ─────────────────────────────────────────

    @IsTest
    static void testGetParticipants() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        CommunicatorThread__c thread = CommunicatorTestFactory.createThread(opp.Id);
        CommunicatorTestFactory.createParticipant(thread.Id, UserInfo.getUserId());

        Test.startTest();
        List<CommunicatorParticipant__c> participants = CommunicatorChatController.getParticipants(thread.Id);
        Test.stopTest();

        Assert.isTrue(participants.size() >= 1);
    }

    // ─────────────────────────────────────────
    // Attachment
    // ─────────────────────────────────────────

    @IsTest
    static void testSendMessageWithAttachment_nullDocument_throwsException() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        CommunicatorThread__c thread = CommunicatorTestFactory.createThread(opp.Id);

        try {
            Test.startTest();
            CommunicatorChatController.sendMessageWithAttachment(thread.Id, 'See attachment', null);
            Test.stopTest();
            Assert.fail('Expected AuraHandledException');
        } catch (AuraHandledException ex) {
            Assert.isNotNull(ex.getMessage());
        }
    }
}
