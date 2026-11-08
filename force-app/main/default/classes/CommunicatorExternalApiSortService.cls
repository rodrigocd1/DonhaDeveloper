public with sharing class CommunicatorExternalApiSortService {

    public static String normalizeDirection(String sortDirection) {
        String direction = String.isBlank(sortDirection) ? 'desc' : sortDirection.trim().toLowerCase();
        if (direction != 'asc' && direction != 'desc') {
            throw CommunicatorExternalApiErrorService.badRequest(
                'INVALID_SORT_DIRECTION',
                'sortDirection deve ser asc ou desc.'
            );
        }
        return direction;
    }

    public static String validateSortField(String sortBy, Set<String> allowlist, String defaultField) {
        String fieldName = String.isBlank(sortBy) ? defaultField : sortBy.trim();
        if (String.isBlank(fieldName)) return null;
        if (allowlist == null || !allowlist.contains(fieldName)) {
            throw CommunicatorExternalApiErrorService.badRequest(
                'INVALID_SORT_FIELD',
                'Campo de ordenacao nao permitido: ' + fieldName
            );
        }
        return fieldName;
    }
}