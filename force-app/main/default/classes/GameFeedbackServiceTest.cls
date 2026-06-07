@IsTest
private class GameFeedbackServiceTest {
    @testSetup
    static void setup() {
        GameTestDataFactory.createDefaultGameConfig();
        GameTestDataFactory.createPlayer('feedback-player', 'google');
    }

    @IsTest
    static void testSubmitFeedbackWithAccount() {
        Map<String, Object> payload = new Map<String, Object>{
            'playerId' => 'feedback-player',
            'mode' => 'Timer Attack',
            'stageNumber' => 12,
            'boardName' => 'Classico Mobile',
            'difficulty' => 'Medio',
            'playerScore' => 8,
            'aiScore' => 5,
            'result' => 'win',
            'durationSeconds' => 180,
            'aiAverageTimeMs' => 450,
            'aiMaxTimeMs' => 1200,
            'powersUsed' => new Map<String, Object>{ 'masterTip' => 1 },
            'feedbackCategory' => 'IA lenta',
            'feedbackStars' => 4,
            'feedbackComment' => 'A IA demorou um pouco.',
            'appVersion' => '0.01.53',
            'deviceInfo' => new Map<String, Object>{ 'platform' => 'android' },
            'source' => 'post_match'
        };

        Test.startTest();
        Map<String, Object> result = GameFeedbackService.submitFeedback(payload);
        Test.stopTest();

        Case gameCase = [SELECT AccountId, Game_Player_Account__c, Game_Player_Id__c, Subject FROM Case WHERE Id = :((Id) result.get('caseId')) LIMIT 1];
        System.assertNotEquals(null, gameCase.AccountId);
        System.assertEquals(gameCase.AccountId, gameCase.Game_Player_Account__c);
        System.assertEquals('feedback-player', gameCase.Game_Player_Id__c);
        System.assert(gameCase.Subject.contains('Laboratorio'));
    }

    @IsTest
    static void testSubmitFeedbackWithoutAccount() {
        Map<String, Object> payload = new Map<String, Object>{
            'playerId' => 'missing-player',
            'mode' => 'Arcade',
            'feedbackCategory' => 'Erro / Bug',
            'feedbackComment' => 'Falhou.',
            'source' => 'guest'
        };

        Test.startTest();
        Map<String, Object> result = GameFeedbackService.submitFeedback(payload);
        Test.stopTest();

        Case gameCase = [SELECT AccountId, Game_Player_Account__c FROM Case WHERE Id = :((Id) result.get('caseId')) LIMIT 1];
        System.assertEquals(null, gameCase.AccountId);
        System.assertEquals(null, gameCase.Game_Player_Account__c);
    }
}
