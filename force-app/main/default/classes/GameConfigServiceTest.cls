@IsTest
private class GameConfigServiceTest {
    @testSetup
    static void setup() {
        GameTestDataFactory.createDefaultGameConfig();
    }

    @IsTest
    static void testReturnsStoredConfig() {
        GameConfigService.resetCache();

        Test.startTest();
        Map<String, Object> config = GameConfigService.getPublicConfig();
        Test.stopTest();

        System.assertEquals('https://dbm-beta.myftp.biz', config.get('betaServerUrl'));
        System.assertEquals(true, config.get('rewardCodesEnabled'));
    }

    @IsTest
    static void testReturnsDefaultConfigWhenMissing() {
        delete [SELECT Id FROM Account WHERE Name = :GameConstants.GAME_CONFIG_ACCOUNT_NAME];
        GameConfigService.resetCache();

        Map<String, Object> config = GameConfigService.getPublicConfig();
        System.assertEquals(false, config.get('maintenanceMode'));
        System.assertEquals('0.01.53', config.get('minimumAppVersion'));
    }
}
