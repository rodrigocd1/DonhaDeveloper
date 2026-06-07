@IsTest
private class GameFeedbackRestTest {
    @testSetup
    static void setup() {
        GameTestDataFactory.createDefaultGameConfig();
        GameTestDataFactory.createPlayer('rest-feedback-player', 'google');
    }

    @IsTest
    static void testSubmitFeedbackReturnsSuccess() {
        GameTestDataFactory.prepareRestContext(
            'POST',
            '/services/apexrest/game/feedback',
            '{"playerId":"rest-feedback-player","mode":"Timer Attack","feedbackCategory":"IA lenta","feedbackComment":"Tudo certo","source":"post_match"}'
        );

        Test.startTest();
        GameFeedbackRest.submitFeedback();
        Test.stopTest();

        Map<String, Object> body = GameTestDataFactory.readRestBody();
        System.assertEquals(true, body.get('success'));
        System.assert(((Map<String, Object>) body.get('data')).containsKey('caseId'));
    }

    @IsTest
    static void testCommentTooLargeReturnsError() {
        String longComment = GameTestDataFactory.buildRepeatedString('x', GameConstants.MAX_COMMENT_LENGTH + 1);
        GameTestDataFactory.prepareRestContext(
            'POST',
            '/services/apexrest/game/feedback',
            '{"playerId":"rest-feedback-player","feedbackCategory":"Erro / Bug","feedbackComment":"' + longComment + '"}'
        );

        GameFeedbackRest.submitFeedback();
        Map<String, Object> body = GameTestDataFactory.readRestBody();
        System.assertEquals(false, body.get('success'));
        System.assertEquals(GameConstants.ERROR_TEXT_TOO_LARGE, body.get('errorCode'));
    }
}
