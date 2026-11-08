public with sharing class CommunicatorExternalApiErrorService {

    public class ApiException extends Exception {
        public String code;
        public Integer statusCode;
        public String action;
        public String example;
        public List<String> details;

        public ApiException(String code, String message, Integer statusCode) {
            super.setMessage(message);
            this.code = code;
            this.statusCode = statusCode;
        }
    }

    public static ApiException badRequest(String code, String message) {
        return new ApiException(code, message, 400);
    }

    public static ApiException unauthorized(String code, String message) {
        return new ApiException(code, message, 401);
    }

    public static ApiException forbidden(String code, String message) {
        return new ApiException(code, message, 403);
    }

    public static ApiException notFound(String code, String message) {
        return new ApiException(code, message, 404);
    }

    public static ApiException methodNotAllowed(String code, String message) {
        return new ApiException(code, message, 405);
    }

    public static ApiException conflict(String code, String message) {
        return new ApiException(code, message, 409);
    }

    public static ApiException unprocessable(String code, String message) {
        return new ApiException(code, message, 422);
    }

    public static ApiException internal(String code, String message) {
        return new ApiException(code, message, 500);
    }

    public static CommunicatorExternalApiDTOs.ApiResponseDTO buildErrorResponse(
        String code,
        String message,
        String action,
        String example,
        List<String> details
    ) {
        CommunicatorExternalApiDTOs.ApiResponseDTO response =
            new CommunicatorExternalApiDTOs.ApiResponseDTO();
        response.success = false;
        response.error = new CommunicatorExternalApiDTOs.ErrorDTO();
        response.error.code = code;
        response.error.message = message;
        response.error.action = action;
        response.error.example = example;
        response.error.details = details;
        return response;
    }
}