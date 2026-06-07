@RestResource(urlMapping='/game/feedback/*')
global with sharing class GameFeedbackRest {
    @HttpPost
    global static void submitFeedback() {
        try {
            GameRestRequestValidator.ensureMethod('POST');
            Map<String, Object> payload = GameRestRequestValidator.requireBodyAsMap();
            GameRestResponse.writeSuccess(
                new Map<String, Object>{ 'data' => GameFeedbackService.submitFeedback(payload) }
            );
        } catch (GameRestException ex) {
            GameRestResponse.writeError(ex);
        } catch (Exception ex) {
            GameRestResponse.writeUnexpectedError('GameFeedbackRest.submitFeedback', ex);
        }
    }
}
