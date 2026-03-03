@IsTest
private class InteractionChatControllerTest {

    // ─── Test data helpers ───────────────────────────────────────────────────

    private static User makeUser(String alias, String profile) {
        Profile p = [SELECT Id FROM Profile WHERE Name = :profile LIMIT 1];
        User u = new User(
            Alias          = alias,
            Email          = alias + '@test.invalid',
            EmailEncodingKey = 'UTF-8',
            LastName       = alias,
            LanguageLocaleKey = 'en_US',
            LocaleSidKey   = 'en_US',
            ProfileId      = p.Id,
            TimeZoneSidKey = 'America/Sao_Paulo',
            UserName       = alias + '@test.invalid.sf'
        );
        insert u;
        return u;
    }

    private static InteractionThread__c makeThread(String recId, Boolean closed) {
        InteractionThread__c t = new InteractionThread__c(
            RecordId__c       = recId,
            SObjectApiName__c = 'Opportunity',
            Status__c         = closed ? 'Closed' : 'Open',
            Reason__c         = 'Suporte',
            IsClosed__c       = closed
        );
        insert t;
        return t;
    }

    private static void addParticipant(Id threadId, Id userId, String role) {
        insert new InteractionParticipant__c(
            Thread__c = threadId,
            User__c   = userId,
            Role__c   = role
        );
    }

    // ─── Tests ───────────────────────────────────────────────────────────────

    @IsTest
    static void testGetOrCreateThread_CreatesNew() {
        User u = makeUser('tst1', 'Standard User');
        // Use a fake 18-char id as the target record
        String fakeRecordId = '006000000000001AAA';

        Test.startTest();
        System.runAs(u) {
            InteractionChatController.ThreadDTO dto =
                InteractionChatController.getOrCreateThread(
                    fakeRecordId, 'Opportunity', 'Suporte', 'Olá!'
                );
            System.assertNotEquals(null, dto, 'Thread deve ser criada');
            System.assertEquals(fakeRecordId, dto.recordId);
            System.assertEquals('Open', dto.status);
        }
        Test.stopTest();
    }

    @IsTest
    static void testGetOrCreateThread_ReturnsExisting() {
        User u = makeUser('tst2', 'Standard User');
        String fakeRecordId = '006000000000002AAA';

        System.runAs(u) {
            InteractionChatController.getOrCreateThread(fakeRecordId, 'Opportunity', 'Suporte', 'Oi');
        }

        Test.startTest();
        System.runAs(u) {
            InteractionChatController.ThreadDTO dto =
                InteractionChatController.getOrCreateThread(fakeRecordId, 'Opportunity', 'Suporte', 'Segunda vez');
            System.assertNotEquals(null, dto);
        }
        Test.stopTest();
    }

    @IsTest
    static void testPostMessage_Success() {
        User u = makeUser('tst3', 'Standard User');
        String fakeRecordId = '006000000000003AAA';

        Id threadId;
        System.runAs(u) {
            InteractionChatController.ThreadDTO t =
                InteractionChatController.getOrCreateThread(fakeRecordId, 'Opportunity', 'Suporte', null);
            threadId = t.id;
        }

        Test.startTest();
        System.runAs(u) {
            InteractionChatController.MessageDTO msg =
                InteractionChatController.postMessage(threadId, 'Mensagem de teste');
            System.assertEquals('UserMessage', msg.messageType);
            System.assertEquals('Mensagem de teste', msg.body);
        }
        Test.stopTest();
    }

    @IsTest
    static void testPostMessage_BlockedWhenClosed() {
        User u = makeUser('tst4', 'Standard User');
        String fakeRecordId = '006000000000004AAA';

        InteractionThread__c t = makeThread(fakeRecordId, true);
        addParticipant(t.Id, u.Id, 'Partner');

        Test.startTest();
        try {
            System.runAs(u) {
                InteractionChatController.postMessage(t.Id, 'tentativa');
            }
            System.assert(false, 'Deveria lançar exceção');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('encerrada') || e.getMessage() != null);
        }
        Test.stopTest();
    }

    @IsTest
    static void testChangeStatus() {
        User u = makeUser('tst5', 'Standard User');
        String fakeRecordId = '006000000000005AAA';

        Id threadId;
        System.runAs(u) {
            InteractionChatController.ThreadDTO t =
                InteractionChatController.getOrCreateThread(fakeRecordId, 'Opportunity', 'Suporte', null);
            threadId = t.id;
        }

        Test.startTest();
        System.runAs(u) {
            InteractionChatController.MessageDTO msg =
                InteractionChatController.changeStatus(threadId, 'Pending');
            System.assertEquals('StatusChange', msg.messageType);
        }
        Test.stopTest();

        InteractionThread__c updated = [SELECT Status__c FROM InteractionThread__c WHERE Id = :threadId];
        System.assertEquals('Pending', updated.Status__c);
    }

    @IsTest
    static void testLinkUploadedFileToThread() {
        User u = makeUser('tst6', 'Standard User');
        String fakeRecordId = '006000000000006AAA';

        Id threadId;
        System.runAs(u) {
            InteractionChatController.ThreadDTO t =
                InteractionChatController.getOrCreateThread(fakeRecordId, 'Opportunity', 'Suporte', null);
            threadId = t.id;
        }

        // Criar ContentVersion/ContentDocument de teste
        ContentVersion cv = new ContentVersion(
            Title          = 'TestFile.pdf',
            PathOnClient   = 'TestFile.pdf',
            VersionData    = Blob.valueOf('dummy'),
            IsMajorVersion = true
        );
        insert cv;
        Id docId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id].ContentDocumentId;

        Test.startTest();
        System.runAs(u) {
            InteractionChatController.MessageDTO msg =
                InteractionChatController.linkUploadedFileToThread(threadId, docId);
            System.assertEquals('File', msg.messageType);
            System.assertEquals(docId, msg.fileDocumentId);
        }
        Test.stopTest();
    }

    @IsTest
    static void testAccessDenied_NonParticipant() {
        User owner  = makeUser('tst7a', 'Standard User');
        User other  = makeUser('tst7b', 'Standard User');
        String fakeRecordId = '006000000000007AAA';

        Id threadId;
        System.runAs(owner) {
            InteractionChatController.ThreadDTO t =
                InteractionChatController.getOrCreateThread(fakeRecordId, 'Opportunity', 'Suporte', null);
            threadId = t.id;
        }

        Test.startTest();
        try {
            System.runAs(other) {
                InteractionChatController.postMessage(threadId, 'hack');
            }
            System.assert(false, 'Deveria lançar exceção de acesso');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage() != null);
        }
        Test.stopTest();
    }

    @IsTest
    static void testGetMessagesSince() {
        User u = makeUser('tst8', 'Standard User');
        String fakeRecordId = '006000000000008AAA';

        Id threadId;
        System.runAs(u) {
            InteractionChatController.ThreadDTO t =
                InteractionChatController.getOrCreateThread(fakeRecordId, 'Opportunity', 'Suporte', 'Início');
            threadId = t.id;
            InteractionChatController.postMessage(threadId, 'msg1');
        }

        Test.startTest();
        System.runAs(u) {
            DateTime since = DateTime.now().addHours(-1);
            List<InteractionChatController.MessageDTO> msgs =
                InteractionChatController.getMessagesSince(threadId, since);
            System.assert(msgs.size() >= 1);
        }
        Test.stopTest();
    }
}
