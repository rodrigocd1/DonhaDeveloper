public class TotemLeadPublicRequestResult {
    @AuraEnabled public String accessToken { get; set; }
    @AuraEnabled public String status { get; set; }
    @AuraEnabled public String result { get; set; }
    @AuraEnabled public String message { get; set; }
}