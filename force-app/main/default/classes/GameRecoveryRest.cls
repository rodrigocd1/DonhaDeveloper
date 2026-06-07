@RestResource(urlMapping='/game/recovery/*')
global with sharing class GameRecoveryRest {
    @HttpPost
    global static void processRecovery() {
        try {
            GameRestRequestValidator.ensureMethod('POST');
            Map<String, Object> payload = GameRestRequestValidator.requireBodyAsMap();
            GameRestResponse.writeSuccess(
                new Map<String, Object>{ 'data' => GameRecoveryService.process(payload) }
            );
        } catch (GameRestException ex) {
            GameRestResponse.writeError(ex);
        } catch (Exception ex) {
            GameRestResponse.writeUnexpectedError('GameRecoveryRest.processRecovery', ex);
        }
    }
}
