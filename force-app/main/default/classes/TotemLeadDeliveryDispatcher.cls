public without sharing class TotemLeadDeliveryDispatcher implements Queueable, Database.AllowsCallouts {
    private static final Integer MAX_ATTEMPTS = 3;
    private Id codeId;

    public TotemLeadDeliveryDispatcher(Id codeId) {
        this.codeId = codeId;
    }

    public void execute(QueueableContext context) {
        List<Totem_Codigo_Validacao__c> records = [
            SELECT Id, Codigo__c, Lead__c, Config_Key__c, Expira_Em__c, Canal__c,
                Status_Envio__c, Tentativas_Envio__c, Message_Key__c, Email_Destino__c,
                Telefone_Destino__c
            FROM Totem_Codigo_Validacao__c
            WHERE Id = :codeId
            LIMIT 1
        ];
        if (records.isEmpty()) {
            return;
        }

        Totem_Codigo_Validacao__c codeRecord = records[0];
        Integer attempts = codeRecord.Tentativas_Envio__c == null
            ? 0
            : codeRecord.Tentativas_Envio__c.intValue();
        if (codeRecord.Status_Envio__c == 'ENVIADO' || attempts >= MAX_ATTEMPTS) {
            return;
        }

        TotemLeadConfigService.Config config;
        TotemLeadDeliveryResult result;
        try {
            config = TotemLeadConfigService.getConfig(codeRecord.Config_Key__c);
            TotemLeadDeliveryGateway gateway = config.marketingCloudEnabled && config.whatsappEnabled
                ? (TotemLeadDeliveryGateway) new TotemLeadMarketingCloudDeliveryGateway()
                : (TotemLeadDeliveryGateway) new TotemLeadEmailDeliveryGateway();
            result = gateway.send(codeRecord, config);
        } catch (Exception error) {
            result = TotemLeadDeliveryResult.failed('DELIVERY_UNEXPECTED');
        }

        codeRecord.Tentativas_Envio__c = attempts + 1;
        codeRecord.Ultimo_Envio_Em__c = Datetime.now();
        codeRecord.Status_Envio__c = result.success ? 'ENVIADO' : 'FALHA';
        codeRecord.Erro_Envio_Categoria__c = result.success ? null : result.category.left(80);
        update codeRecord;

        List<Totem_Interacao__c> interactions = [
            SELECT Id, Status__c, Resultado__c
            FROM Totem_Interacao__c
            WHERE Codigo__c = :codeRecord.Id
            AND Status__c IN ('PENDENTE_ENVIO', 'PROCESSANDO')
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        if (!interactions.isEmpty()) {
            interactions[0].Status__c = result.success ? 'ENVIADO' : 'FALHA_ENVIO';
            interactions[0].Resultado__c = result.success ? 'CODIGO_ENVIADO' : 'ENVIO_FALHOU';
            interactions[0].Erro_Categoria__c = result.success ? null : result.category.left(80);
            update interactions[0];
        }
    }
}