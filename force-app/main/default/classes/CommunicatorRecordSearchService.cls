/**
 * @description Service responsible for searching records across multiple
 *              SObject types configured in CommunicatorConfig__mdt.
 *
 *              Uses SOSL for multi-object full-text search in a single query.
 *              Results are returned as a list of CommunicatorRecordSearchResult
 *              DTOs, grouped by object type.
 */
public with sharing class CommunicatorRecordSearchService {

    /**
     * @description Searches for records matching the keyword across all
     *              configured SObject types.
     * @param keyword Search term (minimum 2 characters).
     * @return List of CommunicatorDTOs.RecordResultDTO.
     */
    public static List<CommunicatorDTOs.RecordResultDTO> searchRecords(String keyword) {
        if (String.isBlank(keyword) || keyword.trim().length() < 2) {
            throw new CommunicatorException('Keyword must have at least 2 characters.');
        }

        List<String> objectNames = CommunicatorConfigService.getObjectApiNames();
        Integer maxResults = CommunicatorConfigService.getMaxSearchResults();
        Boolean filterOpenOnly = CommunicatorConfigService.getFilterOpenOnly();
        String sanitized = sanitizeKeyword(keyword.trim());
        List<String> searchObjectNames = new List<String>();
        Boolean includeRepasse = false;

        for (String objectName : objectNames) {
            if (objectName == 'Repasse__c') {
                includeRepasse = true;
                continue;
            }
            searchObjectNames.add(objectName);
        }

        List<List<SObject>> soslResults = new List<List<SObject>>();
        if (!searchObjectNames.isEmpty()) {
            String returningClause = buildReturningClause(searchObjectNames, maxResults, filterOpenOnly);
            String sosl = 'FIND :sanitized IN NAME FIELDS RETURNING ' + returningClause;

            try {
                soslResults = Search.query(sosl);
            } catch (Exception ex) {
                throw new CommunicatorException('Search failed: ' + ex.getMessage());
            }
        }

        List<CommunicatorDTOs.RecordResultDTO> results = mapResults(soslResults, searchObjectNames);
        if (includeRepasse) {
            CommunicatorDTOs.RecordResultDTO repasseGroup = buildRepasseResults(keyword, maxResults);
            if (repasseGroup != null && repasseGroup.records != null && !repasseGroup.records.isEmpty()) {
                results.add(repasseGroup);
            }
        }

        return results;
    }

    private static String buildReturningClause(
        List<String> objectNames,
        Integer maxResults,
        Boolean filterOpenOnly
    ) {
        Set<String> supportsIsClosedFilter = new Set<String>{ 'Opportunity', 'Case' };

        List<String> parts = new List<String>();
        for (String objName : objectNames) {
            String filter = '';
            if (filterOpenOnly && supportsIsClosedFilter.contains(objName)) {
                filter = ' WHERE IsClosed = false';
            }
            parts.add(objName + '(Id, Name' + filter + ' LIMIT ' + maxResults + ')');
        }
        return String.join(parts, ', ');
    }

    private static List<CommunicatorDTOs.RecordResultDTO> mapResults(
        List<List<SObject>> soslResults,
        List<String> objectNames
    ) {
        List<CommunicatorDTOs.RecordResultDTO> results = new List<CommunicatorDTOs.RecordResultDTO>();

        for (Integer i = 0; i < soslResults.size(); i++) {
            List<SObject> records = soslResults[i];
            String objName = i < objectNames.size() ? objectNames[i] : 'Unknown';

            if (records.isEmpty()) continue;

            CommunicatorDTOs.RecordResultDTO resultGroup = new CommunicatorDTOs.RecordResultDTO();
            resultGroup.objectApiName = objName;
            resultGroup.objectLabel = getObjectLabel(objName);
            resultGroup.records = new List<CommunicatorDTOs.RecordItemDTO>();

            for (SObject rec : records) {
                CommunicatorDTOs.RecordItemDTO item = new CommunicatorDTOs.RecordItemDTO();
                item.recordId = (String) rec.get('Id');
                item.name = (String) rec.get('Name');
                item.objectType = objName;
                resultGroup.records.add(item);
            }

            results.add(resultGroup);
        }

        return results;
    }

    private static String getObjectLabel(String objectApiName) {
        try {
            Schema.SObjectType sType = Schema.getGlobalDescribe().get(objectApiName);
            return sType != null ? sType.getDescribe().getLabel() : objectApiName;
        } catch (Exception ex) {
            return objectApiName;
        }
    }

    private static String sanitizeKeyword(String keyword) {
        return keyword.replaceAll('[\\?&|!{}\\[\\]()\\^~\\*:\\\\\\"\'\\+\\-]', '\\\\$0') + '*';
    }

    private static CommunicatorDTOs.RecordResultDTO buildRepasseResults(String keyword, Integer maxResults) {
        Set<Id> visibleAssessoriaIds = CommunicatorThreadService.getVisibleAssessoriaIdsForCurrentUser();
        Set<Id> candidateOppIds = CommunicatorRepasseService.getCandidateOpportunityIdsByKeyword(
            keyword,
            maxResults,
            visibleAssessoriaIds
        );
        Set<Id> visibleOppIds = CommunicatorOpportunityAccessService.getVisibleOpportunityIds(candidateOppIds);
        List<Repasse__c> repasses = CommunicatorRepasseService.getRepassesByOpportunityIds(
            visibleOppIds,
            keyword,
            maxResults,
            visibleAssessoriaIds
        );
        if (repasses.isEmpty()) {
            return null;
        }

        CommunicatorDTOs.RecordResultDTO resultGroup = new CommunicatorDTOs.RecordResultDTO();
        resultGroup.objectApiName = 'Repasse__c';
        resultGroup.objectLabel = getObjectLabel('Repasse__c');
        resultGroup.records = new List<CommunicatorDTOs.RecordItemDTO>();

        for (Repasse__c repasse : repasses) {
            CommunicatorDTOs.RecordItemDTO item = new CommunicatorDTOs.RecordItemDTO();
            item.recordId = (String) repasse.Id;
            item.name = repasse.Name;
            item.objectType = 'Repasse__c';
            resultGroup.records.add(item);
        }

        return resultGroup;
    }
}