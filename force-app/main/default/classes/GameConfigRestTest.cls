@IsTest
private class GameConfigRestTest {
    @testSetup
    static void setup() {
        GameTestDataFactory.createDefaultGameConfig();
    }

    @IsTest
    static void testGetConfig() {
        GameConfigService.resetCache();
        GameTestDataFactory.prepareRestContext('GET', '/services/apexrest/game/config', null);

        Test.startTest();
        GameConfigRest.getConfig();
        Test.stopTest();

        Map<String, Object> body = GameTestDataFactory.readRestBody();
        System.assertEquals(true, body.get('success'));
        System.assert(((Map<String, Object>) body.get('config')).containsKey('maintenanceMode'));
    }
}
