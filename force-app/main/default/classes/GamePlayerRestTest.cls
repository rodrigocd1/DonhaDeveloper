@IsTest
private class GamePlayerRestTest {
    @testSetup
    static void setup() {
        GameTestDataFactory.createDefaultGameConfig();
    }

    @IsTest
    static void testPostCreatesPlayerAndGetReturnsPlayer() {
        GameTestDataFactory.prepareRestContext(
            'POST',
            '/services/apexrest/game/player',
            '{"playerId":"rest-player","displayName":"Rest Player","loginProvider":"google","profile":{"level":1}}'
        );

        Test.startTest();
        GamePlayerRest.upsertPlayer();
        Test.stopTest();

        Map<String, Object> postBody = GameTestDataFactory.readRestBody();
        System.assertEquals(true, postBody.get('success'));

        GameTestDataFactory.prepareRestContext('GET', '/services/apexrest/game/player', null);
        RestContext.request.addParameter('playerId', 'rest-player');
        GamePlayerRest.getPlayer();

        Map<String, Object> getBody = GameTestDataFactory.readRestBody();
        System.assertEquals(true, getBody.get('success'));
        System.assertEquals('rest-player', ((Map<String, Object>) getBody.get('player')).get('playerId'));
    }

    @IsTest
    static void testInvalidJsonReturnsError() {
        GameTestDataFactory.prepareRestContext(
            'POST',
            '/services/apexrest/game/player',
            '{"playerId":"broken"'
        );

        GamePlayerRest.upsertPlayer();
        Map<String, Object> body = GameTestDataFactory.readRestBody();
        System.assertEquals(false, body.get('success'));
        System.assertEquals(GameConstants.ERROR_INVALID_JSON, body.get('errorCode'));
    }

    @IsTest
    static void testPayloadTooLargeReturnsError() {
        String oversized = '{"playerId":"big","profile":"' + GameTestDataFactory.buildRepeatedString('x', 100001) + '"}';
        GameTestDataFactory.prepareRestContext(
            'POST',
            '/services/apexrest/game/player',
            oversized
        );

        GamePlayerRest.upsertPlayer();
        Map<String, Object> body = GameTestDataFactory.readRestBody();
        System.assertEquals(false, body.get('success'));
        System.assertEquals(GameConstants.ERROR_PAYLOAD_TOO_LARGE, body.get('errorCode'));
    }
}
