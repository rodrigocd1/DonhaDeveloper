public class TotemLeadPublicConfig {
    @AuraEnabled public String key { get; set; }
    @AuraEnabled public String partnerName { get; set; }
    @AuraEnabled public String logoPath { get; set; }
    @AuraEnabled public String backgroundImagePath { get; set; }
    @AuraEnabled public String primaryColor { get; set; }
    @AuraEnabled public String secondaryColor { get; set; }
    @AuraEnabled public String accentColor { get; set; }
    @AuraEnabled public String textColor { get; set; }
    @AuraEnabled public Map<String, Object> content { get; set; }
    @AuraEnabled public List<TotemLeadPublicQuestion> questions { get; set; }
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
}