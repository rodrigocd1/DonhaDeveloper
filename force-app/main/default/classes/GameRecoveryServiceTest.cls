@IsTest
private class GameRecoveryServiceTest {
    @testSetup
    static void setup() {
        GameTestDataFactory.createDefaultGameConfig();
        GameTestDataFactory.createPlayer('recovery-player', 'google');
    }

    @IsTest
    static void testRegisterRecoveryHash() {
        Map<String, Object> payload = new Map<String, Object>{
            'operation' => GameConstants.OPERATION_REGISTER_HASH,
            'playerId' => 'recovery-player',
            'recoveryHash' => 'hash-value'
        };

        Test.startTest();
        Map<String, Object> result = GameRecoveryService.process(payload);
        Test.stopTest();

        Account player = [SELECT Game_Recovery_Hash__c, Game_Recovery_Code_Created_At__c FROM Account WHERE Game_Player_Id__c = 'recovery-player' LIMIT 1];
        System.assertEquals(true, result.get('updated'));
        System.assertEquals('hash-value', player.Game_Recovery_Hash__c);
        System.assertNotEquals(null, player.Game_Recovery_Code_Created_At__c);
    }

    @IsTest
    static void testRegenerateRecoveryHash() {
        update new Account(
            Id = [SELECT Id FROM Account WHERE Game_Player_Id__c = 'recovery-player' LIMIT 1].Id,
            Game_Recovery_Hash__c = 'old-hash'
        );

        Map<String, Object> payload = new Map<String, Object>{
            'operation' => GameConstants.OPERATION_REGENERATE_HASH,
            'playerId' => 'recovery-player',
            'recoveryCode' => 'DBM8XQ7M2PL9A4ZK6TNY3RW5CJV'
        };

        Test.startTest();
        GameRecoveryService.process(payload);
        Test.stopTest();

        Account player = [SELECT Game_Recovery_Hash__c FROM Account WHERE Game_Player_Id__c = 'recovery-player' LIMIT 1];
        System.assertNotEquals('old-hash', player.Game_Recovery_Hash__c);
    }

    @IsTest
    static void testValidateRecoveryHash() {
        update new Account(
            Id = [SELECT Id FROM Account WHERE Game_Player_Id__c = 'recovery-player' LIMIT 1].Id,
            Game_Recovery_Hash__c = 'hash-value'
        );

        Map<String, Object> payload = new Map<String, Object>{
            'operation' => GameConstants.OPERATION_VALIDATE_HASH,
            'playerId' => 'recovery-player',
            'recoveryHash' => 'hash-value'
        };

        Map<String, Object> result = GameRecoveryService.process(payload);
        System.assertEquals(true, result.get('valid'));
    }
}
