public with sharing class TotemLeadPublicController {
    @AuraEnabled(cacheable=true)
    public static TotemLeadPublicConfig getPublicConfig(String configurationKey) {
        try {
            return toPublicConfig(TotemLeadConfigService.getConfig(configurationKey));
        } catch (Exception error) {
            throw handled('Configuração indisponível no momento.');
        }
    }

    @AuraEnabled
    public static TotemLeadPublicRequestResult requestCode(TotemLeadPublicRequest requestData) {
        try {
            TotemLeadApplicationService.RequestResult result = TotemLeadApplicationService.requestCode(
                toInternalRequest(requestData)
            );
            return toPublicRequestResult(result);
        } catch (Exception error) {
            throw handled(safeMessage(error, 'Não foi possível processar a solicitação. Tente novamente.'));
        }
    }

    @AuraEnabled
    public static TotemLeadPublicDeliveryStatus getDeliveryStatus(String accessToken) {
        try {
            return toPublicDeliveryStatus(TotemLeadApplicationService.getDeliveryStatus(accessToken));
        } catch (Exception error) {
            throw handled(safeMessage(error, 'Não foi possível consultar o envio. Tente novamente.'));
        }
    }

    @AuraEnabled
    public static TotemLeadPublicDeliveryStatus retryDelivery(String accessToken) {
        try {
            return toPublicDeliveryStatus(TotemLeadApplicationService.retryDelivery(accessToken));
        } catch (Exception error) {
            throw handled(safeMessage(error, 'Não foi possível reenviar o código. Tente novamente.'));
        }
    }

    @AuraEnabled
    public static TotemLeadPublicValidationResult validateCode(
        TotemLeadPublicValidationRequest requestData
    ) {
        try {
            TotemLeadApplicationService.ValidationResult result = TotemLeadApplicationService.validateCode(
                toInternalValidationRequest(requestData)
            );
            return toPublicValidationResult(result);
        } catch (Exception error) {
            throw handled(safeMessage(error, 'Não foi possível validar o código. Tente novamente.'));
        }
    }

    private static TotemLeadApplicationService.RequestData toInternalRequest(
        TotemLeadPublicRequest source
    ) {
        if (source == null) {
            return null;
        }
        TotemLeadApplicationService.RequestData target = new TotemLeadApplicationService.RequestData();
        target.requestId = source.requestId;
        target.configurationKey = source.configurationKey;
        target.firstName = source.firstName;
        target.lastName = source.lastName;
        target.fullName = source.fullName;
        target.cpf = source.cpf;
        target.email = source.email;
        target.mobilePhone = source.mobilePhone;
        target.consentAccepted = source.consentAccepted;
        target.answersJson = source.answersJson;
        return target;
    }

    private static TotemLeadApplicationService.ValidationRequest toInternalValidationRequest(
        TotemLeadPublicValidationRequest source
    ) {
        if (source == null) {
            return null;
        }
        TotemLeadApplicationService.ValidationRequest target = new TotemLeadApplicationService.ValidationRequest();
        target.accessToken = source.accessToken;
        target.code = source.code;
        return target;
    }

    private static TotemLeadPublicConfig toPublicConfig(TotemLeadConfigService.Config source) {
        TotemLeadPublicConfig target = new TotemLeadPublicConfig();
        target.key = source.key;
        target.partnerName = source.partnerName;
        target.logoPath = source.logoPath;
        target.backgroundImagePath = source.backgroundImagePath;
        target.primaryColor = source.primaryColor;
        target.secondaryColor = source.secondaryColor;
        target.accentColor = source.accentColor;
        target.textColor = source.textColor;
        target.content = source.content;
        target.showCpf = source.showCpf;
        target.requireCpf = source.requireCpf;
        target.requireEmail = source.requireEmail;
        target.requirePhone = source.requirePhone;
        target.requireConsent = source.requireConsent;
        target.consentLabel = source.consentLabel;
        target.consentLink = source.consentLink;
        target.blockMessage = source.blockMessage;
        target.invalidCodeMessage = source.invalidCodeMessage;
        target.deliveryFailureMessage = source.deliveryFailureMessage;
        target.questions = new List<TotemLeadPublicQuestion>();

        for (TotemLeadConfigService.QuestionConfig sourceQuestion : source.questions) {
            TotemLeadPublicQuestion targetQuestion = new TotemLeadPublicQuestion();
            targetQuestion.key = sourceQuestion.key;
            targetQuestion.label = sourceQuestion.label;
            targetQuestion.required = sourceQuestion.required;
            targetQuestion.options = new List<TotemLeadPublicOption>();
            for (TotemLeadConfigService.OptionConfig sourceOption : sourceQuestion.options) {
                TotemLeadPublicOption targetOption = new TotemLeadPublicOption();
                targetOption.key = sourceOption.key;
                targetOption.label = sourceOption.label;
                targetOption.estimatedSavings = sourceOption.estimatedSavings;
                targetQuestion.options.add(targetOption);
            }
            target.questions.add(targetQuestion);
        }
        return target;
    }

    private static TotemLeadPublicRequestResult toPublicRequestResult(
        TotemLeadApplicationService.RequestResult source
    ) {
        TotemLeadPublicRequestResult target = new TotemLeadPublicRequestResult();
        target.accessToken = source.accessToken;
        target.status = source.status;
        target.result = source.result;
        target.message = source.message;
        return target;
    }

    private static TotemLeadPublicDeliveryStatus toPublicDeliveryStatus(
        TotemLeadApplicationService.DeliveryStatus source
    ) {
        TotemLeadPublicDeliveryStatus target = new TotemLeadPublicDeliveryStatus();
        target.status = source.status;
        target.message = source.message;
        target.canRetry = source.canRetry;
        return target;
    }

    private static TotemLeadPublicValidationResult toPublicValidationResult(
        TotemLeadApplicationService.ValidationResult source
    ) {
        TotemLeadPublicValidationResult target = new TotemLeadPublicValidationResult();
        target.valid = source.valid;
        target.message = source.message;
        return target;
    }

    private static String safeMessage(Exception error, String fallback) {
        return error instanceof TotemLeadApplicationService.UserSafeException
            ? error.getMessage()
            : fallback;
    }

    private static AuraHandledException handled(String message) {
        AuraHandledException error = new AuraHandledException(message);
        error.setMessage(message);
        return error;
    }
}