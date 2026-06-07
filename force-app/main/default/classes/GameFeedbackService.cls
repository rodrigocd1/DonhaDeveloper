public with sharing class GameFeedbackService {
    @TestVisible
    private static String cachedCaseOrigin;

    @TestVisible
    private static String cachedCaseStatus;

    public static Map<String, Object> submitFeedback(Map<String, Object> payload) {
        String playerId = GameSecurityUtil.sanitizeText(
            GameJsonUtil.toStringValue(payload.get('playerId')),
            GameConstants.MAX_PLAYER_ID_LENGTH
        );

        Account player = String.isBlank(playerId) ? null : GameAccountService.findPlayer(playerId);
        String feedbackCategory = GameSecurityUtil.sanitizeText(
            GameJsonUtil.toStringValue(payload.get('feedbackCategory')),
            GameConstants.MAX_TEXT_80
        );
        String mode = GameSecurityUtil.sanitizeText(
            GameJsonUtil.toStringValue(payload.get('mode')),
            GameConstants.MAX_TEXT_80
        );
        String subject = buildSubject(feedbackCategory, mode, payload.containsKey('labPayload'));

        Case gameCase = new Case(
            Subject = subject,
            Origin = resolveCaseOrigin(),
            Status = resolveCaseStatus(),
            AccountId = player == null ? null : player.Id,
            Game_Player_Account__c = player == null ? null : player.Id,
            Game_Player_Id__c = playerId,
            Game_Mode__c = mode,
            Game_Feedback_Category__c = feedbackCategory,
            Game_Feedback_Stars__c = GameJsonUtil.toDecimal(payload.get('feedbackStars')),
            Game_Feedback_Comment__c = GameSecurityUtil.sanitizeMultilineText(
                GameJsonUtil.toStringValue(payload.get('feedbackComment')),
                GameConstants.MAX_COMMENT_LENGTH
            ),
            Game_Board_Name__c = GameSecurityUtil.sanitizeText(
                GameJsonUtil.toStringValue(payload.get('boardName')),
                GameConstants.MAX_TEXT_120
            ),
            Game_Stage_Number__c = GameJsonUtil.toDecimal(payload.get('stageNumber')),
            Game_Difficulty__c = GameSecurityUtil.sanitizeText(
                GameJsonUtil.toStringValue(payload.get('difficulty')),
                GameConstants.MAX_TEXT_80
            ),
            Game_Player_Score__c = GameJsonUtil.toDecimal(payload.get('playerScore')),
            Game_Ai_Score__c = GameJsonUtil.toDecimal(payload.get('aiScore')),
            Game_Result__c = GameSecurityUtil.sanitizeText(
                GameJsonUtil.toStringValue(payload.get('result')),
                GameConstants.MAX_TEXT_80
            ),
            Game_Match_Duration_Seconds__c = GameJsonUtil.toDecimal(payload.get('durationSeconds')),
            Game_Ai_Average_Time_Ms__c = GameJsonUtil.toDecimal(payload.get('aiAverageTimeMs')),
            Game_Ai_Max_Time_Ms__c = GameJsonUtil.toDecimal(payload.get('aiMaxTimeMs')),
            Game_Powers_Used_JSON__c = serializeOptionalJson(payload.get('powersUsed')),
            Game_Lab_Payload_JSON__c = serializeOptionalJson(buildLabPayload(payload)),
            Game_App_Version__c = GameSecurityUtil.sanitizeText(
                GameJsonUtil.toStringValue(payload.get('appVersion')),
                GameConstants.MAX_APP_VERSION_LENGTH
            ),
            Game_Device_Info__c = payload.containsKey('deviceInfo')
                ? GameJsonUtil.serializeLimited(payload.get('deviceInfo'), GameConstants.MAX_DEVICE_INFO_LENGTH)
                : null,
            Game_Source__c = GameSecurityUtil.sanitizeText(
                GameJsonUtil.toStringValue(payload.get('source')),
                GameConstants.MAX_TEXT_80
            )
        );
        insert gameCase;

        return new Map<String, Object>{
            'caseId' => gameCase.Id,
            'subject' => gameCase.Subject
        };
    }

    @TestVisible
    static void resetCache() {
        cachedCaseOrigin = null;
        cachedCaseStatus = null;
    }

    private static String resolveCaseOrigin() {
        if (cachedCaseOrigin == null) {
            cachedCaseOrigin = GameSecurityUtil.pickFirstAllowedValue(
                Schema.SObjectType.Case.fields.Origin,
                GameConstants.GAME_CASE_ORIGIN_PREFERRED,
                GameConstants.GAME_CASE_ORIGIN_FALLBACK
            );
        }
        return cachedCaseOrigin;
    }

    private static String resolveCaseStatus() {
        if (cachedCaseStatus == null) {
            cachedCaseStatus = GameSecurityUtil.pickFirstAllowedValue(
                Schema.SObjectType.Case.fields.Status,
                GameConstants.GAME_CASE_STATUS_PREFERRED,
                GameConstants.GAME_CASE_STATUS_PREFERRED
            );
        }
        return cachedCaseStatus;
    }

    private static String buildSubject(String category, String mode, Boolean hasLabPayload) {
        String suffix = String.isNotBlank(mode) ? mode : 'Geral';

        if (hasLabPayload || category == 'IA lenta') {
            suffix = String.isNotBlank(category) ? category : suffix;
            return truncateSubject('[' + GameConstants.GAME_CASE_BRAND + '] Laboratorio - ' + suffix);
        }
        if (category == 'Erro / Bug') {
            return truncateSubject('[' + GameConstants.GAME_CASE_BRAND + '] Erro / Bug - ' + suffix);
        }
        if (category == 'Sugestao de melhoria') {
            return truncateSubject('[' + GameConstants.GAME_CASE_BRAND + '] Sugestao de melhoria');
        }
        if (String.isNotBlank(category) && String.isBlank(mode)) {
            return truncateSubject('[' + GameConstants.GAME_CASE_BRAND + '] ' + category);
        }
        return truncateSubject('[' + GameConstants.GAME_CASE_BRAND + '] Feedback - ' + suffix);
    }

    private static String truncateSubject(String subject) {
        return subject.length() > GameConstants.MAX_SUBJECT_LENGTH
            ? subject.substring(0, GameConstants.MAX_SUBJECT_LENGTH)
            : subject;
    }

    private static Object buildLabPayload(Map<String, Object> payload) {
        if (payload.containsKey('labPayload')) {
            return payload.get('labPayload');
        }

        return new Map<String, Object>{
            'mode' => payload.get('mode'),
            'stageNumber' => payload.get('stageNumber'),
            'boardName' => payload.get('boardName'),
            'difficulty' => payload.get('difficulty'),
            'playerScore' => payload.get('playerScore'),
            'aiScore' => payload.get('aiScore'),
            'durationSeconds' => payload.get('durationSeconds'),
            'aiAverageTimeMs' => payload.get('aiAverageTimeMs'),
            'aiMaxTimeMs' => payload.get('aiMaxTimeMs'),
            'powersUsed' => payload.get('powersUsed'),
            'source' => payload.get('source')
        };
    }

    private static String serializeOptionalJson(Object value) {
        return value == null ? null : GameJsonUtil.serializeLimited(value, GameConstants.MAX_JSON_FIELD_LENGTH);
    }
}
