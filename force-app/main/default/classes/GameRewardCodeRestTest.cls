@IsTest
private class GameRewardCodeRestTest {
    @testSetup
    static void setup() {
        GameTestDataFactory.createDefaultGameConfig();
        GameTestDataFactory.createPlayer('rest-reward-player', 'google');
    }

    @IsTest
    static void testRedeemSuccessResponse() {
        GameTestDataFactory.prepareRestContext(
            'POST',
            '/services/apexrest/game/reward-code',
            '{"playerId":"rest-reward-player","code":"PUTZFORCE"}'
        );

        Test.startTest();
        GameRewardCodeRest.redeemCode();
        Test.stopTest();

        Map<String, Object> body = GameTestDataFactory.readRestBody();
        System.assertEquals(true, body.get('success'));
        System.assert(((Map<String, Object>) body.get('reward')).containsKey('energy'));
    }

    @IsTest
    static void testDuplicateResponse() {
        GameTestDataFactory.prepareRestContext(
            'POST',
            '/services/apexrest/game/reward-code',
            '{"playerId":"rest-reward-player","code":"PUTZFORCE"}'
        );
        GameRewardCodeRest.redeemCode();

        GameTestDataFactory.prepareRestContext(
            'POST',
            '/services/apexrest/game/reward-code',
            '{"playerId":"rest-reward-player","code":"PUTZFORCE"}'
        );
        GameRewardCodeRest.redeemCode();

        Map<String, Object> body = GameTestDataFactory.readRestBody();
        System.assertEquals(false, body.get('success'));
        System.assertEquals(GameConstants.ERROR_CODE_ALREADY_REDEEMED, body.get('errorCode'));
    }
}
