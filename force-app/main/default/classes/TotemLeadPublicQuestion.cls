public class TotemLeadPublicQuestion {
    @AuraEnabled public String key { get; set; }
    @AuraEnabled public String label { get; set; }
    @AuraEnabled public Boolean required { get; set; }
    @AuraEnabled public List<TotemLeadPublicOption> options { get; set; }
}