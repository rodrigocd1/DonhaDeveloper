/**
 * @description Service responsible for REST integration with the external Heroku service.
 */
public with sharing class CommunicatorIntegrationService {

    @TestVisible
    private static ICommunicatorHttpClient httpClient = new CommunicatorHttpClientImpl();

    // ─────────────────────────────────────────
    // Public API
    // ─────────────────────────────────────────

    /**
     * @description Notifies the external Heroku service of a new message event.
     */
    public static CommunicatorDTOs.IntegrationResponseDTO notifyNewMessage(CommunicatorDTOs.MessageEventDTO payload) {
        String endpoint = getNamedCredentialEndpoint('/api/v1/events/message');
        String body     = JSON.serialize(payload);

        HttpRequest  req = buildPostRequest(endpoint, body);
        HttpResponse res = httpClient.send(req);

        return parseResponse(res);
    }

    /**
     * @description Retrieves external message history for a thread.
     */
    public static CommunicatorDTOs.ExternalHistoryDTO getExternalHistory(String externalThreadId) {
        String endpoint = getNamedCredentialEndpoint('/api/v1/threads/' + externalThreadId + '/messages');

        HttpRequest  req = buildGetRequest(endpoint);
        HttpResponse res = httpClient.send(req);

        if (res.getStatusCode() == 200) {
            return (CommunicatorDTOs.ExternalHistoryDTO) JSON.deserialize(
                res.getBody(),
                CommunicatorDTOs.ExternalHistoryDTO.class
            );
        }

        throw new CommunicatorException('External history retrieval failed: ' + res.getStatus());
    }

    // ─────────────────────────────────────────
    // Private helpers
    // ─────────────────────────────────────────

    private static String getNamedCredentialEndpoint(String path) {
        return 'callout:CommunicatorHeroku' + path;
    }

    private static HttpRequest buildPostRequest(String endpoint, String body) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('Accept', 'application/json');
        req.setBody(body);
        req.setTimeout(10000);
        return req;
    }

    private static HttpRequest buildGetRequest(String endpoint) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('GET');
        req.setHeader('Accept', 'application/json');
        req.setTimeout(10000);
        return req;
    }

    private static CommunicatorDTOs.IntegrationResponseDTO parseResponse(HttpResponse res) {
        CommunicatorDTOs.IntegrationResponseDTO dto = new CommunicatorDTOs.IntegrationResponseDTO();
        dto.statusCode = res.getStatusCode();
        dto.success    = (res.getStatusCode() >= 200 && res.getStatusCode() < 300);
        dto.rawBody    = res.getBody();

        if (!dto.success) {
            System.debug(LoggingLevel.ERROR,
                'CommunicatorIntegrationService: HTTP ' + res.getStatusCode() + ' - ' + res.getBody());
        }

        return dto;
    }

    // ─────────────────────────────────────────
    // HTTP client interface (for testability)
    // ─────────────────────────────────────────

    public interface ICommunicatorHttpClient {
        HttpResponse send(HttpRequest req);
    }

    public class CommunicatorHttpClientImpl implements ICommunicatorHttpClient {
        public HttpResponse send(HttpRequest req) {
            return new Http().send(req);
        }
    }
}
