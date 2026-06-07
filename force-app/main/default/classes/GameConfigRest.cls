@RestResource(urlMapping='/game/config/*')
global with sharing class GameConfigRest {
    @HttpGet
    global static void getConfig() {
        try {
            GameRestRequestValidator.ensureMethod('GET');
            GameRestResponse.writeSuccess(
                new Map<String, Object>{ 'config' => GameConfigService.getPublicConfig() }
            );
        } catch (GameRestException ex) {
            GameRestResponse.writeError(ex);
        } catch (Exception ex) {
            GameRestResponse.writeUnexpectedError('GameConfigRest.getConfig', ex);
        }
    }
}
