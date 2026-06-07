public with sharing class GameRewardCodeService {
    public static Map<String, Object> redeemCode(String playerId, String code) {
        if (!GameConfigService.areRewardCodesEnabled()) {
            throw new GameRestException(
                GameConstants.ERROR_REWARD_CODES_DISABLED,
                'Os codigos de recompensa estao desabilitados.',
                403
            );
        }

        String normalizedCode = GameSecurityUtil.normalizeCode(code);
        if (String.isBlank(normalizedCode)) {
            throw new GameRestException(
                GameConstants.ERROR_REQUIRED_FIELD,
                'code e obrigatorio.',
                400
            );
        }

        Map<String, Object> rewardCode = GameConfigService.findRewardCode(normalizedCode);
        if (rewardCode == null || rewardCode.get('active') == false) {
            throw new GameRestException(
                GameConstants.ERROR_INVALID_REWARD_CODE,
                'Codigo de recompensa invalido ou inativo.',
                400
            );
        }

        Account player = resolvePlayerForRedemption(playerId, rewardCode);
        Map<String, Object> reward = GameJsonUtil.toMap(rewardCode.get('reward'));
        Map<String, Object> rewardsState = GameJsonUtil.toMap(
            GameJsonUtil.deserializeUntypedSafe(player.Game_Rewards_JSON__c)
        );
        List<Object> redeemedCodes = rewardsState.containsKey('redeemedCodes')
            ? GameJsonUtil.toList(rewardsState.get('redeemedCodes'))
            : new List<Object>();

        Integer maxRedemptions = GameJsonUtil.toInteger(rewardCode.get('maxRedemptionsPerAccount'));
        maxRedemptions = maxRedemptions == null || maxRedemptions <= 0 ? 1 : maxRedemptions;

        Integer redemptionCount = countRedemptions(redeemedCodes, normalizedCode);
        if (redemptionCount >= maxRedemptions) {
            throw new GameRestException(
                GameConstants.ERROR_CODE_ALREADY_REDEEMED,
                'Esse codigo ja foi usado nesta conta.',
                409
            );
        }

        redeemedCodes.add(new Map<String, Object>{
            'code' => normalizedCode,
            'redeemedAt' => System.now().formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\''),
            'reward' => reward
        });
        rewardsState.put('redeemedCodes', redeemedCodes);

        update new Account(
            Id = player.Id,
            Game_Rewards_JSON__c = GameJsonUtil.serializeLimited(rewardsState, GameConstants.MAX_JSON_FIELD_LENGTH)
        );

        return new Map<String, Object>{
            'message' => 'Codigo resgatado com sucesso.',
            'reward' => reward
        };
    }

    private static Account resolvePlayerForRedemption(String playerId, Map<String, Object> rewardCode) {
        Boolean requiresLogin = rewardCode.get('requiresLogin') == null ? true : (Boolean) rewardCode.get('requiresLogin');
        if (String.isBlank(playerId)) {
            throw new GameRestException(
                requiresLogin ? GameConstants.ERROR_LOGIN_REQUIRED : GameConstants.ERROR_REQUIRED_FIELD,
                requiresLogin ? 'Faca login para resgatar este codigo.' : 'playerId e obrigatorio.',
                400
            );
        }

        Account player = GameAccountService.requirePlayer(playerId);
        String provider = String.isBlank(player.Game_Login_Provider__c)
            ? GameConstants.GAME_LOGIN_PROVIDER_GUEST
            : player.Game_Login_Provider__c;

        if (requiresLogin && provider == GameConstants.GAME_LOGIN_PROVIDER_GUEST) {
            throw new GameRestException(
                GameConstants.ERROR_LOGIN_REQUIRED,
                'Faca login para resgatar este codigo.',
                403
            );
        }

        return player;
    }

    private static Integer countRedemptions(List<Object> redeemedCodes, String normalizedCode) {
        Integer count = 0;
        for (Object item : redeemedCodes) {
            Map<String, Object> redeemedCode = GameJsonUtil.toMap(item);
            String currentCode = GameSecurityUtil.normalizeCode(GameJsonUtil.toStringValue(redeemedCode.get('code')));
            if (currentCode == normalizedCode) {
                count++;
            }
        }
        return count;
    }
}
