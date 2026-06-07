public with sharing class GameRestResponse {
    public static void writeSuccess(Map<String, Object> data) {
        Map<String, Object> payload = new Map<String, Object>{ 'success' => true };
        if (data != null) {
            payload.putAll(data);
        }
        write(200, payload);
    }

    public static void writeError(GameRestException ex) {
        Map<String, Object> payload = new Map<String, Object>{
            'success' => false,
            'errorCode' => ex.errorCode,
            'message' => ex.userMessage
        };
        write(ex.statusCode, payload);
    }

    public static void writeUnexpectedError(String operationName, Exception ex) {
        String requestId = GameSecurityUtil.generateRequestId();
        GameSecurityUtil.logError(operationName, ex, requestId);

        Map<String, Object> payload = new Map<String, Object>{
            'success' => false,
            'errorCode' => GameConstants.ERROR_UNEXPECTED,
            'message' => 'Ocorreu um erro inesperado.',
            'requestId' => requestId
        };
        write(500, payload);
    }

    private static void write(Integer statusCode, Map<String, Object> payload) {
        if (RestContext.response == null) {
            RestContext.response = new RestResponse();
        }

        RestContext.response.statusCode = statusCode;
        RestContext.response.addHeader('Content-Type', 'application/json');
        RestContext.response.responseBody = Blob.valueOf(JSON.serialize(payload));
    }
}
