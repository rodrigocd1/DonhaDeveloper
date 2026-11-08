public with sharing class CommunicatorOpportunityAccessService {

    public static List<Opportunity> getVisibleOpportunitiesByIds(Set<Id> opportunityIds) {
        if (opportunityIds == null || opportunityIds.isEmpty()) {
            return new List<Opportunity>();
        }

        Set<Id> visibleAssessoriaIds = CommunicatorThreadService.getVisibleAssessoriaIdsForCurrentUser();
        if (visibleAssessoriaIds != null && !visibleAssessoriaIds.isEmpty()) {
            List<Opportunity> visibleByAssessoria = new List<Opportunity>();
            for (Opportunity opp : [
                SELECT Id, Name, StageName, LastModifiedDate, AssessoriaCredito__c
                FROM Opportunity
                WHERE Id IN :opportunityIds
                AND AssessoriaCredito__c IN :visibleAssessoriaIds
            ]) {
                visibleByAssessoria.add(opp);
            }
            return visibleByAssessoria;
        }

        return [
            SELECT Id, Name, StageName, LastModifiedDate, AssessoriaCredito__c
            FROM Opportunity
            WHERE Id IN :opportunityIds
        ];
    }

    public static Set<Id> getVisibleOpportunityIds(Set<Id> opportunityIds) {
        Set<Id> visibleOpportunityIds = new Set<Id>();
        for (Opportunity opp : getVisibleOpportunitiesByIds(opportunityIds)) {
            visibleOpportunityIds.add(opp.Id);
        }
        return visibleOpportunityIds;
    }
}