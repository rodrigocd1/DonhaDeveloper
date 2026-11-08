public inherited sharing class TotemLeadEmailDeliveryGateway implements TotemLeadDeliveryGateway {
    public TotemLeadDeliveryResult send(
        Totem_Codigo_Validacao__c codeRecord,
        TotemLeadConfigService.Config config
    ) {
        if (!config.emailEnabled || String.isBlank(codeRecord.Email_Destino__c)) {
            return TotemLeadDeliveryResult.failed('EMAIL_NOT_CONFIGURED');
        }
        if (String.isBlank(config.emailSenderAddress)) {
            return TotemLeadDeliveryResult.failed('EMAIL_SENDER_NOT_CONFIGURED');
        }

        Id senderId = resolveSenderId(config.emailSenderAddress);
        if (!Test.isRunningTest() && senderId == null) {
            return TotemLeadDeliveryResult.failed('EMAIL_SENDER_NOT_CONFIGURED');
        }

        String expiration = codeRecord.Expira_Em__c.format('dd/MM/yyyy HH:mm', 'America/Sao_Paulo');
        String body = config.emailBody
            .replace('{CODE}', codeRecord.Codigo__c)
            .replace('{EXPIRATION}', expiration);

        Messaging.SingleEmailMessage message = new Messaging.SingleEmailMessage();
        message.setToAddresses(new List<String>{ codeRecord.Email_Destino__c });
        message.setSubject(config.emailSubject);
        message.setPlainTextBody(body);
        message.setSaveAsActivity(false);
        if (senderId != null) {
            message.setOrgWideEmailAddressId(senderId);
        }

        try {
            Messaging.SendEmailResult[] results = Messaging.sendEmail(
                new List<Messaging.SingleEmailMessage>{ message },
                false
            );
            if (!results.isEmpty() && results[0].isSuccess()) {
                return TotemLeadDeliveryResult.succeeded();
            }
            return TotemLeadDeliveryResult.failed('EMAIL_PROVIDER_REJECTED');
        } catch (EmailException error) {
            return TotemLeadDeliveryResult.failed('EMAIL_EXCEPTION');
        }
    }

    private static Id resolveSenderId(String senderAddress) {
        // Registros de Org-Wide Email Address não podem ser criados de forma isolada em teste.
        if (Test.isRunningTest()) {
            return null;
        }

        List<OrgWideEmailAddress> senders = [
            SELECT Id
            FROM OrgWideEmailAddress
            WHERE Address = :senderAddress
                AND IsVerified = TRUE
                AND IsAllowAllProfiles = TRUE
            LIMIT 1
        ];
        return senders.isEmpty() ? null : senders[0].Id;
    }
}