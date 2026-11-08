public without sharing class CommunicatorOpportunityDataService {

    public static List<Opportunity> getOpportunitiesByIds(Set<Id> opportunityIds) {
        if (opportunityIds == null || opportunityIds.isEmpty()) return new List<Opportunity>();
        return [
            SELECT Id, Name, StageName
            FROM Opportunity
            WHERE Id IN :opportunityIds
        ];
    }

    public static List<Opportunity> getOpportunitiesWithRelatedRefsByIds(Set<Id> opportunityIds) {
        if (opportunityIds == null || opportunityIds.isEmpty()) return new List<Opportunity>();
        return [
            SELECT Id, StageName, ApuracaoRenda__c, ApuracaoRenda__r.Name,
                   AnaliseCredito__c, SyncedQuoteId, SyncedQuote.Name, SyncedQuote.QuoteNumber
            FROM Opportunity
            WHERE Id IN :opportunityIds
        ];
    }

    public static List<AprovacaoBancaria__c> getAprovacaoBancariaByAnaliseCreditoIds(Set<Id> analiseCreditoIds) {
        if (analiseCreditoIds == null || analiseCreditoIds.isEmpty()) return new List<AprovacaoBancaria__c>();
        return [
            SELECT Id, Name, AnaliseCredito__c
            FROM AprovacaoBancaria__c
            WHERE AnaliseCredito__c IN :analiseCreditoIds
            ORDER BY LastModifiedDate DESC
        ];
    }

    public static List<AnaliseFinanceira__c> getAnaliseFinanceiraByIds(Set<Id> analiseCreditoIds) {
        if (analiseCreditoIds == null || analiseCreditoIds.isEmpty()) return new List<AnaliseFinanceira__c>();
        return [
            SELECT Id, Name
            FROM AnaliseFinanceira__c
            WHERE Id IN :analiseCreditoIds
        ];
    }

    public static List<Quote> getQuotesByOpportunityIds(Set<Id> opportunityIds) {
        if (opportunityIds == null || opportunityIds.isEmpty()) return new List<Quote>();
        return [
            SELECT Id, OpportunityId, Name, QuoteNumber
            FROM Quote
            WHERE OpportunityId IN :opportunityIds
            ORDER BY LastModifiedDate DESC
        ];
    }

    public static List<Repasse__c> getLatestRepassesByOpportunityIds(Set<Id> opportunityIds) {
        if (opportunityIds == null || opportunityIds.isEmpty()) return new List<Repasse__c>();
        return CommunicatorRepasseService.getLatestRepassesByOpportunityIds(opportunityIds).values();
    }
}