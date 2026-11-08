public with sharing class KanbanRepasseModel {
    public KanbanRepasseModel(Boolean includeAll) {}
    public String agregateFiltersSubPage(Repasse__c repasse) {
        return repasse == null ? null : repasse.NomeSintese__c;
    }
}