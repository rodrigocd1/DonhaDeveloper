public interface TotemLeadDeliveryGateway {
    TotemLeadDeliveryResult send(
        Totem_Codigo_Validacao__c codeRecord,
        TotemLeadConfigService.Config config
    );
}