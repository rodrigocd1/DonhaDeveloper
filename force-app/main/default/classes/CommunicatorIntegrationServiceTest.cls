/**
 * @description Test class for CommunicatorIntegrationService.
 */
@IsTest
private class CommunicatorIntegrationServiceTest {

    // ─────────────────────────────────────────
    // Mock HTTP client
    // ─────────────────────────────────────────

    private class MockHttpClient implements CommunicatorIntegrationService.ICommunicatorHttpClient {
        private Integer statusCode;
        private String  responseBody;

        public MockHttpClient(Integer statusCode, String responseBody) {
            this.statusCode   = statusCode;
            this.responseBody = responseBody;
        }

        public HttpResponse send(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(this.statusCode);
            res.setBody(this.responseBody);
            return res;
        }
    }

    // ─────────────────────────────────────────
    // Helpers
    // ─────────────────────────────────────────

    private static CommunicatorDTOs.MessageEventDTO buildPayload() {
        CommunicatorDTOs.MessageEventDTO payload = new CommunicatorDTOs.MessageEventDTO();
        payload.threadExternalId = 'EXT-001';
        payload.messageId        = 'MSG-001';
        payload.senderId         = UserInfo.getUserId();
        payload.senderName       = UserInfo.getName();
        payload.messageBody      = 'Test notification';
        payload.sentAt           = String.valueOf(System.now());
        payload.hasAttachment    = false;
        return payload;
    }

    // ─────────────────────────────────────────
    // Tests
    // ─────────────────────────────────────────

    @IsTest
    static void testNotifyNewMessage_success() {
        CommunicatorIntegrationService.httpClient = new MockHttpClient(200, '{"ok":true}');

        Test.startTest();
        CommunicatorDTOs.IntegrationResponseDTO response =
            CommunicatorIntegrationService.notifyNewMessage(buildPayload());
        Test.stopTest();

        Assert.isTrue(response.success);
        Assert.areEqual(200, response.statusCode);
    }

    @IsTest
    static void testNotifyNewMessage_serverError_returnsFailure() {
        CommunicatorIntegrationService.httpClient = new MockHttpClient(500, '{"error":"Internal Server Error"}');

        Test.startTest();
        CommunicatorDTOs.IntegrationResponseDTO response =
            CommunicatorIntegrationService.notifyNewMessage(buildPayload());
        Test.stopTest();

        Assert.isFalse(response.success);
        Assert.areEqual(500, response.statusCode);
    }

    @IsTest
    static void testGetExternalHistory_success() {
        CommunicatorDTOs.ExternalHistoryDTO historyDto = new CommunicatorDTOs.ExternalHistoryDTO();
        historyDto.threadId   = 'EXT-THREAD-001';
        historyDto.totalCount = 0;
        historyDto.messages   = new List<CommunicatorDTOs.ExternalMessageDTO>();

        CommunicatorIntegrationService.httpClient =
            new MockHttpClient(200, JSON.serialize(historyDto));

        Test.startTest();
        CommunicatorDTOs.ExternalHistoryDTO history =
            CommunicatorIntegrationService.getExternalHistory('EXT-THREAD-001');
        Test.stopTest();

        Assert.isNotNull(history);
        Assert.areEqual('EXT-THREAD-001', history.threadId);
    }

    @IsTest
    static void testGetExternalHistory_notFound_throwsException() {
        CommunicatorIntegrationService.httpClient = new MockHttpClient(404, '{"error":"Not Found"}');

        try {
            Test.startTest();
            CommunicatorIntegrationService.getExternalHistory('EXT-NOT-FOUND');
            Test.stopTest();
            Assert.fail('Expected CommunicatorException');
        } catch (CommunicatorException ex) {
            Assert.isTrue(ex.getMessage().contains('failed'));
        }
    }
}
