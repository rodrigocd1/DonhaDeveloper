public with sharing class GameJsonUtil {
    public static Map<String, Object> parseObject(String jsonText) {
        if (String.isBlank(jsonText)) {
            return new Map<String, Object>();
        }

        Object parsed;
        try {
            parsed = JSON.deserializeUntyped(jsonText);
        } catch (Exception ex) {
            throw new GameRestException(
                GameConstants.ERROR_INVALID_JSON,
                'O payload JSON esta invalido.',
                400
            );
        }

        if (!(parsed instanceof Map<String, Object>)) {
            throw new GameRestException(
                GameConstants.ERROR_INVALID_JSON,
                'O payload precisa ser um objeto JSON.',
                400
            );
        }

        return (Map<String, Object>) parsed;
    }

    public static String serializeLimited(Object value, Integer maxLength) {
        if (value == null) {
            return null;
        }

        String serialized = (value instanceof String)
            ? (String) value
            : JSON.serialize(value);

        if (serialized.length() > maxLength) {
            throw new GameRestException(
                GameConstants.ERROR_JSON_TOO_LARGE,
                'Um dos campos JSON excede o tamanho permitido.',
                400
            );
        }

        return serialized;
    }

    public static Object deserializeUntypedSafe(String jsonText) {
        if (String.isBlank(jsonText)) {
            return null;
        }

        try {
            return JSON.deserializeUntyped(jsonText);
        } catch (Exception ex) {
            return null;
        }
    }

    public static Decimal toDecimal(Object value) {
        if (value == null) {
            return null;
        }
        if (value instanceof Decimal) {
            return (Decimal) value;
        }
        if (value instanceof Integer) {
            return Decimal.valueOf(String.valueOf(value));
        }
        if (value instanceof Long) {
            return Decimal.valueOf(String.valueOf(value));
        }
        if (value instanceof Double) {
            return Decimal.valueOf(String.valueOf(value));
        }
        if (value instanceof String && String.isNotBlank((String) value)) {
            return Decimal.valueOf(((String) value).trim());
        }
        return null;
    }

    public static Integer toInteger(Object value) {
        Decimal decimalValue = toDecimal(value);
        return decimalValue == null ? null : decimalValue.intValue();
    }

    public static String toStringValue(Object value) {
        if (value == null) {
            return null;
        }
        return String.valueOf(value);
    }

    public static Map<String, Object> toMap(Object value) {
        return (value instanceof Map<String, Object>)
            ? (Map<String, Object>) value
            : new Map<String, Object>();
    }

    public static List<Object> toList(Object value) {
        return (value instanceof List<Object>)
            ? (List<Object>) value
            : new List<Object>();
    }
}
