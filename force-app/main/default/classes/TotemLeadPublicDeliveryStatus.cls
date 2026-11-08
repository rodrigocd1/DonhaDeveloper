public class TotemLeadPublicDeliveryStatus {
    @AuraEnabled public String status { get; set; }
    @AuraEnabled public String message { get; set; }
    @AuraEnabled public Boolean canRetry { get; set; }
}