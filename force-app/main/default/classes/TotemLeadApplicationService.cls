public without sharing class TotemLeadApplicationService {
    private static final String TASK_SUBJECT = 'Inteiração Totem';
    private static final String TASK_TYPE = 'Reiteração';
    private static final String TASK_STATUS = 'Aberta';
    private static final Integer MAX_VALIDATION_ATTEMPTS = 10;
    private static final Integer MAX_DELIVERY_ATTEMPTS = 3;

    public class RequestData {
        @AuraEnabled public String requestId;
        @AuraEnabled public String configurationKey;
        @AuraEnabled public String firstName;
        @AuraEnabled public String lastName;
        @AuraEnabled public String fullName;
        @AuraEnabled public String cpf;
        @AuraEnabled public String email;
        @AuraEnabled public String mobilePhone;
        @AuraEnabled public Boolean consentAccepted;
        @AuraEnabled public String answersJson;
    }

    public class RequestResult {
        @AuraEnabled public String accessToken;
        @AuraEnabled public String status;
        @AuraEnabled public String result;
        @AuraEnabled public String message;
    }

    public class DeliveryStatus {
        @AuraEnabled public String status;
        @AuraEnabled public String message;
        @AuraEnabled public Boolean canRetry;
    }

    public class ValidationRequest {
        @AuraEnabled public String accessToken;
        @AuraEnabled public String code;
    }

    public class ValidationResult {
        @AuraEnabled public Boolean valid;
        @AuraEnabled public String message;
    }

    public static RequestResult requestCode(RequestData requestData) {
        TotemLeadConfigService.Config config = TotemLeadConfigService.getConfig(
            requestData == null ? null : requestData.configurationKey
        );
        ValidatedRequest validated = validateRequest(requestData, config);

        Totem_Interacao__c interaction = new Totem_Interacao__c(
            Request_Id__c = validated.requestId,
            Access_Token__c = generateAccessToken(),
            Config_Key__c = config.key,
            Parceiro__c = config.partnerName,
            Status__c = 'PROCESSANDO',
            Data_Hora__c = Datetime.now(),
            Tentativas_Validacao__c = 0
        );
        try {
            insert interaction;
        } catch (DmlException error) {
            if (containsDuplicateError(error)) {
                return existingRequestResult(validated.requestId);
            }
            throw error;
        }

        Lead leadRecord = LeadDeduplicacaoService.buscarLeadPrincipal(
            validated.cpf,
            validated.phone,
            validated.email
        );
        Boolean leadCreated = false;
        if (leadRecord == null) {
            leadRecord = createLead(validated, config);
            leadCreated = true;
        }

        TotemLeadCodeService.Decision codeDecision = TotemLeadCodeService.evaluateOrCreate(
            leadRecord,
            interaction,
            config,
            validated.email,
            validated.phone
        );

        Task taskRecord = createTask(
            leadRecord,
            interaction.Request_Id__c,
            config.partnerName,
            codeDecision.result
        );

        interaction.Lead__c = leadRecord.Id;
        interaction.Codigo__c = codeDecision.codeRecord == null ? null : codeDecision.codeRecord.Id;
        interaction.Task_Id__c = taskRecord.Id;
        interaction.Resultado__c = leadCreated
            ? 'LEAD_NOVO_' + codeDecision.result
            : 'LEAD_EXISTENTE_' + codeDecision.result;
        interaction.Status__c = codeDecision.status;
        update interaction;

        if (codeDecision.enqueueDelivery && codeDecision.codeRecord != null) {
            System.enqueueJob(new TotemLeadDeliveryDispatcher(codeDecision.codeRecord.Id));
        }

        RequestResult response = new RequestResult();
        response.accessToken = interaction.Access_Token__c;
        response.status = codeDecision.status;
        response.result = interaction.Resultado__c;
        response.message = codeDecision.blocked ? config.blockMessage : null;
        return response;
    }

    public static DeliveryStatus getDeliveryStatus(String accessToken) {
        Totem_Interacao__c interaction = getInteraction(accessToken, false);
        TotemLeadConfigService.Config config = TotemLeadConfigService.getConfig(interaction.Config_Key__c);
        return buildDeliveryStatus(interaction, config);
    }

    public static DeliveryStatus retryDelivery(String accessToken) {
        Totem_Interacao__c interaction = getInteraction(accessToken, true);
        TotemLeadConfigService.Config config = TotemLeadConfigService.getConfig(interaction.Config_Key__c);
        if (interaction.Codigo__c == null) {
            return buildDeliveryStatus(interaction, config);
        }

        Totem_Codigo_Validacao__c codeRecord = [
            SELECT Id, Status_Envio__c, Tentativas_Envio__c
            FROM Totem_Codigo_Validacao__c
            WHERE Id = :interaction.Codigo__c
            LIMIT 1
            FOR UPDATE
        ];
        Integer attempts = codeRecord.Tentativas_Envio__c == null
            ? 0
            : codeRecord.Tentativas_Envio__c.intValue();
        if (codeRecord.Status_Envio__c == 'FALHA' && attempts < MAX_DELIVERY_ATTEMPTS) {
            codeRecord.Status_Envio__c = 'PENDENTE';
            update codeRecord;
            interaction.Status__c = 'PENDENTE_ENVIO';
            interaction.Resultado__c = 'REPROCESSANDO_ENVIO';
            interaction.Erro_Categoria__c = null;
            update interaction;
            System.enqueueJob(new TotemLeadDeliveryDispatcher(codeRecord.Id));
        }
        return buildDeliveryStatus(interaction, config);
    }

    public static ValidationResult validateCode(ValidationRequest requestData) {
        String accessToken = normalizeAccessToken(requestData == null ? null : requestData.accessToken);
        String informedCode = normalizeCode(requestData == null ? null : requestData.code);
        Totem_Interacao__c interaction = getInteraction(accessToken, true);
        TotemLeadConfigService.Config config = TotemLeadConfigService.getConfig(interaction.Config_Key__c);

        Integer attempts = interaction.Tentativas_Validacao__c == null
            ? 0
            : interaction.Tentativas_Validacao__c.intValue();
        interaction.Tentativas_Validacao__c = attempts + 1;

        if (attempts >= MAX_VALIDATION_ATTEMPTS || interaction.Codigo__c == null) {
            update interaction;
            return invalidValidation(config);
        }

        Totem_Codigo_Validacao__c codeRecord = [
            SELECT Id, Codigo__c, Lead__c, Expira_Em__c, Utilizado__c, Utilizado_Em__c,
                Status_Envio__c
            FROM Totem_Codigo_Validacao__c
            WHERE Id = :interaction.Codigo__c
            LIMIT 1
            FOR UPDATE
        ];
        Boolean isValid = !String.isBlank(informedCode) &&
            codeRecord.Codigo__c.equalsIgnoreCase(informedCode) &&
            !codeRecord.Utilizado__c &&
            codeRecord.Status_Envio__c == 'ENVIADO' &&
            codeRecord.Expira_Em__c > Datetime.now();

        if (!isValid) {
            update interaction;
            return invalidValidation(config);
        }

        Datetime usedAt = Datetime.now();
        codeRecord.Utilizado__c = true;
        codeRecord.Utilizado_Em__c = usedAt;
        update codeRecord;

        Lead leadRecord = [
            SELECT Id, Dados_Validados_Totem__c, Data_Hora_Validacao_Totem__c
            FROM Lead
            WHERE Id = :codeRecord.Lead__c
            LIMIT 1
            FOR UPDATE
        ];
        leadRecord.Dados_Validados_Totem__c = true;
        if (leadRecord.Data_Hora_Validacao_Totem__c == null) {
            leadRecord.Data_Hora_Validacao_Totem__c = usedAt;
        }
        leadRecord.Parceiro_Ultima_Validacao_Totem__c = config.partnerName;
        update leadRecord;

        interaction.Status__c = 'VALIDADO';
        interaction.Resultado__c = 'CODIGO_VALIDADO';
        update interaction;

        ValidationResult response = new ValidationResult();
        response.valid = true;
        response.message = contentText(
            config,
            'validationSuccessMessage',
            'Dados validados. Você já pode retirar seu brinde!'
        );
        return response;
    }

    private static RequestResult existingRequestResult(String requestId) {
        List<Totem_Interacao__c> records = [
            SELECT Access_Token__c, Status__c, Resultado__c, Config_Key__c
            FROM Totem_Interacao__c
            WHERE Request_Id__c = :requestId
            LIMIT 1
        ];
        if (records.isEmpty()) {
            throw new UserSafeException('Não foi possível processar a solicitação.');
        }
        Totem_Interacao__c interaction = records[0];
        TotemLeadConfigService.Config config = TotemLeadConfigService.getConfig(interaction.Config_Key__c);
        RequestResult response = new RequestResult();
        response.accessToken = interaction.Access_Token__c;
        response.status = interaction.Status__c;
        response.result = interaction.Resultado__c;
        response.message = interaction.Status__c == 'BLOQUEADO' ? config.blockMessage : null;
        return response;
    }

    private static Lead createLead(ValidatedRequest requestData, TotemLeadConfigService.Config config) {
        Id originatorId = resolveOriginator(config.originatorAlias);
        Lead newLead = new Lead(
            FirstName = requestData.firstName,
            LastName = requestData.lastName,
            Company = requestData.fullName,
            Email = requestData.email,
            MobilePhone = requestData.phone,
            CPF__c = requestData.cpf,
            Custo__c = requestData.estimatedSavings,
            LeadSource = config.leadSource,
            Form_Web__c = config.formWeb,
            Originador__c = originatorId
        );
        insert newLead;

        List<Lead> persisted = [
            SELECT Id, OwnerId, CreatedDate, CPF__c, Email, MobilePhone, LastName, Company
            FROM Lead
            WHERE Id = :newLead.Id
            LIMIT 1
        ];
        if (!persisted.isEmpty()) {
            return persisted[0];
        }

        Lead principal = LeadDeduplicacaoService.buscarLeadPrincipal(
            requestData.cpf,
            requestData.phone,
            requestData.email
        );
        if (principal == null) {
            throw new UserSafeException('Não foi possível concluir o cadastro.');
        }
        return principal;
    }

    private static Task createTask(
        Lead leadRecord,
        String requestId,
        String partner,
        String result
    ) {
        Task taskRecord = new Task(
            WhoId = leadRecord.Id,
            OwnerId = leadRecord.OwnerId,
            Subject = TASK_SUBJECT,
            Type = TASK_TYPE,
            Status = TASK_STATUS,
            ActivityDate = null,
            Parceiro_Totem__c = partner,
            Resultado_Totem__c = result,
            Data_Hora_Tentativa_Totem__c = Datetime.now(),
            Request_Id_Totem__c = requestId,
            Description = 'Tentativa registrada pelo Totem de Leads. Resultado: ' + result + '.'
        );
        insert taskRecord;
        return taskRecord;
    }

    private static Id resolveOriginator(String originatorAlias) {
        if (String.isBlank(originatorAlias)) {
            return null;
        }
        List<Originador__c> records = [
            SELECT Id
            FROM Originador__c
            WHERE Apelido__c = :originatorAlias
            LIMIT 1
        ];
        if (records.isEmpty()) {
            throw new UserSafeException('Configuração de origem indisponível.');
        }
        return records[0].Id;
    }

    private static DeliveryStatus buildDeliveryStatus(
        Totem_Interacao__c interaction,
        TotemLeadConfigService.Config config
    ) {
        DeliveryStatus response = new DeliveryStatus();
        response.canRetry = false;

        if (interaction.Status__c == 'BLOQUEADO') {
            response.status = 'BLOQUEADO';
            response.message = config.blockMessage;
            return response;
        }
        if (interaction.Status__c == 'VALIDADO') {
            response.status = 'VALIDADO';
            response.message = contentText(
                config,
                'validationSuccessMessage',
                'Dados validados. Você já pode retirar seu brinde!'
            );
            return response;
        }
        if (interaction.Codigo__c == null) {
            response.status = 'PROCESSANDO';
            return response;
        }

        Totem_Codigo_Validacao__c codeRecord = [
            SELECT Status_Envio__c, Tentativas_Envio__c
            FROM Totem_Codigo_Validacao__c
            WHERE Id = :interaction.Codigo__c
            LIMIT 1
        ];
        if (codeRecord.Status_Envio__c == 'ENVIADO') {
            response.status = 'ENVIADO';
            response.message = contentText(
                config,
                'codeSentMessage',
                'Enviamos o código para o e-mail informado.'
            );
        } else if (codeRecord.Status_Envio__c == 'FALHA') {
            Integer attempts = codeRecord.Tentativas_Envio__c == null
                ? 0
                : codeRecord.Tentativas_Envio__c.intValue();
            response.status = 'FALHA';
            response.message = config.deliveryFailureMessage;
            response.canRetry = attempts < MAX_DELIVERY_ATTEMPTS;
        } else {
            response.status = 'PROCESSANDO';
        }
        return response;
    }

    private static Totem_Interacao__c getInteraction(String accessToken, Boolean lockRecord) {
        String normalizedToken = normalizeAccessToken(accessToken);
        List<Totem_Interacao__c> records;
        if (lockRecord) {
            records = [
                SELECT Id, Access_Token__c, Config_Key__c, Status__c, Resultado__c,
                    Codigo__c, Lead__c, Tentativas_Validacao__c
                FROM Totem_Interacao__c
                WHERE Access_Token__c = :normalizedToken
                LIMIT 1
                FOR UPDATE
            ];
        } else {
            records = [
                SELECT Id, Access_Token__c, Config_Key__c, Status__c, Resultado__c,
                    Codigo__c, Lead__c, Tentativas_Validacao__c
                FROM Totem_Interacao__c
                WHERE Access_Token__c = :normalizedToken
                LIMIT 1
            ];
        }
        if (records.isEmpty()) {
            throw new UserSafeException('Solicitação não localizada. Reinicie o cadastro.');
        }
        return records[0];
    }

    private static ValidatedRequest validateRequest(
        RequestData requestData,
        TotemLeadConfigService.Config config
    ) {
        if (requestData == null) {
            throw new UserSafeException('Preencha os dados para continuar.');
        }

        ValidatedRequest result = new ValidatedRequest();
        result.requestId = normalizeRequestId(requestData.requestId);
        result.fullName = normalizeText(
            String.isBlank(requestData.fullName)
                ? joinName(requestData.firstName, requestData.lastName)
                : requestData.fullName,
            120
        );
        if (String.isBlank(result.fullName)) {
            throw new UserSafeException('Informe o nome completo.');
        }
        List<String> names = result.fullName.split(' ');
        result.firstName = names.size() > 1 ? names[0] : null;
        result.lastName = names.size() > 1
            ? result.fullName.substring(result.fullName.indexOf(' ') + 1)
            : result.fullName;
        result.cpf = digits(requestData.cpf, 11);
        result.phone = digits(requestData.mobilePhone, 13);
        result.email = normalizeEmail(requestData.email);

        if (config.showCpf && config.requireCpf && result.cpf.length() != 11) {
            throw new UserSafeException('Informe um CPF válido.');
        }
        if (config.requirePhone && (result.phone.length() < 10 || result.phone.length() > 13)) {
            throw new UserSafeException('Informe um WhatsApp válido.');
        }
        if (config.requireEmail && !isValidEmail(result.email)) {
            throw new UserSafeException('Informe um e-mail válido.');
        }
        if (config.requireConsent && requestData.consentAccepted != true) {
            throw new UserSafeException('Aceite o consentimento para continuar.');
        }
        result.estimatedSavings = validateAnswers(requestData.answersJson, config.questions);
        return result;
    }

    private static Decimal validateAnswers(
        String answersJson,
        List<TotemLeadConfigService.QuestionConfig> questions
    ) {
        Map<String, Object> answers = new Map<String, Object>();
        if (!String.isBlank(answersJson)) {
            try {
                Object parsed = JSON.deserializeUntyped(answersJson);
                if (parsed instanceof Map<String, Object>) {
                    answers = (Map<String, Object>) parsed;
                }
            } catch (JSONException error) {
                throw new UserSafeException('Responda às perguntas da simulação.');
            }
        }

        Decimal estimatedSavings = 0;
        for (TotemLeadConfigService.QuestionConfig question : questions) {
            String answer = answers.containsKey(question.key)
                ? String.valueOf(answers.get(question.key))
                : null;
            if (question.required && String.isBlank(answer)) {
                throw new UserSafeException('Responda às perguntas da simulação.');
            }
            Boolean validOption = String.isBlank(answer);
            for (TotemLeadConfigService.OptionConfig option : question.options) {
                if (option.key == answer) {
                    validOption = true;
                    if (option.estimatedSavings != null) {
                        estimatedSavings += option.estimatedSavings;
                    }
                    break;
                }
            }
            if (!validOption) {
                throw new UserSafeException('Resposta da simulação inválida.');
            }
        }
        return estimatedSavings;
    }

    private static ValidationResult invalidValidation(TotemLeadConfigService.Config config) {
        ValidationResult response = new ValidationResult();
        response.valid = false;
        response.message = config.invalidCodeMessage;
        return response;
    }

    private static String contentText(
        TotemLeadConfigService.Config config,
        String key,
        String fallback
    ) {
        Object value = config.content == null ? null : config.content.get(key);
        return value == null || String.isBlank(String.valueOf(value))
            ? fallback
            : String.valueOf(value).left(255);
    }

    private static String generateAccessToken() {
        return EncodingUtil.convertToHex(Crypto.generateAesKey(256));
    }

    private static String normalizeRequestId(String value) {
        String normalized = normalizeText(value, 36);
        if (
            String.isBlank(normalized) ||
            normalized.length() < 16 ||
            !Pattern.matches('^[A-Za-z0-9-]+$', normalized)
        ) {
            throw new UserSafeException('Solicitação inválida. Reinicie o cadastro.');
        }
        return normalized;
    }

    private static String normalizeAccessToken(String value) {
        String normalized = normalizeText(value, 64);
        if (
            String.isBlank(normalized) ||
            normalized.length() != 64 ||
            !Pattern.matches('^[A-Fa-f0-9]+$', normalized)
        ) {
            throw new UserSafeException('Solicitação não localizada. Reinicie o cadastro.');
        }
        return normalized;
    }

    private static String normalizeCode(String value) {
        String normalized = normalizeText(value, 30);
        return String.isBlank(normalized) ? null : normalized.toUpperCase();
    }

    private static String normalizeEmail(String value) {
        String normalized = normalizeText(value, 80);
        return String.isBlank(normalized) ? null : normalized.toLowerCase();
    }

    private static Boolean isValidEmail(String value) {
        return !String.isBlank(value) && Pattern.matches(
            '(?i)^[A-Z0-9._%+\\-]+@[A-Z0-9.\\-]+\\.[A-Z]{2,}$',
            value
        );
    }

    private static String digits(String value, Integer maxLength) {
        if (String.isBlank(value)) {
            return '';
        }
        String result = value.replaceAll('[^0-9]', '');
        return result.length() > maxLength ? result.substring(0, maxLength) : result;
    }

    private static String normalizeText(String value, Integer maxLength) {
        if (String.isBlank(value)) {
            return null;
        }
        String result = value.trim().replaceAll('\\s+', ' ');
        return result.length() > maxLength ? result.substring(0, maxLength) : result;
    }

    private static String joinName(String firstName, String lastName) {
        return String.join(
            new List<String>{
                String.isBlank(firstName) ? '' : firstName,
                String.isBlank(lastName) ? '' : lastName
            },
            ' '
        ).trim();
    }

    private static Boolean containsDuplicateError(DmlException error) {
        for (Integer index = 0; index < error.getNumDml(); index++) {
            if (error.getDmlType(index) == StatusCode.DUPLICATE_VALUE) {
                return true;
            }
        }
        return false;
    }

    private class ValidatedRequest {
        String requestId;
        String firstName;
        String lastName;
        String fullName;
        String cpf;
        String email;
        String phone;
        Decimal estimatedSavings;
    }

    public class UserSafeException extends Exception {
    }
}