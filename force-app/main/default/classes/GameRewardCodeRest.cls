@RestResource(urlMapping='/game/reward-code/*')
global with sharing class GameRewardCodeRest {
    @HttpPost
    global static void redeemCode() {
        try {
            GameRestRequestValidator.ensureMethod('POST');
            Map<String, Object> payload = GameRestRequestValidator.requireBodyAsMap();
            String playerId = GameJsonUtil.toStringValue(payload.get('playerId'));
            String code = GameJsonUtil.toStringValue(payload.get('code'));
            Map<String, Object> result = GameRewardCodeService.redeemCode(playerId, code);
            GameRestResponse.writeSuccess(result);
        } catch (GameRestException ex) {
            GameRestResponse.writeError(ex);
        } catch (Exception ex) {
            GameRestResponse.writeUnexpectedError('GameRewardCodeRest.redeemCode', ex);
        }
    }
}
