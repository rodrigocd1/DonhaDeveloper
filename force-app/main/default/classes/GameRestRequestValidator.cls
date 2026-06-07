public with sharing class GameRestRequestValidator {
    public static void ensureMethod(String expectedMethod) {
        String currentMethod = RestContext.request == null ? null : RestContext.request.httpMethod;
        if (currentMethod != expectedMethod) {
            throw new GameRestException(
                GameConstants.ERROR_BAD_REQUEST,
                'Metodo HTTP nao suportado para este endpoint.',
                405
            );
        }
    }

    public static Map<String, Object> requireBodyAsMap() {
        if (RestContext.request == null || RestContext.request.requestBody == null) {
            throw new GameRestException(
                GameConstants.ERROR_BAD_REQUEST,
                'O payload da requisicao e obrigatorio.',
                400
            );
        }

        String body = RestContext.request.requestBody.toString();
        if (String.isBlank(body)) {
            throw new GameRestException(
                GameConstants.ERROR_BAD_REQUEST,
                'O payload da requisicao e obrigatorio.',
                400
            );
        }

        if (body.length() > GameConstants.MAX_REQUEST_BODY_LENGTH) {
            throw new GameRestException(
                GameConstants.ERROR_PAYLOAD_TOO_LARGE,
                'O payload excede o tamanho permitido.',
                413
            );
        }

        return GameJsonUtil.parseObject(body);
    }

    public static String requireQueryParam(String paramName) {
        String value = RestContext.request == null ? null : RestContext.request.params.get(paramName);
        if (String.isBlank(value)) {
            throw new GameRestException(
                GameConstants.ERROR_REQUIRED_FIELD,
                paramName + ' e obrigatorio.',
                400
            );
        }
        return value;
    }

    public static void requireValue(Boolean condition, String errorCode, String message) {
        if (!condition) {
            throw new GameRestException(errorCode, message, 400);
        }
    }
}
