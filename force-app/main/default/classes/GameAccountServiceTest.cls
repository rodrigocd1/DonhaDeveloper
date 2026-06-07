@IsTest
private class GameAccountServiceTest {
    @testSetup
    static void setup() {
        GameTestDataFactory.createDefaultGameConfig();
    }

    @IsTest
    static void testCreatePlayer() {
        Map<String, Object> payload = new Map<String, Object>{
            'playerId' => 'abc123',
            'displayName' => 'Rodrigo',
            'loginProvider' => 'google',
            'googleId' => 'google-sub',
            'deviceId' => 'device-id',
            'profile' => new Map<String, Object>{ 'level' => 10 },
            'progress' => new Map<String, Object>{ 'stage' => 3 },
            'rewards' => new Map<String, Object>{ 'coins' => 5 }
        };

        Test.startTest();
        Map<String, Object> response = GameAccountService.upsertPlayer(payload);
        Test.stopTest();

        Account player = [SELECT Game_Display_Name__c, Game_Login_Provider__c, Game_Google_Id__c FROM Account WHERE Game_Player_Id__c = 'abc123' LIMIT 1];
        System.assertEquals('Rodrigo', player.Game_Display_Name__c);
        System.assertEquals('google', player.Game_Login_Provider__c);
        System.assertEquals('google-sub', player.Game_Google_Id__c);
        System.assertEquals('Rodrigo', response.get('displayName'));
    }

    @IsTest
    static void testUpdatePlayer() {
        GameTestDataFactory.createPlayer('player-update', 'guest');

        Map<String, Object> payload = new Map<String, Object>{
            'playerId' => 'player-update',
            'displayName' => 'Player Updated',
            'loginProvider' => 'google',
            'progress' => new Map<String, Object>{ 'stage' => 12 }
        };

        Test.startTest();
        Map<String, Object> response = GameAccountService.upsertPlayer(payload);
        Test.stopTest();

        Account player = [SELECT Game_Display_Name__c, Game_Login_Provider__c, Game_Progress_JSON__c, Game_Last_Login_At__c FROM Account WHERE Game_Player_Id__c = 'player-update' LIMIT 1];
        System.assertEquals('Player Updated', player.Game_Display_Name__c);
        System.assertEquals('google', player.Game_Login_Provider__c);
        System.assertNotEquals(null, player.Game_Last_Login_At__c);
        System.assertEquals('google', response.get('loginProvider'));
    }
}
