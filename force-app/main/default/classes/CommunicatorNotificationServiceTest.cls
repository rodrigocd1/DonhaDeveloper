/**
 * @description Test class for CommunicatorNotificationService.
 */
@IsTest
private class CommunicatorNotificationServiceTest {

    @TestSetup
    static void setup() {
        Profile adminProfile = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];
        List<User> users = new List<User>();
        for (Integer i = 1; i <= 2; i++) {
            users.add(new User(
                FirstName = 'Notif',
                LastName = 'Recipient' + i,
                Alias = 'nrec' + i,
                Email = 'notif.recipient' + i + '@example.com',
                Username = 'notif.recipient' + i + '.' + System.currentTimeMillis() + '@example.com',
                ProfileId = adminProfile.Id,
                TimeZoneSidKey = 'America/Sao_Paulo',
                LocaleSidKey = 'pt_BR',
                EmailEncodingKey = 'UTF-8',
                LanguageLocaleKey = 'en_US'
            ));
        }
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert users;
        }
    }

    private static List<User> getRecipients() {
        return [SELECT Id FROM User WHERE LastName LIKE 'Recipient%' ORDER BY LastName];
    }

    private static Opportunity createOpportunityRecord() {
        Account account = CommunicatorTestFactory.createAccount();
        return CommunicatorTestFactory.createOpportunity(account.Id);
    }

    private static CommunicatorThread__c createThreadWithParticipants(Id opportunityId, List<User> recipients) {
        CommunicatorThread__c thread = CommunicatorTestFactory.createThread(opportunityId);
        for (User recipient : recipients) {
            CommunicatorTestFactory.createParticipant(thread.Id, recipient.Id);
        }
        return thread;
    }

    private static Integer countNotifications(Id threadId, Id recipientId) {
        return [
            SELECT COUNT()
            FROM CommunicatorNotification__c
            WHERE Thread__c = :threadId AND Recipient__c = :recipientId
        ];
    }

    // ─────────────────────────────────────────
    // notifyParticipants
    // ─────────────────────────────────────────

    @IsTest
    static void notifyParticipants_createsNotificationForEachParticipant() {
        List<User> recipients = getRecipients();
        Opportunity opp = createOpportunityRecord();
        CommunicatorThread__c thread = createThreadWithParticipants(opp.Id, recipients);
        CommunicatorMessage__c message = CommunicatorTestFactory.createMessage(thread.Id, UserInfo.getUserId(), 'Olá');

        Test.startTest();
        CommunicatorNotificationService.notifyParticipants(thread.Id, message.Id);
        Test.stopTest();

        for (User recipient : recipients) {
            Assert.areEqual(1, countNotifications(thread.Id, recipient.Id));
        }
        Assert.areEqual(0, countNotifications(thread.Id, UserInfo.getUserId()));
    }

    @IsTest
    static void notifyParticipants_marksMentionedRecipient() {
        List<User> recipients = getRecipients();
        Opportunity opp = createOpportunityRecord();
        CommunicatorThread__c thread = createThreadWithParticipants(opp.Id, recipients);
        CommunicatorMessage__c message = CommunicatorTestFactory.createMessage(thread.Id, UserInfo.getUserId(), 'Oi @user');

        Test.startTest();
        CommunicatorNotificationService.notifyParticipants(thread.Id, message.Id, new Set<Id>{ recipients[0].Id });
        Test.stopTest();

        CommunicatorNotification__c mentioned = [
            SELECT IsMention__c FROM CommunicatorNotification__c
            WHERE Thread__c = :thread.Id AND Recipient__c = :recipients[0].Id
        ];
        CommunicatorNotification__c regular = [
            SELECT IsMention__c FROM CommunicatorNotification__c
            WHERE Thread__c = :thread.Id AND Recipient__c = :recipients[1].Id
        ];
        Assert.isTrue(mentioned.IsMention__c);
        Assert.isFalse(regular.IsMention__c);
    }

    @IsTest
    static void notifyParticipants_withoutParticipants_createsNothing() {
        Opportunity opp = createOpportunityRecord();
        CommunicatorThread__c thread = CommunicatorTestFactory.createThread(opp.Id);
        CommunicatorMessage__c message = CommunicatorTestFactory.createMessage(thread.Id, UserInfo.getUserId(), 'Sem destinatários');

        Test.startTest();
        CommunicatorNotificationService.notifyParticipants(thread.Id, message.Id);
        Test.stopTest();

        Assert.areEqual(0, [SELECT COUNT() FROM CommunicatorNotification__c WHERE Thread__c = :thread.Id]);
    }

    @IsTest
    static void notifyExplicitRecipients_ignoresInactiveRecipient() {
        List<User> recipients = getRecipients();
        Opportunity opp = createOpportunityRecord();
        CommunicatorThread__c thread = createThreadWithParticipants(opp.Id, recipients);
        CommunicatorMessage__c message = CommunicatorTestFactory.createMessage(thread.Id, UserInfo.getUserId(), 'Teste');
        CommunicatorNotificationService.userIsActiveOverrideByIdForTest = new Map<Id, Boolean>{
            recipients[0].Id => false
        };

        Test.startTest();
        CommunicatorNotificationService.notifyExplicitRecipients(
            thread.Id,
            message.Id,
            new Set<Id>{ recipients[0].Id, recipients[1].Id },
            new Set<Id>{ recipients[0].Id }
        );
        Test.stopTest();

        Assert.areEqual(0, countNotifications(thread.Id, recipients[0].Id));
        Assert.areEqual(1, countNotifications(thread.Id, recipients[1].Id));
    }

    @IsTest
    static void notifyExplicitRecipients_platformRecipientStillTracked() {
        List<User> recipients = getRecipients();
        Opportunity opp = createOpportunityRecord();
        CommunicatorThread__c thread = createThreadWithParticipants(opp.Id, recipients);
        CommunicatorMessage__c message = CommunicatorTestFactory.createMessage(thread.Id, UserInfo.getUserId(), 'Teste');
        CommunicatorNotificationService.userLicenseOverrideByIdForTest = new Map<Id, String>{
            recipients[0].Id => 'Salesforce Platform'
        };

        Test.startTest();
        CommunicatorNotificationService.notifyExplicitRecipients(
            thread.Id,
            message.Id,
            new Set<Id>{ recipients[0].Id, recipients[1].Id },
            new Set<Id>{ recipients[0].Id }
        );
        Test.stopTest();

        Assert.areEqual(1, countNotifications(thread.Id, recipients[0].Id));
        Assert.areEqual(1, countNotifications(thread.Id, recipients[1].Id));
    }

    @IsTest
    static void notifyExplicitRecipients_withoutRecipients_doesNothing() {
        Opportunity opp = createOpportunityRecord();
        CommunicatorThread__c thread = CommunicatorTestFactory.createThread(opp.Id);
        CommunicatorMessage__c message = CommunicatorTestFactory.createMessage(thread.Id, UserInfo.getUserId(), 'Teste');

        Test.startTest();
        CommunicatorNotificationService.notifyExplicitRecipients(thread.Id, message.Id, new Set<Id>(), new Set<Id>());
        CommunicatorNotificationService.notifyExplicitRecipients(null, message.Id, new Set<Id>{ UserInfo.getUserId() }, null);
        CommunicatorNotificationService.notifyExplicitRecipients(thread.Id, message.Id, new Set<Id>{ UserInfo.getUserId() }, null);
        Test.stopTest();

        Assert.areEqual(0, [SELECT COUNT() FROM CommunicatorNotification__c WHERE Thread__c = :thread.Id]);
    }

    // ─────────────────────────────────────────
    // Bulk and system events
    // ─────────────────────────────────────────

    @IsTest
    static void notifyParticipantsBulk_createsNotificationsForMultipleThreads() {
        List<User> recipients = getRecipients();
        Opportunity opp = createOpportunityRecord();
        CommunicatorThread__c firstThread = createThreadWithParticipants(opp.Id, recipients);
        CommunicatorThread__c secondThread = createThreadWithParticipants(opp.Id, new List<User>{ recipients[0] });
        CommunicatorMessage__c firstMessage = CommunicatorTestFactory.createMessage(firstThread.Id, UserInfo.getUserId(), 'Um');
        CommunicatorMessage__c secondMessage = CommunicatorTestFactory.createMessage(secondThread.Id, UserInfo.getUserId(), 'Dois');

        Test.startTest();
        CommunicatorNotificationService.notifyParticipantsBulk(new Map<Id, Id>{
            firstThread.Id => firstMessage.Id,
            secondThread.Id => secondMessage.Id
        });
        Test.stopTest();

        Assert.areEqual(1, countNotifications(firstThread.Id, recipients[0].Id));
        Assert.areEqual(1, countNotifications(firstThread.Id, recipients[1].Id));
        Assert.areEqual(1, countNotifications(secondThread.Id, recipients[0].Id));
        Assert.areEqual(0, countNotifications(secondThread.Id, recipients[1].Id));
    }

    @IsTest
    static void notifyParticipantsBulk_emptyInput_doesNothing() {
        Test.startTest();
        CommunicatorNotificationService.notifyParticipantsBulk(null);
        CommunicatorNotificationService.notifyParticipantsBulk(new Map<Id, Id>());
        Test.stopTest();

        Assert.areEqual(0, [SELECT COUNT() FROM CommunicatorNotification__c]);
    }

    @IsTest
    static void notifySystemEventsBulk_createsTrackingForNonPlatformAndPlatformRecipients() {
        List<User> recipients = getRecipients();
        Opportunity opp = createOpportunityRecord();
        CommunicatorThread__c thread = createThreadWithParticipants(opp.Id, recipients);
        FeedItem feedItem = new FeedItem(ParentId = opp.Id, Body = 'Evento de sistema');
        insert feedItem;
        CommunicatorNotificationService.userLicenseOverrideByIdForTest = new Map<Id, String>{
            recipients[1].Id => 'Salesforce Platform'
        };

        Test.startTest();
        CommunicatorNotificationService.notifySystemEventsBulk(
            new Map<Id, Id>{ thread.Id => feedItem.Id },
            new Map<Id, String>{ thread.Id => 'Nova movimentação na oportunidade' }
        );
        Test.stopTest();

        Assert.areEqual(1, countNotifications(thread.Id, recipients[0].Id));
        Assert.areEqual(1, countNotifications(thread.Id, recipients[1].Id));
    }

    @IsTest
    static void notifySystemEventsBulk_withoutBody_usesDefaultText() {
        List<User> recipients = getRecipients();
        Opportunity opp = createOpportunityRecord();
        CommunicatorThread__c thread = createThreadWithParticipants(opp.Id, new List<User>{ recipients[0] });
        FeedItem feedItem = new FeedItem(ParentId = opp.Id, Body = 'Evento de sistema');
        insert feedItem;

        Test.startTest();
        CommunicatorNotificationService.notifySystemEventsBulk(new Map<Id, Id>{ thread.Id => feedItem.Id }, null);
        Test.stopTest();

        Assert.areEqual(1, countNotifications(thread.Id, recipients[0].Id));
    }

    @IsTest
    static void notifySystemEventsBulk_invalidInput_doesNothing() {
        Test.startTest();
        CommunicatorNotificationService.notifySystemEventsBulk(null, null);
        CommunicatorNotificationService.notifySystemEventsBulk(new Map<Id, Id>(), null);
        CommunicatorNotificationService.notifySystemEventsBulk(new Map<Id, Id>{ null => null }, null);
        Test.stopTest();

        Assert.areEqual(0, [SELECT COUNT() FROM CommunicatorNotification__c]);
    }

    // ─────────────────────────────────────────
    // Unread tracking
    // ─────────────────────────────────────────

    @IsTest
    static void unreadCount_andMarkAsRead_forRecipient() {
        List<User> recipients = getRecipients();
        Opportunity opp = createOpportunityRecord();
        CommunicatorThread__c thread = createThreadWithParticipants(opp.Id, recipients);
        CommunicatorMessage__c message = CommunicatorTestFactory.createMessage(thread.Id, UserInfo.getUserId(), 'Olá');
        CommunicatorNotificationService.notifyParticipants(thread.Id, message.Id);

        System.runAs(new User(Id = recipients[0].Id)) {
            Test.startTest();
            Integer unreadBefore = CommunicatorNotificationService.getUnreadCount(thread.Id);
            CommunicatorNotificationService.markThreadAsRead(thread.Id);
            Integer unreadAfter = CommunicatorNotificationService.getUnreadCount(thread.Id);
            Integer opportunityTotal = CommunicatorNotificationService.getOpportunityUnreadMessageTotal(10, 0, null);
            Test.stopTest();

            Assert.areEqual(1, unreadBefore);
            Assert.areEqual(0, unreadAfter);
            Assert.isNotNull(opportunityTotal);
        }

        CommunicatorParticipant__c participant = [
            SELECT LastReadAt__c FROM CommunicatorParticipant__c
            WHERE Thread__c = :thread.Id AND User__c = :recipients[0].Id
        ];
        Assert.isNotNull(participant.LastReadAt__c);
    }

    @IsTest
    static void markThreadAsRead_withoutParticipant_createsParticipant() {
        Opportunity opp = createOpportunityRecord();
        CommunicatorThread__c thread = CommunicatorTestFactory.createThread(opp.Id);

        Test.startTest();
        CommunicatorNotificationService.markThreadAsRead(thread.Id);
        Test.stopTest();

        Assert.areEqual(1, [
            SELECT COUNT() FROM CommunicatorParticipant__c
            WHERE Thread__c = :thread.Id AND User__c = :UserInfo.getUserId() AND LastReadAt__c != null
        ]);
    }

    // ─────────────────────────────────────────
    // Body and error logging
    // ─────────────────────────────────────────

    @IsTest
    static void buildNotificationBody_handlesAllMessageShapes() {
        Assert.areEqual(
            'Você recebeu uma nova mensagem. Clique para visualizar.',
            CommunicatorNotificationService.buildNotificationBody(null)
        );
        Assert.areEqual(
            'Você recebeu um novo anexo. Clique para visualizar.',
            CommunicatorNotificationService.buildNotificationBody(
                new CommunicatorMessage__c(Body__c = '  ', HasAttachment__c = true)
            )
        );
        Assert.areEqual(
            'Você recebeu uma nova mensagem. Clique para visualizar.',
            CommunicatorNotificationService.buildNotificationBody(new CommunicatorMessage__c(Body__c = null))
        );
        Assert.areEqual(
            'a b c',
            CommunicatorNotificationService.buildNotificationBody(new CommunicatorMessage__c(Body__c = 'a\r\n b   c'))
        );
        String longBody = 'x'.repeat(300);
        String truncated = CommunicatorNotificationService.buildNotificationBody(new CommunicatorMessage__c(Body__c = longBody));
        Assert.areEqual(255, truncated.length());
        Assert.isTrue(truncated.endsWith('...'));
    }

    @IsTest
    static void notifyExplicitRecipients_invalidNotificationType_doesNotBreakFlow() {
        List<User> recipients = getRecipients();
        Opportunity opp = createOpportunityRecord();
        CommunicatorThread__c thread = createThreadWithParticipants(opp.Id, recipients);
        CommunicatorMessage__c message = CommunicatorTestFactory.createMessage(thread.Id, UserInfo.getUserId(), 'Teste');
        CommunicatorNotificationService.notificationTypeIdCache = UserInfo.getUserId();

        Test.startTest();
        CommunicatorNotificationService.notifyExplicitRecipients(thread.Id, message.Id, new Set<Id>{ recipients[0].Id }, null);
        Test.stopTest();

        Assert.areEqual(1, countNotifications(thread.Id, recipients[0].Id));
    }

    @IsTest
    static void logSendFailure_doesNotThrow() {
        Exception sampleException = new NullPointerException();
        sampleException.setMessage('falha simulada');

        Test.startTest();
        CommunicatorNotificationService.logSendFailure(
            'sendCustomNotification',
            sampleException,
            new Set<String>{ UserInfo.getUserId() },
            null
        );
        CommunicatorNotificationService.logSendFailure('sendCustomNotificationText', sampleException, null, null);
        Test.stopTest();

        Assert.isNotNull(sampleException.getMessage());
    }
}
