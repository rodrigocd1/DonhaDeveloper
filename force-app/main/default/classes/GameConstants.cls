public class GameConstants {
    public static final String GAME_CONFIG_ACCOUNT_NAME = 'GAME_CONFIG';
    public static final String GAME_CASE_BRAND = 'Dots & Boxes';
    public static final String GAME_LOGIN_PROVIDER_GUEST = 'guest';
    public static final String GAME_LOGIN_PROVIDER_GOOGLE = 'google';
    public static final String GAME_CASE_ORIGIN_PREFERRED = 'Game';
    public static final String GAME_CASE_ORIGIN_FALLBACK = 'Web';
    public static final String GAME_CASE_STATUS_PREFERRED = 'New';
    public static final String OPERATION_REGISTER_HASH = 'registerHash';
    public static final String OPERATION_VALIDATE_HASH = 'validateHash';
    public static final String OPERATION_REGENERATE_HASH = 'regenerateHash';
    public static final String REWARD_CODE_PUTZFORCE = 'PUTZFORCE';

    public static final Integer MAX_REQUEST_BODY_LENGTH = 100000;
    public static final Integer MAX_PLAYER_ID_LENGTH = 100;
    public static final Integer MAX_DISPLAY_NAME_LENGTH = 80;
    public static final Integer MAX_PROVIDER_LENGTH = 40;
    public static final Integer MAX_EXTERNAL_ID_LENGTH = 255;
    public static final Integer MAX_DEVICE_ID_LENGTH = 255;
    public static final Integer MAX_COMMENT_LENGTH = 4000;
    public static final Integer MAX_TEXT_80 = 80;
    public static final Integer MAX_TEXT_120 = 120;
    public static final Integer MAX_APP_VERSION_LENGTH = 40;
    public static final Integer MAX_JSON_FIELD_LENGTH = 30000;
    public static final Integer MAX_DEVICE_INFO_LENGTH = 4000;
    public static final Integer MAX_SUBJECT_LENGTH = 255;
    public static final Integer MAX_NAME_LENGTH = 255;

    public static final String ERROR_BAD_REQUEST = 'BAD_REQUEST';
    public static final String ERROR_INVALID_JSON = 'INVALID_JSON';
    public static final String ERROR_PAYLOAD_TOO_LARGE = 'PAYLOAD_TOO_LARGE';
    public static final String ERROR_REQUIRED_FIELD = 'REQUIRED_FIELD';
    public static final String ERROR_INVALID_PLAYER_ID = 'INVALID_PLAYER_ID';
    public static final String ERROR_PLAYER_NOT_FOUND = 'PLAYER_NOT_FOUND';
    public static final String ERROR_CONFIG_NOT_FOUND = 'CONFIG_NOT_FOUND';
    public static final String ERROR_TEXT_TOO_LARGE = 'TEXT_TOO_LARGE';
    public static final String ERROR_JSON_TOO_LARGE = 'JSON_TOO_LARGE';
    public static final String ERROR_INVALID_OPERATION = 'INVALID_OPERATION';
    public static final String ERROR_INVALID_REWARD_CODE = 'INVALID_REWARD_CODE';
    public static final String ERROR_CODE_ALREADY_REDEEMED = 'CODE_ALREADY_REDEEMED';
    public static final String ERROR_LOGIN_REQUIRED = 'LOGIN_REQUIRED';
    public static final String ERROR_REWARD_CODES_DISABLED = 'REWARD_CODES_DISABLED';
    public static final String ERROR_RECOVERY_HASH_REQUIRED = 'RECOVERY_HASH_REQUIRED';
    public static final String ERROR_UNEXPECTED = 'UNEXPECTED_ERROR';

    public static final Decimal DEFAULT_NUMBER_ZERO = 0;

    public static final Set<String> PUBLIC_CONFIG_KEYS = new Set<String>{
        'betaServerUrl',
        'ddnsHostname',
        'x1BetaEnabled',
        'x1ComingSoonEnabled',
        'minimumAppVersion',
        'rewardCodesEnabled',
        'bannerAdsEnabled',
        'shopBannerEnabled',
        'stageMapBannerEnabled',
        'profileBannerEnabled',
        'feedbackBannerEnabled',
        'salesforceFeedbackEnabled',
        'labModeEnabled',
        'timerAttackEnabled',
        'nervesOfSteelEnabled',
        'rankedEnabled',
        'maintenanceMode',
        'maintenanceMessage'
    };
}
