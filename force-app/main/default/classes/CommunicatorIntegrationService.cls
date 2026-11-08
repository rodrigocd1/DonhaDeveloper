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
     * @description Publishes a socket-compatible new message event asynchronously.
     *              Main message persistence must never fail due to Heroku unavailability.
     */
    public static void publishNewMessageEventAsync(
        Id messageId,
        Id threadId,
        String messageBody,
        Set<Id> recipientUserIds,
        Boolean hasAttachment
    ) {
        if (messageId == null) return;

        CommunicatorDTOs.MessageEventDTO payload = new CommunicatorDTOs.MessageEventDTO();
        payload.messageId     = String.valueOf(messageId);
        payload.threadId      = threadId == null ? null : String.valueOf(threadId);
        payload.message       = messageBody;
        payload.messageBody   = messageBody; // Backward compatibility for existing consumers.
        payload.senderId      = UserInfo.getUserId();
        payload.senderName    = UserInfo.getName();
        payload.sentAt        = String.valueOf(System.now());
        payload.hasAttachment = (hasAttachment == true);

        if (recipientUserIds != null && !recipientUserIds.isEmpty()) {
            List<String> userIds = new List<String>();
            for (Id recipientId : recipientUserIds) {
                if (recipientId != null) userIds.add(String.valueOf(recipientId));
            }
            userIds.sort();
            if (!userIds.isEmpty()) {
                payload.user_ids = userIds;
            }
        }

        enqueueNewMessageEvent(payload);
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

    @TestVisible
    private static void enqueueNewMessageEvent(CommunicatorDTOs.MessageEventDTO payload) {
        if (payload == null || String.isBlank(payload.messageId)) return;

        if (Test.isRunningTest()) {
            dispatchNewMessageEventSafely(payload);
            return;
        }

        System.enqueueJob(new NewMessageEventQueueable(JSON.serialize(payload)));
    }

    @TestVisible
    private static void dispatchNewMessageEventSafely(CommunicatorDTOs.MessageEventDTO payload) {
        try {
            notifyNewMessage(payload);
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR,
                'CommunicatorIntegrationService.publishNewMessageEventAsync error: ' + ex.getMessage());
        }
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

    private class NewMessageEventQueueable implements Queueable, Database.AllowsCallouts {
        private String payloadJson;

        public NewMessageEventQueueable(String payloadJson) {
            this.payloadJson = payloadJson;
        }

        public void execute(QueueableContext context) {
            CommunicatorDTOs.MessageEventDTO payload =
                (CommunicatorDTOs.MessageEventDTO) JSON.deserialize(
                    payloadJson,
                    CommunicatorDTOs.MessageEventDTO.class
                );
            dispatchNewMessageEventSafely(payload);
        }
    }
}