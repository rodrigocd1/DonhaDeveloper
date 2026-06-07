@RestResource(urlMapping='/game/player/*')
global with sharing class GamePlayerRest {
    @HttpGet
    global static void getPlayer() {
        try {
            GameRestRequestValidator.ensureMethod('GET');
            String playerId = GameRestRequestValidator.requireQueryParam('playerId');
            GameRestResponse.writeSuccess(
                new Map<String, Object>{ 'player' => GameAccountService.getPlayerResponse(playerId) }
            );
        } catch (GameRestException ex) {
            GameRestResponse.writeError(ex);
        } catch (Exception ex) {
            GameRestResponse.writeUnexpectedError('GamePlayerRest.getPlayer', ex);
        }
    }

    @HttpPost
    global static void upsertPlayer() {
        try {
            GameRestRequestValidator.ensureMethod('POST');
            Map<String, Object> payload = GameRestRequestValidator.requireBodyAsMap();
            GameRestResponse.writeSuccess(
                new Map<String, Object>{ 'player' => GameAccountService.upsertPlayer(payload) }
            );
        } catch (GameRestException ex) {
            GameRestResponse.writeError(ex);
        } catch (Exception ex) {
            GameRestResponse.writeUnexpectedError('GamePlayerRest.upsertPlayer', ex);
        }
    }
}
