public without sharing class CommunicatorRepasseService {

    public static Map<Id, Repasse__c> getRepassesByIds(Set<Id> repasseIds) {
        Map<Id, Repasse__c> repassesById = new Map<Id, Repasse__c>();
        if (repasseIds == null || repasseIds.isEmpty()) {
            return repassesById;
        }

        for (Repasse__c repasse : [
            SELECT Id, Name, Oportunidade__c, ContaAssessoria__c
            FROM Repasse__c
            WHERE Id IN :repasseIds
        ]) {
            repassesById.put(repasse.Id, repasse);
        }

        return repassesById;
    }

    public static Set<Id> getAssessoriaIdsByQueueIds(Set<Id> queueIds) {
        Set<Id> assessoriaIds = new Set<Id>();
        if (queueIds == null || queueIds.isEmpty()) {
            return assessoriaIds;
        }

        for (Account assessoriaAccount : [
            SELECT Id
            FROM Account
            WHERE RecordType.DeveloperName = 'AssessoriaCredito'
            AND Status__c = 'Ativo'
            AND IdFila__c IN :queueIds
        ]) {
            assessoriaIds.add(assessoriaAccount.Id);
        }

        return assessoriaIds;
    }

    public static Map<Id, Repasse__c> getLatestRepassesByOpportunityIds(Set<Id> opportunityIds) {
        return getLatestRepassesByOpportunityIds(opportunityIds, null);
    }

    public static Map<Id, Repasse__c> getLatestRepassesByOpportunityIds(
        Set<Id> opportunityIds,
        Set<Id> assessoriaIds
    ) {
        Map<Id, Repasse__c> latestByOppId = new Map<Id, Repasse__c>();
        if (opportunityIds == null || opportunityIds.isEmpty()) {
            return latestByOppId;
        }
        if (assessoriaIds != null && assessoriaIds.isEmpty()) {
            return latestByOppId;
        }

        String query =
            'SELECT Id, Name, Oportunidade__c, ContaAssessoria__c, NomeFase__c, NomeSintese__c, Sintese__r.Name, LastModifiedDate ' +
            'FROM Repasse__c ' +
            'WHERE Oportunidade__c IN :opportunityIds ';
        if (assessoriaIds != null) {
            query += 'AND ContaAssessoria__c IN :assessoriaIds ';
        }
        query += 'ORDER BY LastModifiedDate DESC';

        for (Repasse__c repasse : Database.query(query)) {
            if (repasse.Oportunidade__c != null && !latestByOppId.containsKey(repasse.Oportunidade__c)) {
                latestByOppId.put(repasse.Oportunidade__c, repasse);
            }
        }

        return latestByOppId;
    }

    public static Set<Id> getCandidateOpportunityIdsByKeyword(String keyword, Integer limitSize) {
        return getCandidateOpportunityIdsByKeyword(keyword, limitSize, null);
    }

    public static Set<Id> getCandidateOpportunityIdsByKeyword(
        String keyword,
        Integer limitSize,
        Set<Id> assessoriaIds
    ) {
        Set<Id> opportunityIds = new Set<Id>();
        if (String.isBlank(keyword)) {
            return opportunityIds;
        }
        if (assessoriaIds != null && assessoriaIds.isEmpty()) {
            return opportunityIds;
        }

        Integer queryLimit = (limitSize != null && limitSize > 0) ? limitSize : 20;
        String trimmedKeyword = keyword.trim();
        Set<String> macroPhaseSinteseValues =
            CommunicatorRepassePhaseHelper.getNomeSinteseValuesByMacroPhaseKeyword(trimmedKeyword);

        for (Repasse__c repasse : queryCandidateRepasses(trimmedKeyword, queryLimit, macroPhaseSinteseValues, assessoriaIds)) {
            if (repasse.Oportunidade__c != null) {
                opportunityIds.add(repasse.Oportunidade__c);
            }
        }

        return opportunityIds;
    }

    public static List<Repasse__c> getRepassesByOpportunityIds(
        Set<Id> opportunityIds,
        String keyword,
        Integer limitSize
    ) {
        return getRepassesByOpportunityIds(opportunityIds, keyword, limitSize, null);
    }

    public static List<Repasse__c> getRepassesByOpportunityIds(
        Set<Id> opportunityIds,
        String keyword,
        Integer limitSize,
        Set<Id> assessoriaIds
    ) {
        if (opportunityIds == null || opportunityIds.isEmpty()) {
            return new List<Repasse__c>();
        }
        if (assessoriaIds != null && assessoriaIds.isEmpty()) {
            return new List<Repasse__c>();
        }

        Integer queryLimit = (limitSize != null && limitSize > 0) ? limitSize : 20;
        String trimmedKeyword = String.isBlank(keyword) ? null : keyword.trim();

        if (String.isBlank(trimmedKeyword)) {
            return queryRepassesByOpportunityIds(opportunityIds, null, queryLimit, null, assessoriaIds);
        }

        Set<String> macroPhaseSinteseValues =
            CommunicatorRepassePhaseHelper.getNomeSinteseValuesByMacroPhaseKeyword(trimmedKeyword);
        return queryRepassesByOpportunityIds(
            opportunityIds,
            trimmedKeyword,
            queryLimit,
            macroPhaseSinteseValues,
            assessoriaIds
        );
    }

    public static Integer countRepassesByOpportunityIds(Set<Id> opportunityIds, String keyword) {
        return countRepassesByOpportunityIds(opportunityIds, keyword, null);
    }

    public static Integer countRepassesByOpportunityIds(
        Set<Id> opportunityIds,
        String keyword,
        Set<Id> assessoriaIds
    ) {
        if (opportunityIds == null || opportunityIds.isEmpty()) {
            return 0;
        }
        if (assessoriaIds != null && assessoriaIds.isEmpty()) {
            return 0;
        }

        String trimmedKeyword = String.isBlank(keyword) ? null : keyword.trim();
        if (String.isBlank(trimmedKeyword)) {
            return countRepassesByKeyword(opportunityIds, null, null, assessoriaIds);
        }

        Set<String> macroPhaseSinteseValues =
            CommunicatorRepassePhaseHelper.getNomeSinteseValuesByMacroPhaseKeyword(trimmedKeyword);
        return countRepassesByKeyword(
            opportunityIds,
            trimmedKeyword,
            macroPhaseSinteseValues,
            assessoriaIds
        );
    }

    private static List<Repasse__c> queryCandidateRepasses(
        String trimmedKeyword,
        Integer queryLimit,
        Set<String> macroPhaseSinteseValues,
        Set<Id> assessoriaIds
    ) {
        String likeKeyword = '%' + trimmedKeyword + '%';
        if (assessoriaIds != null && assessoriaIds.isEmpty()) {
            return new List<Repasse__c>();
        }
        if (macroPhaseSinteseValues == null || macroPhaseSinteseValues.isEmpty()) {
            String query =
                'SELECT Oportunidade__c ' +
                'FROM Repasse__c ' +
                'WHERE Oportunidade__c != null ' +
                'AND (Name LIKE :likeKeyword OR Oportunidade__r.Name LIKE :likeKeyword OR NomeSintese__c LIKE :likeKeyword OR Sintese__r.Name LIKE :likeKeyword) ';
            if (assessoriaIds != null) {
                query += 'AND ContaAssessoria__c IN :assessoriaIds ';
            }
            query += 'ORDER BY LastModifiedDate DESC LIMIT :queryLimit';
            return Database.query(query);
        }
        String query =
            'SELECT Oportunidade__c ' +
            'FROM Repasse__c ' +
            'WHERE Oportunidade__c != null ' +
            'AND (Name LIKE :likeKeyword OR Oportunidade__r.Name LIKE :likeKeyword OR NomeSintese__c LIKE :likeKeyword OR Sintese__r.Name LIKE :likeKeyword OR NomeSintese__c IN :macroPhaseSinteseValues OR Sintese__r.Name IN :macroPhaseSinteseValues) ';
        if (assessoriaIds != null) {
            query += 'AND ContaAssessoria__c IN :assessoriaIds ';
        }
        query += 'ORDER BY LastModifiedDate DESC LIMIT :queryLimit';
        return Database.query(query);
    }

    private static List<Repasse__c> queryRepassesByOpportunityIds(
        Set<Id> opportunityIds,
        String trimmedKeyword,
        Integer queryLimit,
        Set<String> macroPhaseSinteseValues,
        Set<Id> assessoriaIds
    ) {
        if (assessoriaIds != null && assessoriaIds.isEmpty()) {
            return new List<Repasse__c>();
        }
        if (String.isBlank(trimmedKeyword)) {
            String query =
                'SELECT Id, Name, Oportunidade__c, Oportunidade__r.Name, ContaAssessoria__c, NomeFase__c, NomeSintese__c, Sintese__r.Name ' +
                'FROM Repasse__c ' +
                'WHERE Oportunidade__c IN :opportunityIds ';
            if (assessoriaIds != null) {
                query += 'AND ContaAssessoria__c IN :assessoriaIds ';
            }
            query +=
                'ORDER BY LastModifiedDate DESC ' +
                'LIMIT :queryLimit';
            return Database.query(query);
        }

        String likeKeyword = '%' + trimmedKeyword + '%';
        if (macroPhaseSinteseValues == null || macroPhaseSinteseValues.isEmpty()) {
            String query =
                'SELECT Id, Name, Oportunidade__c, Oportunidade__r.Name, ContaAssessoria__c, NomeFase__c, NomeSintese__c, Sintese__r.Name ' +
                'FROM Repasse__c ' +
                'WHERE Oportunidade__c IN :opportunityIds ';
            if (assessoriaIds != null) {
                query += 'AND ContaAssessoria__c IN :assessoriaIds ';
            }
            query +=
                'AND (Name LIKE :likeKeyword OR Oportunidade__r.Name LIKE :likeKeyword OR NomeSintese__c LIKE :likeKeyword OR Sintese__r.Name LIKE :likeKeyword) ' +
                'ORDER BY LastModifiedDate DESC ' +
                'LIMIT :queryLimit';
            return Database.query(query);
        }
        String query =
            'SELECT Id, Name, Oportunidade__c, Oportunidade__r.Name, ContaAssessoria__c, NomeFase__c, NomeSintese__c, Sintese__r.Name ' +
            'FROM Repasse__c ' +
            'WHERE Oportunidade__c IN :opportunityIds ';
        if (assessoriaIds != null) {
            query += 'AND ContaAssessoria__c IN :assessoriaIds ';
        }
        query +=
            'AND (Name LIKE :likeKeyword OR Oportunidade__r.Name LIKE :likeKeyword OR NomeSintese__c LIKE :likeKeyword OR Sintese__r.Name LIKE :likeKeyword OR NomeSintese__c IN :macroPhaseSinteseValues OR Sintese__r.Name IN :macroPhaseSinteseValues) ' +
            'ORDER BY LastModifiedDate DESC ' +
            'LIMIT :queryLimit';
        return Database.query(query);
    }

    private static Integer countRepassesByKeyword(
        Set<Id> opportunityIds,
        String trimmedKeyword,
        Set<String> macroPhaseSinteseValues,
        Set<Id> assessoriaIds
    ) {
        if (assessoriaIds != null && assessoriaIds.isEmpty()) {
            return 0;
        }
        if (String.isBlank(trimmedKeyword)) {
            String query =
                'SELECT COUNT() ' +
                'FROM Repasse__c ' +
                'WHERE Oportunidade__c IN :opportunityIds ';
            if (assessoriaIds != null) {
                query += 'AND ContaAssessoria__c IN :assessoriaIds ';
            }
            return Database.countQuery(query);
        }
        String likeKeyword = '%' + trimmedKeyword + '%';
        if (macroPhaseSinteseValues == null || macroPhaseSinteseValues.isEmpty()) {
            String query =
                'SELECT COUNT() ' +
                'FROM Repasse__c ' +
                'WHERE Oportunidade__c IN :opportunityIds ';
            if (assessoriaIds != null) {
                query += 'AND ContaAssessoria__c IN :assessoriaIds ';
            }
            query += 'AND (Name LIKE :likeKeyword OR Oportunidade__r.Name LIKE :likeKeyword OR NomeSintese__c LIKE :likeKeyword OR Sintese__r.Name LIKE :likeKeyword)';
            return Database.countQuery(query);
        }
        String query =
            'SELECT COUNT() ' +
            'FROM Repasse__c ' +
            'WHERE Oportunidade__c IN :opportunityIds ';
        if (assessoriaIds != null) {
            query += 'AND ContaAssessoria__c IN :assessoriaIds ';
        }
        query += 'AND (Name LIKE :likeKeyword OR Oportunidade__r.Name LIKE :likeKeyword OR NomeSintese__c LIKE :likeKeyword OR Sintese__r.Name LIKE :likeKeyword OR NomeSintese__c IN :macroPhaseSinteseValues OR Sintese__r.Name IN :macroPhaseSinteseValues)';
        return Database.countQuery(query);
    }
}