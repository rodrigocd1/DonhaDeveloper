public with sharing class GameAccountService {
    public static Account findPlayer(String playerId) {
        String safePlayerId = GameSecurityUtil.requireSafePlayerId(playerId);
        List<Account> players = [
            SELECT Id,
                   Name,
                   Game_Player_Id__c,
                   Game_Display_Name__c,
                   Game_Login_Provider__c,
                   Game_Google_Id__c,
                   Game_Apple_Id__c,
                   Game_Steam_Id__c,
                   Game_Profile_JSON__c,
                   Game_Progress_JSON__c,
                   Game_Rewards_JSON__c,
                   Game_Feedback_JSON__c,
                   Game_Recovery_Hash__c,
                   Game_Recovery_Code_Created_At__c,
                   Game_Passe_VIP_Active__c,
                   Game_Passe_VIP_Expires_At__c,
                   Game_Last_Login_At__c,
                   Game_Last_Device_Id__c,
                   Game_Is_Beta_Tester__c,
                   Game_Ranked_Points__c,
                   Game_Ranked_Rank__c,
                   Game_Ranked_JSON__c,
                   Game_Timer_Attack_JSON__c,
                   Game_Nerves_Of_Steel_JSON__c,
                   Game_Use_SSO_Photo_In_Ranking__c
            FROM Account
            WHERE Game_Player_Id__c = :safePlayerId
            ORDER BY LastModifiedDate DESC
            LIMIT 1
        ];
        return players.isEmpty() ? null : players[0];
    }

    public static Account requirePlayer(String playerId) {
        Account player = findPlayer(playerId);
        if (player == null) {
            throw new GameRestException(
                GameConstants.ERROR_PLAYER_NOT_FOUND,
                'Jogador nao encontrado.',
                404
            );
        }
        return player;
    }

    public static Map<String, Object> getPlayerResponse(String playerId) {
        Account player = requirePlayer(playerId);
        return buildPlayerResponse(player);
    }

    public static Map<String, Object> upsertPlayer(Map<String, Object> payload) {
        String playerId = GameSecurityUtil.requireSafePlayerId(GameJsonUtil.toStringValue(payload.get('playerId')));
        Account existingPlayer = findPlayer(playerId);
        Boolean isCreate = existingPlayer == null;

        if (isCreate) {
            Account newPlayer = new Account();
            newPlayer.Name = buildAccountName(GameJsonUtil.toStringValue(payload.get('displayName')), playerId);
            newPlayer.Game_Player_Id__c = playerId;
            applyCoreFields(newPlayer, null, payload, true);
            insert newPlayer;
        } else {
            Account updatePlayer = new Account(Id = existingPlayer.Id);
            Boolean hasChanges = applyCoreFields(updatePlayer, existingPlayer, payload, false);
            updatePlayer.Game_Last_Login_At__c = System.now();
            hasChanges = true;
            if (hasChanges) {
                update updatePlayer;
            }
        }

        return buildPlayerResponse(requirePlayer(playerId));
    }

    public static Map<String, Object> buildPlayerResponse(Account player) {
        Map<String, Object> data = new Map<String, Object>{
            'accountId' => player.Id,
            'playerId' => player.Game_Player_Id__c,
            'displayName' => player.Game_Display_Name__c,
            'loginProvider' => player.Game_Login_Provider__c,
            'googleId' => player.Game_Google_Id__c,
            'appleId' => player.Game_Apple_Id__c,
            'steamId' => player.Game_Steam_Id__c,
            'deviceId' => player.Game_Last_Device_Id__c,
            'profile' => GameJsonUtil.deserializeUntypedSafe(player.Game_Profile_JSON__c),
            'progress' => GameJsonUtil.deserializeUntypedSafe(player.Game_Progress_JSON__c),
            'rewards' => GameJsonUtil.deserializeUntypedSafe(player.Game_Rewards_JSON__c),
            'feedback' => GameJsonUtil.deserializeUntypedSafe(player.Game_Feedback_JSON__c),
            'isBetaTester' => player.Game_Is_Beta_Tester__c,
            'rankedPoints' => player.Game_Ranked_Points__c,
            'rankedRank' => player.Game_Ranked_Rank__c,
            'ranked' => GameJsonUtil.deserializeUntypedSafe(player.Game_Ranked_JSON__c),
            'timerAttack' => GameJsonUtil.deserializeUntypedSafe(player.Game_Timer_Attack_JSON__c),
            'nervesOfSteel' => GameJsonUtil.deserializeUntypedSafe(player.Game_Nerves_Of_Steel_JSON__c),
            'vipActive' => player.Game_Passe_VIP_Active__c,
            'vipExpiresAt' => player.Game_Passe_VIP_Expires_At__c,
            'lastLoginAt' => player.Game_Last_Login_At__c,
            'useSsoPhotoInRanking' => player.Game_Use_SSO_Photo_In_Ranking__c
        };
        return data;
    }

    private static Boolean applyCoreFields(Account targetPlayer, Account currentPlayer, Map<String, Object> payload, Boolean isCreate) {
        Boolean hasChanges = false;

        String displayName = GameSecurityUtil.sanitizeText(
            GameJsonUtil.toStringValue(payload.get('displayName')),
            GameConstants.MAX_DISPLAY_NAME_LENGTH
        );
        String loginProvider = GameSecurityUtil.sanitizeText(
            GameJsonUtil.toStringValue(payload.get('loginProvider')),
            GameConstants.MAX_PROVIDER_LENGTH
        );
        if (isCreate && String.isBlank(loginProvider)) {
            loginProvider = GameConstants.GAME_LOGIN_PROVIDER_GUEST;
        }

        hasChanges = setFieldIfChanged(targetPlayer, 'Name', currentValue(currentPlayer, 'Name'), buildAccountName(displayName, GameJsonUtil.toStringValue(payload.get('playerId')))) || hasChanges;
        hasChanges = setFieldIfChanged(targetPlayer, 'Game_Display_Name__c', currentValue(currentPlayer, 'Game_Display_Name__c'), displayName) || hasChanges;
        hasChanges = setFieldIfChanged(targetPlayer, 'Game_Login_Provider__c', currentValue(currentPlayer, 'Game_Login_Provider__c'), loginProvider) || hasChanges;
        hasChanges = setFieldIfChanged(targetPlayer, 'Game_Google_Id__c', currentValue(currentPlayer, 'Game_Google_Id__c'), sanitizeOptionalText(payload.get('googleId'))) || hasChanges;
        hasChanges = setFieldIfChanged(targetPlayer, 'Game_Apple_Id__c', currentValue(currentPlayer, 'Game_Apple_Id__c'), sanitizeOptionalText(payload.get('appleId'))) || hasChanges;
        hasChanges = setFieldIfChanged(targetPlayer, 'Game_Steam_Id__c', currentValue(currentPlayer, 'Game_Steam_Id__c'), sanitizeOptionalText(payload.get('steamId'))) || hasChanges;
        hasChanges = setFieldIfChanged(targetPlayer, 'Game_Last_Device_Id__c', currentValue(currentPlayer, 'Game_Last_Device_Id__c'), sanitizeDeviceId(payload.get('deviceId'))) || hasChanges;

        if (payload.containsKey('profile')) {
            hasChanges = setFieldIfChanged(targetPlayer, 'Game_Profile_JSON__c', currentValue(currentPlayer, 'Game_Profile_JSON__c'), serializeOptionalJson(payload.get('profile'))) || hasChanges;
        }
        if (payload.containsKey('progress')) {
            hasChanges = setFieldIfChanged(targetPlayer, 'Game_Progress_JSON__c', currentValue(currentPlayer, 'Game_Progress_JSON__c'), serializeOptionalJson(payload.get('progress'))) || hasChanges;
        }
        if (payload.containsKey('rewards')) {
            hasChanges = setFieldIfChanged(targetPlayer, 'Game_Rewards_JSON__c', currentValue(currentPlayer, 'Game_Rewards_JSON__c'), serializeOptionalJson(payload.get('rewards'))) || hasChanges;
        }
        if (payload.containsKey('ranked')) {
            hasChanges = setFieldIfChanged(targetPlayer, 'Game_Ranked_JSON__c', currentValue(currentPlayer, 'Game_Ranked_JSON__c'), serializeOptionalJson(payload.get('ranked'))) || hasChanges;
        }
        if (payload.containsKey('timerAttack')) {
            hasChanges = setFieldIfChanged(targetPlayer, 'Game_Timer_Attack_JSON__c', currentValue(currentPlayer, 'Game_Timer_Attack_JSON__c'), serializeOptionalJson(payload.get('timerAttack'))) || hasChanges;
        }
        if (payload.containsKey('nervesOfSteel')) {
            hasChanges = setFieldIfChanged(targetPlayer, 'Game_Nerves_Of_Steel_JSON__c', currentValue(currentPlayer, 'Game_Nerves_Of_Steel_JSON__c'), serializeOptionalJson(payload.get('nervesOfSteel'))) || hasChanges;
        }

        targetPlayer.Game_Last_Login_At__c = System.now();
        hasChanges = true;
        return hasChanges;
    }

    private static String sanitizeOptionalText(Object value) {
        return GameSecurityUtil.sanitizeText(
            GameJsonUtil.toStringValue(value),
            GameConstants.MAX_EXTERNAL_ID_LENGTH
        );
    }

    private static String sanitizeDeviceId(Object value) {
        return GameSecurityUtil.sanitizeText(
            GameJsonUtil.toStringValue(value),
            GameConstants.MAX_DEVICE_ID_LENGTH
        );
    }

    private static String serializeOptionalJson(Object value) {
        return value == null ? null : GameJsonUtil.serializeLimited(value, GameConstants.MAX_JSON_FIELD_LENGTH);
    }

    private static String buildAccountName(String displayName, String playerId) {
        String baseName = String.isNotBlank(displayName)
            ? displayName
            : 'Player ' + GameSecurityUtil.requireSafePlayerId(playerId);

        if (baseName.length() > GameConstants.MAX_NAME_LENGTH) {
            return baseName.substring(0, GameConstants.MAX_NAME_LENGTH);
        }
        return baseName;
    }

    private static Object currentValue(Account currentPlayer, String fieldApiName) {
        return currentPlayer == null ? null : currentPlayer.get(fieldApiName);
    }

    private static Boolean setFieldIfChanged(SObject targetRecord, String fieldApiName, Object currentValue, Object newValue) {
        if (currentValue == null && newValue == null) {
            return false;
        }
        if (currentValue != null && newValue != null && String.valueOf(currentValue) == String.valueOf(newValue)) {
            return false;
        }
        targetRecord.put(fieldApiName, newValue);
        return true;
    }
}
