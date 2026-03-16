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

        List<String>  objectNames     = CommunicatorConfigService.getObjectApiNames();
        Integer       maxResults      = CommunicatorConfigService.getMaxSearchResults();
        Boolean       filterOpenOnly  = CommunicatorConfigService.getFilterOpenOnly();
        String        sanitized       = sanitizeKeyword(keyword.trim());

        // Build SOSL RETURNING clause dynamically
        String returningClause = buildReturningClause(objectNames, maxResults, filterOpenOnly);

        // Objects with IsClosed field — used for open-only filter
        Set<String> closedFilterObjects = new Set<String>{ 'Opportunity', 'Case' };

        String sosl = 'FIND :sanitized IN NAME FIELDS RETURNING ' + returningClause;

        List<List<SObject>> soslResults;
        try {
            soslResults = Search.query(sosl);
        } catch (Exception ex) {
            throw new CommunicatorException('Search failed: ' + ex.getMessage());
        }

        return mapResults(soslResults, objectNames);
    }

    // ─────────────────────────────────────────
    // Private helpers
    // ─────────────────────────────────────────

    private static String buildReturningClause(
        List<String> objectNames,
        Integer      maxResults,
        Boolean      filterOpenOnly
    ) {
        // Objects that support IsClosed field
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
        List<String>        objectNames
    ) {
        List<CommunicatorDTOs.RecordResultDTO> results = new List<CommunicatorDTOs.RecordResultDTO>();

        for (Integer i = 0; i < soslResults.size(); i++) {
            List<SObject> records   = soslResults[i];
            String        objName   = i < objectNames.size() ? objectNames[i] : 'Unknown';

            if (records.isEmpty()) continue;

            CommunicatorDTOs.RecordResultDTO resultGroup = new CommunicatorDTOs.RecordResultDTO();
            resultGroup.objectApiName = objName;
            resultGroup.objectLabel   = getObjectLabel(objName);
            resultGroup.records = new List<CommunicatorDTOs.RecordItemDTO>();

            for (SObject rec : records) {
                CommunicatorDTOs.RecordItemDTO item = new CommunicatorDTOs.RecordItemDTO();
                item.recordId   = (String) rec.get('Id');
                item.name       = (String) rec.get('Name');
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
}
