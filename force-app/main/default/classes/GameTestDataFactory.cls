@IsTest
public class GameTestDataFactory {
    public static void createDefaultGameConfig() {
        GameConfigService.resetCache();
        insert new Account(
            Name = GameConstants.GAME_CONFIG_ACCOUNT_NAME,
            Game_Player_Id__c = GameConstants.GAME_CONFIG_ACCOUNT_NAME,
            Game_Config_JSON__c = JSON.serialize(new Map<String, Object>{
                'betaServerUrl' => 'https://dbm-beta.myftp.biz',
                'ddnsHostname' => 'dbm-beta.myftp.biz',
                'x1BetaEnabled' => false,
                'x1ComingSoonEnabled' => true,
                'minimumAppVersion' => '0.01.53',
                'rewardCodesEnabled' => true,
                'bannerAdsEnabled' => true,
                'shopBannerEnabled' => true,
                'stageMapBannerEnabled' => true,
                'profileBannerEnabled' => true,
                'feedbackBannerEnabled' => false,
                'salesforceFeedbackEnabled' => true,
                'labModeEnabled' => true,
                'timerAttackEnabled' => true,
                'nervesOfSteelEnabled' => true,
                'rankedEnabled' => true,
                'maintenanceMode' => false,
                'maintenanceMessage' => '',
                'rewardCodes' => new List<Object>{
                    new Map<String, Object>{
                        'code' => GameConstants.REWARD_CODE_PUTZFORCE,
                        'active' => true,
                        'neverExpires' => true,
                        'requiresLogin' => true,
                        'maxRedemptionsPerAccount' => 1,
                        'reward' => new Map<String, Object>{
                            'energy' => 5,
                            'masterTips' => 1,
                            'freeRetries' => 1
                        }
                    }
                }
            })
        );
        GameConfigService.resetCache();
    }

    public static Account createPlayer(String playerId, String provider) {
        Account player = new Account(
            Name = 'Player ' + playerId,
            Game_Player_Id__c = playerId,
            Game_Display_Name__c = 'Player ' + playerId,
            Game_Login_Provider__c = provider,
            Game_Rewards_JSON__c = '{"redeemedCodes":[]}'
        );
        insert player;
        return player;
    }

    public static void prepareRestContext(String method, String requestUri, String body) {
        RestRequest request = new RestRequest();
        request.httpMethod = method;
        request.requestUri = requestUri;
        if (body != null) {
            request.requestBody = Blob.valueOf(body);
        }

        RestContext.request = request;
        RestContext.response = new RestResponse();
    }

    public static Map<String, Object> readRestBody() {
        return (Map<String, Object>) JSON.deserializeUntyped(
            RestContext.response.responseBody.toString()
        );
    }

    public static String buildRepeatedString(String seed, Integer size) {
        String output = '';
        while (output.length() < size) {
            output += seed;
        }
        return output.substring(0, size);
    }
}
