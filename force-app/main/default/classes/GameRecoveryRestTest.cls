@IsTest
private class GameRecoveryRestTest {
    @testSetup
    static void setup() {
        GameTestDataFactory.createDefaultGameConfig();
        GameTestDataFactory.createPlayer('rest-recovery-player', 'google');
    }

    @IsTest
    static void testProcessRecoverySuccess() {
        GameTestDataFactory.prepareRestContext(
            'POST',
            '/services/apexrest/game/recovery',
            '{"operation":"registerHash","playerId":"rest-recovery-player","recoveryHash":"hash-value"}'
        );

        Test.startTest();
        GameRecoveryRest.processRecovery();
        Test.stopTest();

        Map<String, Object> body = GameTestDataFactory.readRestBody();
        System.assertEquals(true, body.get('success'));
        System.assertEquals(true, ((Map<String, Object>) body.get('data')).get('updated'));
    }

    @IsTest
    static void testInvalidOperationResponse() {
        GameTestDataFactory.prepareRestContext(
            'POST',
            '/services/apexrest/game/recovery',
            '{"operation":"unknown","playerId":"rest-recovery-player","recoveryHash":"hash-value"}'
        );

        GameRecoveryRest.processRecovery();
        Map<String, Object> body = GameTestDataFactory.readRestBody();
        System.assertEquals(false, body.get('success'));
        System.assertEquals(GameConstants.ERROR_INVALID_OPERATION, body.get('errorCode'));
    }
}
