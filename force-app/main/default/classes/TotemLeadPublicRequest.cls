public class TotemLeadPublicRequest {
    @AuraEnabled public String requestId { get; set; }
    @AuraEnabled public String configurationKey { get; set; }
    @AuraEnabled public String firstName { get; set; }
    @AuraEnabled public String lastName { get; set; }
    @AuraEnabled public String fullName { get; set; }
    @AuraEnabled public String cpf { get; set; }
    @AuraEnabled public String email { get; set; }
    @AuraEnabled public String mobilePhone { get; set; }
    @AuraEnabled public Boolean consentAccepted { get; set; }
    @AuraEnabled public String answersJson { get; set; }
}