public with sharing class GameRecoveryService {
    public static Map<String, Object> process(Map<String, Object> payload) {
        String operation = GameSecurityUtil.sanitizeText(
            GameJsonUtil.toStringValue(payload.get('operation')),
            GameConstants.MAX_PROVIDER_LENGTH
        );
        if (String.isBlank(operation)) {
            throw new GameRestException(
                GameConstants.ERROR_REQUIRED_FIELD,
                'operation e obrigatorio.',
                400
            );
        }

        String playerId = GameSecurityUtil.requireSafePlayerId(
            GameJsonUtil.toStringValue(payload.get('playerId'))
        );
        Account player = GameAccountService.requirePlayer(playerId);

        if (operation == GameConstants.OPERATION_REGISTER_HASH) {
            return registerOrReplaceHash(player, payload, false);
        }
        if (operation == GameConstants.OPERATION_VALIDATE_HASH) {
            return validateHash(player, payload);
        }
        if (operation == GameConstants.OPERATION_REGENERATE_HASH) {
            return registerOrReplaceHash(player, payload, true);
        }

        throw new GameRestException(
            GameConstants.ERROR_INVALID_OPERATION,
            'Operacao de recovery invalida.',
            400
        );
    }

    private static Map<String, Object> registerOrReplaceHash(Account player, Map<String, Object> payload, Boolean isRegeneration) {
        String incomingHash = resolveIncomingHash(payload);
        update new Account(
            Id = player.Id,
            Game_Recovery_Hash__c = incomingHash,
            Game_Recovery_Code_Created_At__c = System.now()
        );

        return new Map<String, Object>{
            'operation' => isRegeneration ? GameConstants.OPERATION_REGENERATE_HASH : GameConstants.OPERATION_REGISTER_HASH,
            'updated' => true
        };
    }

    private static Map<String, Object> validateHash(Account player, Map<String, Object> payload) {
        String incomingHash = resolveIncomingHash(payload);
        Boolean isValid = String.isNotBlank(player.Game_Recovery_Hash__c)
            && player.Game_Recovery_Hash__c == incomingHash;

        return new Map<String, Object>{
            'operation' => GameConstants.OPERATION_VALIDATE_HASH,
            'valid' => isValid,
            'hasRecoveryHash' => String.isNotBlank(player.Game_Recovery_Hash__c)
        };
    }

    private static String resolveIncomingHash(Map<String, Object> payload) {
        String recoveryHash = GameSecurityUtil.sanitizeText(
            GameJsonUtil.toStringValue(payload.get('recoveryHash')),
            GameConstants.MAX_EXTERNAL_ID_LENGTH
        );
        if (String.isNotBlank(recoveryHash)) {
            return recoveryHash;
        }

        String recoveryCode = GameSecurityUtil.sanitizeText(
            GameJsonUtil.toStringValue(payload.get('recoveryCode')),
            GameConstants.MAX_EXTERNAL_ID_LENGTH
        );
        if (String.isNotBlank(recoveryCode)) {
            return GameSecurityUtil.hashSha256(recoveryCode);
        }

        throw new GameRestException(
            GameConstants.ERROR_RECOVERY_HASH_REQUIRED,
            'recoveryHash ou recoveryCode e obrigatorio.',
            400
        );
    }
}
