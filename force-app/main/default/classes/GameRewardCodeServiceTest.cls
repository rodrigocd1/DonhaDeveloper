@IsTest
private class GameRewardCodeServiceTest {
    @testSetup
    static void setup() {
        GameTestDataFactory.createDefaultGameConfig();
        GameTestDataFactory.createPlayer('reward-player', 'google');
        GameTestDataFactory.createPlayer('guest-player', 'guest');
    }

    @IsTest
    static void testRedeemPutzforce() {
        Test.startTest();
        Map<String, Object> response = GameRewardCodeService.redeemCode('reward-player', 'PUTZFORCE');
        Test.stopTest();

        Account player = [SELECT Game_Rewards_JSON__c FROM Account WHERE Game_Player_Id__c = 'reward-player' LIMIT 1];
        System.assert(((String) response.get('message')).contains('sucesso'));
        System.assert(player.Game_Rewards_JSON__c.contains('PUTZFORCE'));
    }

    @IsTest
    static void testPreventDuplicateRedemption() {
        GameRewardCodeService.redeemCode('reward-player', 'PUTZFORCE');

        try {
            GameRewardCodeService.redeemCode('reward-player', 'PUTZFORCE');
            System.assert(false, 'Expected duplicate redemption error.');
        } catch (GameRestException ex) {
            System.assertEquals(GameConstants.ERROR_CODE_ALREADY_REDEEMED, ex.errorCode);
        }
    }

    @IsTest
    static void testRequireLoginWhenRewardNeedsIt() {
        try {
            GameRewardCodeService.redeemCode('guest-player', 'PUTZFORCE');
            System.assert(false, 'Expected login required error.');
        } catch (GameRestException ex) {
            System.assertEquals(GameConstants.ERROR_LOGIN_REQUIRED, ex.errorCode);
        }
    }
}
