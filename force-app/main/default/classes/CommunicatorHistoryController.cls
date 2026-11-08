@RestResource(urlMapping='/communicator/history/')
global with sharing class CommunicatorHistoryController {

    @HttpGet
    global static String doGet() {
        System.RestRequest req = RestContext.request;
        System.RestResponse resHttp = RestContext.response;

        try {
            String idParam = req.params.get('Id');
            String idsParam = req.params.get('Ids');

            CommunicatorHistoryService.HistoryResponse res;
            if (!String.isBlank(idsParam)) {
                List<String> ids = new List<String>();
                for (String rawId : idsParam.split(',')) {
                    String normalizedId = rawId == null ? null : rawId.trim();
                    if (!String.isBlank(normalizedId)) {
                        ids.add(normalizedId);
                    }
                }
                res = CommunicatorHistoryService.getHistory(ids);
            } else {
                res = CommunicatorHistoryService.getHistory(idParam);
            }

            resHttp.statusCode = res.success ? 200 : 400;

            return JSON.serialize(res);

        } catch (Exception e) {
            resHttp.statusCode = 500;
            return JSON.serialize(errorResponse('Erro no GET: ' + e.getMessage()));
        }
    }

    private static CommunicatorHistoryService.HistoryResponse errorResponse(String msg) {
        CommunicatorHistoryService.HistoryResponse res =
            new CommunicatorHistoryService.HistoryResponse();

        res.success = false;
        res.error = msg;

        return res;
    }
}