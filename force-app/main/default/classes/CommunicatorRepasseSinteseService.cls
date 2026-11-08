public with sharing class CommunicatorRepasseSinteseService {

    private static KanbanRepasseModel kanbanRepasseModel;

    public static String getGroupedSinteseLabel(Repasse__c repasse) {
        if (repasse == null || String.isBlank(repasse.NomeSintese__c)) {
            return null;
        }
        return getKanbanRepasseModel().agregateFiltersSubPage(repasse);
    }

    @TestVisible
    private static KanbanRepasseModel getKanbanRepasseModel() {
        if (kanbanRepasseModel == null) {
            kanbanRepasseModel = new KanbanRepasseModel(true);
        }
        return kanbanRepasseModel;
    }
}