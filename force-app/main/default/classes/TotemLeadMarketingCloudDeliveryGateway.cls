public inherited sharing class TotemLeadMarketingCloudDeliveryGateway implements TotemLeadDeliveryGateway {
    public TotemLeadDeliveryResult send(
        Totem_Codigo_Validacao__c codeRecord,
        TotemLeadConfigService.Config config
    ) {
        if (
            !config.marketingCloudEnabled ||
            !config.whatsappEnabled ||
            String.isBlank(config.marketingCloudNamedCredential) ||
            String.isBlank(config.marketingCloudDefinitionKey) ||
            String.isBlank(codeRecord.Telefone_Destino__c)
        ) {
            return TotemLeadDeliveryResult.failed('MARKETING_CLOUD_NOT_CONFIGURED');
        }

        HttpRequest request = new HttpRequest();
        request.setMethod('POST');
        request.setEndpoint(
            'callout:' + config.marketingCloudNamedCredential + '/messaging/v1/ott/messages'
        );
        request.setHeader('Content-Type', 'application/json');
        request.setTimeout(10000);
        request.setBody(JSON.serialize(new Map<String, Object>{
            'definitionKey' => config.marketingCloudDefinitionKey,
            'messageKey' => codeRecord.Message_Key__c,
            'recipient' => new Map<String, Object>{
                'contactKey' => String.valueOf(codeRecord.Lead__c),
                'to' => normalizeE164(codeRecord.Telefone_Destino__c),
                'attributes' => new Map<String, Object>{
                    'code' => codeRecord.Codigo__c,
                    'expiration' => codeRecord.Expira_Em__c.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'')
                }
            }
        }));

        try {
            HttpResponse response = new Http().send(request);
            if (response.getStatusCode() >= 200 && response.getStatusCode() < 300) {
                return TotemLeadDeliveryResult.succeeded();
            }
            return TotemLeadDeliveryResult.failed('MARKETING_CLOUD_HTTP_' + response.getStatusCode());
        } catch (CalloutException error) {
            return TotemLeadDeliveryResult.failed('MARKETING_CLOUD_CALLOUT');
        }
    }

    private static String normalizeE164(String value) {
        String digits = value == null ? '' : value.replaceAll('[^0-9]', '');
        if (digits.length() == 10 || digits.length() == 11) {
            digits = '55' + digits;
        }
        return '+' + digits;
    }
}