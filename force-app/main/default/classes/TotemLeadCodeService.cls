public without sharing class TotemLeadCodeService {
    private static final Integer MAX_DELIVERY_ATTEMPTS = 3;

    public class Decision {
        public Totem_Codigo_Validacao__c codeRecord { get; set; }
        public String result { get; set; }
        public String status { get; set; }
        public Boolean enqueueDelivery { get; set; }
        public Boolean blocked { get; set; }
    }

    public static Decision evaluateOrCreate(
        Lead leadRecord,
        Totem_Interacao__c interaction,
        TotemLeadConfigService.Config config,
        String email,
        String phone
    ) {
        Datetime nowValue = Datetime.now();
        Datetime blockStart = nowValue.addDays(-config.blockDays);
        Totem_Codigo_Validacao__c activeCode;
        Boolean usedInsideBlock = false;

        for (Totem_Codigo_Validacao__c codeRecord : [
            SELECT Id, Codigo__c, Lead__c, Config_Key__c, Parceiro__c, Gerado_Em__c,
                Expira_Em__c, Utilizado__c, Utilizado_Em__c, Canal__c, Status_Envio__c,
                Tentativas_Envio__c, Message_Key__c, Email_Destino__c, Telefone_Destino__c
            FROM Totem_Codigo_Validacao__c
            WHERE Lead__c = :leadRecord.Id
            FOR UPDATE
        ]) {
            if (
                codeRecord.Utilizado__c &&
                codeRecord.Utilizado_Em__c != null &&
                codeRecord.Utilizado_Em__c >= blockStart
            ) {
                usedInsideBlock = true;
            }
            if (
                !codeRecord.Utilizado__c &&
                codeRecord.Expira_Em__c > nowValue &&
                (
                    activeCode == null ||
                    codeRecord.Gerado_Em__c > activeCode.Gerado_Em__c
                )
            ) {
                activeCode = codeRecord;
            }
        }

        Decision decision = new Decision();
        decision.enqueueDelivery = false;
        decision.blocked = false;

        if (usedInsideBlock) {
            decision.result = 'BLOQUEADO_CODIGO_UTILIZADO';
            decision.status = 'BLOQUEADO';
            decision.blocked = true;
            return decision;
        }

        if (activeCode != null) {
            decision.codeRecord = activeCode;
            Integer deliveryAttempts = activeCode.Tentativas_Envio__c == null
                ? 0
                : activeCode.Tentativas_Envio__c.intValue();
            if (activeCode.Status_Envio__c == 'FALHA' && deliveryAttempts < MAX_DELIVERY_ATTEMPTS) {
                activeCode.Email_Destino__c = email;
                activeCode.Telefone_Destino__c = phone;
                activeCode.Status_Envio__c = 'PENDENTE';
                update activeCode;
                decision.result = 'REPROCESSANDO_ENVIO';
                decision.status = 'PENDENTE_ENVIO';
                decision.enqueueDelivery = true;
            } else {
                decision.result = 'BLOQUEADO_CODIGO_ATIVO';
                decision.status = 'BLOQUEADO';
                decision.blocked = true;
            }
            return decision;
        }

        decision.codeRecord = createUniqueCode(leadRecord, interaction, config, email, phone);
        decision.result = 'NOVO_CODIGO';
        decision.status = 'PENDENTE_ENVIO';
        decision.enqueueDelivery = true;
        return decision;
    }

    private static Totem_Codigo_Validacao__c createUniqueCode(
        Lead leadRecord,
        Totem_Interacao__c interaction,
        TotemLeadConfigService.Config config,
        String email,
        String phone
    ) {
        for (Integer attempt = 0; attempt < 2; attempt++) {
            List<String> candidates = generateCandidates(config.codePrefix, 8);
            Set<String> existing = new Set<String>();
            for (Totem_Codigo_Validacao__c existingRecord : [
                SELECT Codigo__c
                FROM Totem_Codigo_Validacao__c
                WHERE Codigo__c IN :candidates
            ]) {
                existing.add(existingRecord.Codigo__c);
            }

            String selected;
            for (String candidate : candidates) {
                if (!existing.contains(candidate)) {
                    selected = candidate;
                    break;
                }
            }
            if (selected == null) {
                continue;
            }

            Datetime generatedAt = Datetime.now();
            Totem_Codigo_Validacao__c codeRecord = new Totem_Codigo_Validacao__c(
                Codigo__c = selected,
                Lead__c = leadRecord.Id,
                Interacao_Origem__c = interaction.Id,
                Config_Key__c = config.key,
                Parceiro__c = config.partnerName,
                Gerado_Em__c = generatedAt,
                Expira_Em__c = generatedAt.addHours(config.codeValidityHours),
                Utilizado__c = false,
                Canal__c = config.marketingCloudEnabled && config.whatsappEnabled
                    ? 'WhatsApp'
                    : 'E-mail',
                Status_Envio__c = 'PENDENTE',
                Tentativas_Envio__c = 0,
                Message_Key__c = interaction.Access_Token__c,
                Email_Destino__c = email,
                Telefone_Destino__c = phone
            );
            try {
                insert codeRecord;
                return codeRecord;
            } catch (DmlException error) {
                if (!containsDuplicateError(error) || attempt == 1) {
                    throw error;
                }
            }
        }
        throw new CodeGenerationException('CODE_GENERATION_EXHAUSTED');
    }

    @TestVisible
    private static List<String> generateCandidates(String prefix, Integer quantity) {
        List<String> result = new List<String>();
        Set<String> uniqueValues = new Set<String>();
        while (result.size() < quantity) {
            Integer randomValue = Crypto.getRandomInteger();
            Integer numericCode = Math.mod(randomValue, 100000);
            if (numericCode < 0) {
                numericCode = -numericCode;
            }
            String numericText = String.valueOf(numericCode);
            while (numericText.length() < 5) {
                numericText = '0' + numericText;
            }
            String candidate = prefix + '-' + numericText;
            if (uniqueValues.add(candidate)) {
                result.add(candidate);
            }
        }
        return result;
    }

    private static Boolean containsDuplicateError(DmlException error) {
        for (Integer index = 0; index < error.getNumDml(); index++) {
            if (error.getDmlType(index) == StatusCode.DUPLICATE_VALUE) {
                return true;
            }
        }
        return false;
    }

    public class CodeGenerationException extends Exception {
    }
}