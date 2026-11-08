/**
 * @name: RestServiceHelper
 * @scope: public
 * @classification: service
 * @layer: service
 * @category: general
 * @type: service
 * @stack: apex
 * @author: Leo Garcia
 * @lastModified: 2025-05-13 04:52:31
 * @description: RestServiceHelper class
 * @intent: Provides class functionality
 * @dependsOn: [[]]
 * @exposedTo: [[internal]]
 * @tags: []
 * @gpt: []
 */

public abstract class RestServiceHelper {

    @TestVisible public static String  environment       = (EnvironmentUtils.getRaw() != null) ? EnvironmentUtils.getRaw() : 'sandbox';
    @TestVisible public static String  logLevelDefault   = (EnvironmentUtils.getLogLevel() != null) ? EnvironmentUtils.getLogLevel() : 'INFO';
    @TestVisible public static Integer maxDebugLength    = (EnvironmentUtils.getMaxDebugLength() != null ) ? (Integer)EnvironmentUtils.getMaxDebugLength() : 3000;
    private static final String className = 'RestServiceHelper';
    private static final String logCategory = 'REST';

    // ============= SUPORTE A TESTES =============    
    @TestVisible private static String lastExceptionMessage;

    // ============= EXCEÇÕES PERSONALIZADAS =============    
    public class AccessException extends Exception {}
    public class BadRequestException extends Exception {}
    public class NotFoundException extends Exception {}
    public class ConflictException extends Exception {}

    // ============= MÉTODOS DE RESPOSTA SIMPLIFICADOS =============    
    @TestVisible
    public static void unauthorized(String message) {
        sendResponse(401, message);
    }

    @TestVisible
    public static void unauthorized(String message, Object details) {
        sendResponse(401, message, details);
    }

    @TestVisible
    public static void badRequest(String message) {
        sendResponse(400, message);
    }

    @TestVisible
    public static void badRequest(String message, Object details) {
        sendResponse(400, message, details);
    }

    @TestVisible
    public static void notFound(String message) {
        sendResponse(404, message);
    }

    @TestVisible
    public static void notFound(String message, Object details) {
        sendResponse(404, message, details);
    }

    @TestVisible
    public static void notAcceptable(String message) {
        sendResponse(406, message);
    }

    @TestVisible
    public static void notAcceptable(String message, Object details) {
        sendResponse(406, message, details);
    }

    @TestVisible
    public static void internalServerError(String message) {
        sendResponse(500, message);
    }

    @TestVisible
    public static void internalServerError(String message, Object details) {
        sendResponse(500, message, details);
    }

    @TestVisible
    public static void accepted(String message) {
        sendResponse(202, message);
    }

    @TestVisible
    public static void accepted(String message, Object details) {
        sendResponse(202, message, details);
    }

    // ============= MÉTODOS DE RESPOSTA DETALHADOS =============    
    @TestVisible
    public static void sendResponse(Integer statusCode, String message) {
        sendResponse(statusCode, message, null);
    }

    @TestVisible
    public static void sendResponse(Integer statusCode, String message, Object details) {
        RestContext.response.addHeader('Content-Type', 'application/json');
        RestContext.response.statusCode = statusCode;

        Map<String, Object> response = new Map<String, Object> {
            // 'status' => (statusCode >= 200 && statusCode < 300) ? 'success' : 'error', // Aguardando OK do time de API para incluir essa chave padronizada
            'message' => message
        };

        if (details != null) {
            response.put('details', details);
        }

        RestContext.response.responseBody = Blob.valueOf(JSON.serializePretty(response));

        // Log da resposta
        // logResponse(statusCode, message, response);
    }

    @TestVisible
    private static void logResponse(Integer statusCode, String message, Map<String, Object> response) {
        Logger logger = new Logger()
            .setClass(className)
            .setMethod('sendResponse')
            .setCategory(logCategory);
        logger.info('Resposta enviada: ' + message, JSON.serializePretty(response));
    }

    // ============= MÉTODOS DE VALIDAÇÃO =============    
    @TestVisible
    public static void validateAccessToken(String headerName, String expectedTokenPrefix) {
        String accessToken = RestContext.request.headers.get(headerName);
        if (accessToken == null || !accessToken.startsWith(expectedTokenPrefix)) {
            throw new AccessException('Token de acesso inválido ou ausente.');
        }
    }

    @TestVisible
    public static Map<String, Object> getRequestBody() {
        RestRequest req = RestContext.request;
        if (req.requestBody == null || String.isBlank(req.requestBody.toString())) {
            lastExceptionMessage = 'O corpo da requisição está vazio.';
            throw new BadRequestException(lastExceptionMessage);
        }
        try {
            return (Map<String, Object>) JSON.deserializeUntyped(req.requestBody.toString());
        } catch (Exception e) {
            throw new BadRequestException('Erro ao processar o corpo da requisição.');
        }
    }

    // ============= UTILITÁRIO DE MAPEAMENTO SOBJECT =============    
    @TestVisible
    public static void mapFieldsFromRequest(Map<String, Object> requestBody, SObject record, String objectName) {
        Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();
        Schema.SObjectType objectType = globalDescribe.get(objectName.toLowerCase());

        if (objectType == null) {
            throw new IllegalArgumentException('Objeto inválido: ' + objectName);
        }

        Map<String, Schema.SObjectField> fieldMap = objectType.getDescribe().fields.getMap();

        for (String fieldName : requestBody.keySet()) {
            if (fieldMap.containsKey(fieldName)) {
                Object fieldValue = requestBody.get(fieldName);
                if (fieldValue != null) {
                    record.put(fieldName, fieldValue);
                }
            } else {
                // Utilizando Logger para rastrear campos ignorados
                logIgnoredField(fieldName, objectName);
            }
        }
    }

    @TestVisible
    private static void logIgnoredField(String fieldName, String objectName) {
        Logger logger = new Logger()
            .setClass(className)
            .setMethod('mapFieldsFromRequest')
            .setCategory(logCategory);
        logger.warn('Campo ignorado: ' + fieldName + ' (não encontrado no objeto ' + objectName + ')', null);
    }

        /**
     * Decodifica e sanitiza uma resposta JSON (ex: unicode, caracteres ilegais).
     */
    public static String cleanBody(String raw) {
        if (String.isBlank(raw)) return null;

        String decoded = normalizeJson(raw);
        decoded = decoded.replaceAll('[^\\x20-\\x7E\\n\\r\\t]', '');

        return (decoded.length() > Logger.maxDebugLength)
            ? decoded.left(Logger.maxDebugLength) + '...'
            : decoded;
    }

    @TestVisible
    public static String normalizeJson(String jsonRaw) {
        try {
            // Wrap as {"v": <raw>} and parse
            String wrapped = '{"v":' + jsonRaw + '}';
            Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(wrapped);
            Object value = parsed.get('v');
            return JSON.serializePretty(value);
        } catch (Exception e) {
            System.debug('ERROR: RestServiceHelper.normalizeJson exception: '+e);
            System.debug('Returning same input not normalized ...');
            return jsonRaw;
        }
    }

    /**
     * Attempts to parse a raw HTTP response body as JSON.
     * If invalid, returns diagnostic wrapper instead of throwing.
     *
     * @param responseBody raw response as string
     * @return parsed Map if valid JSON; else metadata about failure
     */
    @TestVisible
    public static Map<String, Object> deserializeOrWrap(String responseBody) {
        Map<String, Object> result = new Map<String, Object>();

        if (String.isBlank(responseBody)) {
            result.put('internal_status', 'BLANK');
            result.put('internal_message', 'Response body was blank.');
            return result;
        }

        String trimmed = responseBody.trim();

        try {
            if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
                Object parsed = JSON.deserializeUntyped(trimmed);
                if (parsed instanceof Map<String, Object>) {
                    return (Map<String, Object>) parsed;
                } else {
                    result.put('internal_status', 'NOT_OBJECT');
                    result.put('internal_message', 'Parsed JSON is not a Map.');
                    result.put('raw_preview', trimmed.left(1000));
                    return result;
                }
            } else {
                result.put('internal_status', 'NON_JSON');
                result.put('internal_message', 'Response is not JSON-formatted.');
                result.put('raw_content_type', 'text/plain or html');
                result.put('raw_length', trimmed.length());
                result.put('raw_preview', trimmed.left(1000));
                return result;
            }
        } catch (Exception ex) {
            result.put('internal_status', 'DESERIALIZATION_ERROR');
            result.put('internal_message', 'JSON parse failed: ' + ex.getMessage());
            result.put('raw_preview', trimmed.left(1000));
            return result;
        }
    }


    
}