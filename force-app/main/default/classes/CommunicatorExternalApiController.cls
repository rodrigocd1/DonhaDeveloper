@RestResource(urlMapping='/comunicador/v1/*')
global with sharing class CommunicatorExternalApiController {

    @HttpGet
    global static void doGet() {
        handleRequest('GET');
    }

    @HttpPost
    global static void doPost() {
        handleRequest('POST');
    }

    private static void handleRequest(String methodName) {
        RestRequest request = RestContext.request;
        System.RestResponse response = RestContext.response;
        try {
            List<String> pathParts = getPathParts(request.requestURI);
            CommunicatorExternalApiDTOs.ApiResponseDTO payload = route(methodName, pathParts, request);
            response.statusCode = 200;
            writeJsonResponse(response, payload);
        } catch (CommunicatorExternalApiErrorService.ApiException ex) {
            response.statusCode = ex.statusCode;
            writeJsonResponse(
                response,
                CommunicatorExternalApiErrorService.buildErrorResponse(
                    ex.code,
                    ex.getMessage(),
                    ex.action,
                    ex.example,
                    ex.details
                )
            );
        } catch (Exception ex) {
            response.statusCode = 500;
            writeJsonResponse(
                response,
                CommunicatorExternalApiErrorService.buildErrorResponse(
                    'UNEXPECTED_ERROR',
                    ex.getMessage(),
                    null,
                    null,
                    null
                )
            );
        }
    }

    private static CommunicatorExternalApiDTOs.ApiResponseDTO route(
        String methodName,
        List<String> pathParts,
        RestRequest request
    ) {
        Map<String, String> params = request.params == null
            ? new Map<String, String>()
            : new Map<String, String>(request.params);
        String body = request.requestBody == null ? null : request.requestBody.toString();

        if (methodName == 'GET' && matches(pathParts, new List<String>{ 'search', 'records' })) {
            return CommunicatorExternalApiService.searchRecords(params);
        }
        if (methodName == 'GET' && matches(pathParts, new List<String>{ 'conversations' })) {
            return CommunicatorExternalApiService.getListConversations(params);
        }
        if (methodName == 'GET' && pathParts.size() == 3 && pathParts[0] == 'records' && pathParts[2] == 'threads') {
            return CommunicatorExternalApiService.getListRecordThreads(pathParts[1], params);
        }
        if (methodName == 'GET' && pathParts.size() == 3 && pathParts[0] == 'records' && pathParts[2] == 'messages') {
            return CommunicatorExternalApiService.getListRecordMessages(pathParts[1], params);
        }
        if (methodName == 'GET' && pathParts.size() == 3 && pathParts[0] == 'threads' && pathParts[2] == 'chat') {
            return CommunicatorExternalApiService.getThreadChat(pathParts[1], params);
        }
        if (methodName == 'GET' && pathParts.size() == 3 && pathParts[0] == 'threads' && pathParts[2] == 'messages') {
            return CommunicatorExternalApiService.getListThreadMessages(pathParts[1], params);
        }
        if (methodName == 'POST' && matches(pathParts, new List<String>{ 'messages' })) {
            return CommunicatorExternalApiService.sendMessage(body);
        }
        if (methodName == 'POST' && pathParts.size() == 3 && pathParts[0] == 'threads' && pathParts[2] == 'read') {
            return CommunicatorExternalApiService.setThreadAsRead(pathParts[1], body);
        }
        if (methodName == 'GET' && matches(pathParts, new List<String>{ 'notifications' })) {
            return CommunicatorExternalApiService.getListNotifications(params);
        }
        if (methodName == 'GET' && matches(pathParts, new List<String>{ 'unread-count' })) {
            return CommunicatorExternalApiService.getUnreadCount(params);
        }
        if (methodName == 'GET' && matches(pathParts, new List<String>{ 'groups' })) {
            return CommunicatorExternalApiService.getListGroups(params);
        }
        if (methodName == 'POST' && matches(pathParts, new List<String>{ 'groups' })) {
            return CommunicatorExternalApiService.createGroup(body);
        }
        if (methodName == 'GET' && pathParts.size() == 2 && pathParts[0] == 'groups') {
            return CommunicatorExternalApiService.getGroupDetail(pathParts[1], params);
        }
        if (methodName == 'GET' && pathParts.size() == 3 && pathParts[0] == 'groups' && pathParts[2] == 'members') {
            return CommunicatorExternalApiService.getListGroupMembers(pathParts[1], params);
        }
        if (methodName == 'POST' && pathParts.size() == 3 && pathParts[0] == 'groups' && pathParts[2] == 'users') {
            return CommunicatorExternalApiService.setGroupUsers(pathParts[1], body);
        }
        if (methodName == 'POST' && pathParts.size() == 3 && pathParts[0] == 'groups' && pathParts[2] == 'messages') {
            return CommunicatorExternalApiService.sendGroupMessage(pathParts[1], body);
        }
        if (methodName == 'GET' && pathParts.size() == 3 && pathParts[0] == 'groups' && pathParts[2] == 'chat') {
            return CommunicatorExternalApiService.getGroupChat(pathParts[1], params);
        }
        if (methodName == 'POST' && matches(pathParts, new List<String>{ 'broadcast-groups' })) {
            return CommunicatorExternalApiService.createBroadcastGroup(body);
        }
        if (methodName == 'POST' && matches(pathParts, new List<String>{ 'broadcasts' })) {
            return CommunicatorExternalApiService.sendBroadcast(body);
        }
        if (methodName == 'GET' && matches(pathParts, new List<String>{ 'broadcasts' })) {
            return CommunicatorExternalApiService.getListBroadcasts(params);
        }
        if (methodName == 'GET' && pathParts.size() == 2 && pathParts[0] == 'broadcasts') {
            return CommunicatorExternalApiService.getBroadcastDetail(pathParts[1], params);
        }
        if (methodName == 'POST' && pathParts.size() == 3 && pathParts[0] == 'broadcasts' && pathParts[2] == 'read') {
            return CommunicatorExternalApiService.setBroadcastAsRead(pathParts[1], body);
        }

        throw CommunicatorExternalApiErrorService.notFound(
            'ROUTE_NOT_FOUND',
            'Endpoint nao encontrado.'
        );
    }

    private static List<String> getPathParts(String requestUri) {
        List<String> result = new List<String>();
        if (String.isBlank(requestUri)) return result;
        String normalized = requestUri;
        Integer markerIndex = normalized.indexOf('/comunicador/v1/');
        if (markerIndex >= 0) {
            normalized = normalized.substring(markerIndex + '/comunicador/v1/'.length());
        }
        for (String part : normalized.split('/')) {
            if (String.isNotBlank(part)) {
                result.add(part);
            }
        }
        return result;
    }

    private static Boolean matches(List<String> actual, List<String> expected) {
        if (actual == null || expected == null || actual.size() != expected.size()) return false;
        for (Integer index = 0; index < expected.size(); index++) {
            if (actual[index] != expected[index]) return false;
        }
        return true;
    }

    private static void writeJsonResponse(System.RestResponse response, Object payload) {
        response.addHeader('Content-Type', 'application/json;charset=UTF-8');
        response.responseBody = Blob.valueOf(JSON.serialize(payload));
    }
}