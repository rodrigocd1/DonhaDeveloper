public with sharing class GameSecurityUtil {
    public static String sanitizeText(String value, Integer maxLength) {
        if (String.isBlank(value)) {
            return null;
        }

        String sanitized = value.replaceAll('[\\x00-\\x08\\x0B\\x0C\\x0E-\\x1F]', ' ');
        sanitized = sanitized.trim();
        sanitized = sanitized.replaceAll('\\s+', ' ');

        if (sanitized.length() > maxLength) {
            throw new GameRestException(
                GameConstants.ERROR_TEXT_TOO_LARGE,
                'Um dos campos de texto excede o tamanho permitido.',
                400
            );
        }

        return sanitized;
    }

    public static String sanitizeMultilineText(String value, Integer maxLength) {
        if (String.isBlank(value)) {
            return null;
        }

        String sanitized = value.replaceAll('[\\x00-\\x08\\x0B\\x0C\\x0E-\\x1F]', ' ');
        sanitized = sanitized.trim();

        if (sanitized.length() > maxLength) {
            throw new GameRestException(
                GameConstants.ERROR_TEXT_TOO_LARGE,
                'Um dos campos de texto excede o tamanho permitido.',
                400
            );
        }

        return sanitized;
    }

    public static String normalizeCode(String code) {
        if (String.isBlank(code)) {
            return null;
        }
        return code.trim().toUpperCase();
    }

    public static String requireSafePlayerId(String playerId) {
        String sanitized = sanitizeText(playerId, GameConstants.MAX_PLAYER_ID_LENGTH);
        if (String.isBlank(sanitized)) {
            throw new GameRestException(
                GameConstants.ERROR_REQUIRED_FIELD,
                'playerId e obrigatorio.',
                400
            );
        }

        if (!Pattern.matches('^[A-Za-z0-9@._:-]+$', sanitized)) {
            throw new GameRestException(
                GameConstants.ERROR_INVALID_PLAYER_ID,
                'playerId contem caracteres nao permitidos.',
                400
            );
        }

        return sanitized;
    }

    public static String hashSha256(String value) {
        Blob input = Blob.valueOf(value == null ? '' : value);
        return EncodingUtil.convertToHex(Crypto.generateDigest('SHA-256', input));
    }

    public static String generateRequestId() {
        Blob source = Blob.valueOf(String.valueOf(System.now().getTime()) + ':' + String.valueOf(Crypto.getRandomLong()));
        return EncodingUtil.convertToHex(Crypto.generateDigest('MD5', source)).substring(0, 12);
    }

    public static void logError(String operationName, Exception ex, String requestId) {
        System.debug(
            LoggingLevel.ERROR,
            '[Game][' + requestId + '][' + operationName + '] ' + ex.getMessage()
        );
    }

    public static String pickFirstAllowedValue(Schema.DescribeFieldResult fieldDescribe, String preferredValue, String fallbackValue) {
        List<Schema.PicklistEntry> values = fieldDescribe.getPicklistValues();
        String activeFallback = null;

        for (Schema.PicklistEntry entry : values) {
            if (!entry.isActive()) {
                continue;
            }
            if (entry.getValue() == preferredValue) {
                return preferredValue;
            }
            if (activeFallback == null && entry.getValue() == fallbackValue) {
                activeFallback = fallbackValue;
            }
            if (activeFallback == null) {
                activeFallback = entry.getValue();
            }
        }

        return activeFallback;
    }
}
