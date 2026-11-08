public inherited sharing class TotemLeadConfigService {
    private static final String DEFAULT_KEY = 'VEO';

    public class OptionConfig implements Comparable {
        @AuraEnabled public String key { get; set; }
        @AuraEnabled public String label { get; set; }
        @AuraEnabled public Decimal estimatedSavings { get; set; }
        public Decimal sortOrder { get; set; }

        public Integer compareTo(Object otherObject) {
            OptionConfig other = (OptionConfig) otherObject;
            Decimal currentOrder = sortOrder == null ? 999 : sortOrder;
            Decimal otherOrder = other.sortOrder == null ? 999 : other.sortOrder;
            if (currentOrder == otherOrder) {
                return key == other.key ? 0 : (key < other.key ? -1 : 1);
            }
            return currentOrder < otherOrder ? -1 : 1;
        }
    }

    public class QuestionConfig implements Comparable {
        @AuraEnabled public String key { get; set; }
        @AuraEnabled public String label { get; set; }
        @AuraEnabled public Boolean required { get; set; }
        @AuraEnabled public List<OptionConfig> options { get; set; }
        public Decimal sortOrder { get; set; }

        public Integer compareTo(Object otherObject) {
            QuestionConfig other = (QuestionConfig) otherObject;
            Decimal currentOrder = sortOrder == null ? 999 : sortOrder;
            Decimal otherOrder = other.sortOrder == null ? 999 : other.sortOrder;
            if (currentOrder == otherOrder) {
                return key == other.key ? 0 : (key < other.key ? -1 : 1);
            }
            return currentOrder < otherOrder ? -1 : 1;
        }
    }

    public class Config {
        @AuraEnabled public String key { get; set; }
        @AuraEnabled public String partnerName { get; set; }
        @AuraEnabled public String logoPath { get; set; }
        @AuraEnabled public String backgroundImagePath { get; set; }
        @AuraEnabled public String primaryColor { get; set; }
        @AuraEnabled public String secondaryColor { get; set; }
        @AuraEnabled public String accentColor { get; set; }
        @AuraEnabled public String textColor { get; set; }
        @AuraEnabled public Map<String, Object> content { get; set; }
        @AuraEnabled public List<QuestionConfig> questions { get; set; }
        @AuraEnabled public Boolean showCpf { get; set; }
        @AuraEnabled public Boolean requireCpf { get; set; }
        @AuraEnabled public Boolean requireEmail { get; set; }
        @AuraEnabled public Boolean requirePhone { get; set; }
        @AuraEnabled public Boolean requireConsent { get; set; }
        @AuraEnabled public String consentLabel { get; set; }
        @AuraEnabled public String consentLink { get; set; }
        @AuraEnabled public String blockMessage { get; set; }
        @AuraEnabled public String invalidCodeMessage { get; set; }
        @AuraEnabled public String deliveryFailureMessage { get; set; }

        public String leadSource { get; set; }
        public String originatorAlias { get; set; }
        public String formWeb { get; set; }
        public String codePrefix { get; set; }
        public Integer codeValidityHours { get; set; }
        public Integer blockDays { get; set; }
        public Boolean emailEnabled { get; set; }
        public Boolean whatsappEnabled { get; set; }
        public Boolean marketingCloudEnabled { get; set; }
        public String emailSenderAddress { get; set; }
        public String emailSubject { get; set; }
        public String emailBody { get; set; }
        public String marketingCloudNamedCredential { get; set; }
        public String marketingCloudDefinitionKey { get; set; }
    }

    public static Config getConfig(String requestedKey) {
        String normalizedKey = normalizeKey(requestedKey);
        Set<String> keys = new Set<String>{ DEFAULT_KEY, normalizedKey };

        Map<String, Totem_Lead_Config__mdt> recordsByKey = new Map<String, Totem_Lead_Config__mdt>();
        for (Totem_Lead_Config__mdt record : [
            SELECT DeveloperName, Active__c, Partner_Name__c, Lead_Source__c,
                Originator_Alias__c, Form_Web__c, Logo_Path__c, Background_Image_Path__c,
                Primary_Color__c, Secondary_Color__c, Accent_Color__c, Text_Color__c,
                Content_JSON__c, Code_Prefix__c, Code_Validity_Hours__c, Block_Days__c,
                Email_Enabled__c, Whatsapp_Enabled__c, Marketing_Cloud_Enabled__c,
                Block_Message__c, Invalid_Code_Message__c, Delivery_Failure_Message__c,
                Consent_Label__c, Consent_Link__c, Require_Consent__c, Show_CPF__c,
                Require_CPF__c, Require_Email__c, Require_Phone__c, Email_Subject__c,
                Email_Body__c, Email_Sender_Address__c, MC_Named_Credential__c,
                MC_Definition_Key__c
            FROM Totem_Lead_Config__mdt
            WHERE DeveloperName IN :keys
        ]) {
            recordsByKey.put(record.DeveloperName.toUpperCase(), record);
        }

        Totem_Lead_Config__mdt defaultRecord = recordsByKey.get(DEFAULT_KEY);
        if (defaultRecord == null || !defaultRecord.Active__c) {
            throw new ConfigException('CONFIG_DEFAULT_INVALID');
        }

        Totem_Lead_Config__mdt requestedRecord = recordsByKey.get(normalizedKey);
        if (requestedRecord == null || !requestedRecord.Active__c) {
            normalizedKey = DEFAULT_KEY;
            requestedRecord = defaultRecord;
        }

        Config config = fromRecord(defaultRecord, DEFAULT_KEY);
        if (normalizedKey != DEFAULT_KEY) {
            overlay(config, requestedRecord, normalizedKey);
        }
        config.questions = loadQuestions(normalizedKey);
        return config;
    }

    private static Config fromRecord(Totem_Lead_Config__mdt record, String key) {
        Config config = new Config();
        config.key = key;
        config.partnerName = valueOrDefault(record.Partner_Name__c, 'VEO');
        config.logoPath = record.Logo_Path__c;
        config.backgroundImagePath = record.Background_Image_Path__c;
        config.primaryColor = valueOrDefault(record.Primary_Color__c, '#0B5A7A');
        config.secondaryColor = valueOrDefault(record.Secondary_Color__c, '#0A4E6B');
        config.accentColor = valueOrDefault(record.Accent_Color__c, '#F6E85C');
        config.textColor = valueOrDefault(record.Text_Color__c, '#FFFFFF');
        config.content = parseContent(record.Content_JSON__c);
        config.showCpf = record.Show_CPF__c;
        config.requireCpf = record.Require_CPF__c;
        config.requireEmail = record.Require_Email__c;
        config.requirePhone = record.Require_Phone__c;
        config.requireConsent = record.Require_Consent__c;
        config.consentLabel = record.Consent_Label__c;
        config.consentLink = record.Consent_Link__c;
        config.blockMessage = valueOrDefault(record.Block_Message__c, 'Cadastro já realizado!');
        config.invalidCodeMessage = valueOrDefault(
            record.Invalid_Code_Message__c,
            'Verifique o código digitado ou reinicie o cadastro.'
        );
        config.deliveryFailureMessage = valueOrDefault(
            record.Delivery_Failure_Message__c,
            'Não foi possível enviar o código. Tente novamente.'
        );
        config.leadSource = valueOrDefault(record.Lead_Source__c, 'Totem Leads');
        config.originatorAlias = record.Originator_Alias__c;
        config.formWeb = valueOrDefault(record.Form_Web__c, 'totem_leads');
        config.codePrefix = sanitizePrefix(record.Code_Prefix__c);
        config.codeValidityHours = numberOrDefault(record.Code_Validity_Hours__c, 24, 1);
        config.blockDays = numberOrDefault(record.Block_Days__c, 7, 0);
        config.emailEnabled = record.Email_Enabled__c;
        config.whatsappEnabled = record.Whatsapp_Enabled__c;
        config.marketingCloudEnabled = record.Marketing_Cloud_Enabled__c;
        config.emailSenderAddress = record.Email_Sender_Address__c;
        config.emailSubject = valueOrDefault(record.Email_Subject__c, 'Seu código do Totem');
        config.emailBody = valueOrDefault(
            record.Email_Body__c,
            'Seu código é {CODE}. Ele é válido até {EXPIRATION}.'
        );
        config.marketingCloudNamedCredential = record.MC_Named_Credential__c;
        config.marketingCloudDefinitionKey = record.MC_Definition_Key__c;
        return config;
    }

    private static void overlay(Config config, Totem_Lead_Config__mdt record, String key) {
        config.key = key;
        config.partnerName = overlayValue(config.partnerName, record.Partner_Name__c);
        config.logoPath = overlayValue(config.logoPath, record.Logo_Path__c);
        config.backgroundImagePath = overlayValue(config.backgroundImagePath, record.Background_Image_Path__c);
        config.primaryColor = overlayValue(config.primaryColor, record.Primary_Color__c);
        config.secondaryColor = overlayValue(config.secondaryColor, record.Secondary_Color__c);
        config.accentColor = overlayValue(config.accentColor, record.Accent_Color__c);
        config.textColor = overlayValue(config.textColor, record.Text_Color__c);
        config.content.putAll(parseContent(record.Content_JSON__c));
        config.showCpf = record.Show_CPF__c;
        config.requireCpf = record.Require_CPF__c;
        config.requireEmail = record.Require_Email__c;
        config.requirePhone = record.Require_Phone__c;
        config.requireConsent = record.Require_Consent__c;
        config.consentLabel = overlayValue(config.consentLabel, record.Consent_Label__c);
        config.consentLink = overlayValue(config.consentLink, record.Consent_Link__c);
        config.blockMessage = overlayValue(config.blockMessage, record.Block_Message__c);
        config.invalidCodeMessage = overlayValue(config.invalidCodeMessage, record.Invalid_Code_Message__c);
        config.deliveryFailureMessage = overlayValue(
            config.deliveryFailureMessage,
            record.Delivery_Failure_Message__c
        );
        config.leadSource = overlayValue(config.leadSource, record.Lead_Source__c);
        config.originatorAlias = overlayValue(config.originatorAlias, record.Originator_Alias__c);
        config.formWeb = overlayValue(config.formWeb, record.Form_Web__c);
        if (!String.isBlank(record.Code_Prefix__c)) {
            config.codePrefix = sanitizePrefix(record.Code_Prefix__c);
        }
        config.codeValidityHours = numberOrDefault(
            record.Code_Validity_Hours__c,
            config.codeValidityHours,
            1
        );
        config.blockDays = numberOrDefault(record.Block_Days__c, config.blockDays, 0);
        config.emailEnabled = record.Email_Enabled__c;
        config.whatsappEnabled = record.Whatsapp_Enabled__c;
        config.marketingCloudEnabled = record.Marketing_Cloud_Enabled__c;
        config.emailSenderAddress = overlayValue(
            config.emailSenderAddress,
            record.Email_Sender_Address__c
        );
        config.emailSubject = overlayValue(config.emailSubject, record.Email_Subject__c);
        config.emailBody = overlayValue(config.emailBody, record.Email_Body__c);
        config.marketingCloudNamedCredential = overlayValue(
            config.marketingCloudNamedCredential,
            record.MC_Named_Credential__c
        );
        config.marketingCloudDefinitionKey = overlayValue(
            config.marketingCloudDefinitionKey,
            record.MC_Definition_Key__c
        );
    }

    private static List<QuestionConfig> loadQuestions(String requestedKey) {
        Set<String> keys = new Set<String>{ DEFAULT_KEY, requestedKey };
        Map<String, QuestionConfig> byKey = new Map<String, QuestionConfig>();

        List<Totem_Lead_Pergunta__mdt> questionRecords = [
            SELECT Config_Key__c, Question_Key__c, Label__c, Sort_Order__c, Required__c, Active__c
            FROM Totem_Lead_Pergunta__mdt
            WHERE Config_Key__c IN :keys AND Active__c = TRUE
            ORDER BY Sort_Order__c, DeveloperName
        ];
        applyQuestionRecords(byKey, questionRecords, DEFAULT_KEY);
        if (requestedKey != DEFAULT_KEY) {
            applyQuestionRecords(byKey, questionRecords, requestedKey);
        }

        Map<String, Map<String, OptionConfig>> optionsByQuestion = new Map<String, Map<String, OptionConfig>>();
        List<Totem_Lead_Opcao__mdt> optionRecords = [
            SELECT Config_Key__c, Question_Key__c, Option_Key__c, Label__c,
                Sort_Order__c, Estimated_Savings__c, Active__c
            FROM Totem_Lead_Opcao__mdt
            WHERE Config_Key__c IN :keys AND Active__c = TRUE
            ORDER BY Sort_Order__c, DeveloperName
        ];
        applyOptionRecords(optionsByQuestion, optionRecords, DEFAULT_KEY);
        if (requestedKey != DEFAULT_KEY) {
            applyOptionRecords(optionsByQuestion, optionRecords, requestedKey);
        }

        List<QuestionConfig> result = byKey.values();
        for (QuestionConfig question : result) {
            Map<String, OptionConfig> optionMap = optionsByQuestion.get(question.key);
            question.options = optionMap == null ? new List<OptionConfig>() : optionMap.values();
            question.options.sort();
        }
        result.sort();
        return result;
    }

    private static void applyQuestionRecords(
        Map<String, QuestionConfig> target,
        List<Totem_Lead_Pergunta__mdt> records,
        String configKey
    ) {
        for (Totem_Lead_Pergunta__mdt record : records) {
            if (record.Config_Key__c != configKey || String.isBlank(record.Question_Key__c)) {
                continue;
            }
            QuestionConfig question = new QuestionConfig();
            question.key = record.Question_Key__c;
            question.label = record.Label__c;
            question.required = record.Required__c;
            question.sortOrder = record.Sort_Order__c;
            target.put(question.key, question);
        }
    }

    private static void applyOptionRecords(
        Map<String, Map<String, OptionConfig>> target,
        List<Totem_Lead_Opcao__mdt> records,
        String configKey
    ) {
        for (Totem_Lead_Opcao__mdt record : records) {
            if (record.Config_Key__c != configKey || String.isBlank(record.Question_Key__c)) {
                continue;
            }
            if (!target.containsKey(record.Question_Key__c)) {
                target.put(record.Question_Key__c, new Map<String, OptionConfig>());
            }
            OptionConfig option = new OptionConfig();
            option.key = record.Option_Key__c;
            option.label = record.Label__c;
            option.estimatedSavings = record.Estimated_Savings__c;
            option.sortOrder = record.Sort_Order__c;
            target.get(record.Question_Key__c).put(option.key, option);
        }
    }

    private static Map<String, Object> parseContent(String jsonValue) {
        if (String.isBlank(jsonValue)) {
            return new Map<String, Object>();
        }
        try {
            Object parsed = JSON.deserializeUntyped(jsonValue);
            return parsed instanceof Map<String, Object>
                ? (Map<String, Object>) parsed
                : new Map<String, Object>();
        } catch (JSONException error) {
            throw new ConfigException('CONFIG_CONTENT_INVALID');
        }
    }

    private static String normalizeKey(String requestedKey) {
        if (String.isBlank(requestedKey)) {
            return DEFAULT_KEY;
        }
        String normalized = requestedKey.trim().toUpperCase().replaceAll('[^A-Z0-9_]', '');
        return String.isBlank(normalized) ? DEFAULT_KEY : normalized.left(80);
    }

    private static String sanitizePrefix(String value) {
        String normalized = String.isBlank(value)
            ? DEFAULT_KEY
            : value.trim().toUpperCase().replaceAll('[^A-Z0-9]', '');
        return String.isBlank(normalized) ? DEFAULT_KEY : normalized.left(15);
    }

    private static Integer numberOrDefault(Decimal value, Integer fallback, Integer minimum) {
        Integer result = value == null ? fallback : value.intValue();
        return Math.max(minimum, result);
    }

    private static String overlayValue(String fallback, String candidate) {
        return String.isBlank(candidate) ? fallback : candidate.trim();
    }

    private static String valueOrDefault(String candidate, String fallback) {
        return String.isBlank(candidate) ? fallback : candidate.trim();
    }

    public class ConfigException extends Exception {
    }
}