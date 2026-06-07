public with sharing class GameConfigService {
    @TestVisible
    private static Boolean configLoaded = false;

    @TestVisible
    private static Account cachedGameConfigAccount;

    @TestVisible
    private static Map<String, Object> cachedResolvedConfig;

    public static Map<String, Object> getPublicConfig() {
        Map<String, Object> publicConfig = new Map<String, Object>();
        Map<String, Object> resolvedConfig = getResolvedConfig();

        for (String key : GameConstants.PUBLIC_CONFIG_KEYS) {
            if (resolvedConfig.containsKey(key)) {
                publicConfig.put(key, resolvedConfig.get(key));
            }
        }

        return publicConfig;
    }

    public static Map<String, Object> getResolvedConfig() {
        if (cachedResolvedConfig != null) {
            return cachedResolvedConfig;
        }

        Map<String, Object> resolvedConfig = buildDefaultConfig();
        Account configAccount = getGameConfigAccount();
        if (configAccount == null) {
            cachedResolvedConfig = resolvedConfig;
            return cachedResolvedConfig;
        }

        String rawConfig = String.isNotBlank(configAccount.Game_Config_JSON__c)
            ? configAccount.Game_Config_JSON__c
            : configAccount.Game_Profile_JSON__c;

        Object parsed = GameJsonUtil.deserializeUntypedSafe(rawConfig);
        if (parsed instanceof Map<String, Object>) {
            mergeSupportedKeys(resolvedConfig, (Map<String, Object>) parsed);
        }

        cachedResolvedConfig = resolvedConfig;
        return cachedResolvedConfig;
    }

    public static Map<String, Object> findRewardCode(String normalizedCode) {
        if (String.isBlank(normalizedCode)) {
            return null;
        }

        List<Object> rewardCodes = GameJsonUtil.toList(getResolvedConfig().get('rewardCodes'));
        for (Object item : rewardCodes) {
            Map<String, Object> rewardCode = GameJsonUtil.toMap(item);
            if (normalizedCode == GameSecurityUtil.normalizeCode(GameJsonUtil.toStringValue(rewardCode.get('code')))) {
                return rewardCode;
            }
        }

        return null;
    }

    public static Boolean areRewardCodesEnabled() {
        Object value = getResolvedConfig().get('rewardCodesEnabled');
        return value == null ? true : (Boolean) value;
    }

    public static Account getGameConfigAccount() {
        if (configLoaded) {
            return cachedGameConfigAccount;
        }

        List<Account> records = [
            SELECT Id, Name, Game_Player_Id__c, Game_Config_JSON__c, Game_Profile_JSON__c
            FROM Account
            WHERE Name = :GameConstants.GAME_CONFIG_ACCOUNT_NAME
               OR Game_Player_Id__c = :GameConstants.GAME_CONFIG_ACCOUNT_NAME
            ORDER BY LastModifiedDate DESC
            LIMIT 1
        ];

        cachedGameConfigAccount = records.isEmpty() ? null : records[0];
        configLoaded = true;
        return cachedGameConfigAccount;
    }

    @TestVisible
    static void resetCache() {
        configLoaded = false;
        cachedGameConfigAccount = null;
        cachedResolvedConfig = null;
    }

    private static Map<String, Object> buildDefaultConfig() {
        Map<String, Object> config = new Map<String, Object>{
            'betaServerUrl' => '',
            'ddnsHostname' => '',
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
            'maintenanceMessage' => ''
        };
        config.put('rewardCodes', buildDefaultRewardCodes());
        return config;
    }

    private static List<Object> buildDefaultRewardCodes() {
        return new List<Object>{
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
        };
    }

    private static void mergeSupportedKeys(Map<String, Object> targetConfig, Map<String, Object> sourceConfig) {
        for (String key : GameConstants.PUBLIC_CONFIG_KEYS) {
            if (sourceConfig.containsKey(key)) {
                targetConfig.put(key, sourceConfig.get(key));
            }
        }

        if (sourceConfig.containsKey('rewardCodes') && sourceConfig.get('rewardCodes') instanceof List<Object>) {
            targetConfig.put('rewardCodes', sourceConfig.get('rewardCodes'));
        }
    }
}
